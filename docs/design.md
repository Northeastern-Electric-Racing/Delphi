# Delphi — Design (v5: workspace as branch root)

Goals: `docs/goals.md`. Diagram: `docs/delphi-flow.png`.

## 1. Model

`main` holds every workspace as a self-contained folder, `context/<scope>/workspaces/<name>/`
(`CLAUDE.md`, `.claude/…`, `docs/…` at normal paths). For each workspace, CI maintains a
**projection branch** `ws/<name>` whose **repo root is that folder** (`git subtree split
--prefix=<folder>`: deterministic, keeps the folder's history). Anyone — a person, or an agent that
simply checks out a branch — works on a branch cut from `ws/<name>`; the workspace is the repo root.
Changes go back as a PR to `main`: the branch's diff is re-rooted under the folder. There are no
shared blocks, no compile, no sync: each workspace owns its files.

## 2. Repository (main)

```
context/<scope>/scope.yml
context/<scope>/workspaces/<name>/
  workspace.yml          # name (= folder), harness, repos
  CLAUDE.md  .claude/…  docs/…  anything else
```

`workspace.yml`: `name`, `harness` (adapter: launch + provenance), `repos` (name: git URL, cloned
into `repos/` in local checkouts, git-ignored). YAML subset as before. Workspace folders never nest.

## 3. Projection branches (`delphi split [--check] [--push]`)

For every workspace folder on the current commit: `ws/<name>` = `git subtree split --prefix=<folder>`.
`--check` exits 1 if any local `ws/*` ref differs; `--push` force-updates the remote `ws/*` refs
(and deletes `ws/<name>` for removed workspaces). CI runs `delphi split --push` on every push to
`main`; only CI writes `ws/*` (protect them).

## 4. Working on a workspace

- **Any agent or person:** check out `ws/<name>`, create a branch, edit, push. Open a PR **into
  `ws/<name>`**; CI mirrors it into a PR to `main` (below) and comments the link. No Delphi CLI
  needed.
- **With the CLI:** `delphi checkout <name> [--as <c>]` clones Delphi at `ws/<name>` into
  `<workspace_root>/<c>`, creates branch `edit/<gh-user>/<c>`, clones repos, installs the provenance
  commit hook. `refresh` = `git merge origin/ws/<name>` (exit 2 on conflict).

## 5. Propose (branch → PR to main)

`delphi propose [checkout | [<name>] --branch <b>] [--dry-run]` (`--branch`: a branch on origin;
the workspace is the one whose `ws/*` it shares history with, unless named):

1. Base = merge-base of the branch and `origin/ws/<name>`; patch = `base..branch` (binary-safe,
   modes kept).
2. In a temp worktree off `origin/main`: apply the patch under the folder with a 3-way apply. A
   conflict (the folder changed on `main` in the same lines) exits 1 listing files: refresh, resolve,
   re-run.
3. `delphi check`, commit with provenance trailers (one commit; message lists the source branch),
   push `propose/<gh-user>/<name>-<branch>` (`/` etc. in the branch become `-`; `$DELPHI_USER`
   overrides the user, e.g. `github-actions` in CI) with a lease, open/update one PR to `main`.

CI mirror: on PRs targeting `ws/*`, run `delphi propose --branch <head> --yes` (bot provenance) and
comment the `main` PR link on the `ws/*` PR. After the `main` PR merges, CI re-splits; the edit
branch's refresh is a clean merge (same change on both sides).

## 6. Commands

| Command | Does |
|---|---|
| `delphi create <scope> <name> [--from <dir>]` | new workspace folder (yml + files) via PR to main |
| `delphi list` | workspaces on `origin/main` (name, scope, harness, branch) |
| `delphi checkout <name> [--as <c>]` | §4 |
| `delphi open [c] [--shell]` | warn if behind `ws/<name>`; launch the harness (or a shell) at the root |
| `delphi refresh [c]` | fetch + merge `origin/ws/<name>` |
| `delphi diff [c] [--upstream]` | changes vs `ws/<name>`; `--upstream`: new on `ws/<name>` since, with author + subject |
| `delphi propose [c \| [name] --branch b] [--dry-run]` | §5 |
| `delphi status` | local checkouts: dirty, ahead (unproposed), behind |
| `delphi split [--check] [--push]` | §3 |
| `delphi check` | scopes have `scope.yml`; `workspace.yml` valid, name = folder, unique; adapter exists; no nested workspaces; no symlinks; no instruction-file names outside workspaces |
| `delphi setup [dir]` | remember where the Delphi checkout is |

Writers take `--yes`, `--model`, `--effort`.

## 7. Unchanged

Provenance (trailers, commit hook, resolution order), `--yes`/non-interactive rules, `gh` only for
PRs, `safe_path` on every external path, exit codes (0/1/2), offline tolerance, `delphi.conf`.

## 8. Removed (vs v3)

Links (`blocks`/`docs`/`skills`/`settings` keys), `instructions`/`mcp` generation, `skill.yml`,
`delphi sync`, sparse checkouts, `mv` (moving a workspace is an ordinary PR; `split` follows).
