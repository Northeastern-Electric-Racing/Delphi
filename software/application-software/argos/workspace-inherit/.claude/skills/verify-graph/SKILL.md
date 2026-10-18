---
name: verify-graph
description: Playwright CLI verification of the graph page — modes, controls, topic selection, and data rendering. Use after any change to graph-page components, graph rendering, data flow, or mode switching logic.
user-invocable: true
---

Get the ticket's branch running with `run-local <branch>`; that branch's client URL is `BASE_URL`. Then `RUN=$(bash scripts/seed.sh)`: the id of a 50-hour run spanning two midnights, made once in the local database and shared by parallel checks, so other sessions starting runs can't change which run you check. Screenshots go to `pictures/<branch>/verify-graph/NN-<name>.png` (gitignored).

Drive the page with `playwright-cli` (`npm i -g @playwright/cli`): `bash scripts/open.sh <branch> "$BASE_URL/graph"` opens a session named after the branch, with its snapshot and console files in `pictures/<branch>/verify-graph/playwright-cli/`; then `P="playwright-cli -s=<branch>"`.

Per check: act with `$P click "button:has-text('Pause')"` (or `role=combobox[name='Quick Select']`, `role=option[name='5 minutes']`, or a ref from a snapshot) → assert with `$P find "<text>"` or `$P snapshot` → `$P screenshot --filename=pictures/<branch>/verify-graph/NN-<name>.png`. To pick the seeded run, click Select Run, then `bash scripts/select-run.sh <branch> $RUN`. Run the groups in order; stop and fix at the first failure. `$P close` at the end.

| # | Do | Assert |
|---|---|---|
| 1 | Open `{BASE_URL}/graph` | Header "Real Time"; Pause, Time Range, Select Run, Clear Graph; "X (sec):", Y Min/Max, "Historical:" Quick Select and Custom; no Realtime button |
| 2 | Expand BMS › Segment_Total_Volt (click the tree toggles), click leaf "0", wait 3s | URL has `?topics=BMS%2FSegment_Total_Volt%2F0`; a series is drawn |
| 3 | Pause↔Play; Time Range↔Point Range; Tog Sidebar twice | Labels flip ("X (points):" in point range); sidebar hides, then returns. Leave it playing, in time range |
| 4 | Select Run, then select-run.sh, wait 3s | Header "Run #$RUN"; Realtime shown; no Pause or Time Range; Y Min/Max remain; x-axis spans the run's 50 hours, with a dated day-boundary line at each midnight |
| 5 | Realtime; open Quick Select, pick "5 minutes" | 11 options (1, 2, 5, 10, 15, 30 min, 1, 2, 4, 8, 24 hours); header "Historical"; Realtime shown, no Pause; x-axis about 5 min, or since the data starts |
| 6 | `$P console --clear`; cycle Realtime → Run → Realtime → "1 minute" → Realtime | Headers match each mode; no console errors in `$P console error` beyond develop's: NG0100 in `_MessagesPerSecondComponent` and, after mode switches, in `_GraphPageComponent` |
| 7 | In real time, wait 10s | x-axis about 30s, not the whole session (historical auto-fit doesn't leak) |

Report a checklist (one line per group, `[x]` or `[ ]` with the failure) and the screenshot folder.
