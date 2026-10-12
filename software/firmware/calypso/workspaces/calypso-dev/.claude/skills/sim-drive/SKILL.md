---
name: sim-drive
description: Run calypso-sim against a Siren (Zenoh or MQTT), drive it, and verify what arrives on the wire. Use to reproduce a UI state, feed a consumer, or test a sim change.
---

Read the worktree's `calypso-sim/README.md` first; run with `(cd worktrees/calypso/<branch> && cargo run -q -p calypso-sim -- <flags>)`.

1. **Siren:** a running Argos stack (`:7447` Zenoh, `:1883` MQTT) is someone's; ask before publishing into it. Otherwise start your own: `mosquitto -p 18833 &` (`-u localhost:18833`), or `docker run -d --rm --name sim-zenohd -p 17447:7447 eclipse/zenoh` with `--zenoh --zenoh-conf` pointing at `{mode:"client", connect:{endpoints:["tcp/127.0.0.1:17447"]}, scouting:{multicast:{enabled:false}}}`.
2. **Drive:** `--mock` (heartbeat, filter with `--enable-topic REGEX`), `--key-map FILE --play ACTION` (replay), or `--stream --mock` (JSON-RPC on stdin: `publish`, `set_filter`, `add_topic`, ...).
3. **Verify on the wire:** `mosquitto_sub -p 18833 -t '<topic>' -F '%U %t'`, or a Python `eclipse-zenoh` subscriber. Rate ≈ `1000 / sim_freq` Hz.
4. Stop what you started.
