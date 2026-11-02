---
name: pr-conventions
description: Argos specifics for pull requests (base branch, commit format, checks, labels, screenshots, UI QA). Load before opening, updating, or reviewing an Argos PR, alongside open-pr, update-pr, and review.
user-invocable: false
---

# Argos PR conventions

The shared rules are in the `open-pr` skill; this adds only what is Argos's.

- Base branch: `develop`. Commit format: `^#[0-9]+ - ` (the format in CLAUDE.md).
- Checks: `bash scripts/lint.sh <branch>` (frontend prettier and ng lint, only if angular-client/ changed).
- AGLint, after `npm ci` in angular-client/: `bash scripts/aglint.sh <branch>` runs `aglint check --fast` once from the worktree root over every subproject with an `.aglint/` (angular-client, scylla-server), skipping those the branch doesn't touch, against `origin/develop`. It exits 0 PASS, 4 WARN, 1 FAIL, 2 or 3 if AGLint itself failed (show the user). It prints nothing when `aglint` isn't on PATH or no subproject has an `.aglint/`; say nothing then. Run other `aglint` commands from the worktree root with `--root <subproject>`: `aglint explain <id> --root angular-client` gives a signal's evidence and fix; the combined report is in `.aglint/out/`.
  - FAIL: fix the cause and rerun, or stop and show the user the failing signals.
  - WARN: show the user the top signals, then fix them, or ask the user before `aglint accept <id> --reason "…" --expires <YYYY-MM-DD>`. Never accept on your own; commit `.aglint/accepted.yml` with the change.
  - PR body: one Testing line with the verdict and any accepted signals.
- Labels: one written-by (`by: human` if the user wrote it, `by: ai-assisted` if they gave the substance, `by: ai` if you wrote it) and at least one area label (`frontend`, `backend`, `devops`), besides `open-pr`'s category label.
- Screenshots: `pictures/<branch>/` at the worktree root (git-ignored).
- UI QA: get the branch running with `run-local <branch>`, then drive it with Playwright, using the `playwright-cdp` server if `curl -s localhost:9222/json/version` responds, otherwise `playwright`.
