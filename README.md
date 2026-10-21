# Delphi

NER's AI-harness context (instructions, skills, docs, settings), organized by the org chart under
`software/`. A **workspace** is a folder `software/**/workspaces/<leaf>/` with a `workspace.yml`,
named by the **short name** of each folder above it, from `software/` down, then its own folder's
name, joined by dots: `software/application-software/argos/workspaces/argos-dev` is
`s.app.argos.argos-dev` (a folder's short name is its `short-name` file, else its name;
`.delphi/names.sh` prints them all). For each one, CI keeps a branch **`ws/<name>`**
whose repo root *is* that folder. Each workspace explicitly declares its harness, and its folder on
`main` already contains native files for that harness. People and agents work on it with plain git. Design: `docs/design.md`. Goals: `docs/goals.md`.

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
`main` directly (protect them). Code changes go in a worktree, `worktrees/<repo>/<branch>` (`.delphi/new-worktree.sh`, from its own store at `worktrees/<repo>/.bare`, separate from the clone at `repos/<repo>`), through that repo's own PRs.

**Conflicts.** If `main` and `ws/<name>` changed the same lines, CI lists the files and skips that
workspace. Fix it in a PR into `ws/<name>`: on a branch cut from `ws/<name>`, run
`git merge -Xsubtree=<folder> origin/main`, resolve, commit.

## workspace.yml

```yaml
name: s.app.argos.argos-dev   # its dotted name
harness: claude-code
repos:                  # cloned at repos/<name>/; separately, worktrees (default branch first) at worktrees/<name>/<branch>/
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
are unique (give a folder a `short-name` that no sibling's name or short name clashes with). Files live at normal harness paths. `workspace.generated` records main-owned rendered files;
workspace instructions, docs and opted-out copies remain workspace-owned. The workflow comes from
the template. The scripts, `.delphi/*.sh`
(listed in `.delphi/manifest.yml`), live once at main's root: sync puts
`.delphi/` on every `ws/*` branch, so change them only through PRs to main.

## Codex

Argos's `default-codex` workspace targets the Codex harness across hosts:

```sh
git clone -b ws/s.app.argos.default-codex https://github.com/Northeastern-Electric-Racing/Delphi.git delphi
cd delphi
bash .delphi/setup.sh
```

Open the checked-out workspace in Codex normally; it discovers `AGENTS.md` and `.agents/skills/`
from the workspace branch. Follow `AGENTS.md` and use `.delphi/exec.sh` for helper commands; it sets the layout for every command
and its child processes, even when shell exports do not persist. Start a fresh session after a
workspace switch. Host dependencies and credentials are configured by the user or host; the
workspace doesn't depend on a particular cloud environment. Codex does not enable Delphi's Claude
plugin sets or install MCP servers. Use tools already available in the selected host.

`harness:` is validated against `ci/harnesses.sh`. Authoring selects its native instruction template
and skill destination while preserving translated project defaults. Shared source format and
workspace harness selection are independent. See `docs/design.md` for adding
another adapter.

## Versions

`.delphi/manifest.yml` lists Delphi's own files under a `version:` (MAJOR.MINOR.PATCH), and
`.delphi/versions` records each version's hash of them; `bash .delphi/version.sh` prints this
checkout's. Changing any listed file is a new version, and `ci/check.sh` says what line to add. When
a version needs cleanup in people's clones, it ships `.delphi/migrations/<version>-<slug>.sh`, which
`setup.sh` runs once per workspace (`git config delphi.<name>.version` records how far each is).

## New workspace

`tools/new-workspace.sh [--harness claude-code|codex] <org-path under software/> <leaf>` copies `templates/workspace/` into
`software/<org-path>/workspaces/<leaf>/`, adds the project's `workspace-defaults/` if it has one, and
opens a PR to `main`, labelled `by: ai` (put `--by ai-assisted` or `--by human` first to change it).
Once it merges, CI creates `ws/<name>` (its dotted name).

**Project folders.** The folder above `workspaces/` (e.g. `software/application-software/argos/`)
can hold shared context (`README.md`), a guide to its workspaces (`AUTHORING.md`), and
`workspace-defaults/` (what a new workspace there starts with).

**Source bundles.** Keep the existing `workspace-defaults/` and `workspace-inherit/` layouts.
They are Claude-authored by default; optional `source.yml` declares another source `format:`.
Defaults seed workspace-owned files once; inheritance stays managed. Every workspace independently
declares `harness:` in its own manifest. Unsupported native settings conversions fail explicitly.

**Shared skills.** Keep Claude sources under `workspace-inherit/.claude/skills/<name>/` at an org
or project folder, including their tool permissions and invocation metadata. The main-side renderer
preserves Claude output and translates Codex output to `.agents/skills/`, omitting Claude-only
skill fields only from the Codex copies.

**Render before merging.** After changing shared sources, harness selections, opt-outs or plugin
configuration, run `bash ci/render.sh` on a main-based branch and include its native output in the
PR. `bash ci/render.sh --check` checks freshness without writing; `ci/check.sh` includes it.
Workspaces on main already contain their native instructions, skills and supported settings.
Branch refresh copies those reviewed files without running adapters. Workspace configuration
edits are rendered in the proposal to main and arrive back after merge.

**Ownership.** Edit shared sources on main. `workspace.generated` records managed copies and
origins; don't edit it or those copies directly. To keep a workspace's own copy, list its native
path under `opt-out:` in `workspace.yml`, then render on main or use the normal workspace proposal
flow. Workspace-owned files stay editable and proposable. A workspace can read shared sources by
listing `main` under `workspaces:`.

## CI (`.github/workflows/delphi.yml`)

- PRs to `main`: `ci/check.sh` validates the repo.
- Pushes to `main` or `ws/**`: `ci/sync.sh` refreshes and proposes every workspace.

Repo settings: allow GitHub Actions to create PRs. Don't make `check` a required status check:
PRs opened by CI don't trigger workflows (sync.sh runs `ci/check.sh` itself before proposing).

Developing Delphi: see `CLAUDE.md`; `bash tests/e2e.sh` runs everything in a local sandbox.
