# Round 1 review: throwaway-shutdown-logic-scylla (lens: spec, conventions, architecture, integration)

Worktree: `/home/user/Delphi/worktrees/argos/throwaway-shutdown-logic-scylla`, diff `origin/shutdown-loop-page...HEAD` (3 commits). Paths below are relative to the worktree unless they start with `/`.

**What I checked.** I copied `scylla-server/` and the client's `shutdown-page/` folder to the scratchpad and ran `cargo test --lib` there; the worktree itself was not touched. All 25 unit tests on the branch pass, including the TS-to-Rust parity test. I also added a throwaway probe test to the scratch copy only. It feeds the tracker one message at a time, the way `shutdown_handler` does. A single TSMS-on raised five spurious Faults (see B1). Sibling diffs were read-only.

Counts, including the Integration section: **1 blocker, 10 major, 13 minor, 7 nit.** M9 and I3 are the same finding, counted once; I1 is the tenth major.

## Findings

### Blocker

- **B1 · blocker · `scylla-server/src/shutdown_handler.rs:40-45`, `scylla-server/src/shutdown_loop/tracker.rs:140-180`. Every loop closing raises a run of short-lived spurious Faults, and they push real car Faults out of the 100-entry ring buffer.**
  - **Issue.** The handler runs `evaluate` after *every* input message. Calypso publishes each signal on its own topic, and the VCU and BMS frames arrive at different times. So while a frame is half applied, the break walks down the loop. I confirmed this with the probe. Start with the loop open at TSMS, then turn TSMS on (VCU signals 1 ms apart, the BMS frame 300 ms later). The tracker publishes `Shutdown_Open_TSMS`→0, then raises and clears in turn `Shutdown_Open_HVD`, `Bms/Shutdown_Open_ACC_SENSE` (held about 300 ms, until the BMS frame arrives), `TSIP_SENSE`, `TS_MINUS` and `TS_PLUS`.
  - **Effect.** Each 1 creates a new Fault list entry (`register_fault`), and each 0 marks it expired. Each is also a stored datapoint. That is 5 junk entries per TSMS cycle. `AllocRingBuffer::new(100)` (`socket_handler.rs:141`) overwrites its oldest entries, so about 20 pit cycles on a test day evict every real BMS/MPU/Charger/DTI Fault.
  - **Why the tests miss it.** The tracker tests call `record` several times and then `evaluate` once (`tracker.rs:245-270`), which never matches how the handler runs.
  - **Fix (one of these, or both).**
    - (a) Debounce Faults: raise `Shutdown_Open_*` only once the same break index has held for a grace window. At least `MISMATCH_GRACE_MS` within a board. Across boards, until the other board has sampled since the change, the same rule `is_mismatch` already uses.
    - (b) Coalesce: evaluate on a short timer (for example 50–100 ms) or once per input timestamp, not once per message.
  - **Test.** Add a tracker test that records one message at a time and asserts that a closing transition publishes no Fault 1s.

### Major

- **M1 · major · `scylla-server/src/shutdown_handler.rs:73`. Stored `Argos/Shutdown/*` datapoints are on scylla's clock, but the car's datapoints are on the car's clock, which defeats the history argument.**
  - **Issue.** `mqtt_processor.rs:276-295` stamps car data with the packet's own timestamp whenever it is after 2000. The handler stamps its output with `Utc::now()`. ADR 0009 itself says the car's clock "can be off". When it is, the graph page and Grafana show the verdict shifted against the readings that caused it. "Why did the car shut down on lap 7?" then gets an answer offset by the clock skew.
  - **Fix.**
    - Keep scylla receive times for staleness and grace, as now.
    - Stamp each event-triggered publish with the triggering message's `data.timestamp`. Stamp heartbeats with the newest input's car timestamp plus (now − its receive time).
    - Note that `(time, name, runId)` upserts use `on_conflict_do_nothing` (`services/data_service.rs:77`). Several signals of one frame share a car timestamp, so this only works together with B1(b) coalescing. Otherwise later states in the same millisecond are silently dropped.
  - **ADR wording.** Amend ADR 0009's "Times are scylla's own" to: "Staleness and grace windows use when scylla received each message, never the car's clock, which can be off. The published datapoints carry the car's timestamp of the input that produced them, so they line up with the car data beside them."

