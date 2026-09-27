# Delphi — developing it

Delphi stores NER's AI-harness context. Each workspace is a folder `software/**/workspaces/<name>/`
on `main`; branch `ws/<name>` has that folder as its repo root, and `ci/sync.sh` keeps the two in
sync with `git merge -Xsubtree=<folder>` both ways. There is no CLI: a few shell scripts run by CI.
`docs/design.md` is the source of truth; `docs/goals.md` lists what any change must keep.

## Layout

- `ci/sync.sh [<name>]`: per workspace, merge main into `ws/<name>` (creating it joined to main),
  then PR `ws/<name>` changes into main via `up/<name>`. Runs on pushes to main and `ws/**`.
- `ci/check.sh [<dir>]`: validates workspaces (runs on PRs to main, and on each `up/<name>`).
- `tools/new-workspace.sh`: new workspace folder from `templates/workspace/` as a PR.
- `templates/workspace/`: `workspace.yml`, `CLAUDE.md` (`{{name}}`, `{{folder}}`), `.delphi/setup.sh`.
- `software/…/workspaces/<name>/`: the workspaces. Org structure is plain directories.
- `.github/workflows/delphi.yml`, `.github/CODEOWNERS`.
- `tests/e2e.sh`: end-to-end test in a throwaway sandbox (bare origin, stub `gh` logging to `gh.log`).

## Rules

- Keep it small: fewest lines that implement the design; short, commented header per script.
  Prefer deleting to adapting. Runtime tools: bash, git, and `gh` (only to open or update PRs).
- Every script: `#!/usr/bin/env bash`, `set -euo pipefail`, `shellcheck`-clean.
- `.delphi/setup.sh` runs on people's machines: bash 3.2 (macOS) and Git Bash safe. No bash-4
  features (associative arrays, `mapfile`, `${x,,}`, `|&`), POSIX awk only. Every copy in a
  workspace must match `templates/workspace/.delphi/setup.sh`.
- `bash tests/e2e.sh` and `ci/check.sh` must pass. Add a test there for every behavior change.
- Never test against real GitHub repos or this checkout's origin; use the sandbox in `tests/e2e.sh`.
