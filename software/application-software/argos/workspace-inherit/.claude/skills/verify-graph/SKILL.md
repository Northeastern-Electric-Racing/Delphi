---
name: verify-graph
description: Playwright CLI verification of the graph page — modes, controls, topic selection, and data rendering. Use after any change to graph-page components, graph rendering, data flow, or mode switching logic.
user-invocable: true
---

Get the branch's client running with `run-local <branch>`; its URL is `BASE_URL`. Then run the base checks:

```
bash scripts/check.sh <branch> "$BASE_URL"
```

It seeds a 50-hour run spanning two midnights (once, shared by parallel checks), opens a `playwright-cli` session named after the branch, and runs `scripts/check.js`. That covers: page loads in real time, a topic from the tree draws live, the seeded run, historical Quick Select, back to real time, and no console errors beyond develop's NG0100. It prints `[x]`/`[ ]` per check and exits 1 on a failure. Each `look:` line names a screenshot and what it should show: open it and judge it, since only a picture shows whether a chart is right.

Go further where the diff points, by hand in the same session (`P="playwright-cli -s=<branch>"`): controls the diff touches (Pause↔Play, Time Range↔Point Range, Tog Sidebar, Tog Mult Yaxis, Y Min/Max, Custom range, Clear Graph), zoom, pan and hover, several topics, or mode switching for console errors. Reproduce a failed check the same way before fixing it; `check.js` has its steps.

- Act: `$P click "button:has-text('Pause')"`, `role=combobox[name='Quick Select']`, `role=option[name='5 minutes']`, or a ref from `$P snapshot`.
- Assert: `$P find "<text>"`, `$P snapshot`, `$P console error`; longer Playwright code with `$P run-code "async (page) => {…}"`.
- The seeded run: click Select Run, then `bash scripts/select-run.sh <branch> $(bash scripts/seed.sh)`.
- Screenshots: `$P screenshot --filename=pictures/<branch>/verify-graph/NN-<name>.png` (gitignored).

When a hand check keeps coming back, add it to `check.js`. Report `check.sh`'s lines plus one line per hand check, and the screenshot folder. `$P close` at the end.
