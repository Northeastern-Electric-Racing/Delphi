# Delphi — developing it

Delphi stores NER's AI-harness context. Each workspace is a folder `software/**/workspaces/<leaf>/`
on `main`, named by its place in the tree (the path without `workspaces/`:
`software/application-software/argos/argos-dev`); branch `ws/<name>` has that folder as its repo root. `ci/sync.sh` keeps them in sync with
subtree merges: **refresh** (main → `ws/<name>`) and **propose** (`ws/<name>` → PR to main via
`propose/<name>`). There is no CLI, just a few shell scripts run by CI. `docs/design.md` is the
source of truth; `docs/goals.md` lists what any change must keep.

## Layout

- `ci/sync.sh [refresh|propose] [<name>]`: refresh and/or propose each workspace (both by default).
  Runs on pushes to main and `ws/**`.
- `ci/check.sh [<dir>]`: validates the repo. Runs on PRs to main and on each proposal.
- `tools/new-workspace.sh`: new workspace folder from `templates/workspace/` as a PR.
- `ci/plugins.sh`: writes `.claude-plugin/marketplace.json` from the plugin sets
  (`software/**/plugins/<harness>/<set>/`, named `<scope>[.<set>]`; a folder's scope is its name or
  its `plugins/scope`), each workspace's `workspace.yml` `plugins:` defaults (the
  `default` set of every folder above), and its `.claude/settings.json` (never edit
  it by hand). Run it after changing a set or a `workspace.yml`'s `plugins:`.
- `.delphi/{setup,new-worktree,switch,park}.sh`: the scripts every workspace runs; `.delphi/paths.sh`
  is the layout (`DELPHI_ROOT`, `DELPHI_WORKTREES`, …) that they and skill scripts source. Only here: sync
  puts `.delphi/` at the root of every `ws/*` branch and strips it from proposals.
- `.delphi/manifest.yml` (Delphi's files and their `version:`), `.delphi/versions` (one line per
  version, with its hash from `.delphi/version.sh`), `.delphi/migrations/<version>-<slug>.sh` (clone
  cleanup, run by `setup.sh`).
- `templates/workspace/`: `workspace.yml`, `CLAUDE.md` (`{{name}}`, `{{folder}}`), the managed
  `.github/workflows/delphi.yml` every workspace carries unchanged, and default `new-worktree`, `switch-workspace`, `setup-workspace`,
  and `journal` skills.
- `software/…/workspaces/<name>/`: the workspaces. Org structure is plain directories. A project
  folder (the one holding `workspaces/`) may add `README.md`, `AUTHORING.md`, and `defaults/`.
- `.github/workflows/delphi.yml` (identical to the template's copy), `.github/CODEOWNERS`.
- `tests/e2e.sh`: end-to-end test in a throwaway sandbox (bare origin, stub `gh` logging to `gh.log`).

## Rules

- Keep it small: fewest lines that implement the design; a short header comment per script.
  Prefer deleting to adapting. Runtime tools: bash, git, and `gh` (only to open or update PRs).
- Every script: `#!/usr/bin/env bash`, `set -euo pipefail`, `shellcheck`-clean.
- Skill scripts (plugins and workspaces) take the workspace root as their first argument, which the
  SKILL.md fills with `${CLAUDE_PROJECT_DIR}`, then branch or repo names; they source
  `<root>/.delphi/paths.sh` for every folder. Never search for the root or default to the cwd's branch.
  The call is always `bash ${CLAUDE_SKILL_DIR}/scripts/<script>.sh ${CLAUDE_PROJECT_DIR} …`, so those two
  tokens are all another harness replaces.
- `.delphi/*.sh` run on people's machines: bash 3.2 (macOS) and Git Bash safe. No bash-4
  features (associative arrays, `mapfile`, `${x,,}`, `|&`), POSIX awk only.
- Changing the workflow: update the template, `.github/`, and every workspace copy in the same PR,
  or `ci/check.sh` fails. `.delphi/*.sh` has one copy, at the root.
- Changing any file `.delphi/manifest.yml` lists makes a new version: bump `version:` (PATCH for a
  fix, MINOR for something new, MAJOR when clones need cleanup, MINOR while 0.x), then append
  `<what bash .delphi/version.sh prints> <what changed>` to `.delphi/versions`. Only add lines there.
- When people's clones need cleanup, ship a migration rather than instructions: safe to re-run, a no-op
  on a fresh clone, run from the workspace root, deletes only what nothing is lost from and otherwise
  exits 1 saying what to do. Never edit a released one.
- `bash tests/e2e.sh` and `ci/check.sh` must pass. Add a test there for every behavior change.
- Never test against real GitHub repos or this checkout's origin; use the sandbox in `tests/e2e.sh`.
