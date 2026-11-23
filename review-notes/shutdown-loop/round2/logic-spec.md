# Round 2 review: throwaway-shutdown-logic-scylla (lens: spec, ADRs, conventions, architecture)

Worktree `/home/user/Delphi/worktrees/argos/throwaway-shutdown-logic-scylla` at `d01e0b9f`, diff `origin/shutdown-loop-page...HEAD`. Paths are relative to the worktree unless absolute.

**What I ran.**
- `cargo test --lib --locked`: 44 passed.
- `cargo fmt --check`: clean.
- `cargo clippy --all-targets`: no warnings in changed files; the warnings it reports are older ones in `lap_timing.rs` and the `rule_structs_test`.
- `ng test --include=src/pages/shutdown-page/**`: 8 files, 116 tests, all pass.
- `git grep` for the old topic names, `a == 0`, "if the team wants" and `shutdown-loop.server`: no hits.

**Glossary.** The glossary edits aren't uncommitted, as the prompt expected. They are committed in Delphi as `9d2f875` ("Glossary: add loop node, Vcu node, derived Argos/Shutdown topics and Faults") on `claude/pensive-babbage-0blz3j`, and the working tree is clean. I reviewed that commit. The UI branch's delta touches no docs, so it hasn't added glossary text of its own.

## Round-1 MUST status

| # | Status | Evidence (spec / ADR / architecture lens) |
|---|---|---|
| L1 coalesce + hold | VERIFIED-FIXED | Coalescing: `COALESCE_MS = 25` and a fixed burst deadline (`shutdown_handler.rs:20,46-50`). Hold: `FAULT_HOLD_MS = 500` plus the `sampled_since` check on `Shutdown_Open_*` (`tracker.rs:27,307-316`). Clears stay immediate. Handler tests replay the sim's VCU order on a virtual clock: `closing_from_a_tsms_break…`, `closing_with_a_slow_bms…`, `resetting_the_bms_latch…`, `a_held_opening_is_raised_once…`, `a_300_ms_opening_is_not_a_fault`, plus `assert_one_status_per_frame`. All pass. The ADR (l.18, l.28) and spec (l.46, l.63) state the 25 ms / 500 ms rules and the accepted cost. |
| L2 `openOnly` CAN latch | VERIFIED-FIXED | `open_only`/`openOnly` exist in both models. The parity test now checks the flag (`model.rs:152-181`). There are vectors for all L2 cases (`CAN latch: …`, 7 vectors). Spec step 3 (l.108) carries the rule. Both `open_from` and `openFrom` filter on `open_only`. |
| L3 Fault names / `NO_FAULT_LOOP_NODES` | VERIFIED-FIXED | `candidate_faults` (`tracker.rs:75-121`) does three things: it names Faults by the suspect stretch (`_TO_`), skips them when every suspect is in `NO_FAULT_LOOP_NODES = ["glvms","tsms","hvd"]`, and skips them when the stretch is exactly `can-latch`. Spec l.59 and ADR l.28 match. See nit N7 on the ADR's "interlocks do" wording. |
| L4 stop heartbeats when nothing is live | VERIFIED-FIXED | Gated by `heartbeat && any_live` (`tracker.rs:225`). The test `heartbeats_stop_once_every_input_is_stale_and_resume_with_new_input` passes. ADR l.29 and spec l.46 match. |
| L5 car time base | VERIFIED-FIXED | `burst_stamp` / `newest` (`tracker.rs:185-188,240-242`). Staleness uses a monotonic `Instant` (`shutdown_handler.rs:100-101`). ADR l.20 uses spec M1's wording. |
| L6 golden vectors + CI trigger | VERIFIED-FIXED, with a caveat | `shutdown-loop.vectors.json` holds 26 vectors. They cover all 5 codes and 3 verdicts, the L2 cases, cross-board mismatch before and after a fresh sample, the stale boundaries (3000/3001 ms and 60000/60001 ms), a fresh start, and unmeasured no-data. Both the vitest spec and `matches_the_angular_client_golden_vectors` iterate the file, and `resolveJsonModule` is set. The `scylla-ci.yml` trigger is correct: the three exact paths are under `scylla:`, and the checkout is a full repo checkout. The Docker build (context `./scylla-server`) runs no tests, so it isn't affected. Caveat: the vectors don't exercise the reading-update half of the algorithm (finding M2). |
| L7 mock panel wins over scylla | PARTIAL (on this branch) | `preferServer` exists and is tested in the service spec. But this branch's `components/mock-panel/mock-panel.component.ts` never sets it: there are no `preferServer` hits outside the service. The wiring and its spec landed in the UI branch's merge commit `6bde6a19`. On this branch the ADR (l.21) and spec step 8 (l.116) already claim the behaviour. See M3. |
| L8 contract (`staleAfterMs`, topic renames) | VERIFIED-FIXED | `Break_Node` and `Node_States` are used in Rust (`tracker.rs:17-18`), in `SHUTDOWN_SERVER_TOPICS`, in the spec and in the ADR. No old names remain. `staleAfterMs` is set at `utils.ts:160` and asserted as 3000/60000. Doc-comment nit at N13. |
| L9 gap check restored | VERIFIED-FIXED | `item.last_seen - at > FAULT_MIN_REG_GAP` and `item.last_seen = at` are restored. The long-gap test and the ADR's "Fixed on the way" bullet are gone. The diff also carries S6 (discard exemption), S7 (stamped clear) and S8 (`reopen_fault`); all three were requested as SHOULDs. `shutdown_fault_topics_raise_and_clear` passes. |
| L10 docs | VERIFIED-FIXED, with new wording issues | ADR 0009 now decides: it contains no "if the team wants" and no `a == 0`. It carries the M6 and M8 texts, the Two-copies bullet with the vectors path, the L3+L1 Faults bullet, Extra data, Times, and the S1 held-while-Unknown sentence. ADR 0008 has the "Derived telemetry is car data" bullet. Spec items m7, m8, the `openOnly` rule, the Data Fault paragraph and n6 (`Storage.get` sentence at l.44, Constraints at l.147) are all done. The glossary covers Topic, Node with `Vcu`, Fault, the ambiguity addendum, and Loop node under "Shutdown loop". New issues: M1, M4, N8, N9, N10. |

