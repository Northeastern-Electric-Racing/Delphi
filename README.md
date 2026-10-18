# Delphi

NER's AI-harness context (instructions, skills, docs, settings), organized by the org chart under
`software/`. A **workspace** is a folder `software/**/workspaces/<leaf>/` with a `workspace.yml`,
named by the **short name** of each folder above it, from `software/` down, then its own folder's
name, joined by dots: `software/application-software/argos/workspaces/argos-dev` is
`s.app.argos.argos-dev` (a folder's short name is its `short-name` file, else its name;
`.delphi/names.sh` prints them all). For each one, CI keeps a branch **`ws/<name>`**
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
git clone -b ws/s.app.argos.argos-dev https://github.com/Northeastern-Electric-Racing/Delphi.git delphi
cd delphi && .delphi/setup.sh           # clones repos: into repos/ (git-ignored)
.delphi/switch.sh s.app.nero.nero-experimental   # switch freely (or to main; --list lists them): the hook parks them (and workspace.yml's park: folders) in .delphi/parked/
claude plugin install delphi@delphi --scope user   # then /ws-delphi in Claude Code: a pane to keep open that switches workspaces (/ws-delphi --web: in a browser)
git switch -c my-change                 # edit, commit, push, open a PR into ws/s.app.argos.argos-dev
git fetch origin && git merge origin/ws/s.app.argos.argos-dev   # update your branch any time
```

After your PR merges into `ws/<name>`, CI proposes it: a PR `ws/<name> → main` from
`propose/<name>`, labelled `by: ai` (change the label if you wrote it; CI keeps it). Merge that with a
merge commit or squash, never rebase. Never push to `ws/*` or
`main` directly (protect them). Code changes go in the clone at `repos/<repo>` (one thing at a time) or a worktree from it, `worktrees/<repo>/<branch>` (`.delphi/new-worktree.sh`), through that repo's own PRs.

**Conflicts.** If `main` and `ws/<name>` changed the same lines, CI lists the files and skips that
workspace. Fix it in a PR into `ws/<name>`: on a branch cut from `ws/<name>`, run
`git merge -Xsubtree=<folder> origin/main`, resolve, commit.

## workspace.yml

```yaml
name: s.app.argos.argos-dev   # its dotted name
harness: claude-code
repos:                  # cloned at repos/<name>/ by .delphi/setup.sh; worktrees from it in worktrees/<name>/
  argos: https://github.com/Northeastern-Electric-Racing/Argos.git
references-git:         # read-only dependency sources, shallow-cloned into references/<name>/
  socketioxide: https://github.com/Totodore/socketioxide.git v0.18.7   # optional tag or branch
workspaces:             # Delphi workspaces (by name) or main, cloned into workspaces/<name>/ to read
  - main
```

`repos:` are the code you change. `references-git:` are open-source dependencies the agent reads for
context: `setup.sh` checks each out shallow and detached at its pin (or the default branch), with
pushes disabled, and refreshes them on every run. They get no clone in `repos/` and no worktrees. Names are
unique across both maps. The `-git` suffix leaves room for other kinds of references later.
`workspaces:` are other workspaces (`- <name>`) or `main` to read: full clones of Delphi itself, each on
its branch (`ws/<name>` or `main`) tracking origin, so `git status` and `git log` work as usual. Every
run switches a clone back to its branch if it was switched away, pulls it, and runs its own setup, so its repos and
references are there too (a workspace inside another's `workspaces/` skips its own `workspaces:`). By convention they aren't
edited from the workspace that links them; to change one, work in its own clone or switch to it.

The workspace's dotted name is repeated in `name:` so a checkout knows which workspace it is; names
are unique (give a folder a `short-name` that no sibling's name or short name clashes with). Every other file in the folder is the workspace's own, at its normal harness
path, except `.github/workflows/delphi.yml` (a copy of the template's). The scripts, `.delphi/*.sh`
(listed in `.delphi/manifest.yml`), live once at main's root: sync puts
`.delphi/` on every `ws/*` branch, so change them only through PRs to main.

## Versions

`.delphi/manifest.yml` lists Delphi's own files under a `version:` (MAJOR.MINOR.PATCH), and
`.delphi/versions` records each version's hash of them; `bash .delphi/version.sh` prints this
checkout's. Changing any listed file is a new version, and `ci/check.sh` says what line to add. When
a version needs cleanup in people's clones, it ships `.delphi/migrations/<version>-<slug>.sh`, which
`setup.sh` runs once per workspace (`git config delphi.<name>.version` records how far each is).

## New workspace

`tools/new-workspace.sh <org-path under software/> <leaf>` copies `templates/workspace/` into
`software/<org-path>/workspaces/<leaf>/`, adds the project's `workspace-defaults/` if it has one, and
opens a PR to `main`, labelled `by: ai` (put `--by ai-assisted` or `--by human` first to change it).
Once it merges, CI creates `ws/<name>` (its dotted name).

**Project folders.** The folder above `workspaces/` (e.g. `software/application-software/argos/`)
can hold shared context (`README.md`), a guide to its workspaces (`AUTHORING.md`), and
`workspace-defaults/` (what a new workspace there starts with).

**Inherited files.** Any folder under `software/`, `software/` itself included, can hold
`workspace-inherit/`: files (usually skills, never `CLAUDE.md`) that CI writes onto the `ws/*` branch
of every workspace below it on each sync. Edit them on `main`; a workspace's own edit is undone. To
keep its own copy, a workspace lists the path under `opt-out:` in its `workspace.yml`.
A workspace that lists `main` under `workspaces:` reads them at `workspaces/main/` (recommended for every
new workspace); to change them, switch to `main`.

## CI (`.github/workflows/delphi.yml`)

- PRs to `main`: `ci/check.sh` validates the repo.
- Pushes to `main` or `ws/**`: `ci/sync.sh` refreshes and proposes every workspace.

Repo settings: allow GitHub Actions to create PRs. Don't make `check` a required status check:
PRs opened by CI don't trigger workflows (sync.sh runs `ci/check.sh` itself before proposing).

Developing Delphi: see `CLAUDE.md`; `bash tests/e2e.sh` runs everything in a local sandbox.