- **M2 · major · `scylla-server/src/socket_handler.rs:480-516` (`send_socket_msg`), ADR 0009:20. The server's own status is subject to the socket discard, which undercuts the reason for preferring it.**
  - **Issue.** `Argos/Shutdown/NodeStates` goes out on `DATA_SOCKET_KEY` through the shared `upload_counter`, so `SOCKET_DISCARD_PERCENT` drops it like any car topic. The ADR's rationale is "the server sees every message; a client may have some dropped by the socket discard setting". Yet the server's 1 Hz verdict is dropped at the same rate. With discard at 50%, the 3 s freshness window misses about 12% of the time (0.5³), so `source` flaps between server and local.
  - **Fix.** Exempt `Argos/Shutdown/` topics from the discard: emit them without touching `upload_counter`, or through a `send_socket_msg_always`.
  - **ADR wording.** Add to the bullet: "scylla's own `Argos/Shutdown/*` datapoints are exempt from the socket discard."

- **M3 · major · `.github/workflows/scylla-ci.yml:33-36`. The parity test never runs on a client-only change.**
  - **Issue.** `matches_the_angular_client_loop` reads `../angular-client/.../shutdown-loop.model.ts` and `shutdown-page.topics.ts`. Scylla CI's `paths-filter` only matches `scylla-server/**`. A PR that reorders the client loop, which the spec itself expects ("the latch's position after BSPD ... should be checked against the netmap diagram"), passes CI. The next unrelated scylla PR then goes red.
  - **Fix.** Add to the `scylla:` filter:
    ```
    - "angular-client/src/pages/shutdown-page/shutdown-loop.model.ts"
    - "angular-client/src/pages/shutdown-page/shutdown-page.topics.ts"
    ```

- **M4 · major · `angular-client/src/pages/shutdown-page/shutdown-loop.server.ts:46`, spec §Status algorithm step 8. Server states are trusted on length alone, so a reordered loop mis-attributes the culprit without any error.**
  - **Issue.** `resolveLoopStatus` accepts the server codes whenever `codes.length === local.nodes.length`. Reordering nodes keeps the length at 19, so a client and scylla built from different revisions paint the suspect on the wrong node. That is a cached client, or a laptop on an older image. This is the one question the page exists to answer.
  - **Fix.** Publish a loop identity with the states, for example `Argos/Shutdown/Loop_Version` as a hash of the ordered ids, or a leading version value in `NodeStates`. Fall back to local when it differs.
  - **Spec wording.** "...and has one valid code per loop node **and the same loop version as this client**...".

- **M5 · major · ADR 0009:26 ("each side ports the other's unit tests"), `scylla-server/src/shutdown_loop/status.rs:271-548`. The parity guard covers the node table only, and the ADR overstates the test port.**
  - **Issue.** `shutdown-loop.utils.spec.ts` has about 30 cases. `status.rs` has 14, which leaves out these TS cases:
    - non-zero counts as closed
    - no mismatch within grace of the downstream reading flipping back
    - EM placeholder closed / downstream
    - not stale at exactly 60 s
    - smoothing of one late message
    - relearning a slower rate
    - `noDataInStretch`, which Rust doesn't compute

    Small differences already exist:
    - TS `live` requires `node.board`; Rust only requires `topic`.
    - TS uses `prev.value === value`; Rust uses `abs < f32::EPSILON`.

    Nothing catches drift in the algorithm itself, which is the part most likely to change.
  - **Fix.** Use shared golden vectors. Test fixtures are only needed at test time, so the ADR's Docker-context objection doesn't apply; the parity test already reads across the boundary. Put `docs/spec/shutdown-loop-page/vectors.json` (readings with value, received/changed time and interval; `now`; expected codes and verdict) in the repo. Read it from a Jest spec and from a `cargo test`, and add the file to both CI path filters.
  - **ADR wording.** Replace the bullet with: "**Two copies of the algorithm.** `shutdown-loop.utils.ts` and `scylla-server/src/shutdown_loop/status.rs` must change together. A `cargo test` checks the node table against the client's, and both test suites run the same golden vectors (`docs/spec/shutdown-loop-page/vectors.json`), so a change to either algorithm fails until the other matches."

