# Round 1 judge: throwaway-shutdown-logic-scylla

Inputs: logic-correctness.md, logic-live.md, logic-spec.md, plus the integration sections of ui-spec.md. I checked every
claimed blocker and major against the worktree at `2a2ad987` by reading the code. All of them hold:
- `shutdown_handler.rs:41-45` evaluates after every `record`.
- `tracker.rs:140` is the only gate on heartbeats.
- `status.rs:83-107` / `utils.ts:78-97` derive a latch value of 1, and `status.rs:229-231` / `utils.ts:156` then flag it as a
  same-board mismatch.
- `socket_handler.rs` changes the gap check for every Node.
- `scylla-ci.yml` filters on `scylla-server/**` only.

The reviewers' harnesses already showed the failures live and in a differential test, so I didn't rerun them.

## 1. Verdict

**Needs another round.** The algorithm ports are faithful (0 differences in 100k random cases), but the server publishes
spurious Faults on every transition. The derived CAN latch is also modelled as a voltage point, so a routine BRB press or
latch trip raises a "mismatch". Both make the main new feature (Faults and history) misleading.

## 2. MUST FIX (in order)

### L1. Spurious Faults and status churn from per-message evaluation
*(correctness major 1, live majors 1 and 2, spec B1)*

**Decision: do both of the following.**
- **Coalesce, for history and Rules.** Evaluate at most once per burst. The first shutdown input sets a deadline of
  `COALESCE_MS = 25` ms. Later inputs don't push it back, so a steady stream is still evaluated every 25 ms. All inputs
  until the deadline are recorded, then `evaluate` runs once. Use `tokio::time::sleep_until` on an `Option<Instant>` in the
  `select!`. Draining with `try_recv` alone is not enough, because a frame's later signals may not be queued yet.
- **Hold before raising a Fault, for the Fault list.** A Fault key goes into the published active set only when both hold:
  - it has been a candidate continuously for `FAULT_HOLD_MS = 500` ms (all Fault kinds);
  - for `Shutdown_Open_*` only, a message on the break topic arrived after the key first became a candidate (for the
    derived CAN latch: a 0x502 message). This covers the cross-board close: the VCU closes, the BMS senses still hold an
    old 0, and the BMS frame comes up to one BMS interval later. A fixed hold can't cover that when the BMS is slower than
    2 Hz.
- **Clearing stays immediate:** one 0 as soon as the key leaves the candidate set. A candidate that never got raised
  publishes nothing.
- **Accepted cost:** a real opening shorter than 500 ms shows in `Verdict` / `Break_Node` history and on the page, but is
  not a Fault. State this in the spec and the ADR.

**Why both:** coalescing alone leaves the cross-board window. The hold alone leaves stored `BreakNode` values like
14→15→16→17 within 1 ms, and lets Rules on Verdict fire on half-applied frames.

