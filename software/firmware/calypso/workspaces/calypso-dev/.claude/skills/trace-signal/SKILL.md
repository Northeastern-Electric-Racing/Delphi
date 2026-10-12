---
name: trace-signal
description: Trace a CAN message or telemetry topic through Calypso (spec → codegen → decode/encode → Siren) and explain why it is or isn't published or simulated. Use for "where does topic X come from", "why don't I see X", or "can this reach the car".
---

Answer from the worktree's code and spec, citing `file:line`:

1. **Spec:** `grep -rn '<topic or id>' Odyssey-Definitions/can-messages/`: the message `id`, `fields` (topics), point `sim` blocks, message `sim_freq`.
2. **Codegen:** `build.rs` → `libs/calypso-cangen/src/` (`validate.rs`, `can_gen_{decode,encode,simulate}.rs`).
3. **Decode:** `src/main.rs` (`DECODE_FUNCTION_MAP`) → `mqtt_handler.rs` or `zenoh_handler.rs`.
4. **Encode:** only `Calypso/Bidir/Command/…` with a `CommandData` payload, and only with `-e`. Nothing else reaches CAN.
5. **Sim:** only messages with `sim_freq` (a period in ms) are simulated; `calypso-sim --list-topics` shows which.

Report the chain and any break in it.
