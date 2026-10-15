---
name: trace-signal
description: Trace a CAN message or topic through Calypso and explain why it is or isn't published, simulated, or sent to the car. Use for "where does topic X come from", "why don't I see X", or "can this reach the car".
---

In `worktrees/calypso/<branch>/`, cite `file:line` for each link:

1. **Spec:** `grep -rn '<id or topic prefix>' Odyssey-Definitions/can-messages/`. Topic names can be templates (`BMS/PerCell/Alpha/{4}/Volts/{5}`), so grep an id or a prefix.
2. **Codegen:** `build.rs` → `libs/calypso-cangen/`.
3. **Decode:** `src/main.rs` (`DECODE_FUNCTION_MAP`) → `mqtt_handler.rs` or `zenoh_handler.rs`.
4. **Encode:** only `Calypso/Bidir/Command/…` with a `CommandData` payload, and only with `-e`.
5. **Sim:** only messages with `sim_freq` (a period in ms); `calypso-sim --list-topics` shows which.

Report the chain and any break in it.
