# Round 1 review: live end-to-end QA, `throwaway-shutdown-logic-scylla`

Reviewer lens: live E2E QA. HEAD `2a2ad987`, clean worktree. Shared stack (scylla :8000, client :4200, calypso sim, siren, odyssey-db :5432) was only read: nothing in it was stopped or restarted.

For the controlled sequences I started a separate private stack and removed it afterwards: my own mosquitto (:18830), postgres (:15432), and a copy of this branch's `target/debug/scylla-server` on :8100. The :4200 dev client was pointed at it by routing `assets/env.js`. A raw-MQTT + protobuf publisher drove the frames at 4 Hz, in the sim's VCU frame order (BMS, BOTS, BSPD, HV_C, HVD, IMD, CKPT, INERTIA_SW, TSMS). Scripts and logs are in `/tmp/claude-0/-home-user-Delphi/6e25b80b-05af-58e5-9050-4f2faa446aec/scratchpad/r1-logic-live/`: `scenario.js` with `scenario-log.json`, `rules.js`, `live.js` with `live-samples.json`, `sock.js`, `lag.js` and `disagree.js`.

**What works (verified):**
- All `Argos/Shutdown/*` topics reach clients over the socket. The status topics arrive 6.4/s on the sim, with a max gap of 936 ms, so the 1 s heartbeat holds.
- The page uses `source: 'server'`: 375 of 375 live samples.
- The page falls back to `local` about 3 s after NodeStates stop. I dropped the NodeStates frames with `routeWebSocket`.
- In steady state, local and server agree on verdict and node states in every controlled phase: closed, break at TSMS, mismatch, CAN latch trip, silent → unknown.
- Faults are refreshed every second (last_seen advances), and expire with a single 0 on close and on staleness. The TSMS Fault cleared 3.5 s after the inputs went silent.
- Derived data is stored with the Run (runId 1) and served by `/data/Argos%2FShutdown%2FNodeStates/1`.
- `/datatypes` lists 26 `Argos/Shutdown/*` types.
- Rules can target the new topics and fire.
- No panics or new WARN/ERROR lines in either scylla log.
- scylla RSS stays flat at 100–120 MB over 3 min, at about 36% CPU (debug build).
- Browser heap swings between 18 and 48 MB and is collected; DOM nodes stay at about 800.

## Findings

- **major: every transition raises spurious Faults and writes spurious BreakNode/Verdict datapoints, because the server evaluates after each single message, not per CAN frame**
  - **Where:** `scylla-server/src/shutdown_handler.rs:41-45` (`tracker.record` then `publish(tracker.evaluate(now,false))` on every message), together with `tracker.rs` `evaluate`/`active_faults`, which have no grace before raising `Shutdown_Open_*`.
  - **Issue:** A VCU frame's nine GPIO topics arrive as nine MQTT messages about 1 µs apart. The handler evaluates and publishes after each one, so half-applied frames become status snapshots and Faults.
    - Breaking at TSMS: HVD is published before TSMS, so `Shutdown_Open_HVD` is raised, then cleared 0.1 ms later.
    - Closing the loop: VCU closes before the BMS frame lands, so the four Bms Faults `Shutdown_Open_ACC_SENSE`, `TSIP_SENSE`, `TS_MINUS` and `TS_PLUS` are raised, each for under 1 ms. On the car the BMS frame arrives independently, so this window lasts up to one BMS interval. The spec's cross-board guard (spec.md:104) covers mismatch only, not the break.
    - CAN latch trip: `Shutdown_Open_BOTS` and `Shutdown_Open_MC_HVIL` are raised spuriously.
  - **Effects:**
    - The Faults page shows bogus "loop open" Faults.
    - Rules fire falsely: a rule on the HVD Fault fired when the loop broke at TSMS, and a `Verdict < 0.5` rule fired when the loop *closed*.
    - The stored history carries bogus BreakNode values (14→15→16→17→-1 within 1 ms), which also leaves duplicate x-values at the same ms in `/data`.
    - Data volume is 6.4 status snapshots/s × 5 topics on the sim, against the ADR's "about five datapoints a second".
  - **Repro:** Publish all-closed frames, switch to TSMS=0, HVD=0 with BMS senses at 0, then back to closed. Watch `Argos/Shutdown/Fault/*` on the socket, or the Faults page. This is `scenario.js` / `rules.js`.
  - **Fix:**
    - Coalesce before evaluating: drain the receiver with `try_recv` before `evaluate`, or evaluate on a short (about 20–50 ms) debounce timer instead of per message.
    - Also require a break, and therefore its `Shutdown_Open_*` Fault, to hold for a grace window before raising, plus a cross-board rule like the mismatch one: a break first seen on BMS right after VCU closed should wait for a fresh BMS sample.
    - Add a tracker test that feeds one frame message by message.
  - **Evidence:**
    - Controlled run: 5 real events produced 22 Fault entries. 13 were spurious: 16 Bms `Shutdown_Open_*` rows and 5 `Shutdown_Open_HVD` rows across all runs (`/home/user/Delphi/pictures/throwaway-shutdown-logic-scylla/review-r1/faults-page-private-controlled.png`).
    - Socket log excerpt: `13 BreakNode 12 / Fault/Vcu/Shutdown_Open_HVD 1 / BreakNode 11 / Shutdown_Open_HVD 0 / Shutdown_Open_TSMS 1` and `23.66 BreakNode 14 … Fault/Bms/Shutdown_Open_ACC_SENSE 1 … 0 … BreakNode -1`.
    - Live DB, sim: `Argos/Shutdown/Fault/Vcu/Shutdown_Open_COCKPIT_BRB` has exactly 2 rows, `{1}` at …258384130 and `{0}` at …258384242 (112 µs). The surrounding NodeStates rows step break 10→5→4 within 0.4 ms while one VCU frame (all at …258380593-596) is applied.
    - Rule log: `Rule r1qa-hvd2 triggered` at 05:30:54.69, while the loop was broken at TSMS.