All 10 are VERIFIED-FIXED or PARTIAL; none are NOT-FIXED or REGRESSED. These SHOULDs are done and documented: S1, S2, S3, S4 (2 s), S6, S7, S8, S9 (`ArgosInserter`, one warning per publish; `sleep_until` replaces the interval), S10, S11 and S12. S5 (loop identity) isn't done, and the docs don't claim it.

## New findings

Counts: 0 blocker, 0 major, 5 minor, 9 nit.

### M1 · minor · `docs/adr/0009-full-stack-shutdown-loop-status-in-scylla.md:16`, `docs/spec/shutdown-loop-page/spec.md:46`. The recommended Rule `a < 0.5` also fires on Unknown (-1)

- **Issue.** `Verdict` is 1, 0 or -1, and `a < 0.5` is true for -1. The ADR's example "can notify the pit" therefore also notifies on Unknown, and that is not one-off. The tracker heartbeats the status every second while *any* input is live (`tracker.rs:225`). So a silent BMS with a live VCU publishes `Verdict = -1` every second. Because the Rule matches on every tick, it passes any debounce (`rule_structs.rs:294-323`).
- **Failure scenario.**
  1. Make a Rule `a < 0.5` on `Argos/Shutdown/Verdict`, as both docs suggest.
  2. Unplug the BMS, or let 0x95 stop (the sim defines no `sim_freq` for 0x95, spec l.149).
  3. The pit is told the loop is open, although the page says UNKNOWN.
