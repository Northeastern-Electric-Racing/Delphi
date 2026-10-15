---
name: sim-drive
description: Run calypso-sim against a private Siren and check what arrives on the wire. Use to test a sim change or feed a consumer.
---

Modes and flags are in `worktrees/calypso/<branch>/calypso-sim/README.md`. The sim defaults to MQTT on `localhost:1883`, which may be someone's running Argos stack (`:1883` MQTT, `:7447` Zenoh): ask before publishing there.

1. Start your own broker in the background: `mosquitto -p 18833`.
2. Run: `(cd worktrees/calypso/<branch> && cargo run -q -p calypso-sim -- -u localhost:18833 <mode flags>)`.
3. Check: `mosquitto_sub -p 18833 -t '<topic>' -F '%U %t'`; expect about `1000 / sim_freq` messages a second.
4. Stop what you started.

For Zenoh, pass `--zenoh --zenoh-conf FILE` with multicast scouting off and a private router endpoint, or it joins whatever router is running.