**Acceptance (tracker or handler tests that feed one message at a time, in the sim's VCU order):**
- Close from a break at TSMS. VCU signals are 1 ms apart and the BMS frame comes 300 ms later; then normal frames follow at
  4 Hz. No Fault value 1 is published. `Break_Node` goes from the TSMS index, through at most the acc-sense index (the
  honest cross-board window, until the BMS frame), to -1. It never takes the HVD index or any other intermediate VCU
  index.
- BMS latch reset: every VCU bit is 0, then one frame turns them all to 1, topic by topic. No Fault value 1 is published.
- A break at TSMS held for 2 s publishes:
  - exactly one raise, at t ≥ 500 ms after the break and after a later TSMS message;
  - refreshes on heartbeats;
  - one 0 when it closes.
- A 300 ms break publishes no Fault.
- Per burst of 9 VCU messages, at most one status publish (Verdict, Break_Node, Node_States, Mismatch).
- `cargo test`, clippy and fmt pass. The existing tracker tests are updated to the new timing.

**Files:**
- `scylla-server/src/shutdown_handler.rs`
- `scylla-server/src/shutdown_loop/tracker.rs`

### L2. The derived CAN latch counts only as evidence of an opening
*(correctness major 2, and correctness minor "same-board sampled-after")*

**Decision.** The 0x502 faults tell us whether a fault is tripped, not whether there is loop voltage after the latch. The
latch can also stay latched after its fault clears.

- Add `openOnly?: true` to `LoopNode` (Rust: `open_only: bool`), set only on `can-latch`.
- The derivation is unchanged: 0 if any live fault is tripped, 1 if all five are live and clear, otherwise none. That keeps
  `NodeStatus.value` and `Argos/Shutdown/CAN_Latch`.
- In `computeLoopStatus` / `compute_loop_status`, an `openOnly` node is a measurement point only while its live reading is
  0. Otherwise it is treated exactly like an unmeasured node:
  - closed (inferred) before the break;
  - downstream-open after it, never a mismatch;
  - suspect inside the stretch;
  - the unmeasured no-data rule when there is no break.
- An `openOnly` node never counts toward `allLive`, `silentBoards`, Rust's `silent`, or the "VCU live" evidence for GLVMS.
- In `isMismatch`, the derived latch is its own source. Same source means `sameBoard && !breakNode.openOnly &&
  !node.openOnly`. So when the break is the CAN latch, downstream GPIOs need a 0x123 sample taken after the break before
  they can be flagged.

**Acceptance (TS and Rust, readings derived from fault topics, not by setting `VCU/Faults/Critical` directly):**
- All 9 GPIOs are 0 and held 10 s, and the 5 faults are live 0. Result: `can-latch` is downstream-open with no mismatch,
  `mismatch` is false, and the verdict is open with suspects side-brb-r, side-brb-l and bms-latch.
- One fault is tripped and BSPD is 1. Suspects are `[can-latch]`. GPIOs downstream from a 0x123 frame received before the
  trip, still reading 1 after 600 ms, are not flagged as mismatches.
- The faults are clear, BSPD is 1 and HV_C is 0. Suspects are `[can-latch, mc-hvil]` (no blame on MC HVIL alone).
- Every GPIO and BMS sense is live 1 and the 0x502 faults are stale. The verdict is closed, and VCU is not in
  `silentBoards`.
- `openFrom` in `shutdown-loop.utils.spec.ts` and `open_from` in `status.rs` stop writing the CAN latch topic directly.
- The parity test checks `openOnly` as well.

**Files:**
- `angular-client/src/pages/shutdown-page/shutdown-loop.model.ts`
- `angular-client/src/pages/shutdown-page/shutdown-loop.utils.ts`
- `angular-client/src/pages/shutdown-page/shutdown-loop.utils.spec.ts`
- `scylla-server/src/shutdown_loop/model.rs`
- `scylla-server/src/shutdown_loop/status.rs`

### L3. Which openings are Faults, and what they're called
*(spec M7, m1, m2)*

**Decision.**
- **Name:** `Shutdown_Open_<A>` when the suspect stretch is a single loop node A, and `Shutdown_Open_<A>_TO_<B>` when it
  runs from first suspect A to last suspect B (e.g. `Shutdown_Open_SIDE_BRB_R_TO_BMS_LATCH`). The Fault is still raised on
  the board of the break reading. This makes "BMS latch" blame for a side BRB press impossible, which is the page's
  anti-goal.
- **No `Shutdown_Open_*` when every suspect is an operator switch:** `glvms`, `tsms`, `hvd`. Keep this as a Rust-only
  constant, `NO_FAULT_LOOP_NODES`. These openings are still recorded in `Verdict` / `Break_Node`. TSMS off in the pits is
  not a fault in the glossary's sense.
- **CAN latch trip:** when the stretch is exactly `can-latch`, raise only the per-fault `CAN_Latch_<FAULT>` Faults, not a
  second `Shutdown_Open_CAN_LATCH` for the same event.
- **Rejected alternative (spec m2):** moving `VCU/Faults/Critical/*` to a socket-handler regex. The regex path registers
  value-0 messages as Faults, which is wrong.

**Acceptance (tracker tests):**
- The BMS GPIO opens: the Fault is `Vcu/Shutdown_Open_SIDE_BRB_R_TO_BMS_LATCH`.
- TSMS opens: no `Shutdown_Open_*` Fault is published, and Verdict is 0.
- A critical fault trips: `CAN_Latch_<FAULT>` is raised, and `Shutdown_Open_CAN_LATCH` is absent.
- HVD is 1 and Acc_Sense is 0: the Fault is `Bms/Shutdown_Open_EM_INTERLOCK_TO_ACC_SENSE`.

**Files:**
- `scylla-server/src/shutdown_loop/tracker.rs`
- spec Data section (see L10)

### L4. Stop heartbeats once nothing is live
*(correctness minor 1, spec m6)*

**Decision.** When no shutdown input is live, publish the Unknown snapshot once (on the change), then skip heartbeats until
a new input arrives. The client then falls back to local after `SERVER_FRESH_MS`, and local computes the same Unknown.

**Acceptance:**
- Tracker test: after every input has gone stale and the Unknown snapshot is out, `evaluate(now + k, true)` returns
  nothing for k up to 10 min.
- A new input resumes publishing.

**Files:** `scylla-server/src/shutdown_loop/tracker.rs`

### L5. Stamp outputs with the car's time base; keep staleness on scylla's clock
*(spec M1)*

**Decision.** This is not the correctness reviewer's monotonic-clock point; that one is S3 below.
- Event publishes carry the newest input `ClientData.timestamp` in the burst. That value is already the car time, or
  scylla's time when the car clock is unset, as `mqtt_processor` decides.
- Heartbeats carry that newest input timestamp plus the time since scylla received it.
- Staleness and grace stay on receive time.

**Why this matters:** the ADR's main argument for the server path is history beside the car's readings.

**Acceptance:**
- Unit test: with an input stamped 10 min before scylla's now, its event publish carries that stamp, and a heartbeat 1 s
  later carries the stamp plus about 1 s.
- Update the "Times are scylla's own" bullet in ADR 0009 (L10).

**Files:**
- `scylla-server/src/shutdown_handler.rs`
- `scylla-server/src/shutdown_loop/tracker.rs` (if the tracker carries the timestamp)

### L6. Make the parity guard real
*(spec M3 and M5)*

**Decision on parity strength:** the regex table check stays, and shared golden vectors are added. Round 2 changes the
algorithm in both copies (L2), so these vectors are its acceptance check.
- Put the vectors in `angular-client/src/pages/shutdown-page/shutdown-loop.vectors.json`. That is inside the client's
  Docker context and in the folder the cargo test already reads.
- Each vector holds raw readings (value, receivedAt, changedAt, intervalMs?) including the fault topics, plus `now`, the
  expected codes and the expected verdict. The derivation runs inside both tests.

**Decision on the CI trigger:** add these paths to the `scylla:` filter in `.github/workflows/scylla-ci.yml`:
- `angular-client/src/pages/shutdown-page/shutdown-loop.model.ts`
- `angular-client/src/pages/shutdown-page/shutdown-page.topics.ts`
- `angular-client/src/pages/shutdown-page/shutdown-loop.vectors.json`

The client CI already covers the folder.

**Acceptance:**
- There are 20 or more vectors, covering:
  - all 5 codes and all 3 verdicts;
  - the L2 cases;
  - cross-board mismatch, before and after a fresh sample;
  - stale boundaries: exactly at `staleAfterMs` is live, and 1 ms past it is not;
  - a reading that went stale and started afresh;
  - unmeasured no-data.
- A Jest spec and a `cargo test` both iterate the file and pass. Enable `resolveJsonModule` in `tsconfig.spec.json` if
  needed.
- Changing one expected code fails both.

**Files:**
- the vectors file
- `shutdown-loop.utils.spec.ts`
- `scylla-server/src/shutdown_loop/status.rs` (tests)
- `.github/workflows/scylla-ci.yml`

### L7. The mock panel must win over scylla
*(spec I3/M9: a regression this branch introduces)*

**Decision.**
- `ShutdownLoopService` exposes `readonly preferServer = signal(true)`. When it is false, `status` skips
  `resolveLoopStatus` and returns local with `source: 'local'`.
- The base mock panel sets it to false while publishing and back to true when it stops.

**Acceptance:**
- Service spec: with fresh server states and `preferServer` false, `source` is `'local'`.
- Mock panel spec: toggling publishing flips the signal.

**Files:**
- `shutdown-loop.service.ts` and its spec
- `components/mock-panel/mock-panel.component.ts` and its spec

### L8. The exported contract the UI and 3D branches code against
*(ui-spec contract §4, spec I1, spec n1)*

**Decision.**
- `NodeStatus` gains `staleAfterMs?: number`, set whenever the node has a reading. For the CAN latch it is the derived
  reading's value.
- Rename the server topics now, before they are stored anywhere real, to match the `Snake_Case` style of the synthetic
  and car topics:
  - `Argos/Shutdown/BreakNode` → `Argos/Shutdown/Break_Node`
  - `Argos/Shutdown/NodeStates` → `Argos/Shutdown/Node_States`

  Rename them in Rust, in `SHUTDOWN_SERVER_TOPICS`, in the spec and in the ADR.

**Acceptance:**
- Utils spec: `staleAfterMs` is 3000 for a 4 Hz reading and 60000 for a reading with one message.
- No string `Argos/Shutdown/BreakNode` or `Argos/Shutdown/NodeStates` remains in code, spec or ADR.
- Tests pass.

**Files:**
- `shutdown-loop.utils.ts`
- `shutdown-page.topics.ts`
- `tracker.rs`
- spec and ADR

### L9. Take the Fault-list gap-check change out of this branch
*(spec m4, correctness minor "gap-check fix")*

**Decision.** Keep the `register_fault` / `clear_fault` extraction, but restore the original comparison and assignment
(`item.last_seen - at > FAULT_MIN_REG_GAP`, `item.last_seen = at`).
- Shutdown Faults don't need the fix: they refresh every second, and their clear is explicit.
- The fix changes the Faults page for every Node. Combined with the regex path registering value-0 messages, it floods the
  ring after any 8 s dropout.
- Drop the long-gap test and the ADR's "Fixed on the way" bullet.
- When this throwaway becomes tickets, file the gap-check fix and the value-0 problem as their own ticket.

**Acceptance:**
- `socket_handler.rs` diff against base touches only the shutdown branch, the extraction and `clear_fault`.
- `shutdown_fault_topics_raise_and_clear` still passes.

**Files:** `scylla-server/src/socket_handler.rs`, ADR 0009

### L10. Docs: make the ADR decide, and bring the spec and glossary in line
*(live major 3 "Rule `a == 0`", spec M6, M8, m3 wording, m7, m8, n6)*

**ADR 0009:**
- **Rules example:** "a Rule like `a < 0.5` on `Argos/Shutdown/Verdict` can notify the pit (Rule values are floats, so
  write `a < 0.5` or `a == 0.0`, not `a == 0`)." Coercion in the Rule engine is out of scope; offer it as an idea ticket.