- **Fix.**
  - ADR l.16: "a Rule like `a == 0.0` on `Argos/Shutdown/Verdict` can notify the pit when the loop opens (Rule values are floats: compare with a float literal such as `0.0`; `a == 0` never matches, and `a < 0.5` also matches Unknown, -1)".
  - Spec l.46: "(Rule values are floats: write `a == 0.0` for open; `a < 0.5` also matches unknown)".
- **Evidence.** In evalexpr 13.1, `Eq` is structural (`operator/mod.rs:302-305`), so `0.0 == 0.0` holds and `Float == Int` does not. `a < 0.5` holds for -1.

### M2 · minor · `docs/adr/0009-…:27`, `shutdown-loop.vectors.json`. The golden vectors don't cover the reading update, so "a change to either algorithm fails until the other matches" overclaims

- **Issue.** Each vector supplies finished `Reading`s (`value`, `receivedAt`, `changedAt`, `intervalMs`). The other half of the duplicated algorithm is never run against shared data. That half is `nextReading` (`utils.ts:68-73`) and `Reading::next` (`status.rs:49-72`): rate smoothing (`INTERVAL_SMOOTHING`), the fresh start after a stale gap, and change detection (`===` against `f32::EPSILON`). The same is true of the duplicated constants `INTERVAL_SMOOTHING` and `STALE_INTERVAL_MULTIPLE` (indirectly).
- **Failure scenario.** Change `INTERVAL_SMOOTHING` to 0.5 in `status.rs` only. Both suites stay green: each copy's own `Reading::next` unit test asserts its own numbers. Client and scylla then disagree on staleness, and so on the verdict, near a rate change.
- **Fix** (either one):
  - Add a small `sequences` array to the same file: messages (`topic`, `value`, `t`) and then `now`, with the expected `codes` and `verdict`. Both runners fold the messages through `nextReading` / `Reading::next` before computing. That's about 15 lines per runner.
  - Or narrow the ADR's wording: "…run the same golden vectors for the status from given readings; the reading update (`nextReading` / `Reading::next`) is ported by hand, with matching unit tests".

### M3 · minor · `angular-client/src/pages/shutdown-page/components/mock-panel/mock-panel.component.ts` (no `preferServer`), ADR 0009:21, spec:116. L7 is only half done on this branch

- **Issue.** The judge put the mock-panel wiring in this branch, but the branch only adds the signal. The ADR and spec here already say the page "while the dev mock panel publishes … computes locally".
- **Failure scenario.**
  1. Check out or merge this branch alone, with the backend running.
  2. Publish from the mock panel.
  3. scylla's states override the mock, which is the round-1 regression I3/M9.
- The UI branch's merge commit fixes it (`mock-panel.component.ts:40` and its spec there). It only matters if the stack doesn't land together.
- **Fix.** Move the two `preferServer.set(...)` calls and the mock-panel spec into this branch, so the UI merge only restyles. Or accept it and record in the cross-branch notes that L7 lands in the UI branch.

### M4 · minor · `docs/adr/0008-multi-comp-argos-database.md:18`. The new bullet's criterion contradicts ADR 0008's own laps

- **Issue.** The bullet reads "Only data that isn't a function of a Run (tracks, laps, settings) goes here." Laps are per-Run:
  - ADR 0008 l.3 says "each Run's laps".
  - The `lap` table has `runId` (`argos_migrations/2026-11-15-232433-0000_create_lap/up.sql`).
  - Laps are computed from the Run's GPS.

  So the stated test would put laps in the car database. "Settings" don't exist in `argos-db`. A future maintainer applying the rule would get the opposite of what ADR 0008 decided.
- **Fix.** "**Derived telemetry is car data.** Datapoints scylla computes from a Run's car data alone, such as `Argos/Message` and `Argos/Shutdown/*` (ADR 0009), stay in the car database with the readings they come from. Data Argos draws or keeps itself goes here: tracks, and each Run's laps, which depend on a drawn track and must outlast test-day wipes."

