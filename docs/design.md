# Delphi — Design

Goals: `docs/goals.md`. No CLI: plain git plus a few shell scripts run by GitHub Actions.

## 1. Model

`main` holds every workspace as a folder, `software/**/workspaces/<name>/`, with its files at their
normal harness paths (`CLAUDE.md`, `.claude/…`, `docs/…`). For each workspace there is a branch
**`ws/<name>`** whose **repo root is that folder**. The two are kept in sync by subtree merges
(`git merge -Xsubtree=<folder>`) in both directions, so both histories stay joined and changes on
either side meet in normal three-way merges. Nothing is shared or generated between workspaces.

## 2. Repository (main)

```
software/<org>/…/workspaces/<name>/   workspace.yml  CLAUDE.md  .claude/…  docs/…  .delphi/setup.sh
ci/sync.sh  ci/check.sh               CI scripts
tools/new-workspace.sh                new workspace as a PR
templates/workspace/                  what new-workspace copies
tests/e2e.sh                          sandbox test of all of the above
```

Org folders under `software/` are plain directories. `workspace.yml` is tiny YAML: `harness:
<adapter>` and an optional `repos:` map of `<name>: <git-url>`. The name is the folder name:
lowercase letters, digits, `-`; unique repo-wide. Workspaces never nest; no symlinks under
`software/`. `ci/check.sh` enforces this on every PR to `main` and lists all problems.
`.github/CODEOWNERS` assigns reviewers per org folder.

## 3. Sync (`ci/sync.sh [<name>]`)

Runs on every push to `main` or `ws/**`, for every workspace on `origin/main` (or one):

1. **Down.** If `ws/<name>` is missing, create it as one commit, `git commit-tree
   <main>:<folder> -p <main>` ("delphi: create ws/<name> from <folder>"): root = folder, parent =
   main, so there are no unrelated histories. Otherwise merge `origin/main` into `ws/<name>` with
   `--no-ff -Xsubtree=<folder>` and push if the tree changed. (`--no-ff` matters: once ws commits
   are in main, a fast-forward would put main's whole tree on the ws branch.)
2. **Up.** Build `up/<name>` = `origin/main` + `git merge --no-ff -Xsubtree=<folder> ws/<name>`
   ("delphi: bring ws/<name> into main"). If its tree equals main's, stop. Otherwise run
   `ci/check.sh` on it, force-push it, and create or update the PR `ws/<name> → main` with `gh`
   (body: changed files, ws commit subjects and authors).

A conflict in either step is reported with its files; that workspace is skipped, the others
continue, and the script exits 1. A `ws/*` branch without a folder on main gets a notice (never
deleted). Merges happen in a temporary worktree, so the caller's checkout is untouched.

## 4. Working on a workspace

1. Clone or check out `ws/<name>` (it is the workspace root); run `.delphi/setup.sh` once.
2. Branch, commit, push, open a PR into `ws/<name>`. Refresh with `git merge origin/ws/<name>`.
3. After it merges, sync opens the PR to `main`; after that merges (merge commit or squash, never
   rebase: rebasing replays folder-rooted commits onto main), sync merges main back into ws.
4. On a sync conflict: on a branch cut from `ws/<name>`, `git merge -Xsubtree=<folder>
   origin/main`, resolve, and PR it into `ws/<name>`.

Nobody pushes to `ws/*` or `main` directly (branch protection; CI's token is the exception).

## 5. `.delphi/setup.sh` (in every workspace)

Reads `repos:` from `workspace.yml`, clones each into `repos/<name>` unless present, and adds
`/repos/` to the clone's `.git/info/exclude` once. Nothing else. Must run on macOS `/bin/bash` 3.2
and Git Bash: no bash-4 features, POSIX awk only.

## 6. New workspaces (`tools/new-workspace.sh <org-path> <name>`)

Validates the name (format, not on main, no leftover `ws/<name>`), copies `templates/workspace/`
into `software/<org-path>/workspaces/<name>/` (filling `{{name}}`/`{{folder}}` in `CLAUDE.md`) in a
temporary worktree on branch `new-workspace/<name>`, runs `ci/check.sh`, pushes, opens a PR.
Sync creates `ws/<name>` once it merges.

## 7. CI (`.github/workflows/delphi.yml`)

- `check`: PRs to main, read-only token, runs `ci/check.sh`.
- `sync`: pushes to main or `ws/**`; checks out main (scripts never come from a ws branch) with
  full history, sets the bot identity, runs `ci/sync.sh` (contents + pull-requests write; one run at
  a time). Pushes and PRs made with `GITHUB_TOKEN` don't trigger workflows: no loops, and
  CI-opened PRs don't run `check`, which is why sync runs `ci/check.sh` itself.

## 8. Testing

`tests/e2e.sh` builds a sandbox (temp dir, bare origin, stub `gh` logging to `gh.log`, two
workspaces in different org folders) and drives the scripts as CI and people would. Never test
against GitHub.
