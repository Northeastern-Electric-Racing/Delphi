---
name: workflow
description: Run a task through three gated phases (Spec, Design, Execute). Use when starting or resuming a task, when the user says "/workflow", mentions spec/intent/MVP/design/execute, or asks to revert to an earlier phase.
---

1. Spec: pin down the intent and the MVP. See `spec.md`.
2. Design: pick the simplest design with a matrix. See `design.md`.
3. Execute: implement, then review. See `execute.md`.

Follow `standards.md` in every phase and pass it to every subagent.

- Start every reply with a phase marker, e.g. `Phase: Spec (1/3)`.
- End each phase by asking **approve / revise / revert**. Advance only on approve.
- Save each phase to `.workflow/<phase>.md` at the worktree root, and add `.workflow/` to the file `git rev-parse --git-path info/exclude` prints.
- To resume, read `.workflow/` and continue from the current phase.

## Revert to phase X

1. Move later phase files into `.workflow/archive/<timestamp>/`.
2. If code was written, run `git add -N .` and show `git diff --stat <base>`, using the base in `execute.md`.
3. Only if the user confirms, reset to the base and remove files added since.