### M5 · minor · `scylla-server/src/shutdown_loop/tracker.rs:257-284` vs spec:63 and ADR:19. "Until its board reads again" is implemented as "until every reading of its board is live", and `board_live` means something else than in the status code

- **Issue.**
  - While the verdict is Unknown, a raised Fault clears only when *all* of its board's non-`openOnly` readings are live. For `Vcu`, that also means all five 0x502 faults (`tracker.rs:262-271`).
  - The spec and ADR say "until its board reads again", which a reader takes to mean any message from it.
  - `compute_loop_status` / `computeLoopStatus` use `boardLive` for "*some* measured reading of the board is live" (`utils.ts:129-130`).

  So two closures with the same name in the same feature mean different things.
- **Failure scenario.**
  1. A `Vcu/Shutdown_Open_*` Fault is raised.
  2. The VCU drops out, and the verdict goes Unknown.
  3. 0x123 comes back but 0x502 doesn't (stale or not sent), while the BMS stays silent, so the verdict stays Unknown.
  4. The Fault stays active on the Faults page with no refresh, for as long as that lasts.

  This is defensible, but nothing documents it.
- **Fix.**
  - Rename the closure to `board_fully_live`, with a one-line comment.
  - Spec l.63: "…held instead, neither refreshed nor cleared until every reading of its board (for `Vcu`, the 0x123 GPIOs and the 0x502 faults) is live again". Mirror it in the ADR.

### N6 · nit · ADR 0009:18. "never on a half-applied frame" overclaims

- **Issue.** The 25 ms deadline is fixed from the first input. A frame from the *other* board, or the 0x502 frame, that starts within ms of the deadline is split across two evaluations. Faults are protected by the hold, but status datapoints can still be half-applied now and then. The test `assert_one_status_per_frame` only covers VCU frames that start a burst.
- **Fix.** "…so the signals of one frame, which arrive within a few ms of each other, are evaluated together."

### N7 · nit · ADR 0009:28. "latches, kill buttons, interlocks, BOTS and the inertia switch do" contradicts HVD

- **Issue.** HVD is `kind: 'interlock'` in the model and spec table, yet it is in `NO_FAULT_LOOP_NODES`.
- **Fix.** "…latches, kill buttons, the MC HVIL and EM interlocks, BOTS and the inertia switch do."

### N8 · nit · spec:51 and spec:69-89. The `Break_Node` index base is ambiguous

- **Issue.** The table is numbered 1–19, and "Node indexes follow the loop order below" doesn't say the published index is 0-based (`b as f32`, `tracker.rs:214`). A Grafana panel or Rule author will be off by one.
- **Fix.** "0-based index of *F* in the loop order (table row # − 1), -1 if none".

### N9 · nit · spec:93. "while any VCU reading is live, the GLV master switch is known closed" is now wrong for the CAN latch

- **Issue.** Step 3 (l.108) correctly says the derived latch is no such evidence, and the code agrees: `boardLive` uses `measured()`, which excludes `openOnly`.
- **Fix.** "while any VCU GPIO (0x123) reading is live".

### N10 · nit · `/home/user/Delphi/docs/CONTEXT.md:46` (Loop node). The entry reads as one entry, but it shows a merge seam and one inaccuracy

- **Seam.** "Not a CAN node, and it may have no CAN device of its own" says the same thing twice.
- **Inaccuracy.** "It has a reading if a board measures the loop voltage just after it" doesn't hold for the CAN latch: its reading is derived from the 0x502 faults and only shows an opening.
- **Suggested single text.** "One element of the series shutdown loop (switch, kill button, latch, interlock, sense point, AIRs), in loop order from the GLV master switch to the AIR coils. Most measured ones have a reading of the loop voltage just after them; the CAN latch's reading is derived from the VCU's critical faults and can only show it open. Not a CAN Node: many have no CAN device of their own. `LoopNode` in the angular-client, `shutdown_loop::model::LoopNode` in scylla-server."
- The rest of the glossary edits match ADR 0009 and the code: Topic, Node with `Vcu`, Fault, and the ambiguity addendum.