- **Rejected option "Only the server computes":** use spec M6's wording verbatim, including the Nero note.
- **First consequence:** replace it with spec M8's "Derived telemetry counts as car data" text.
- **Glossary consequence:** "`docs/CONTEXT.md` now lists `Vcu` as a Node, persisted derived topics under Topic, derived
  Faults under Fault, and **loop node**."
- **"Two copies" bullet:** use spec M5's wording, with the vectors path from L6.
- **"Every loop opening is a Fault" bullet:** replace it with L3's rule: operator switches are not Faults; names follow
  the suspect stretch; a CAN latch trip gives only `CAN_Latch_<FAULT>`. Add L1's hold: openings under 500 ms are not
  Faults; a cross-board break needs a fresh sample.
- **"Extra data" bullet:** "five status datapoints per heartbeat while any input is live, plus one set per change burst,
  plus one per active Fault per second; nothing once every input is stale."
- **"Times" bullet:** spec M1's wording.
- **Fault-ending sentence:** "...so the Fault ends when the loop closes or its readings go stale, not when an unrelated
  message arrives." (Unless S1 is done; then say Faults are held while Unknown.)

**ADR 0008:** add spec M8's bullet "Derived telemetry is car data" under "Why this shape".

**Spec:**
- Spec m7: name the `computeLoopStatus(nodes, readings, now)` signature and point at the Rust port.
- Spec m8: step 3 wording for unmeasured nodes and the AIRs.
- Add the `openOnly` CAN latch rule (L2) to step 3, replacing the current CAN latch bullet: "the CAN latch's reading
  shows only an opening: a live tripped fault makes it a measurement point reading 0; otherwise it is treated as
  unmeasured, never a mismatch and never 'no data'."
