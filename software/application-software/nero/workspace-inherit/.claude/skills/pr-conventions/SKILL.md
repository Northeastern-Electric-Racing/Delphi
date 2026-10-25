---
name: pr-conventions
description: Nero specifics for pull requests (base branch, commit format, checks, labels, screenshots, UI QA). Load before opening, updating, or reviewing a Nero PR, alongside open-pr, update-pr, and review.
user-invocable: false
---

# Nero PR conventions

The shared rules are in the `open-pr` skill; this adds only what is Nero's.

- Base branch: `develop`. Commit format: `^#[0-9]+ ` (the format in CLAUDE.md).
- Checks: in the worktree, `clang-format --dry-run --Werror` on the C++ files changed since `origin/develop` (not under `deps/`); stop on any error.
- Labels: only `open-pr`'s category label.
- Screenshots: `playwright/test-results/<case>/` in the worktree, never committed.
- UI QA, only if QML or a page changed: in the worktree's `playwright/`, add or update a case for each changed page, run `npm test`, and inspect `test-results/<case>/` (CLAUDE.md's Playwright section).