- **M6 · major · ADR 0009:11 and the overall design. Duplicating the algorithm is defensible only with M5; the ADR's reasons for keeping a client copy are partly wrong.**
  - **Issue.** The client gets every reading *through scylla's socket*. There is no trackside mode where the client sees data while scylla is down, so "offline use" doesn't apply. A "slow link" slows the client's raw readings just as much as the verdict. The real reasons to keep a client copy:
    - (1) Version skew and rollout: an older scylla, or `--no-metadata`, doesn't matter since the task runs either way.
    - (2) The mock panel and dev fixtures, which only exist client-side.
    - (3) The socket discard, which M2 fixes for the server output.

    **Nero** cannot use either copy. scylla publishes to its own Socket.IO, not to Siren, so a driver-display verdict would need a third port or an MQTT publish. Worth saying so the next person doesn't assume Nero is covered.
  - **Recommendation.** Keep both for now, with M5's vectors. If drift becomes a burden, the cleaner end state is server-only plus a thin client fallback that shows raw readings with "status unavailable".
  - **ADR wording.** Rewrite the rejected option as: "**Only the server computes; the client just displays.** Rejected for now: the client already receives every reading through scylla, so this is not about offline use, but the page would go blank against a scylla without the task (older images), the dev mock panel publishes only into the client, and a client copy keeps the page usable while the server output is missing. The cost is two copies, guarded by golden vectors. Nero cannot use either copy: scylla's output goes to its socket, not to Siren."

- **M7 · major · `scylla-server/src/shutdown_loop/tracker.rs:64`, spec:57. `Shutdown_Open_<NODE>` names the measurement point, which blames it even when the suspect stretch is wider.**
  - **Issue.** `BMS_GPIO = 0` raises `Vcu/Shutdown_Open_BMS_LATCH`, but the suspects are Side BRB R, Side BRB L and the BMS latch. Someone hits a side BRB, and the Faults page and stored history say "BMS latch". That is the anti-goal the page is built around ("blames only the first open stretch").
  - **Fix.** Name the Fault after where the loop was *seen* open: `Shutdown_Open_Before_<F>` ("the loop is open somewhere up to F's reading").
  - **Spec wording.** "`Shutdown_Open_Before_<NODE>` on the board whose reading found the break, where `<NODE>` is the first live measurement point reading 0 (the suspects are every loop node from the last live closed reading up to it)."