- The Fault paragraph in Data gets L1 and L3.
- Rename the topics (L8).
- Spec n6: move the `Storage.get` sentence back under the first table, and update the Constraints line to ADR 0007 and
  `docs/CONTEXT.md`.

**`/home/user/Delphi/docs/CONTEXT.md`:** apply spec M8's exact texts for:
- Topic
- Node (adds `Vcu`)
- Fault
- the Flagged-ambiguities Node addendum
- a new **Loop node** entry under a "Shutdown loop" heading

The logic branch owns these edits; the UI branch must not add its own.

**Acceptance:**
- `grep "a == 0" docs/adr/0009*` finds nothing.
- The ADR has no "if the team wants".
- The glossary's Node list includes `Vcu`.
- The spec's Data section matches the topic names and Fault rules the code uses.

## 3. SHOULD FIX (if time)

- **S1** (spec m3): while the verdict is Unknown, don't clear active Faults. Stop refreshing them, and publish their 0
  only when a live evaluation shows them gone. A VCU dropout then no longer looks like a recovery.
- **S2** (live minor 2): schedule the next evaluation at the earliest pending deadline (grace, hold or stale expiry) with
  `sleep_until`, alongside the heartbeat. This cuts the up-to-1 s lag behind the client on time-driven changes. It is
  cheap once L1's deadline exists.