- **major: shutdown Faults flood the shared 100-entry Fault ring buffer and evict real BMS/Charger/MPU Fault history within about 30 s**
  - **Where:** `socket_handler.rs` `register_fault` / `clear_fault` (each raise after a clear enqueues a new entry) with `AllocRingBuffer::<FaultData>::new(100)` (socket_handler.rs:147).
  - **Issue:**
    - Each Fault that clears and comes back is a new ring entry. On the sim's random bits that is about 5 new entries/s.
    - On the live stack the buffer held 85 Vcu shutdown entries out of 100 (spanning 16.7 s), and the oldest entry was 33 s old.
    - 62 of the 85 had a lifetime of 0 ms: raised, then cleared before any heartbeat.
    - Anything real (BMS/Charger/MPU) that expired more than about 30 s ago is gone from the Faults page.
    - The real car's bits are steadier, but a flapping sensor, or finding 1's glitches on every TSMS flip in the pits, have the same effect. The ADR acknowledges "the Fault list gets busier", but not eviction.
  - **Repro:** `node sock.js 60` against :8000, then inspect `faults-last.json` in the same folder. Or open http://localhost:4200/faults and expand Vcu.
  - **Fix:**
    - Raise a shutdown Fault only after it has held for a grace window (this also fixes finding 1).
    - Re-open the expired entry when a Fault recurs within FAULT_MIN_REG_GAP, instead of enqueuing a new one.
    - Or keep shutdown Faults in their own ring (or a larger one) so they cannot evict car Faults.
  - **Evidence:**
    - `ringbuffer size 100 byNode { Vcu: 85, Charger: 5, Bms: 10 } … oldest entry age s 33 … vcu entries 85 span s 16.7 … expired with lifetime <50ms: 62`.
    - Screenshot: `/home/user/Delphi/pictures/throwaway-shutdown-logic-scylla/review-r1/faults-page-live-sim-flood.png`.

- **major: the ADR's advertised Rule `a == 0` on `Argos/Shutdown/Verdict` never fires**
  - **Where:** `docs/adr/0009-full-stack-shutdown-loop-status-in-scylla.md` ("a Rule like `a == 0` on `Argos/Shutdown/Verdict` can notify the pit"); rule evaluation in `rule_structs.rs:270-285`.
  - **Issue:** Rule variables are set as evalexpr Floats, and `Float(0.0) == Int(0)` is false. The derived topics are integer codes (Verdict 1/0/-1, BreakNode, Fault 1/0), so users will write `a == 0` or `a == 1`, and those rules silently never fire. That is a missed pit alert. The int/float quirk itself is older than this branch, but this branch's integer-coded topics and the ADR example are what make it bite.
  - **Repro:** On the private stack, PUT `/rules/add` with three rules on Verdict: `a == 0` (debounce 0), `a < 0.5` (debounce 0) and `a < 0.5` (debounce 2). Subscribe all three, then break the loop. Only the `a < 0.5` rules notified.
  - **Fix:** Change the ADR/spec example to `a < 0.5` or `a == 0.0`. Better, make the rule engine coerce numeric comparisons, for example by setting integral values as Int or normalising the expression, and add a test.
  - **Evidence:** `rule_notify r1qa-verdict2 … values [0]` and `Rule r1qa-verdict-db2 triggered`. There was no notification for `r1qa-verdict` (`a == 0`) across the same break.

