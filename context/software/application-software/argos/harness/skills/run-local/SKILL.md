---
name: run-local
description: Bring up the local Argos environment for running or testing — Docker backend (right profile for what changed) + Angular client on the next free port. Use whenever you need to actually run the app locally, not just start the frontend.
---

Make sure a backend is up on the right profile (see Local Development in CLAUDE.md). The backend listens on `:$((8000 + 10*STACK_OFFSET))`, so find it in 8000–8090 rather than assuming 8000, and flag a Docker scylla-server when `scylla-server/` has changes. If it's down, ask the user to start it. Then reuse a running client or start `npx ng serve --port <first free port in 4200–4210>` in the background, wait for "Compiled successfully" in its log, and report the URL and whether the backend is UP.