- **S3** (correctness minor, clock): measure staleness, grace and hold intervals on a monotonic clock. On the server, use
  ms since a `tokio::time::Instant` taken at task start. On the client, use `performance.now()` for receive times.
- **S4** (live minor 1): lower `SERVER_FRESH_MS` from 3000 to 2000 ms. The observed max NodeStates age was 1.36 s.
- **S5** (correctness nit, spec M4): add a loop identity. Prepend a 24-bit hash of the ordered loop node ids to
  `Node_States`, or publish `Argos/Shutdown/Loop_Version`. The client falls back to local when it differs.
  - It is a SHOULD because client and scylla ship together in compose, and the parity test pins one checkout.
- **S6** (spec M2): exempt `Argos/Shutdown/` datapoints from `SOCKET_DISCARD_PERCENT` in the socket data loop. The
  default is 0, so this only bites when discard is set, but it is what the ADR's "prefer server" rationale assumes.
- **S7** (live nit): `clear_fault` takes the timestamp and sets `last_seen = max(last_seen, at)`, so a short Fault shows
  its real duration.
- **S8** (live major 2, remainder): when a Fault recurs within `FAULT_MIN_REG_GAP` of its clear, reopen the expired entry
  instead of enqueuing a new one. After L1 and L3, a flapping sensor is the remaining eviction path.
- **S9** (spec m5, n3, n4):
  - publish through `ArgosInserter`;
  - call `heartbeat.set_missed_tick_behavior(MissedTickBehavior::Delay)`;
  - warn once per publish, not once per datapoint, when a channel has no receivers.
- **S10** (spec n2): change the derived reading's key from `VCU/Faults/Critical` to `Argos/Shutdown/CAN_Latch`, which is
  the published topic, so it can't collide with a future car topic.
- **S11** (spec n5): rename `shutdown-loop.server.ts` to `shutdown-loop.scylla.ts`. Angular uses `*.server.ts` for SSR.
- **S12** (spec I5): add a comment above `SHUTDOWN_LOOP` in the client: "Parsed by scylla-server's
  `matches_the_angular_client_loop` test: keep one `id:` per entry and topics as `VCU.X`/`BMS.X`."

## 4. REJECTED

- **Separate or larger Fault ring for shutdown Faults** (live major 2, option 3): over-built. L1 and L3 remove the flood
  at its source, and S8 covers recurrence.
- **Hold-before-raise for clears too:** it delays the "loop closed again" signal. S8 handles flapping without it.
- **Raise Faults only on a closed→open transition** (spec m1, second half): a car that boots with a latched BMS latch
  must still show a Fault.
- **Loop-open should not be a Fault at all, only latch trips:** too narrow. A kill button, BOTS, inertia switch or
  interlock opening is exactly what the pit needs on the Faults page. L3 excludes only operator switches.
- **Make `LoopStatus.source` required** (spec I6): it would churn about 8 sibling fixtures for no behavioural gain. It
  stays optional; the UI renders `source ?? 'local'`.