- **M8 · major · ADR 0009:24-25; `/home/user/Delphi/docs/CONTEXT.md` (Topic, Node, Fault); `docs/adr/0008-multi-comp-argos-database.md`. The ADR flags conflicts but doesn't decide them, and the docs it says must change are unchanged.**
  - **Issue.** An ADR should record the decision, not "if the team wants". ADR 0008 rejected `Argos/Track/*` datapoints on technical grounds (floats only, needs a Run), not on principle. Its rule "car database stays car-only" can stand with a clarification. `Argos/Message` (`ArgosInserter`) is already the precedent. The glossary still says synthetic topics are "never persisted" and that a Node is one of four. Charybdis's cloud upload will also carry `Argos/Shutdown/*`, which the ADR doesn't mention.
  - **Fix: replace ADR 0009's first consequence with:**
    > **Derived telemetry counts as car data.** ADR 0008 keeps Argos-only data out of the car database. `Argos/Shutdown/*`, like `Argos/Message`, is not Argos-only: it is a function of one Run's car data, has no meaning outside that Run, and must sit beside the readings for history, Grafana and Rules. It is stored in the car database and goes to the cloud with the rest of the Run. ADR 0008 is amended to say so.
  - **Fix: add to ADR 0008's "Why this shape", after the first bullet:**
    > - **Derived telemetry is car data.** Datapoints scylla computes from a Run's car data, such as `Argos/Message` and `Argos/Shutdown/*` (ADR 0009), stay in the car database with the readings they come from. Only data that isn't a function of a Run (tracks, laps, settings) goes here.
  - **Fix: glossary (`/home/user/Delphi/docs/CONTEXT.md`), Topic:**
    > A handful of synthetic topics under `Argos/` are generated by scylla-server rather than the car. Some are broadcast live only (`Argos/Message_Rate`, `Argos/Viewers`, `Latency`); others are derived from a Run's car data and persisted like it (`Argos/Message`, `Argos/Shutdown/*`, ADR 0009).
  - **Fix: glossary, Node:**
    > An on-vehicle CAN device that reports faults — one of `Bms`, `Dti`, `Mpu`, `Charger`, `Vcu`. Used for attributing faults to their source.
  - **Fix: glossary, Fault:**
    > A discrete fault event attributed to a Node — raised by the Node itself, or derived by scylla-server from the Node's readings (the shutdown loop Faults, ADR 0009) — tracked with its first-occurrence time, last-seen time, and an expired flag once it stops recurring or its source reports it cleared.
  - **Fix: glossary, Flagged ambiguities → Node, append:**
    > The Shutdown Loop page's `LoopNode` is a **loop node**: one element of the series shutdown loop, which may have no CAN device of its own. Say "loop node".
  - **Fix: glossary, optional new entry under Alerting or a new "Shutdown loop" heading:**
    > **Loop node**: one element of the series shutdown loop (switch, kill button, latch, interlock, sense point, AIRs), in loop order; it has a reading if a board measures the loop voltage just after it. _Avoid_: Node (unqualified).
  - **Fix: ADR 0009's glossary bullet** should then read: "`docs/CONTEXT.md` now lists `Vcu` as a Node, persisted derived topics under Topic, and derived Faults under Fault."

- **M9 · major · Integration: the mock panel is overridden by scylla whenever the backend runs (see Integration conflicts, I3).**

### Minor

- **m1 · minor · ADR 0009:27, `tracker.rs:57-92`. "Every TSMS-off is a Fault" is underplayed.**
  - **Issue.** Apart from B1, a car sitting on GLV with TSMS off holds `Vcu/Shutdown_Open_TSMS` active for hours, re-sent every second. Every power-up or power-down creates an entry, and a Rule `a == 0` on `Verdict` notifies the pit every time.
  - **Fix.**
    - Raise `Shutdown_Open_*` only for loop nodes of kind latch, kill or interlock, plus BOTS and the inertia switch. Leave out the operator switches (GLVMS, TSMS, HVD), and only raise after the loop had been closed (closed→open transition). Record the opening in `Verdict`/`BreakNode` only.
    - Alternatively, keep them all but say in the ADR that this is a known cost, not a "small follow-up if it gets noisy".
  - **ADR wording.** "**Operator switches are not Faults.** Opening the loop at the GLV master switch, TSMS or HVD is recorded in `Argos/Shutdown/Verdict` and `BreakNode` but raises no Fault; latches, kill buttons, interlocks, BOTS and the inertia switch do."

