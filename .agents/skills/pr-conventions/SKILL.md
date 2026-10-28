---
name: pr-conventions
description: Argos specifics for pull requests (base branch, commit format, checks, labels, screenshots, UI QA). Load before opening, updating, or reviewing an Argos PR, alongside open-pr, update-pr, and review.
---

Run every skill helper through the workspace bootstrap, including in fresh shells and sub-agents:

```sh
bash "<absolute-workspace-root>/.delphi/exec.sh" bash "<absolute-installed-skill-folder>/scripts/<script>.sh" <arguments...>
```

Replace the placeholders with the known workspace root, this skill's installed native folder, the script name, and its arguments. Obtain the workspace's absolute path once with `bash .delphi/paths.sh` from the checked-out workspace root. The wrapper sets `DELPHI_ROOT` for every invocation and preserves the caller's working directory; do not assume shell exports persist.


# Argos PR conventions

The shared rules are in the `open-pr` skill; this adds only what is Argos's.

- Base branch: `develop`. Commit format: `^#[0-9]+ - ` (the format in AGENTS.md).
- Checks: `bash "<absolute-workspace-root>/.delphi/exec.sh" bash "<absolute-installed-skill-folder>/scripts/lint.sh" <branch>` (frontend prettier and ng lint, only if angular-client/ changed).
- Labels: one written-by (`by: human` if the user wrote it, `by: ai-assisted` if they gave the substance, `by: ai` if you wrote it) and at least one area label (`frontend`, `backend`, `devops`), besides `open-pr`'s category label.
- Screenshots: `pictures/<branch>/` at the worktree root (git-ignored).
- UI QA: get the branch running with `run-local <branch>`, then drive it with Playwright, using the `browser automation available in this harness` server if `curl -s localhost:9222/json/version` responds, otherwise `browser automation available in this harness`.