- **Fall back to local whenever a local reading changed after the server snapshot** (live minor 1, option 1): more
  complex than S4, and S2 removes most of the lag.
- **"TS `live` requires `node.board`; Rust only `topic`" and `===` vs `f32::EPSILON`** (spec M5): no behavioural
  difference. The board is present iff the topic is, and values are integral. The L6 vectors would catch any drift.
- **Rule-engine Int/Float coercion in this branch** (live major 3, "better" fix): pre-existing behaviour. Fix the docs
  (L10) and offer an idea ticket.
- **`GET /data/{topic}/{runId}` has no ORDER BY; NG0100 flood from `current-run-display`:** pre-existing and outside this
  diff. Offer them as tickets.
- **Show value staleness next to server states in this branch** (spec m9, I4): display belongs to the UI branch. See the
  cross-branch notes.
- **Show `source` in the page** (live nit, spec m10): UI branch, cross-branch notes.
- **Switch to a server-only algorithm now** (spec M6, recommendation): not now. Spec M6 itself recommends keeping both
  copies with vectors.

## 5. Cross-branch notes (the API after round 2)

- **Unchanged:**
  - `computeLoopStatus(nodes: readonly LoopNode[], readings: Readings, now: number): LoopStatus`, called with
    `withDerivedReadings(readings, now)`;
  - `resolveLoopStatus(local, server, now)`;
  - `summarizeLoop(statuses)`.
  - The UI and 3D code only read `ShutdownLoopService.status()`, and never use `STALE_AFTER_MS`, `isLive` or board
    timeouts for copy. `STALE_AFTER_MS` is only the 60 s cap.
- **`NodeStatus`:** `{ node, state, value?, ageMs?, staleAfterMs?, mismatch }`. `staleAfterMs` is new and set whenever
  `value` is.
  - Copy should read like "No reading for 12 s (expected within ~3 s)" and name the loop node or topic, not the board.
- **`LoopNode`:** gains `openOnly?: true`, on `can-latch` only.
  - For that node, `value` is the CAN-fault summary (1 = all clear, 0 = tripped), not a loop voltage. Its `state` may be
    inferred, and it is never `mismatch`.
  - The UI should label it as "CAN faults clear" / "tripped", not "reads 1".
  - The node can be `closed`, `suspect` or `downstream-open` without being a measurement point. Draw it like an
    unmeasured node unless `value === 0`.
- **`LoopStatus`:** `{ verdict, nodes, suspects, noDataInStretch, silentBoards, mismatch, airsEnergized, source? }`.
  - `source` stays optional. Render it in `loop-meta` as "Status: scylla" / "Status: this browser" (`source ?? 'local'`).
  - When `source === 'server'`, explainNode explains from the states and says scylla decided. Local values can lag or
    lead by up to about 1 s.
  - `silentBoards` means boards with at least one measured, non-`openOnly` loop node in `no-data`.
- **`ShutdownLoopService.preferServer: WritableSignal<boolean>`:** the UI branch's restyled mock panel must set it false
  while publishing (L7). Change the copy "stale after 60 s" to "goes stale a few seconds after publishing stops". The mock
  publishes at 1 Hz, so a reading goes stale after 5 s.
- **Server topics:** `Argos/Shutdown/{Verdict, Break_Node, Node_States, Mismatch, CAN_Latch}` and
  `Argos/Shutdown/Fault/{Vcu|Bms}/…`. Fault names follow L3. No UI code should hard-code them; use
  `SHUTDOWN_SERVER_TOPICS`.
- **`SHUTDOWN_LOOP` entries:** stay one line per entry, with one `id:` and topics as `VCU.X`/`BMS.X`, because the cargo
  parity test parses them.
  - 3D positions stay in `shutdown-loop.positions-3d.ts`.
  - The UI's planned `short` field may be added inline. The parser ignores unknown keys, but keep it on the same line.
- **Glossary:** "loop node" lands in `docs/CONTEXT.md` from this branch (L10). The UI branch uses the term in copy and
  names, but does not edit CONTEXT.md.
- **Merge order:** logic, then ui (rebased, applying the ui-spec contract §2–§4 and the notes above), then one 3D variant.
