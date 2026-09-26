# Delphi — Design (v2: mapped workspaces)

Supersedes the v1 spec (line-level compile and routing). Goals: `docs/goals.md`.

## 1. Model in one paragraph

Context lives once in Delphi under `context/`, organized by scope (org chart). A **layout**
lists which context files a workspace gets and where they go. A **workspace** is its own git repo
where every file sits at a normal harness location (`CLAUDE.md`, `.claude/skills/…`, `docs/…`).
Every compiled file is a **1:1 copy of one source file** (the one exception is the optional
assembled instruction file). Each file is either **synced** (linked to its source: refresh updates
it, propose sends edits back) or **copied** (copied in once, then yours). Nothing is synced unless
the layout says so.

## 2. Layout

`context/<scope>/layouts/<name>/`:

```
manifest.yml
files/            # optional: the layout's own files, placed at the workspace root, synced
  CLAUDE.md
  .claude/skills/argos-notes/SKILL.md
```

```yaml
name: argos-dev                       # = directory name, unique
harness: claude-code                  # adapter: launch + provenance
instructions:                         # optional: assembled into the harness instruction file
  - software/harness/instructions/base.md
sync:                                 # linked to their source
  - software/application-software/argos/harness/skills/run-local
  - software/application-software/argos/blocks/pr-body.md -> .claude/skills/open-pr/pr-body.md
copy:                                 # copied once, then yours
  - software/harness/skills/new-worktree
repos:
  argos: https://github.com/Northeastern-Electric-Racing/Argos.git
```

- Entry = `<source> [-> <dest>]`. Source is a file or directory under `context/`; a directory maps
  every file under it (recursive, 1:1, executable bit kept).
- Default dest (when `->` is omitted), by source path (first match of the path component):
  `…/harness/skills/<n>[/…]` → `<skills dir>/<n>[/…]`; `…/docs[/<rest>]` → `docs[/<rest>]`;
  anything else → `context/<source>`.
