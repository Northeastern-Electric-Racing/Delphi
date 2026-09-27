# Delphi — developing it

Delphi stores NER's AI-harness context. Each workspace is a folder `software/**/workspaces/<name>/`
on `main`; branch `ws/<name>` has that folder as its repo root. `ci/sync.sh` keeps them in sync with
subtree merges: **refresh** (main → `ws/<name>`) and **propose** (`ws/<name>` → PR to main via
`propose/<name>`). There is no CLI, just a few shell scripts run by CI. `docs/design.md` is the
source of truth; `docs/goals.md` lists what any change must keep.

## Layout

- `ci/sync.sh [refresh|propose] [<name>]`: refresh and/or propose each workspace (both by default).
  Runs on pushes to main and `ws/**`.
- `ci/check.sh [<dir>]`: validates the repo. Runs on PRs to main and on each proposal.
- `tools/new-workspace.sh`: new workspace folder from `templates/workspace/` as a PR.
- `templates/workspace/`: `workspace.yml`, `CLAUDE.md` (`{{name}}`, `{{folder}}`), and the managed
  files every workspace carries unchanged: `.delphi/setup.sh`, `.delphi/new-worktree.sh`,
  `.github/workflows/delphi.yml`; and a default `new-worktree` skill.
- `software/…/workspaces/<name>/`: the workspaces. Org structure is plain directories.
- `.github/workflows/delphi.yml` (identical to the template's copy), `.github/CODEOWNERS`.
- `tests/e2e.sh`: end-to-end test in a throwaway sandbox (bare origin, stub `gh` logging to `gh.log`).

## Rules

- Keep it small: fewest lines that implement the design; a short header comment per script.
  Prefer deleting to adapting. Runtime tools: bash, git, and `gh` (only to open or update PRs).
- Every script: `#!/usr/bin/env bash`, `set -euo pipefail`, `shellcheck`-clean.
- `.delphi/*.sh` run on people's machines: bash 3.2 (macOS) and Git Bash safe. No bash-4
  features (associative arrays, `mapfile`, `${x,,}`, `|&`), POSIX awk only.
- Changing a managed file (`.delphi/*.sh`, the workflow): update the template, `.github/`, and every
  workspace copy in the same PR, or `ci/check.sh` fails.
- `bash tests/e2e.sh` and `ci/check.sh` must pass. Add a test there for every behavior change.
- Never test against real GitHub repos or this checkout's origin; use the sandbox in `tests/e2e.sh`.
