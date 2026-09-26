# Delphi — Design (v3: workspaces live in Delphi)

Goals: `docs/goals.md`. Flow diagram: `docs/delphi-flow.png`.

## 1. Model

Every workspace is a **folder inside Delphi**, fully materialized and committed: its
`CLAUDE.md`, `.claude/skills/…`, `docs/…` are real files on `main`. Working on a workspace means a
**sparse checkout of just that folder** on your own branch, then a PR. Everything is compared
against `main` with plain git.

Some files in a workspace are **linked** to a shared source elsewhere in Delphi (e.g. a skill
several teams use): the `blocks`, `docs`, `skills` and `settings` entries of `workspace.yml`.
`delphi sync` reconciles links: a change made on one side (the source or any linked copy) is
written to the source and every linked copy. Sync runs when you propose, CI
checks it on every PR, and CI re-runs it on `main` after merges, so `main` is always reconciled.

## 2. Repository

```
context/                                   # scopes (org chart), as before
  <scope>/scope.yml
  <scope>/blocks/ docs/ harness/           # shared sources
  <scope>/workspaces/<name>/               # a workspace
    workspace.yml
    CLAUDE.md                              # committed (generated if `instructions:` is set)
    .mcp.json                              # generated if `mcp:` is set
    .claude/skills/…  docs/…  anything else  # a skill may be composed from blocks (§2.1)
```

```yaml
# workspace.yml
name: argos-dev                    # = folder name, unique repo-wide
harness: claude-code               # adapter: file names, launch, provenance
instructions:                      # optional: CLAUDE.md is generated from these parts (don't hand-edit)
  - harness/instructions/workspace.md
  - software/harness/instructions/base.md
blocks:                            # linked: shared source -> path in this folder, kept in sync
  - software/application-software/argos/blocks/glossary.md          # default dest: context/<same path>
docs:
  - software/application-software/argos/docs/CONTEXT.md           # default dest: docs/CONTEXT.md
skills:
  - software/harness/skills/run-local                             # default dest: .claude/skills/run-local
mcp:                               # optional: .mcp.json is generated from these fragments
  - software/harness/mcp/github.json
settings: software/harness/settings/default.json                  # default dest: .claude/settings.json
repos:                             # cloned into repos/ in your checkout, git-ignored
  argos: https://github.com/Northeastern-Electric-Racing/Argos.git
```

Only `name` and `harness` are required. Paths are relative to `context/`. A scope's shared
sources sit in its `blocks/`, `docs/` and `harness/{instructions,skills,mcp,settings}/`.

- **Linked keys** (`blocks`, `docs`, `skills`, `settings`): entries are `<source> [-> <dest>]`,
  and each source must sit in its key's directory. Default dests:

  | Key | Source | Default dest |
  |---|---|---|
  | `blocks` | a file or directory under a scope's `blocks/` | `context/<source>` |
  | `docs` | under a scope's `docs/` | `docs/<path below that docs/>` |
  | `skills` | a native skill directory `…/harness/skills/<n>` | `<skills dir>/<n>` (`.claude/skills/<n>`) |
  | `settings` | at most one file under a scope's `harness/settings/` | the harness settings file (`.claude/settings.json`) |

  A directory source links every file under it.
- **Generated keys**: `instructions` (parts under `…/harness/instructions/`) → the instruction file
  (`CLAUDE.md`), parts joined by a blank line; `mcp` (fragments under `…/harness/mcp/`, each one
  `"name": {…}` member of `mcpServers`, no trailing comma) → the harness MCP file (`.mcp.json`) =
  `{"mcpServers": {` line + fragments joined by `,` lines + `}}` line. Omitted when the key is
  empty.
