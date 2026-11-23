# Round 1, correctness review: throwaway-shutdown-logic-scylla (base origin/shutdown-loop-page)

Checks run: `cargo test` (44 passed) and `ng test` on shutdown-page specs (80 passed). Differential check of the TS
`computeLoopStatus(withDerivedReadings(...))` against the Rust `compute_loop_status(apply_derived_readings(...))`:
100,000 random reading sets with boundary ages (499/500/501, 2999/3000/3001, 9999/10000/10001, 59999/60000/60001),
fractional intervals, partial presence and tripped faults. Result: **0 differences** in node codes or verdict (all 5 codes
and all 3 verdicts covered). Harness: `scratchpad/r1-logic-correctness/` (`gen.js`, `ts-harness.js`, `harness/` crate that
`#[path]`-includes the worktree's `shutdown_loop/*.rs`, `cmp.js`). The two algorithms agree, so the findings below affect both.

- **major** · `scylla-server/src/shutdown_handler.rs:370-374`, `scylla-server/src/shutdown_loop/tracker.rs:170-181`
  - **Issue:** scylla evaluates the loop, and raises or clears Faults, after *every* input message. A CAN frame arrives as one
    MQTT message per signal (0x123 is 9 topics), so the tracker sees partial frames that mix the new frame with the old one.
    The break jumps node by node through those partial states. Each jump raises a `Shutdown_Open_*` (or `Shutdown_Mismatch_*`)
    Fault and clears it microseconds later. The mismatch grace does not help: when the break moves onto a node that has read 0
    for a long time, its old `changedAt` already passes the 500 ms check.
  - **Failure scenario (real car):** the BMS latch is reset while every VCU bit read 0, and the next 0x123 frame has every
    bit 1. scylla publishes `Shutdown_Open_IMD_LATCH`=1→0, `_BSPD_LATCH`, `_MC_HVIL`, `_BOTS`, `_INERTIA`, `_COCKPIT_BRB`,
    `_TSMS` and `_HVD`, each raised and cleared. That is 8 spurious Faults, plus Verdict/BreakNode/NodeStates rows for each
    one. Every clear expires its ring-buffer entry, so the next raise `enqueue`s a new one. The 100-entry fault ring buffer
    fills with these Faults, which evicts real BMS/Charger faults and resets their `occured_at` when they come back. With
    `SCYLLA_SOCKET_DISCARD_PERCENT>0`, the client in server mode can be left showing a mid-frame NodeStates for up to 1 s.
  - **Evidence:**
    - Harness `harness partial` (frame published topic by topic):
      `after VCU/Shutdown/BMS_GPIO -> …Shutdown_Open_IMD_LATCH = [1.0]` / `after VCU/Shutdown/IMD_GPIO -> …Shutdown_Open_IMD_LATCH = [0.0]`,
      and the same through `…Shutdown_Open_HVD`.
    - Live stack, run 1: 1720 raises, of which 270 lasted under 50 ms. The DB shows
      `Shutdown_Mismatch_BOTS 1795411333355246 {1}` then `1795411333355298 {0}`, a 52 µs Fault, raised although the grace
      window is 500 ms.
    - The live `faults` socket shows 100/100 entries in the ring buffer, 85 of them shutdown Faults, and 52 of those are
      single-message (`last_seen == occured_at`).
    - Made worse by an existing bug: `GET /data/{topic}/{runId}` has no ORDER BY (`services/data_service.rs:16-24`), so
      these sub-millisecond 1/0 pairs come back in either order. The graph page showed `Shutdown_Mismatch_BOTS` stuck at 1
      for 57.7 s.
  - **Suggested fix:**
    - Coalesce inputs: mark the tracker dirty on a message and evaluate on a short tick (for example 20–50 ms after the
      first input of a burst), or evaluate once per received frame.
    - Also, or instead, give Fault raise and clear a hold-down: active only after it has held for `MISMATCH_GRACE_MS`.
    - Add a tracker test that feeds a frame topic by topic.

- **major** · `angular-client/src/pages/shutdown-page/shutdown-loop.utils.ts:78-97,156`, `scylla-server/src/shutdown_loop/status.rs:83-107,229-233`, `scylla-server/src/shutdown_loop/tracker.rs:67-76`
  - **Issue:** the derived CAN latch reading is the latch's *own* state (no critical fault, so 1). It is not the loop voltage
    after the latch, but the algorithm treats it as a measurement point like the GPIOs. Any break upstream of it puts the
    CAN latch downstream of *F* while it still reads 1. After 500 ms (same board, so no sampled-after check) it is flagged as
    a **mismatch**, for as long as the break lasts.
  - **Failure scenario:** a marshal presses a side BRB, or the BMS/IMD/BSPD latch trips. `BMS_GPIO`=0, every later GPIO is
    0, and the CAN faults are all clear. The page shows the "mismatch" header warning on the CAN latch. scylla publishes
    `Argos/Shutdown/Mismatch`=1 and keeps the `Vcu/Shutdown_Mismatch_CAN_LATCH` Fault active (repeated every second, stored
    with the Run). This is the "sensor/wiring inconsistency" alarm that the page's anti-goals say must not appear, on a
    routine event. The same assumption means a CAN latch that stays latched after its fault clears would read 1, so the
    blame would go to MC HVIL.
  - **Evidence:** a case with all 9 GPIOs at 0 (held 10 s), all 5 faults live at 0 and BMS senses at 0 gives these codes in
    both implementations: TS `[0,1,1,1,2,2,4,2,…]` and RS `[0.0,1.0,1.0,1.0,2.0,2.0,4.0,…]` (index 6 = can-latch,
    code 4 = mismatch). The partial-frame harness also clears `Shutdown_Mismatch_CAN_LATCH` while the BMS latch is open,
    which shows it was active. The live run has 60 raises of `Shutdown_Mismatch_CAN_LATCH`. Tests hide it: `openFrom`
    (`shutdown-loop.utils.spec.ts:28-31`) and `open_from` (`status.rs:307-313`) set the CAN latch topic to 0 directly
    instead of deriving it from faults.
  - **Suggested fix:**
    - Use the derived latch only as evidence of opening. A tripped fault makes it a live 0. All clear makes it unmeasured:
      it is not a measurement point and never a mismatch, and it is not counted as no-data for the verdict.
    - At minimum, never flag a mismatch on the CAN latch node.
    - Add tests that derive the latch from fault readings with an upstream break.

- **minor** · `scylla-server/src/shutdown_loop/tracker.rs:140-168`, `scylla-server/src/shutdown_handler.rs:384-387`
  - **Issue:** once any shutdown reading has arrived, every heartbeat publishes Verdict, BreakNode, NodeStates (19 floats)
    and Mismatch to the socket and the DB, forever, even after every input has gone stale. `readings` is never emptied, and
    the derived topic is reinserted too.
  - **Failure scenario:** the car is powered off with scylla left running in the garage overnight. That is about 4 rows/s,
    roughly 345k rows a day of `Verdict=-1` / all-no-data under the last Run, plus a socket emit every second.
  - **Evidence:** `if self.readings.is_empty() { return Vec::new(); }` is the only gate.
    `stale_inputs_clear_faults_and_go_unknown` shows it still publishes at +61 s.
  - **Suggested fix:** once every input is stale and the Unknown snapshot has been published, publish only on change, or
    drop stale readings from the map.

- **minor** · `scylla-server/src/socket_handler.rs:409-432,448` (fault gap-check fix)
  - **Issue:** the corrected gap check (`at - item.last_seen > FAULT_MIN_REG_GAP`) now works, but the regex path registers
    a "fault" for *every* message on `BMS/Faults/*` and `Charger/Box/F_*`, whatever its value, including 0 (not tripped).
    Before the fix every topic held one entry forever. Now, after any gap of more than 8 s in a topic, every such topic adds
    a new entry and expires the old one.
  - **Failure scenario:** a telemetry dropout of more than 8 s (trackside Wi-Fi), a car power cycle, or a fault frame sent
    slower than 1 per 8 s. 10 BMS + 5 charger topics give about 15 new entries per gap, mostly value-0 "faults", and about 7
    gaps evict the whole 100-entry buffer.
  - **Evidence:** live `BMS/Faults/Critical/Cell_Voltage_Low` has values `{0.0: 383, 1.0: 379}`, all routed through
    `register_fault`. The regex branch never reads `data.values`.
  - **Suggested fix:** skip value 0 in the regex branch (as the DTI branch already does), or treat 0 as a clear, like the
    new shutdown path. Otherwise state the blast radius in the PR.

- **minor** · `shutdown-loop.utils.ts:156,171`, `status.rs:231,268`
  - **Issue:** "sampled after the break" is skipped for any same-*board* pair. The CAN latch (0x502) and the GPIOs (0x123)
    are both `VCU` but are different frames sampled independently, which is the very case the amended spec gives as the
    reason. It moved staleness to per frame for the same reason.
  - **Failure scenario:** if 0x123 is slower than 2 Hz, a CAN fault trips (break = can-latch). The downstream GPIOs still
    hold a pre-break 0x123 sample of 1, and after 500 ms they are flagged as mismatches (and Faults on the server) until the
    next 0x123 frame. The sim runs both frames at 4 Hz, which hides it.
  - **Suggested fix:** compare by source frame, not board. For example, give `LoopNode` a `frame` key, or treat the derived
    CAN latch as its own source.

- **minor** · `scylla-server/src/shutdown_handler.rs:369,385`, `status.rs:41-43`, `shutdown-loop.service.ts:37`
  - **Issue:** staleness, rate learning and grace windows all use wall-clock time (`Utc::now()` / `Date.now()`).
  - **Failure scenario:** a backward clock step, such as NTP correcting a Pi base station that booted with fake-hwclock
    time, makes `now - received_at` negative or small. Readings then stay "live" for the size of the step after the car
    goes silent, which shows stale values as live (an anti-goal) and keeps Faults active. A forward step makes everything
    stale at once.
  - **Suggested fix:** use `tokio::time::Instant` (server) and `performance.now()` (client) for these intervals, and keep
    wall time only for datapoint timestamps.

- **nit** · `angular-client/src/pages/shutdown-page/shutdown-loop.server.ts:129-136`
  - **Issue:** server NodeStates are applied to nodes by position, guarded only by the length. A client and scylla from
    different builds with the same node count in a different order (for example a reorder like the CAN latch move) would
    paint the server's states onto the wrong nodes without any sign. The `cargo test` match only holds within one checkout.
  - **Suggested fix:** publish a loop-definition hash or version, or the BreakNode id, and fall back to local on a mismatch.