- Dests are unique and never nested (no dest inside another entry's dest, including the
  instruction file and the layout's `files/`), and never under `.git/`, `.delphi/`, `repos/`, or
  `worktrees/`. One exception: a **file** dest may sit inside a **directory** entry's dest when
  that directory's source has nothing at that path, so an extra file can join a synced skill
  folder (e.g. `…/skills/open-pr` plus `…/pr-body.md -> .claude/skills/open-pr/pr-body.md`). Each
  file keeps its own source; a new file in the folder goes to the folder's source.
- `instructions` builds the harness instruction file (e.g. `CLAUDE.md`) from parts, blank line
  between. It is **generated**: edits to it are not proposed (sync a part to edit it). A layout
  uses either `instructions` or its own `files/<instruction file>`, not both.
- YAML subset as before (scalars, lists, one-level maps).

## 3. Workspace

Git repo at `<workspace_root>/<name>`. Refs as in v1: `generated` (compiles only),
tag `generated-merged` (last compile merged into `working`), `working` (the user's branch).
Bookkeeping in `.git/delphi/` (never in the working tree).

**Compile** = synced files + layout `files/` + assembled instruction file + `.delphi/manifest.yml`
(editable copy of the layout manifest) + `.delphi/lock.tsv`:

```
# dest	source	kind
CLAUDE.md	software/harness/instructions/base.md	assembled     (one row per part)
.claude/skills/run-local/SKILL.md	software/…/harness/skills/run-local/SKILL.md	sync
CLAUDE.md	software/…/layouts/argos-dev/files/CLAUDE.md	layout     (when not assembled)
.claude/settings.json	software/harness/settings/claude.json	copy     (listed only)
.delphi/manifest.yml	software/…/layouts/argos-dev/manifest.yml	layout
```

Copied files are **not** part of the compile (the lock lists them so refresh knows what to copy).
They are committed to `working` directly (`delphi: copy …`) when first listed, and recorded in
`.git/delphi/copied` (`dest<TAB>source<TAB>delphi-commit`, the Delphi commit copied from). A dest
that already exists is left alone (warned, recorded). Copies are never overwritten or proposed,
and they never count as pending changes; `diff` lists a copy you edited as local.

## 4. Commands

| Command | Does |
|---|---|
| `workspace new <layout> [--as ws] [--ref b]` | compile at `origin/<ref>`, init repo, add copies, clone repos |
| `workspace open [ws] [--shell]` | warn if behind; launch the harness (or a shell) in it |
| `workspace refresh [ws] [--ref b]` | compile → commit on `generated` → `git merge` into `working` (exit 2 on conflict; re-run to finish); add newly listed copies; print which synced files changed upstream and who changed them |
| `workspace diff [ws] [--upstream]` | what you changed vs. what came from Delphi (below); `--upstream`: sources changed on `origin/<ref>` since your compile, incl. copies whose source moved on |
| `workspace propose [ws] [--dry-run]` | refresh, route (below), one PR per workspace (force-updated) |
| `workspace status` | one row per workspace: dirty, clean/proposed/unproposed, behind |
| `layout new <scope> <name> --from <file>` / `layout list` | layout PR / list layouts |
| `block mv <old> <new>` | move a source (any path under `context/` except layouts and `scope.yml`), log it in `moves.tsv`, rewrite manifests and scope recommendations; workspaces follow on refresh |
| `check` | validate the repo (below) |
| `setup [dir]` | remember where the Delphi checkout is |

`propose --dry-run` prints the same listing as `workspace diff` (stdout), one line per changed
file: `update|new|manifest <dest> -> <source>`, `noop|local <dest> (<reason>)`, then
`Unresolved:` with `<dest>: <reason>`. `diff --upstream` prints
`<kind> <dest> <- <source> (<author>: <subject>)` per changed source. `status` counts a workspace
as clean when nothing proposable is pending (local files don't count). `propose` makes one commit
on the propose branch.

## 5. What changed, and where it goes (routing)

Pending diff = `generated-merged..HEAD` (committed changes only; `diff` and `--dry-run` warn
about uncommitted ones). Per changed file:

| Change | Result |
|---|---|
| synced or layout file, modified (incl. binary, mode) | copy the file over its source |
| synced file, deleted | no-op if its entry was removed from `.delphi/manifest.yml`, else unresolved |
| layout file, deleted | unresolved (remove it from the layout's `files/` in Delphi) |
| new file inside a synced **directory** | new file in that source directory (the innermost entry wins) |
| new `sync` entry in `.delphi/manifest.yml` whose source doesn't exist yet | source created from the workspace file(s) |
| new file whose source already exists in Delphi | unresolved (it arrives on refresh once the entry merges) |
| symlink, type change, other `.delphi/` files | unresolved |
| `.delphi/manifest.yml` modified | replaces the layout manifest |
| assembled instruction file | unresolved ("generated; sync a part to edit it"); deleting it is a no-op if `instructions` was dropped |
| anything else (copies, new files elsewhere) | **local**: listed, never proposed |

One source synced to several dests: identical edits route once; differing edits are unresolved.
Unresolved items are listed in the PR body; they never block it.

**Shared awareness.** `diff`, `propose`, and `refresh` tag a synced file **shared** when other
layouts on `origin/main` also use its source in `instructions`, `sync`, or `copy`
(`shared: argos-dev, nero-dev`), so you know an edit reaches other teams. Refresh lists synced
files updated from Delphi with the last author and commit subject (`updated <dest> (<author>:
<subject>)`, `removed <dest>`, `copied <dest>`).

## 6. Unchanged from v1

PR path (temp worktree from `compile_commit`, provenance trailers, `--yes`, lease on the
propose branch, `gh` only for PRs), provenance resolution and the workspace commit hook,
`moves.tsv`, `delphi.conf`, harness adapters (names + launch + provenance), path safety
(`safe_path` on every path from config, flags, lock, manifests, `moves.tsv`), exit codes
(0 ok, 1 error, 2 refresh conflict), offline tolerance.

## 7. Removed

Line-level lock and hunk routing, instruction-fragment routing, built `.skill` specs,
MCP fragment assembly (MCP/settings are ordinary synced or copied files), manifest keys
`blocks`/`docs`/`skills`/`mcp`/`settings`, the interactive `layout new` picker (use `--from` or the
`delphi-new-layout` skill), and the bash CLI. v1 workspaces must be recreated
(`delphi` detects the old lock and says so).

## 8. check

Scopes have `scope.yml`; Delphi's own YAML (`scope.yml`, layout manifests) parses (other `.yml`
files are content and may use full YAML); scope `recommend` paths exist; manifests: `name` = directory and unique, adapter
exists, only known keys, entries well-formed, sources exist, dests safe and unique (no dest inside
another entry's dest, except a file inside a directory entry's dest where that directory has no
file; layout `files/` not under reserved paths), not both `instructions` and a `files/` instruction file; no file named after
an instruction file under `context/` except inside `layouts/*/files/`; `moves.tsv` rows
well-formed (three fields, safe paths); no symlinks, no empty files.
