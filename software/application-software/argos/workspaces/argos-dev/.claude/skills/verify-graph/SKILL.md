---
name: verify-graph
description: Playwright MCP verification of the graph page — modes, controls, topic selection, and data rendering. Use after any change to graph-page components, graph rendering, data flow, or mode switching logic.
user-invocable: true
---

Run from the ticket's worktree. Get the app with `run-local` (its `find-app.sh` gives the client URL as `BASE_URL`); historical runs with data must exist. Screenshots go to `pictures/<branch>/verify-graph/NN-<name>.png` (gitignored).

Per check: `browser_navigate` → `browser_snapshot` (assert) → `browser_click` or `browser_run_code` → `browser_take_screenshot`. Two clicks need `browser_run_code` with a body from `helpers.js`: **selectRun** ("Select this Run" sits under a PrimeNG overlay) and **selectTopic** (a tree click on a leaf navigates away). Run the groups in order; stop and fix at the first failure.

| # | Do | Assert |
|---|---|---|
| 1 | Open `{BASE_URL}/graph` | Header "Real Time"; Pause, Time Range, Select Run, Clear Graph; "X (sec):", Y Min/Max, "Select Range"; no Realtime button |
| 2 | Expand BMS › Pack, selectTopic "Voltage", wait 3s | URL has `?topics=BMS/Pack/Voltage`; a series is drawn |
| 3 | Pause↔Play; Time Range↔Point Range; Tog Sidebar twice | Labels flip ("X (points):" in point range); sidebar hides, then returns |
| 4 | Select Run, then selectRun, wait 3s | Header "Run #N"; Realtime shown; no Pause or Time Range; Y Min/Max remain; x-axis spans more than 30s |
| 5 | Realtime; open Select Range, pick "5 minutes" | 7 options (1, 2, 5, 10, 15, 30 min, 1 hour); header "Hist Range"; Realtime shown, no Pause; x-axis about 5 min |
| 6 | Cycle Realtime → Run → Realtime → "1 minute" → Realtime | Headers match each mode; no console errors (`browser_console_messages`) |
| 7 | In real time, wait 10s | x-axis about 30s, not the whole session (historical auto-fit doesn't leak) |

Report a checklist (one line per group, `[x]` or `[ ]` with the failure) and the screenshot folder.