- **m2 · minor · `tracker.rs:85` with `:64`. A CAN latch trip raises two Faults for one event.**
  - **Issue.** Both `Shutdown_Open_CAN_LATCH` and `CAN_Latch_<FAULT>` are raised (the test at `tracker.rs:276-290` asserts both).
  - **Fix.** Either raise only the per-fault one when the break is at `can-latch`, or better, register `VCU/Faults/Critical/*` as ordinary `Vcu` Faults in the socket handler with a `VCU\/Faults\/Critical\/(.*)` regex, the existing pattern used for BMS, MPU and Charger. Then the loop only adds the break Fault. That also surfaces VCU critical faults that never touch the loop.

- **m3 · minor · `tracker.rs:171-174`, ADR 0009:18. Faults clear when data goes *stale*, not only when the loop closes.**
  - **Issue.** When the inputs go stale, `break_idx` becomes `None` and the Fault is published as 0, which reads as "expired" on the Faults page. A VCU dropout mid-fault therefore looks like a recovery (the test `stale_inputs_clear_faults_and_go_unknown` asserts this).
  - **Fix.** Hold active Faults while the verdict is Unknown, or document it.
  - **ADR wording.** "...so the Fault ends when the loop closes or its readings go stale, not when an unrelated message arrives."

- **m4 · minor · `socket_handler.rs:448`, ADR 0009:29. The gap-check fix changes the existing Faults page for every Node and is out of scope.**
  - **Issue.** Correcting `last_seen - now` means BMS/MPU/Charger Faults that recur after 8 s now start new entries. Before, there was one entry forever. It's a real fix, but it's a visible behaviour change unrelated to the shutdown loop, buried in a feature commit.
  - **Fix.** File it as its own dev ticket and commit (`create-ticket`) when this throwaway is turned into tickets. Also update `FaultData.expired`'s doc (`metadata_structs.rs:56`, "whether another fault of the same node and name as occured after this fault"), which `clear_fault` now breaks. Suggested: "whether the fault has stopped: another occurrence came after a long gap, or its source reported it cleared".

- **m5 · minor · `shutdown_handler.rs:63-90`. Server-generated DB inserts bypass `ArgosInserter`.**
  - **Issue.** `argos_inserter.rs` documents "Use this anywhere the server itself needs to insert a datapoint into the DB".
  - **Fix.** Take an `ArgosInserter` instead of `db_tx: broadcast::Sender`.

- **m6 · minor · `tracker.rs:140-145`. Heartbeats never stop.**
  - **Issue.** Once any reading has arrived, `readings` is never emptied. After the car is switched off, scylla publishes `Verdict = -1` plus `NodeStates` (all 3s) every second into the last Run indefinitely, which is about 430k rows a day. `Argos/Message` sets a precedent, but this adds to it.
  - **Fix.** Publish the unknown snapshot once, then skip heartbeats while no input is live.

- **m7 · minor · spec:93. The Status algorithm still names the old signature.**
  - **Fix.** "Pure function `computeLoopStatus(nodes, readings, now) → LoopStatus` in `shutdown-loop.utils.ts`, no Angular dependency, unit-tested; scylla-server's `compute_loop_status` (`shutdown_loop/status.rs`) is a port of it."

- **m8 · minor · spec:101. Step 3 doesn't match the code for unmeasured nodes or the AIRs.**
  - **Fix.** "Unmeasured nodes before the break: closed (inferred). With no break, an unmeasured node is closed only if a live reading after it reads 1, or every measurement point is live; otherwise no data. AIRs: energized iff the verdict is LOOP CLOSED."

- **m9 · minor · `shutdown-loop.server.ts:45-55`. Server states are mixed with local values and ages, so displays can contradict themselves.**
  - **Issue.** A node can show `closed` from the server while its local value reads 0, or the reverse, within the up-to-1 s gap or when the client discarded a message. The 3D tooltips (`car-view-3d.model.ts:129`, gltf `car-view-3d.utils.ts:165`) and the UI's node detail print value and state side by side.
  - **Fix.** Either show the value's source, or when `source === 'server'` and the local value disagrees, mark the value "(older)". At minimum, note it in the spec.

