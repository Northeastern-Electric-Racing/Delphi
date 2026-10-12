# Design

Build a matrix as a markdown table:

- Rows are options, at most 4. Row 1 is the simplest option that meets the MVP, and it is the baseline.
- Columns are criteria, at most 6. Pick the ones that tell the options apart:
  - Done criteria: meets them.
  - Simplicity: fewest moving parts.
  - Ease of change: cost of the next change.
  - Fit: matches existing patterns, components, and conventions.
  - Shape: size of the change, meaning files touched and blast radius.
  - Risk: what could break, and how we'd know.
- Each cell is `better`, `same`, or `worse` than the baseline, plus a few words of evidence. No scores or weights.

| Option | Simplicity | Fit | Shape |
|---|---|---|---|
| A. Reuse existing service (baseline) | same: 1 file | same: existing pattern | same: 1 file |
| B. New shared util | worse: new abstraction | worse: new pattern | worse: 3 new files |

1. For a hard call, spawn one read-only subagent per option to check feasibility.
2. Recommend one option with a one-line reason.
3. List the files to touch and what changes in each.
4. Save to `design.md`.