- **minor: after server states stop, the page keeps showing the stale server status for up to 3 s while its own fresher local readings say otherwise**
  - **Where:** `angular-client/src/pages/shutdown-page/shutdown-loop.server.ts:16,46` (`SERVER_FRESH_MS = 3_000`; freshness is judged only by the server message's age).
  - **Issue:**
    - I dropped NodeStates frames while the loop went CAN-latch-open → closed. For 2.6 s the page showed "open, cause CAN latch" from the last server snapshot, while local already said closed.
    - The same happens on any NodeStates gap: socket discard percent, broadcast lag, or the scylla task ending.
    - With a 1 s heartbeat, 3 s is generous, and the observed max NodeStates age was 1.36 s.
  - **Repro:** `scenario.js`, phase `closed-drop-server`.
  - **Fix:** Fall back to local when any local reading changed after `server.receivedAt` plus a small margin, or lower `SERVER_FRESH_MS` to about 1.5–2 s.
  - **Evidence:** `50.99 shown server open ccccccsddd… | local closed ccccccccc… DIFF age 1506` … `52.37 … DIFF age 2880` → `52.86 shown local closed`.

- **minor: server status lags time-driven changes (mismatch grace, staleness) by up to the 1 s heartbeat**
  - **Where:** `shutdown_handler.rs:14,55-58`. Evaluation happens only when a shutdown input arrives or on `HEARTBEAT` (1 s).
  - **Issue:**
    - With sim frames sometimes about 900 ms apart, a mismatch whose 500 ms grace expires between messages is published only at the next heartbeat.
    - On the live sim, 36 of 357 samples (100 ms apart) had local and server node codes differing, for at most 800 ms each. The difference was always a mismatch flag.
    - Silence → unknown reached the server 0.5 s after local.
    - The verdict never disagreed.
  - **Repro:** `node disagree.js`. For example, readings were received 888 ms ago and changed 888 ms ago; local flags a mismatch, while the last server snapshot is 839 ms old and has none.
  - **Fix:** Schedule the next evaluation at the earliest pending deadline (grace expiry or stale expiry) using `tokio::time::sleep_until`, alongside the heartbeat.
  - **Evidence:** In `live.js` output, verdict was 375/375 `open/open`, with 28 node-code disagreements, all in `!` flags. `disagree.js`: `maxStreak 8`.

- **nit: a cleared Fault's last_seen is not set to the clear time**
  - **Where:** `socket_handler.rs` `clear_fault`.
  - **Issue:** A break that lasted 250–900 ms shows on the Faults page as Occurred = Last Seen, which reads as 0 s. Last Seen only advances on heartbeats.
  - **Fix:** In `clear_fault`, set `item.last_seen = item.last_seen.max(data.timestamp)`, passing the timestamp in.
  - **Evidence:** In `faults-page-private-controlled.png`, `Shutdown_Open_HVD 05:27:49 05:27:49`. The live ring has 62 entries with a 0 ms lifetime.

- **nit: the page never shows whether the status came from the server or was computed locally**
  - **Where:** `shutdown-page.component.html` and `loop-banner`. `status().source` is computed but never rendered.
  - **Issue:** Operators and QA cannot tell which path the page is on. I needed `ng.getComponent(...)` to check.
  - **Fix:** Add a small "computed by scylla / locally" hint in the banner, or a dev-mode badge.
  - **Evidence:** `controlled-*.png` show no indication. For example `controlled-closed-drop-server.png` (source local) looks identical to `controlled-closed.png` (source server).

- **nit (pre-existing, not from this diff; FYI): NG0100 errors flood the console on /shutdown**
  - **Where:** `angular-client/src/components/current-run-display/current-run-display.component.ts`, a plain `currentRun` field set from a subscription under zoneless change detection.
  - **Issue:** About 9 errors/s on /shutdown (1665 in 3 min), and 0 on /graph. It also happens on the 4201 `throwaway-shutdown-ui` client, so it comes from the shutdown-page base rather than this branch. It makes real console errors hard to spot during QA.
  - **Fix:** Make `currentRun` a signal (or use `toSignal`), on a separate ticket.
  - **Evidence:** `NG0100: ExpressionChangedAfterItHasBeenCheckedError … Previous value: '0'. Current value: '1'. Expression location: _CurrentRunDisplayComponent`. `ng100.js` counts: 4201/shutdown 72, 4200/graph 0, 4200/shutdown 112 (8 s each).

## Notes (not findings)

- The sim never publishes `BMS/Shutdown/*` (0 rows in the DB), so on the shared stack the BMS loop nodes are always no-data and no Bms Faults appear. The BMS paths were exercised only on the private stack.
- The `ForeignKeyViolation` batch error at startup (scylla.log 05:18:46) comes from `Argos/Message` being inserted with run_id -1 before the first Run exists, which is older than this branch. `shutdown_handler::publish` correctly skips `RUN_ID == -1`.
- Rates on the shared stack: derived rows are about 45/s against about 4000/s total ingest (about 1%), so the DB itself is not flooded. Finding 2 is about the Fault ring.
- Screenshots: `/home/user/Delphi/pictures/throwaway-shutdown-logic-scylla/review-r1/` contains `controlled-{closed,break-tsms,closed-2,mismatch,can-latch,closed-drop-server,break-tsms-2,silent}.png`, `faults-page-private-controlled.png`, `faults-page-live-sim-flood.png`, `faults-page-collapsed.png` and `shutdown-page-live-sim.png`.