- **m10 · minor · `LoopStatus.source` is computed but never rendered.**
  - **Issue.** Spec step 8 makes `source` part of the design, but nothing on the base branch or the UI branch displays it. A user can't tell whether scylla or the browser produced the verdict.
  - **Fix.** Show it in the UI branch's `loop-meta` chip row ("status: scylla" or "status: this browser").

### Nit

- **n1 · nit · `tracker.rs:10-14`, spec:50-55. Topic segment style is inconsistent.**
  - **Issue.** `BreakNode` and `NodeStates` are PascalCase. The synthetic and car topics use `Snake_Case` segments (`Message_Rate`, `TS_Plus_Sense`, and `CAN_Latch` here).
  - **Fix.** Use `Argos/Shutdown/Break_Node` and `Argos/Shutdown/Node_States`.

- **n2 · nit · `model.rs:45`, `shutdown-page.topics.ts` `CAN_LATCH: 'VCU/Faults/Critical'`. The derived reading's internal key looks like a car topic.**
  - **Issue.** The key sits in the VCU namespace and is the parent of the real `VCU/Faults/Critical/*` topics. A future car topic or bin with that name would collide.
  - **Fix.** Use a non-topic key such as `derived/can-latch` or `Argos/Shutdown/CAN_Latch`, which the server already publishes.

- **n3 · nit · `shutdown_handler.rs:27`.** `tokio::time::interval` defaults to `MissedTickBehavior::Burst`, so after a stall several heartbeats fire back to back. Use `heartbeat.set_missed_tick_behavior(MissedTickBehavior::Delay)`.

- **n4 · nit · `shutdown_handler.rs:83-88`.** If a channel has no receivers, it warns once per datapoint per second. Log once per publish, or `debug!` after the first. Also, `now` (line 40/56) and `timestamp` (line 73) are two separate `Utc::now()` calls; pass one through (moot if M1 is done).

- **n5 · nit · `shutdown-loop.server.ts` filename.** Angular uses `*.server.ts` for SSR entry points (`main.server.ts`, `app.config.server.ts`). Argos has no SSR, but `shutdown-loop.scylla.ts` or `shutdown-loop.remote.ts` avoids the confusion.

- **n6 · nit · spec:57 and spec:141.**
  - "Values arrive via `Storage.get(topic)`…" now trails the Faults paragraph. Move it back under the first Data table.
  - Constraints still cite the PrimeNG-era rules ("external templates/styles, Material icons"). ADR 0007 and `docs/CONTEXT.md` Conventions now govern. Suggested: "Angular conventions in `docs/CONTEXT.md` (Conventions) and ADR 0007: standalone, OnPush, signals + `computed()`, external templates, `inject()`, Tailwind on theme tokens, `<ui-icon>`, no emojis."

### What's sound

- Task shape and lifecycle match `track_handler`: cancellation token, `task_tracker`, `Lagged`/`Closed` handling, and the self-output filter by prefix.
- `--no-metadata` still gets status datapoints.
- The ADR filename and `full-stack` prefix follow `docs/CONTEXT.md` Conventions.
- Per-reading adaptive staleness and the cross-board "sampled after the break" rule are well reasoned. The spec explains both clearly with the reasons for the amendment.
- The "loop node vs glossary Node" terminology note at the top of the spec is the right move. It just needs the glossary side (M8).

## Integration conflicts

I verified by grep across the three sibling worktrees. **Nothing in any sibling calls `computeLoopStatus` or uses `BoardLastSeen`, `lastSeen`, `receivedAt` or `changedAt`**, so the signature change and the removed type cause no compile errors. The files don't overlap textually:

