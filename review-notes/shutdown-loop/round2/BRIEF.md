# Round-2 reviewer brief (shared by all 12 reviewers)

Argos = NER's trackside telemetry platform (Angular client + Rust scylla-server). Four throwaway branches improve the Shutdown Loop page from PR #1025. They now stack:
- `throwaway-shutdown-logic-scylla` (d01e0b9f): loop-status logic, Rust port, Argos/Shutdown/* topics + Faults. Base for review: origin/shutdown-loop-page.
- `throwaway-shutdown-ui` (6bde6a19): merges logic, plus the shared contract and the UI. Base for review: origin/throwaway-shutdown-logic-scylla (review only its own delta).
- `throwaway-shutdown-3d-procedural` (4df0fb6b) and `throwaway-shutdown-3d-gltf` (40739def): each merges ui, plus its own 3D car view. Base for review: origin/throwaway-shutdown-ui (review only its own delta). The user wants both 3D approaches kept as separate branches; shared files are meant to be byte-identical across them.

Round-1 records (read your branch's): /tmp/claude-0/-home-user-Delphi/6e25b80b-05af-58e5-9050-4f2faa446aec/scratchpad/reviews/round1/ — judge-<logic|ui|proc|gltf>.md (binding fix list; judge-ui.md also holds the SHARED CONTRACT), plus the three round-1 reviews per branch.

Worktrees: /home/user/Delphi/worktrees/argos/<branch> are READ ONLY for you: never edit, commit, stash, checkout, reset or npm install there. You may run tests and builds there (they write only caches/dist). Put scratch scripts/copies under /tmp/claude-0/-home-user/6e25b80b-05af-58e5-9050-4f2faa446aec/scratchpad/r2rev-<your-id>/.

Live stack from run-local (shared; never stop or restart it, never stop other people's servers):
- backend http://localhost:8000 = logic branch's scylla via `cargo run` (log /tmp/argos-run-local/scylla.log; all four branches have identical scylla-server code); Docker project odyssey_scylla-dev (calypso sim publishing random shutdown bits, siren MQTT, postgres; see the worktree's compose/ for ports/creds).
- clients: logic http://localhost:4200, ui :4201, 3d-procedural :4202, 3d-gltf :4203 (page path /shutdown). The dev mock panel sets preferServer=false while it publishes; the live sim overwrites mock values unless you block the socket in your test browser.
- Playwright is pre-installed: `require('playwright')`, `chromium.launch()` (software WebGL). Screenshots at deviceScaleFactor 1 to /home/user/Delphi/pictures/<branch>/review-r2/ (kebab-case); look at every screenshot you take.
- Rust needs: RUSTFLAGS="-L /tmp/claude-0/-home-user/6e25b80b-05af-58e5-9050-4f2faa446aec/scratchpad/libpq"

Every reviewer must:
1. Check every round-1 MUST FIX in your branch's judge file that falls under your lens: VERIFIED-FIXED / PARTIAL / NOT-FIXED / REGRESSED, with evidence.
2. Find new issues in your lens (including regressions caused by round-2 changes and merges).
3. Verify each finding before writing it down; drop speculation.

Output: markdown at the path given in your prompt with sections "Round-1 MUST status" (table) and "New findings" (each: severity blocker/major/minor/nit, file:line or URL+viewport, issue, failure scenario/steps, suggested fix, evidence). Reply with a ≤6-line summary: counts by severity, how many round-1 MUSTs are verified, and the top 3 findings.
