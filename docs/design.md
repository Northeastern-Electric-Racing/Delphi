# Delphi — Design (v3: workspaces live in Delphi)

Goals: `docs/goals.md`. Flow diagram: `docs/delphi-flow.png`.

## 1. Model

Every workspace is a **folder inside Delphi**, fully materialized and committed: its
`CLAUDE.md`, `.claude/skills/…`, `docs/…` are real files on `main`. Working on a workspace means a
**sparse checkout of just that folder** on your own branch, then a PR. Everything is compared
against `main` with plain git.

Some files in a workspace are **linked** to a shared source elsewhere in Delphi (e.g. a skill
several teams use). `delphi sync` reconciles links: a change made on one side (the source or any
linked copy) is written to the source and every linked copy. Sync runs when you propose, CI
checks it on every PR, and CI re-runs it on `main` after merges, so `main` is always reconciled.

## 2. Repository

```
context/                                   # scopes (org chart), as before
  <scope>/scope.yml
  <scope>/blocks/ docs/ harness/           # shared sources
  <scope>/workspaces/<name>/               # a workspace
    workspace.yml
    CLAUDE.md                              # committed (generated if `instructions:` is set)
    .claude/skills/…  docs/…  anything else
```

```yaml
# workspace.yml
name: argos-dev                    # = folder name, unique repo-wide
harness: claude-code               # adapter: instruction file name, launch, provenance
instructions:                      # optional: CLAUDE.md is generated from these parts (don't hand-edit)
  - harness/instructions/workspace.md
  - software/harness/instructions/base.md
links:                             # shared source -> path in this folder, kept in sync
  - software/harness/skills/run-local                 # default dest: .claude/skills/run-local
  - software/application-software/argos/blocks/pr-body.md -> .claude/skills/open-pr/pr-body.md
repos:                             # cloned into repos/ in your checkout, git-ignored
  argos: https://github.com/Northeastern-Electric-Racing/Argos.git
```

- Link = `<source> [-> <dest>]`; source is a file or directory under `context/`; a directory links
  every file under it. Default dest: `…/harness/skills/<n>` → `<skills dir>/<n>`,
  `…/docs/<rest>` → `docs/<rest>`, else `context/<source>`.
- Files in the folder that aren't linked are the workspace's own. There is no "copy" mode: copying
  something in is just adding a file.
- YAML subset as before.

## 3. Sync (`delphi sync [--check] [--base <rev>]`)

For every link (source `S`, linked copies `C1…Cn` across all workspaces), per file, against the
base revision (default: merge-base with `origin/main`):

| Situation | Result |
|---|---|
| Nothing changed, all equal | nothing |
| Exactly one distinct new state among `S, C1…Cn` (edit, add, or delete) | written to `S` and every copy |
| Two or more different new states | **conflict**: listed, exit 1 (fix by hand, re-run) |
| New link, dest missing | copied from `S` |
| New link, source missing | `S` created from the copy |
| `instructions:` set | `CLAUDE.md` regenerated from its parts; a hand edit is a conflict ("generated; edit a part") |

`--check` changes nothing and exits 1 if anything would change. Sync is deterministic and
idempotent.

## 4. Local checkouts

A checkout is `git clone --filter=blob:none --no-checkout` of Delphi's origin, with a **non-cone**
sparse pattern for the one folder (so Delphi's root `CLAUDE.md` is never checked out), on branch
`ws/<gh-user>/<checkout>`. The harness runs inside the folder. `repos/` and the adapter's local
settings file are git-ignored via `.git/info/exclude`. Bookkeeping: `.git/delphi/meta`
(workspace path, harness, last pushed commit).

## 5. Commands

| Command | Does |
|---|---|
| `delphi create <scope> <name> --from <workspace.yml>` | new workspace folder (yml + synced files) via PR |
| `delphi list` | workspaces on `origin/main` (name, scope, harness) |
| `delphi checkout <name> [--as <checkout>]` | sparse clone, branch, clone repos |
| `delphi open [checkout] [--shell]` | warn if behind `main`; launch the harness (or a shell) in the folder |
| `delphi refresh [checkout]` | `git fetch` + `git merge origin/main` (exit 2 on conflict; resolve with git) |
| `delphi diff [checkout] [--upstream]` | your changes vs `main`, per file, tagged **own** or **linked** (`shared: <workspaces>`); `--upstream`: files changed on `main` since your last refresh, with author and subject |
| `delphi propose [checkout] [--dry-run]` | refresh, sync (in a temp worktree; commits `delphi: sync shared files`), `check`, push the branch, open/update one PR per checkout; PR body lists changed files, shared impact, provenance |
| `delphi status` | every local checkout: dirty, ahead (unpushed), behind `main` |
| `delphi mv <old> <new>` | move a source or workspace path, rewrite `links`/`instructions` in every `workspace.yml`, PR |
| `delphi sync [--check]` | reconcile links (§3) |
| `delphi check` | validate (§6) |
| `delphi setup [dir]` | remember where the Delphi checkout is |

Common flags on commands that write to Delphi: `--yes`, `--model`, `--effort`.

**CI** (`.github/workflows/delphi.yml`): on PRs, `delphi check` + `delphi sync --check`; on
pushes to `main`, `delphi sync` and commit the result if anything changed.

## 6. check

Scopes have `scope.yml`; every `workspace.yml` parses; `name` = folder and unique; adapter
exists; only known keys; link sources exist; dests are inside the folder, unique, not under
`repos/`; no file named after an instruction file outside a workspace folder; no symlinks.

## 7. Unchanged

Provenance (trailers on every commit Delphi writes, the workspace commit hook, resolution order),
`--yes` / non-interactive rules, `gh` only for PRs, `safe_path` on every path from config, flags,
and manifests, exit codes (0 ok, 1 error, 2 merge conflict), offline tolerance, `delphi.conf`.

## 8. Removed (vs v2)

Compile, lock, `generated` / `generated-merged` refs, per-file routing, `copy` entries,
`moves.tsv` (moves are just commits on `main`), `layouts/` (replaced by `workspaces/`), and the
`workspace`/`layout`/`block` command groups (flattened). v2 workspaces must be recreated with
`delphi checkout`.
