---
name: pr-conventions
description: Nero specifics for pull requests (base branch, commit format, checks, labels, screenshots, UI QA). Load before opening, updating, or reviewing a Nero PR, alongside open-pr, update-pr, and review.
user-invocable: false
---

# Nero PR conventions

The shared rules are in the `open-pr` skill; this adds only what is Nero's.

- Base branch: `develop`. Commit format: `^#[0-9]+ ` (the format in CLAUDE.md).
- Checks: in the worktree, `clang-format --dry-run --Werror` on the C++ files changed since `origin/develop` (not under `deps/`); stop on any error.
- Labels: none.
- Screenshots: `/tmp/nero-shots/<branch>/`, never in the repo.
- UI QA, only if QML or a page changed: build, run against mock telemetry, capture each changed page with the screenshot tool (CLAUDE.md's Screenshots), and inspect the shots.