### N11 · nit · `angular-client/src/pages/shutdown-page/shutdown-page.topics.ts:55`. The `CanLatch` doc says "1 = closed, 0 = open"

- **Issue.** This contradicts the `openOnly` contract and spec l.54 ("1 = every critical fault clear / 0 = one tripped"). It is the comment the UI and 3D branches read when they label the value, and the judge's cross-branch notes say not to call it "closed".
- **Fix.** "1 = every critical fault clear, 0 = one tripped (not loop voltage: the latch can stay open after its fault clears); absent while unknown."

### N12 · nit · dead code and duplicate constants

- **Dead code.** `Board::fault_node` (`model.rs:16`) and `ShutdownTracker::readings()` (`tracker.rs:352`) have no callers.
- **Alias.** `DERIVED_CAN_LATCH_TOPIC` (`tracker.rs:20`) only aliases `CAN_LATCH_TOPIC`.
- **Duplicate string.** In the client, `'Argos/Shutdown/CAN_Latch'` is defined twice: `SHUTDOWN_TOPICS.VCU.CAN_LATCH` and `SHUTDOWN_SERVER_TOPICS.CanLatch`.
- **Why it matters.** Small things, but they add surface a maintainer has to keep in step.
- **Fix.** Delete the two unused functions and the alias, and define `CanLatch: SHUTDOWN_TOPICS.VCU.CAN_LATCH`.

### N13 · nit · `angular-client/src/pages/shutdown-page/shutdown-loop.utils.ts:18-23`. The `NodeStatus` field docs say "Set only for measured nodes with a reading"

- **Issue.** The code (l.155-160) sets `value`, `ageMs` and `staleAfterMs` whenever the node's topic has a reading, including the CAN latch. Under the file's own `measured()` helper the CAN latch is *not* measured, so the comment points UI authors the wrong way.
- **Fix.** "Set whenever the node's topic has a reading (for the CAN latch, the derived one)."

### N14 · nit · maintainability of the vectors file and one test fixture

- **Vectors file.** `shutdown-loop.vectors.json` is 3315 lines. Each of the 26 vectors repeats all 18 readings in full (about 120 lines each), and nothing explains how to add one. A student adding a case will copy and paste a block, and reviewing a diff of it is hard.
  - **Fix (optional).** A top-level `base` reading set plus per-vector `readings` overrides (`null` to delete), expanded by both runners in about 5 lines each.
- **Test fixture.** Separately, `socket_handler.rs:605,623` uses `Shutdown_Open_TSMS`, a name L3 makes impossible.
  - **Fix.** Use `Shutdown_Open_COCKPIT_BRB`.

## Architecture and Rust idioms (no finding)

- **Task lifecycle.** The task is spawned like `track_handler` (`main.rs:307-317`, `task_tracker.spawn(tokio::spawn(fut))`). It stops on the `CancellationToken` and on `RecvError::Closed`, and only warns on `Lagged`.
- **Channels.**
  - It reads `mqtt_send_socket` and drops its own `Argos/Shutdown/` output on the way back in (`shutdown_handler.rs:113`).
  - The derived CAN latch key can't come in from outside: the prefix filter drops it, and `record`'s input set excludes it.
  - The client doesn't subscribe to it and deletes it in `withDerivedReadings`, so there is no collision with scylla's published `CAN_Latch`.
- **`ArgosInserter`.** It is used for the DB path, as its doc asks.
- **Scheduling.** `sleep_until` replaces the interval. `Scheduler` is a pure state machine, testable on a virtual clock. I checked that `wake` always moves `next_wake` forward or clears a deadline that has passed, so it can't busy-loop.
- **Complexity.** The `Scheduler` and the Fault gating (hold, fresh sample, held-while-Unknown, reopen) are real complexity, but each piece was required by round 1 and has a named test. The over-building I'd push back on is small (N12, N14). I don't see more beyond what round 1 already accepted, the two copies of the algorithm.
