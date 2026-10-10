---
name: review
description: Review changes since a fixed point (commit, branch, tag, or merge-base) for bugs, standards and bloat, spec fit, and UI behavior, in parallel read-only subagents. Use when the user wants to review a branch, a PR, or work in progress, asks to "review since X", or at the end of the workflow's Execute phase.
---

1. Fixed point: use the one given, else ask. Run `git add -N .` so new files show, then confirm `git diff <ref>` is non-empty.
2. Spec: use a path given, else `.workflow/spec.md`, else the issue referenced in the commits. If there is none, skip the Spec axis.
3. Standards: the workflow skill's `standards.md`, plus the CLAUDE.md files covering the touched paths.
4. Spawn read-only subagents in parallel. Give each the diff command, and ask each to stay under 400 words:
   - Bugs: correctness, edge cases, error handling.
   - Standards: violated rules by file, dead code, speculative abstraction, and comments that break the comment rule. Skip what formatters and linters enforce.
   - Spec: missing or partial done criteria, anything from Non-goals, and wrong behavior. Quote the spec line.
   - UI QA, only if QML or a page changed: in `playwright/`, add or update a case for each changed page, run `npm test`, and inspect `test-results/<case>/`.
5. Report one table, most severe first, and end with the finding count. Note "UI QA: skipped, no UI change" when it applies.

| Severity | Axis | File:line | Problem | Fix |
|---|---|---|---|---|

Don't fix anything unless the user asks.