- **logic** touches `shutdown-loop.service.ts`, `utils.ts`, the new `server.ts` and `topics.ts`.
- **ui** touches `display.ts`, the components and the page component.
- **3d-*** add new files plus small `shutdown-page.component.{html,ts}` edits.

The conflicts are semantic:

- **I1 · major · throwaway-shutdown-ui `components/loop-banner/loop-banner.component.ts:4,96` and `shutdown-loop.display.ts:3,240` (`boardFreshness`). The UI still treats `STALE_AFTER_MS` (60 s) as *the* staleness threshold.**
  - **Issue.** After this branch, 60 s is only the cap. A reading at 4 Hz goes stale after 3 s. The banner would say "No data from BMS for over 60 s" after 3 s, and the board chip would show "fresh" while that board's nodes are already `no-data`. Being per-board, `boardFreshness` also contradicts the new per-reading model: the CAN latch faults can be live while the 0x123 GPIO frame is stale.
  - **Fix on merge.** Add `staleAfterMs?: number` (or `live: boolean`) to `NodeStatus` from `computeLoopStatus`. Compute board staleness as "any measured node of the board is `no-data`". Reword the banner: "No recent data from BMS (nothing within its expected message interval): its readings are skipped, which can widen the suspect stretch."

- **I2 · minor · throwaway-shutdown-ui `components/mock-panel/mock-panel.component.html:7`, "stale after 60 s without publishing".** The mock publishes at 1 Hz, so readings now go stale about 5 s after it stops. Change to "stale a few seconds after publishing stops".

- **I3 · major (M9) · mock panel (base and UI branch) vs `resolveLoopStatus`. The mock's scenarios are overridden by scylla.**
  - **Issue.** `run-local` always runs scylla, and scylla computes `NodeStates` from the Calypso sim's random bits. The mock panel only writes into the client's `Storage`. Within 3 s the page shows scylla's verdict on the sim, not the mock's "break at TSMS" scenario. The spec's builder's call ("dev-only fixture/mock-publish path inside the frontend") is effectively broken whenever the backend is up.
  - **Fix.** While the mock is publishing, force local: add a `preferServer` signal on `ShutdownLoopService` that the mock panel turns off, or have the mock also publish a matching `Argos/Shutdown/NodeStates`. The UI branch's restyled mock panel is where this lands, so coordinate the merge order: logic first, then the UI adapts the mock.

- **I4 · minor · 3D branches (`car-view-3d.model.ts:129` procedural, `car-view-3d.utils.ts:165` gltf) and UI `node-detail.component.ts:47`.** They render `value` and `ageMs` next to `state`. With `source === 'server'` these can disagree (m9). After merge, decide in one place, probably `shutdown-loop.display.ts` in the UI branch, how a server-state/local-value mismatch is shown, and have the 2D, 3D and detail views use it.

- **I5 · minor · the parity test parses `SHUTDOWN_LOOP` with regexes (`model.rs:130-160`).** No sibling edits `shutdown-loop.model.ts` or `shutdown-page.topics.ts`: 3D positions live in the separate `shutdown-loop.positions-3d.ts`, which is good. But any later merge that adds a nested object with an `id:` key inside a loop entry, or lets Prettier wrap a topics entry over two lines, breaks the parser with a confusing panic. Keep 3D/UI data out of `SHUTDOWN_LOOP`, and add a comment above `SHUTDOWN_LOOP` in the client: "Parsed by scylla-server's `matches_the_angular_client_loop` test: keep one `id:` per entry and topics as `VCU.X`/`BMS.X`."

- **I6 · nit · spec fixtures.** The UI and 3D specs build `LoopStatus` literals without `source`. That's fine while it stays optional. If it becomes required (it arguably should, for m10), about 8 fixtures across `loop-banner`, `node-detail`, `car-view-3d` and `display` specs need it.

**Suggested merge order:** logic first, because it changes the model the others render. Then UI, adapting I1–I4 and the mock panel. Then one 3D variant on top of UI's selection store.
