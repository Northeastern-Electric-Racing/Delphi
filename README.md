# Delphi

NER's AI-harness context (instructions, skills, docs, settings), organized by the org chart under
`software/`. A **workspace** is a folder `software/**/workspaces/<name>/` with a `workspace.yml`.
For each workspace, CI keeps a branch **`ws/<name>`** whose repo root *is* that folder, so any
person or agent works on it with plain git. `main` and `ws/<name>` are kept in sync by subtree
merges in both directions (`ci/sync.sh`). Design: `docs/design.md`. Goals: `docs/goals.md`.

## Using a workspace

```sh
git clone -b ws/argos-dev https://github.com/Northeastern-Electric-Racing/Delphi.git argos-dev
cd argos-dev && .delphi/setup.sh        # clones workspace.yml's repos into repos/ (git-ignored)
git switch -c my-change                 # edit, commit, push, open a PR into ws/argos-dev
git fetch origin && git merge origin/ws/argos-dev   # refresh your branch any time
```

1. Your PR into `ws/<name>` is reviewed and merged.
2. CI opens (or updates) a PR `ws/<name> → main` from branch `up/<name>`. Merge it with a merge
   commit or squash, never rebase.
3. CI merges `main` back into `ws/<name>`.

Never push to `ws/*` or `main` directly (protect them). Code changes go in `repos/<name>` with that
repo's own PRs.

**Conflicts.** If `main` and `ws/<name>` changed the same lines, CI reports the files and skips that
workspace. Fix it in a PR into `ws/<name>`:
`git merge -Xsubtree=<folder> origin/main` on a branch cut from `ws/<name>`, resolve, commit.

## workspace.yml

```yaml
harness: claude-code
repos:                  # cloned into repos/<name> by .delphi/setup.sh
  argos: https://github.com/Northeastern-Electric-Racing/Argos.git
```

The workspace's name is its folder name (unique repo-wide). Everything else in the folder is the
workspace's own files, at their normal harness paths.

## New workspace

`tools/new-workspace.sh <org-path under software/> <name>` copies `templates/workspace/` into
`software/<org-path>/workspaces/<name>/` and opens a PR to `main`. After it merges, CI creates
`ws/<name>`.

## CI (`.github/workflows/delphi.yml`)

- PRs to `main`: `ci/check.sh` validates every workspace.
- Pushes to `main` or `ws/**`: `ci/sync.sh` merges `main` into every `ws/<name>` and opens PRs to
  `main` for workspace changes. Allow GitHub Actions to create PRs in the repo settings.

Developing Delphi: see `CLAUDE.md`; `bash tests/e2e.sh` runs everything in a local sandbox.
