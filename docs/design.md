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
- Default dest (when `->` is omitted), by source path:
  `…/harness/skills/<n>[/…]` → `<skills dir>/<n>[/…]`; `…/docs/<rest>` → `docs/<rest>`;
  anything else → `context/<source>`.
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
CLAUDE.md	-	assembled
.claude/skills/run-local/SKILL.md	software/…/harness/skills/run-local/SKILL.md	sync
CLAUDE.md	software/…/layouts/argos-dev/files/CLAUDE.md	layout     (when not assembled)
.delphi/manifest.yml	software/…/layouts/argos-dev/manifest.yml	layout
```

Copied files are **not** part of the compile. They are committed to `working` directly
(`delphi: copy …`) when first listed, and recorded in `.git/delphi/copied`
(`dest<TAB>source<TAB>delphi-commit`). They are never overwritten or proposed.

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
| `block mv <old> <new>` | move a source, log it in `moves.tsv`, rewrite manifests; workspaces follow on refresh |
| `check` | validate the repo (below) |
| `setup [dir]` | remember where the Delphi checkout is |

`propose --dry-run` prints the same listing as `workspace diff`.

## 5. What changed, and where it goes (routing)

Pending diff = `generated-merged..HEAD` (committed changes only). Per changed file:

| Change | Result |
|---|---|
| synced or layout file, modified (incl. binary, mode) | copy the file over its source |
| synced or layout file, deleted | no-op if its entry was removed from `.delphi/manifest.yml`, else unresolved |
| new file inside a synced **directory** | new file in that source directory |
| new `sync` entry in `.delphi/manifest.yml` whose source doesn't exist yet | source created from the workspace file(s) |
| `.delphi/manifest.yml` modified | replaces the layout manifest |
| assembled instruction file | unresolved ("generated; sync a part to edit it") |
| anything else (copies, new files elsewhere) | **local**: listed, never proposed |

One source synced to several dests: identical edits route once; differing edits are unresolved.
Unresolved items are listed in the PR body; they never block it.

**Shared awareness.** `diff`, `propose`, and `refresh` tag a synced file **shared** when other
layouts on `origin/main` also use its source (`shared: argos-dev, nero-dev`), so you know an edit
reaches other teams. Refresh lists synced files updated from Delphi with the last author and
commit subject.

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

Scopes have `scope.yml`; every `.yml` parses; manifests: `name` = directory and unique, adapter
exists, only known keys, entries well-formed, sources exist, dests safe and unique (no dest inside
another entry's dest), not both `instructions` and a `files/` instruction file; no file named after
an instruction file under `context/` except inside `layouts/*/files/`; `moves.tsv` rows
well-formed; no symlinks, no empty files.
