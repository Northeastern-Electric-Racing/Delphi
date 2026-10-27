# Argos PR conventions

The shared rules are in the `open-pr` skill; this adds only what is Argos's.

- Base branch: `develop`. Commit format: `^#[0-9]+ - ` (the format in the workspace instructions).
- Checks: `bash scripts/lint.sh <branch>` (frontend prettier and ng lint, only if angular-client/ changed).
- Labels: one written-by (`by: human` if the user wrote it, `by: ai-assisted` if they gave the substance, `by: ai` if you wrote it) and at least one area label (`frontend`, `backend`, `devops`), besides `open-pr`'s category label.
- Screenshots: `pictures/<branch>/` at the worktree root (git-ignored).
- UI QA: get the branch running with the `run-local` skill, then verify the relevant UI with the browser tools available in this Codex host. If browser tooling is unavailable, report the verification that remains.