- Sources live outside workspace folders (a workspace's own files are not link sources).
- Files in the folder that aren't linked or generated are the workspace's own. There is no "copy"
  mode: copying something in is just adding a file.
- YAML subset as before.

### 2.1 Composed skills

Any skill directory under `context/` (a scope's `harness/skills/<n>/` source, or `<skills dir>/<n>/`
in a workspace folder) may hold a `skill.yml`; its `SKILL.md` is then generated from blocks:

```yaml
# .claude/skills/open-pr/skill.yml
name: open-pr                                          # required
description: Run pre-PR checks and open a draft PR     # required
body:                                                  # blocks, each a file under a scope's blocks/
  - software/application-software/argos/blocks/open-pr.md
  - software/application-software/argos/blocks/pr-body.md
```

`SKILL.md` = `---`, `name: <name>`, `description: <description>`, `---` lines, then each body
block, one blank line between blocks (each block ends with one newline). `skill.yml` is an
ordinary file: a linked skill directory carries it to every copy, so a block edit regenerates the
source's and every copy's `SKILL.md` alike. A shared block is edited once, in its source; it is
not linked into the workspace.

## 3. Sync (`delphi sync [--check] [--base <rev>]`)

For every link (a `blocks`, `docs`, `skills` or `settings` entry: source `S`, linked copies `C1…Cn`
across all workspaces), per file, against the
base revision (default: merge-base with `origin/main`):

| Situation | Result |
|---|---|
| Nothing changed, all equal | nothing |
| Exactly one distinct new state among `S, C1…Cn` (edit, add, or delete) | written to `S` and every copy |
| Two or more different new states | **conflict**: listed, exit 1 (fix by hand, re-run) |
| New link, dest missing | copied from `S` |
| New link, source missing | `S` created from the copy |
| `instructions:` set | `CLAUDE.md` regenerated from its parts; a hand edit is a conflict ("generated; edit a part") |
| `mcp:` set | `.mcp.json` regenerated from its fragments; a hand edit is a conflict ("generated; edit a fragment") |
| A `skill.yml` (§2.1) | its `SKILL.md` regenerated from its blocks; a hand edit is a conflict ("generated from skill.yml; edit a block") |

`--check` changes nothing and exits 1 if anything would change. Sync is deterministic and
idempotent.

Details:
- A file's state is its content plus executable bit (the owner's x bit, as git records it), or
  "absent". A member has a **new state** if
  it differs from that path at every base revision. Only members whose link existed at a base
  count; a newly linked copy that exists must equal the result, else it is a conflict ("newly
  linked … but differs"; delete it to take the source).
- Nothing new but members differ (e.g. `main` after two racing merges): the source wins; with no
  source, agreeing copies create it.
- A directory link covers every file under its source or under any copy of it, so a file added
  to (or deleted from) one copy is added to (deleted from) the source and every copy. Deleting
  removes emptied directories.
- Conflicting files are left untouched; everything else is still written.
- Skills' `SKILL.md` (§2.1) are generated before links are reconciled, so a regenerated source
  fans out to its copies; a hand-edited one (it changed since the base and differs from what
  generation gives) is a conflict and its link is left alone. `CLAUDE.md` and `.mcp.json` are
  generated after links are reconciled.
- `propose`'s base, once it has pushed, is the last commit it pushed (already reconciled) merged
  with `origin/main` (`git merge-tree`), so re-proposing a shared edit never conflicts with its own
  earlier sync and reverting it is a new state; if that merge conflicts, it passes two bases (the
  merge-base with `origin/main` and the last pushed commit).

## 4. Local checkouts

A checkout is `git clone --filter=blob:none --no-checkout` of Delphi's origin, with a **non-cone**
sparse pattern for the one folder (so Delphi's root `CLAUDE.md` is never checked out), on branch
`ws/<gh-user>/<checkout>` (`$USER` when origin is not on GitHub; continued from origin if that
branch already exists). Checkouts live in `<workspace_root>/<checkout>/` (`delphi.conf`); the
folder sits at its usual path inside, and the harness runs there. Repos are cloned into the
folder's `repos/`. `repos/` and the adapter's local settings file are git-ignored via
`.git/info/exclude`. Bookkeeping: `.git/delphi/meta` (workspace, folder path, harness, branch,
last pushed commit). `refresh` and `propose` need a clean checkout (commit or stash first).

## 5. Commands

| Command | Does |
|---|---|
| `delphi create <scope> <name> --from <workspace.yml>` | new workspace folder (yml + synced files) via PR |
| `delphi list` | workspaces on `origin/main` (name, scope, harness) |
| `delphi checkout <name> [--as <checkout>]` | sparse clone, branch, clone repos |
| `delphi open [checkout] [--shell]` | warn if behind `main`; launch the harness (or a shell) in the folder |
| `delphi refresh [checkout]` | `git fetch` + `git merge origin/main` (exit 2 on conflict; resolve with git) |
| `delphi diff [checkout] [--upstream]` | your committed changes vs `main`, per file, tagged **own**, **linked** (`<- source`, `shared: <workspaces>`), **generated** (`CLAUDE.md`, `.mcp.json`, a `SKILL.md` with a `skill.yml`), or **sync** (outside the folder, written by an earlier propose); `--upstream`: files changed on `main` since your last refresh, with author and subject |
| `delphi propose [checkout] [--dry-run]` | refresh, sync (in a temp full worktree at the branch head; commits `delphi: sync shared files` with trailers), `check`, push the branch (lease: absent or last pushed), fast-forward the local branch, open/update one PR per checkout; PR body lists changed files as in `diff` (shared impact) plus the provenance table. `--dry-run`: no refresh or push; shows the sync writes and the PR body |
| `delphi status` | every local checkout: dirty, ahead (own commits not pushed and not on `main`), behind `main` |
| `delphi mv <old> <new>` | move a source or workspace path, rewrite its entries (`instructions`, `mcp`, `blocks`, `docs`, `skills`, `settings`) in every `workspace.yml` (and scope `recommend:`, skill `body:`), PR; a link whose default dest would change gets an explicit `-> <old dest>`; a moved workspace gets its new `name` |
| `delphi sync [--check] [--base <rev>]` | reconcile links (§3) in the current Delphi checkout |
| `delphi check` | validate (§6) |
| `delphi setup [dir]` | remember where the Delphi checkout is |

Common flags on commands that write to Delphi: `--yes`, `--model`, `--effort`.

`create` and `mv` run sync (base: `origin/main`) and `check` in a temp worktree before the PR
(branches `delphi/create/<name>`, `delphi/mv/<name>-<time>`).

**CI** (`.github/workflows/delphi.yml`): on PRs (the PR head, full history, read-only token),
`delphi check` + `delphi sync --check`; on pushes to `main`, `delphi sync --base HEAD` and commit
the result as `github-actions[bot]` (`delphi: sync shared files`, provenance trailers
`github-actions`/`none`) if anything changed. The bot's push uses `GITHUB_TOKEN`, so it triggers no
run; if `main` moved meanwhile the push is dropped and the newer push's run syncs.

## 6. check

Scopes have `scope.yml`; every `workspace.yml` parses; `name` = folder and unique; adapter
exists; only known keys (`links:` is unknown); instruction parts, MCP fragments and link sources
exist; each entry sits in its key's directory (§2: `skills` entries are a directory directly under
`harness/skills/`, `mcp`/`settings` entries are files); at most one `settings`; sources neither
inside nor containing workspace folders; dests are inside the folder, unique, not nested in a
directory link's dest, not under `repos/`, not `workspace.yml`, not a generated file; no file named
after an instruction file outside a workspace folder; every folder under `workspaces/` has a `workspace.yml`; scope `recommend:`
paths exist; every `skill.yml` parses, has `name` and `description`, only known keys (`name`,
`description`, `body`), and its `body` entries are existing files under a scope's `blocks/`; no symlinks.

## 7. Unchanged

Provenance (trailers on every commit Delphi writes, the workspace commit hook, resolution order),
`--yes` / non-interactive rules, `gh` only for PRs, `safe_path` on every path from config, flags,
and manifests, exit codes (0 ok, 1 error, 2 merge conflict), offline tolerance, `delphi.conf`.

## 8. Removed (vs v2)

Compile, lock, `generated` / `generated-merged` refs, per-file routing, `copy` entries,
`moves.tsv` (moves are just commits on `main`), `layouts/` (replaced by `workspaces/`), and the
`workspace`/`layout`/`block` command groups (flattened), `--ref`, and the unproposed-age
tracking in `status` (`stale_days`). v2 workspaces must be recreated with `delphi checkout`.
