---
name: run-local
description: Bring up the local Argos environment for running or testing — Docker backend (right profile for what changed) + Angular client on the next free port. Use whenever you need to actually run the app locally, not just start the frontend.
allowed-tools: Bash(lsof:*), Bash(npx ng serve:*), Bash(curl:*), Bash(sleep:*), Bash(pkill:*), Bash(tail:*), Bash(timeout:*), Bash(docker ps:*), Bash(./argos.sh:*)
user-invocable: true
---

## Context

Current directory:
`!pwd`

Running Angular instances:
`!lsof -i :4200-4210 -sTCP:LISTEN 2>/dev/null | grep LISTEN || echo "None"`

Docker backend status (scylla-server on :8000/8010/.../8090, one per STACK_OFFSET):
`!for p in 8000 8010 8020 8030 8040 8050 8060 8070 8080 8090; do if lsof -nP -i :$p -sTCP:LISTEN 2>/dev/null | grep -q LISTEN; then c=$(docker ps --filter "publish=$p" --format '{{.Names}}' | head -1); echo "  :$p UP (${c:-host listener, likely cargo run})"; fi; done | grep . || echo "Backend DOWN (no listeners in 8000..8090 step 10)"`
`!docker ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null | grep -E '(scylla|mosquitto|db|calypso)' | sort || echo "No Argos containers running"`

## Task

Start the Angular dev client on the next free port, and make sure the backend is running: `ng serve` alone silently gives false negatives for UI checks.

**Ports are not fixed.** The backend is on `:$((8000 + 10*STACK_OFFSET))` (see `compose/README.md`) and the client takes the first free port in 4200–4210. Use the ports from the Context scan above, and say so in your summary if the backend isn't on `:8000`.

### Step 1: Confirm the backend is up, on the right profile

Pick the profile per the Local Development rules in CLAUDE.md. If Docker is running scylla-server but the checkout has `scylla-server/` changes, flag it: the UI test will hit a stale binary.

If the backend is DOWN, either:
- suggest the user run `! ./argos.sh <profile> up` so output streams into the conversation, or
- if they've authorized container starts, run `./argos.sh <profile> up -d` and wait for `curl -s http://localhost:<port>/datatypes` to respond.

Don't continue silently while it's down, unless the change is pure static/style with no server-driven content. Then say in the summary that only layout was verified.

### Step 2: Start the client
If a server is already running for this repo's `angular-client/`, report its port. Otherwise start one on the first port in 4200–4210 with no listener (`lsof -i :<port> -sTCP:LISTEN`):
```bash
cd <angular-client-path> && npx ng serve --port <port> > /tmp/ng-serve-<port>.log 2>&1 &
```

### Step 3: Wait for readiness
The first compile takes ~10-60s, so don't poll with curl:
```bash
timeout 120 tail -f /tmp/ng-serve-<port>.log | grep -m1 -E "(Compiled successfully|Local:.*localhost)"
```

### Step 4: Confirm and report
Confirm a 200 from `curl -s -o /dev/null -w "%{http_code}" http://localhost:<port>`.

Report: **Dev client ready at http://localhost:<port>**, and state whether the backend is UP or DOWN.
