# Delphi

NER's AI-harness context (instructions, skills, docs, settings), organized by the org chart under
`software/`. A **workspace** is a folder `software/**/workspaces/<leaf>/` with a `workspace.yml`,
named by its place in the tree: the folder's path without `workspaces/`
(`software/application-software/argos/argos-dev`). For each one, CI keeps a branch **`ws/<name>`**
whose repo root *is* that folder, so people and agents work on it with plain git. Design: `docs/design.md`. Goals: `docs/goals.md`.

## How it works

```
   ┌───────────────────────────────┐
   │ main                          │
   │ software/…/workspaces/<name>/ │
   └───────────────────────────────┘
        │                  ▲
        │ refresh          │ merge PR
        │ (CI)             │ (after check.sh)
        ▼                  │
   ┌──────────────────┐  ┌──────────────────┐
   │ ws/<name>        │  │ propose/<name>   │
   │ root = workspace │─►│ PR to main       │
   └──────────────────┘  └──────────────────┘
        │         ▲    propose (CI)
        │ branch  │ merge PR
        ▼         │
   ┌──────────────────┐
   │ your branch      │
   │ edit · commit    │
   └──────────────────┘

   refresh: main → ws/<name>        (folder becomes root)
   propose: ws/<name> → main PR     (root goes back under folder)
   CI runs both on every push to main or ws/**
```

Both directions are subtree merges (`git merge -Xsubtree=<folder>`) done by `ci/sync.sh`, so the
histories stay joined and edits on either side meet in normal three-way merges.

## Using a workspace

```sh
git clone -b ws/software/application-software/argos/argos-dev https://github.com/Northeastern-Electric-Racing/Delphi.git delphi
cd delphi && .delphi/setup.sh           # repos/ stores + default-branch worktrees in worktrees/ (git-ignored)
.delphi/switch.sh nero-experimental    # switch freely (or to main; the full name works too): the hook parks them in .delphi/parked/
git switch -c my-change                 # edit, commit, push, open a PR into ws/software/application-software/argos/argos-dev
git fetch origin && git merge origin/ws/software/application-software/argos/argos-dev   # update your branch any time
```

After your PR merges into `ws/<name>`, CI proposes it: a PR `ws/<name> → main` from
`propose/<name>`. Merge that with a merge commit or squash, never rebase. Never push to `ws/*` or
`main` directly (protect them). Code changes go in a worktree, `worktrees/<repo>/<branch>` (`.delphi/new-worktree.sh`), through that repo's own PRs.

**Conflicts.** If `main` and `ws/<name>` changed the same lines, CI lists the files and skips that
workspace. Fix it in a PR into `ws/<name>`: on a branch cut from `ws/<name>`, run
`git merge -Xsubtree=<folder> origin/main`, resolve, commit.

## workspace.yml

```yaml
name: software/application-software/argos/argos-dev   # its place in the tree
harness: claude-code
repos:                  # stored in repos/<name>, checked out in worktrees/<name>/ by .delphi/setup.sh
  argos: https://github.com/Northeastern-Electric-Racing/Argos.git
references-git:         # read-only dependency sources, shallow-cloned into references/<name>/
  socketioxide: https://github.com/Totodore/socketioxide.git v0.18.7   # optional tag or branch
workspaces:             # Delphi workspaces (ws/<name>) or main, read-only, shallow-cloned into linked/<branch>/
  - main
```

`repos:` are the code you change. `references-git:` are open-source dependencies the agent reads for
context: `setup.sh` checks each out shallow and detached at its pin (or the default branch), with
pushes disabled, and refreshes them on every run. They get no store and no worktrees. Names are
unique across both maps. The `-git` suffix leaves room for other kinds of references later.
`workspaces:` are other workspaces (`- ws/<name>`) or `main` to read: the same kind of read-only copy, of Delphi itself.
To change one, switch to it instead.

The workspace's name is its place in the tree, repeated in `name:` so a checkout knows which
workspace it is. Workspaces in different places may end in the same name; but since git can't hold
both `ws/a` and `ws/a/b`, no workspace may be named like a project folder beside it. Every other file in the folder is the workspace's own, at its normal harness
path, except `.github/workflows/delphi.yml` (a copy of the template's). The scripts, `.delphi/*.sh`
(`setup.sh`, `new-worktree.sh`, `switch.sh`, `park.sh`, `version.sh`), live once at main's root: sync puts
`.delphi/` on every `ws/*` branch, so change them only through PRs to main.

## Versions

`.delphi/manifest.yml` lists Delphi's own files under a `version:` (MAJOR.MINOR.PATCH), and
`.delphi/versions` records each version's hash of them; `bash .delphi/version.sh` prints this
checkout's. Changing any listed file is a new version, and `ci/check.sh` says what line to add. When
a version needs cleanup in people's clones, it ships `.delphi/migrations/<version>-<slug>.sh`, which
`setup.sh` runs once per workspace (`git config delphi.<name>.version` records how far each is).

## New workspace

`tools/new-workspace.sh <org-path under software/> <name>` copies `templates/workspace/` into
`software/<org-path>/workspaces/<name>/`, adds the project's `workspace-defaults/` if it has one, and
opens a PR to `main`. Once it merges, CI creates `ws/software/<org-path>/<name>`.

**Project folders.** The folder above `workspaces/` (e.g. `software/application-software/argos/`)
can hold shared context (`README.md`), a guide to its workspaces (`AUTHORING.md`), and
`workspace-defaults/` (what a new workspace there starts with).

**Inherited files.** Any folder under `software/`, `software/` itself included, can hold
`workspace-inherit/`: files (usually skills, never `CLAUDE.md`) that CI writes onto the `ws/*` branch
of every workspace below it on each sync. Edit them on `main`; a workspace's own edit is undone. To
keep its own copy, a workspace lists the path under `opt-out:` in its `workspace.yml`.
A workspace that lists `main` under `workspaces:` reads them at `linked/main/` (recommended for every
new workspace); to change them, switch to `main`.

## CI (`.github/workflows/delphi.yml`)

- PRs to `main`: `ci/check.sh` validates the repo.
- Pushes to `main` or `ws/**`: `ci/sync.sh` refreshes and proposes every workspace.

Repo settings: allow GitHub Actions to create PRs. Don't make `check` a required status check:
PRs opened by CI don't trigger workflows (sync.sh runs `ci/check.sh` itself before proposing).

Developing Delphi: see `CLAUDE.md`; `bash tests/e2e.sh` runs everything in a local sandbox.
