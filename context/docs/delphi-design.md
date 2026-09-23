# Delphi — Context Repository Design

**Date:** 2026-09-23
**Status:** Draft for review
**Owner:** Application Software (NER)

## 1. Purpose

Delphi is a monorepo that stores Northeastern Electric Racing's AI-harness context — knowledge, instructions, skills, MCP definitions, settings — in a **compressed** form organized by the org chart, plus a small bash CLI that:

1. **Compiles** a chosen combination of that context (a *layout*) into an **uncompressed**, local, git-initialized *workspace* where a harness (Claude Code first) runs for real development.
2. **Refreshes** that workspace when Delphi's `main` moves.
3. **Proposes** changes made in the workspace back to the monorepo as a PR, routing each edit to the block it came from and recording the model, harness, and effort level used.

High-level commands stay simple; complexity lives in `lib/`.

## 2. Terminology

| Term | Meaning |
|---|---|
| **Scope** | A directory under `context/` representing an org unit (club → area → subteam → team). Identified by its path. |
| **Block** | A tracked unit of context, identified by its path relative to `context/`. |
| **Basic block** | Text/markdown under a scope's `blocks/`. |
| **Doc** | Project documentation (glossary, ADRs) under a scope's `docs/`, compiled into the workspace's `docs/`. |
| **Harness block** | Under a scope's `harness/`: instruction fragments, skills, MCP fragments, settings. |
| **Layout** | A `manifest.yml` under a scope's `layouts/<name>/` selecting blocks, a harness, and code repos. Compressed side. |
| **Workspace** | A local git-initialized directory, outside the repo, compiled from a layout. Uncompressed side. Many workspaces may come from one layout. |
| **Compile** | The deterministic function `(delphi commit, layout) → files + lock`. |
| **Lock** | `.delphi/lock.tsv`: segment map from compiled output line ranges to their sources. |
| **Segment** | A contiguous line range of one output file that came from one source. |
| **Pending diff** | `git diff generated-merged HEAD` over routable paths: everything the workspace has changed relative to its latest compile. |

## 3. Repository structure

```
Delphi/
├── CLAUDE.md                        # for developing Delphi itself
├── .claude/skills/
│   ├── delphi-new-layout/           # LLM workflow: build a layout from recommendations
│   └── delphi-propose/              # LLM workflow: resolve unresolved items, then propose
├── delphi.conf                      # key=value repo config
├── moves.tsv                        # block rename/move log
├── bin/delphi                       # dispatcher
├── lib/
│   ├── core.sh                      # config, logging, prompts, safe_path, layout lookup, move resolution
│   ├── parse.sh                     # awk YAML-subset parser
│   ├── compile.sh                    # layout → files + lock
│   ├── route.sh                     # pending diff + lock → routing plan
│   ├── pr.sh                        # temp worktree, commit w/ trailers, push + gh PR
│   ├── provenance.sh                # resolve harness/model/effort
│   ├── layout.sh                    # `delphi layout …`
│   ├── workspace.sh                 # `delphi workspace …`
│   ├── block.sh                     # `delphi block …`
│   ├── check.sh                     # `delphi check`
│   └── harness/
│       └── claude-code.sh           # harness adapter
└── context/                         # root scope = NER club-wide
    ├── scope.yml
    ├── blocks/  docs/  harness/  layouts/
    └── software/                    # child scope
        ├── scope.yml
        ├── blocks/  docs/  harness/  layouts/
        ├── finishline/
        ├── application-software/
        │   ├── argos/
        │   └── nero/
        └── firmware/
            └── …
```

### 3.1 Scope shape

Every scope directory contains a required `scope.yml` and any of these **reserved** subdirectories:

```
<scope>/
├── scope.yml
├── blocks/                          # basic blocks: *.md, *.txt (subdirs allowed)
├── docs/                            # project docs: CONTEXT.md, adr/*.md (subdirs allowed)
├── harness/
│   ├── instructions/*.md            # fragments stacked into the harness instruction file
│   ├── skills/<name>/SKILL.md (+ any files)   # native skill
│   ├── skills/<name>.skill          # built skill spec
│   ├── mcp/<name>.json              # MCP server fragment
│   └── settings/<name>.json         # harness settings file
└── layouts/<name>/manifest.yml
```

Any other subdirectory is a child scope. Scope names follow the Fall 2026 roster structure (`Software → FinishLine | Software Product | Application Software → {Argos, NERO} | Firmware → {…}`); scopes are created as content arrives, not up front.

**No file anywhere under `context/` may be named after a harness instruction file** (`CLAUDE.md`, `AGENTS.md`, …) — enforced by `check`.

### 3.2 Workspace location

Workspaces compile **outside** the repo so Delphi's own `CLAUDE.md` is never loaded as an ancestor file:

```
<workspace_root>/                    # default ../Delphi-workspaces (relative to repo root)
├── argos-dev/
└── argos-dev--bug-612/
```

## 4. File formats

### 4.1 YAML subset (parsed by `lib/parse.sh`)

All `.yml` and `.skill` files use this subset:

- Full-line `#` comments and trailing ` #` comments.
- Top-level `key: value` (scalar; unquoted or `"double-quoted"`).
- Top-level `key:` followed by `  - item` lines (list; two-space indent).
- Top-level `key:` followed by `  subkey: value` lines (one-level map; two-space indent).
- **Not supported** (parse error with `file:line`): tabs, anchors/aliases, flow style (`[a, b]`, `{}`), multi-line strings, deeper nesting.

Parser output (tab-separated, one record per line):

| Construct | Output |
|---|---|
| scalar | `key<TAB>value` |
| list item | `key<TAB>value` (repeated) |
| map entry | `key<TAB>subkey<TAB>value` |

Consumers know each key's type from the schemas below. Parser uses POSIX awk only (verified against BSD awk and mawk).

### 4.2 `scope.yml`

```yaml
name: Argos
recommend:                            # paths relative to context/; offered, never auto-included
  - software/application-software/argos/blocks/overview.md
  - software/application-software/argos/harness/skills/run-tests
```

### 4.3 `manifest.yml` (layout)

```yaml
name: argos-dev                       # must equal the layout directory name; unique repo-wide
harness: claude-code                  # required; must match lib/harness/<harness>.sh
instructions:                         # stacked, in order, into $HARNESS_INSTRUCTIONS
  - software/harness/instructions/base.md
  - software/application-software/argos/harness/instructions/argos.md
blocks:                               # basic blocks; trailing * glob allowed (non-recursive, sorted)
  - software/application-software/argos/blocks/*
docs:                                 # project docs; same entry rules as blocks
  - software/application-software/argos/docs/CONTEXT.md
  - software/application-software/argos/docs/adr/*
skills:                               # native skill dir or .skill spec
  - software/application-software/argos/harness/skills/run-tests
mcp:
  - software/harness/mcp/github.json
settings: software/harness/settings/default.json   # optional; at most one in v1
repos:                                # name: git URL
  argos: git@github.com:Northeastern-Electric-Racing/Argos.git
```

All paths are relative to `context/`. Only `name` and `harness` are required. Unknown keys are errors.

### 4.4 `.skill` (built skill spec)

```yaml
name: run-tests
description: Run and interpret Argos test suites.
body:                                 # stacked into SKILL.md body
  - software/application-software/argos/blocks/testing.md
references:                           # copied to references/<basename>
  - software/application-software/argos/blocks/ci.md
```

Lets one basic block serve as plain context in one layout and as a skill in another without duplication.

### 4.5 MCP fragment

Each `harness/mcp/<name>.json` contains exactly one member of the `mcpServers` object, no trailing comma:

```json
"github": {
  "command": "gh-mcp",
  "args": []
}
```

### 4.6 `delphi.conf`

```
workspace_root=../Delphi-workspaces
stale_days=14
```

Parsed line-by-line as `key=value` (never `source`d). Relative paths resolve against the repo root. `DELPHI_WORKSPACE_ROOT` env var overrides `workspace_root`.

### 4.7 `moves.tsv`

```
# old<TAB>new<TAB>date
software/blocks/git.md	software/blocks/git-conventions.md	2026-10-02
software/application-software/argos/blocks/old-dir	software/application-software/argos/blocks/ops	2026-10-05
```

Append-only. Rows are applied **in order, each once** (exact match, or directory-prefix match for directory entries), and only the rows that are new to the consumer: `block mv` applies the row it appends; a workspace applies the rows added since its `compile_commit`. Paths may therefore be reused, and a block can be moved back.

### 4.8 `lock.tsv`

```
# output	start	end	source	sha
CLAUDE.md	1	3	@gen:delphi	-
CLAUDE.md	4	4	@glue	-
CLAUDE.md	5	44	software/harness/instructions/base.md	a1b2c3…
CLAUDE.md	45	45	@glue	-
CLAUDE.md	46	92	software/application-software/argos/harness/instructions/argos.md	d4e5f6…
.claude/skills/run-tests/SKILL.md	1	4	@gen:software/application-software/argos/harness/skills/run-tests.skill	-
.claude/skills/run-tests/SKILL.md	5	60	software/application-software/argos/blocks/testing.md	f7a8b9…
.delphi/manifest.yml	1	20	software/application-software/argos/layouts/argos-dev/manifest.yml	0c1d2e…
```

`sha` is the git blob id of the source at the compiled commit. Every line of every compiled file except `lock.tsv` itself belongs to exactly one segment. Source kinds: a path under `context/`, `@glue` (separator lines), `@gen:<origin>` (generated lines).

### 4.9 Workspace state

| Location | In workspace git? | Contents |
|---|---|---|
| `.delphi/manifest.yml` | tracked (compiled) | Editable copy of the layout manifest; edits propose back to the layout. |
| `.delphi/lock.tsv` | tracked (compiled) | Segment map of the compile. Always read from `generated-merged`, never the working copy. |
| `.git/delphi/meta` | not tracked (inside `.git/`) | `key=value`: `layout`, `layout_path`, `ref` (Delphi branch the workspace tracks, default `main`), `created`, `last_proposed`, `last_proposed_hash`, `last_pushed`, `pending_since`, `compile_commit` (the Delphi commit `generated-merged`'s content corresponds to — authoritative; may be newer than that commit's trailer when later compiles were identical). |
| `.git/info/exclude` | not tracked | `repos/`, `worktrees/`, `$HARNESS_IGNORE`. |
| `.git/hooks/commit-msg` | not tracked | Provenance trailer hook (§9). |

Keeping state inside `.git/` means Delphi bookkeeping never dirties the working tree and never shows up in the pending diff.

**Refs in the workspace repo:**

| Ref | Meaning |
|---|---|
| `generated` (branch) | History of compiles only. Each commit's message is `delphi: compile <layout>@<short-sha>` with trailer `Delphi-Compile: <full delphi commit>`. |
| `generated-merged` (tag) | The latest compile that has been **merged into `working`**. Its current Delphi commit is `meta.compile_commit`. |
| `working` | The user's branch, where all development happens. |

`generated` and `generated-merged` differ only while a refresh is pending (compile committed, merge not yet completed).

The workspace repo is created with `git init` and shares no history with Delphi; none of these refs are Delphi branches. `generated` holds only Delphi's compiled output (never user work); `working` starts from the first compile and merges each later one. The only links back to Delphi are the `Delphi-Compile` trailer text and `meta.compile_commit`.

## 5. Compiling (`lib/compile.sh`)

`compile <commit> <layout-path> <outdir>`: deterministic. Reads sources from a temporary detached worktree of Delphi at `<commit>`, writes output files and `<outdir>/.delphi/lock.tsv`. Each source file's content is emitted with a trailing newline added if missing, so segments never share a line.

| Manifest key | Output | Segments |
|---|---|---|
| `instructions` | `$HARNESS_INSTRUCTIONS`: delphi header, then fragments in order, one blank line between each. Emitted even when the list is empty (header only). | `@gen:delphi` header, `@glue` blank lines, block per fragment |
| `blocks` | `context/<path>` — mirrors the block's path exactly (e.g. `software/application-software/argos/blocks/ops/x.md` → `context/software/application-software/argos/blocks/ops/x.md`) | one segment per file |
| `docs` | `docs/<path below the scope's docs/>` (e.g. `software/application-software/argos/docs/adr/0001-x.md` → `docs/adr/0001-x.md`) | one segment per file |
| `skills` (native) | `$HARNESS_SKILLS_DIR/<name>/…`, each file copied 1:1 | one segment per file |
| `skills` (`.skill`) | `$HARNESS_SKILLS_DIR/<name>/SKILL.md` = generated frontmatter (`name`, `description`) + body blocks with `@glue` between; references copied to `references/<basename>` | `@gen:<spec>` frontmatter, block per body/reference |
| `mcp` | `$HARNESS_MCP_FILE`: `{"mcpServers": {` + fragments separated by a `,` line + `}}`. Omitted when the list is empty. | `@gen:delphi` wrapper, block per fragment, `@glue` commas |
| `settings` | `$HARNESS_SETTINGS_FILE`, copied 1:1 | one segment |
| (always) | `.delphi/manifest.yml` copy of the layout manifest | one segment |

**Delphi header** (top of the instruction file, placed first so appends at the end of the file land in a real block): a short note that this workspace was compiled by Delphi from layout `<name>`, that edits are expected, and that finished work should be committed so `delphi workspace propose` can send it upstream.

Compile errors (missing path, empty glob, parse error, duplicate output path, unsafe path) abort with no partial output.

## 6. Commands

`bin/delphi <group> <verb> [args]`. `ws` is an alias for `workspace`. Commands that take `[<workspace>]` default to the workspace containing the current directory.

**Common flags** for commands that write to Delphi (`layout new`, `block mv`, `workspace propose`): `--model <m>`, `--effort <e>` (provenance, §9) and `--yes` (skip the push confirmation; also `DELPHI_YES=1`). Without `--yes`, a non-interactive run (no TTY — e.g. an agent's shell tool) fails fast with a message to pass `--yes` rather than hanging.

### 6.1 `delphi layout new <scope> <layout> [--from <file>]`

1. Validate: scope has `scope.yml`; `<layout>` matches `[a-z0-9-]+` and is unique repo-wide.
2. Without `--from` (basic script): collect `recommend` entries from the scope and each ancestor (closest first, deduped); ask y/n per item; ask harness (choices = `lib/harness/*.sh`); prompt for repos (`name url` lines until blank). Items are placed into manifest keys by path: `*/harness/instructions/*` → `instructions`, `*/harness/skills/*` → `skills`, `*/harness/mcp/*` → `mcp`, `*/harness/settings/*` → `settings` (more than one → re-ask), `*/blocks/*` → `blocks`, `*/docs/*` → `docs`.
3. With `--from`: use the given manifest verbatim (used by the `delphi-new-layout` skill).
4. Via `pr.sh` (§7): write `context/<scope>/layouts/<layout>/manifest.yml`, run `check`, commit, PR on branch `delphi/layout/<layout>`. Prints the branch name.

### 6.2 `delphi layout list`

Prints `name<TAB>scope<TAB>harness` for every layout on `origin/main`.

### 6.3 `delphi workspace new <layout> [--as <workspace>] [--ref <branch>]`

1. `git fetch`. Resolve the layout by name **in the tree of `origin/<ref>`** (default `main`), following `moves.tsv` at that commit. Workspace name defaults to the layout name; error if `<workspace_root>/<workspace>` exists.
2. Compile at `origin/<ref>` into a temp dir.
3. `git init` the workspace; write `.git/info/exclude`, `.git/delphi/meta` (with `ref`, `pending_since` empty), and the `commit-msg` hook.
4. Copy the compile in, commit on `generated`, tag `generated-merged`, create and check out `working` from it; set `meta.compile_commit`. The working tree is clean.
5. Clone each repo into `repos/<name>`; create empty `worktrees/`. Clone failures warn and are summarized at the end; the workspace is still usable.

`--ref` lets you try a layout before its PR merges (`workspace new argos-dev --ref delphi/layout/argos-dev`). Such a workspace refreshes from that branch; `propose` refuses until the layout exists on `main` (§6.6), and `refresh --ref main` switches it over once merged.

### 6.4 `delphi workspace open [<workspace>] [--model m] [--effort e] [--shell]`

1. Resolve workspace (argument, current directory, or numbered picker over `status` output).
2. Warn if the compile is behind its ref (suggest `refresh`) or if any workspace is `unproposed` for more than `stale_days`.
3. Export `DELPHI_HARNESS`, `DELPHI_MODEL`, `DELPHI_EFFORT` and `exec harness_launch` in the workspace directory; with `--shell`, `exec $SHELL` there instead.

### 6.5 `delphi workspace refresh [<workspace>] [--ref <branch>]`

Idempotent; re-running always picks up where it left off. No `--continue`.

1. Require a clean working tree and no merge in progress. `--ref` updates `meta.ref` first.
2. `git fetch` Delphi; resolve the layout path through `moves.tsv` at `origin/<ref>`; update `meta.layout_path`.
3. **Compile step** — skipped if `generated` is ahead of `generated-merged` (a pending refresh): compile at `origin/<ref>` commit `C` into a temporary worktree of the workspace repo checked out on `generated`, replacing its tracked contents.
   - Content changed → commit with trailer `Delphi-Compile: C`.
   - Content identical → set `meta.compile_commit = C` (no commits; keeps the recorded commit current, e.g. after a squash-merged layout PR or unrelated `main` activity), report "up to date", exit 0.
   If `origin/<ref>` no longer exists, fail with "branch `<ref>` is gone — run `refresh --ref main`".
4. **Merge step** — skipped if `generated` is already an ancestor of `HEAD`: `git merge --no-edit generated`. On conflict, exit **2**: "resolve conflicts, commit, then re-run `delphi workspace refresh`."
5. **Finalize** (only once `generated` is an ancestor of `HEAD`): move tag `generated-merged` to `generated`; set `meta.compile_commit` from that commit's `Delphi-Compile` trailer. Rewrite any moved paths in `.delphi/manifest.yml`; if changed, commit `delphi: apply moves`. If the pending diff is now empty, set `meta.pending_since = HEAD`. Exit 0.

All commits Delphi itself makes in a workspace (compiles, merges, `apply moves`) use `--no-verify` so the provenance hook never tags them.

**Exit codes:** 0 = up to date or finalized; 2 = merge conflict awaiting resolution; 1 = error.

If a refresh is pending when `--ref` changes, the pending compile is merged and finalized first, then the compile step runs once more against the new ref. Compile and merge commits only appear in workspace history when the compiled content actually changed.

### 6.6 `delphi workspace propose [<workspace>] [--dry-run]`

**One live PR per workspace**, on branch `delphi/propose/<gh-user>/<workspace>` (`<gh-user>` from `gh api user --jq .login`; workspace names are local, so the user part prevents teammates' branches colliding). Each propose rebuilds that branch from scratch with the **entire** current pending diff and force-updates it, so the PR always equals "everything this workspace still differs from `main` by." Proposing twice never duplicates; a merged PR's changes drop out after the next refresh; a closed/rejected change keeps reappearing until it is reverted in the workspace (the documented escape hatch).

1. `--dry-run`: skip refresh; route against the current `generated-merged` (warn if behind); print the plan and unresolved items; change nothing; stop.
2. Require a clean working tree and `meta.ref = main` (else: "layout not on main yet — merge its PR, then `refresh --ref main`"). Run `refresh`; continue only if it exits 0.
3. Compute the pending diff and route it (§8) into a plan.
4. If the plan has no routed changes and no unresolved items: print "nothing to propose", exit 0.
5. Via `pr.sh`, building from `meta.compile_commit` (so patches apply exactly), in order:
   1. **Layout manifest** — if `.delphi/manifest.yml` changed, replace the layout manifest with it (moved paths resolved).
   2. **Block edits** — apply routed hunks.
   3. **New blocks** — add files; append each to the layout manifest's `blocks:`/`docs:`/`skills:` unless an existing entry or glob already covers it.
   4. Run `check`; abort (no push) on failure, printing the violations.
   Each step with changes is one commit with provenance trailers.
6. Push (force, with an explicit lease — §7); `gh pr create` if no open PR exists for the branch, otherwise `gh pr edit` to replace the body. Refuse if an open PR on the branch was authored by someone other than the current `gh` user. PR body: routed-change summary, provenance table (§9), **Unresolved** section (each item as a fenced diff with its workspace path and reason).
7. Set `meta.last_proposed` = today and `meta.last_proposed_hash` = pending diff hash.

**Pending diff hash:** `git hash-object` of the `-U0` pending diff with `@@` hunk headers and `index` lines stripped, so upstream changes that only shift line numbers don't flip a workspace back to `unproposed`.

### 6.7 `delphi workspace status [--offline]`

For each directory in `workspace_root` containing `.git/delphi/meta`, print: workspace, layout, ref, dirty flag, **state**, age, behind flag.

| State | Condition |
|---|---|
| `clean` | pending diff empty |
| `proposed` | pending diff hash = `last_proposed_hash` |
| `unproposed` | otherwise |

Age = days since `last_proposed` (or `created`) for `unproposed`. Behind = `origin/<ref>` has commits since `meta.compile_commit` touching any lock source, the layout manifest, or a directory covered by a manifest glob. `--offline` skips `git fetch`. Status cannot see whether a PR was closed; a rejected workspace stays `proposed` until its change is reverted or re-proposed.

### 6.8 `delphi block mv <old> <new>`

Only paths under a scope's `blocks/`, `docs/`, or `harness/` (layouts cannot be moved in v1). Via `pr.sh`: validate `old` exists and `new` does not, both inside `context/`; `git mv`; append to `moves.tsv`; rewrite exact and directory-prefix references in every `manifest.yml`, `scope.yml`, and `.skill`; run `check`; commit; PR on branch `delphi/mv/<basename>-<YYYYMMDD>`. Existing workspaces pick up the move on their next `refresh`/`propose`.

### 6.9 `delphi check`

Exits non-zero listing every violation:

- Every scope directory has `scope.yml`; every `.yml`/`.skill` parses.
- Manifests: required keys present, no unknown keys, `name` equals directory, harness adapter exists, at most one `settings`, layout names unique.
- Every referenced path exists (each glob matches ≥1 file) and resolves inside `context/`.
- Entries are under the key matching their location (`skills` entries are a dir with `SKILL.md` or a `.skill` file, etc.).
- No file under `context/` is named any adapter's `$HARNESS_INSTRUCTIONS`.
- `moves.tsv` rows well-formed.
- MCP fragments form valid JSON when wrapped — only if `jq` is installed; otherwise skipped with a note.

## 7. Writing to Delphi (`lib/pr.sh`)

All commands that modify the monorepo use one path:

1. `git fetch --prune`; create a temporary worktree of Delphi on the command's branch, starting from a given commit (default `origin/main`). The user's own checkout is never touched.
2. Caller applies changes inside it.
3. Commit with provenance trailers (§9).
4. Confirm `Push <branch> and open/update PR? [y/N]` unless `--yes`; then push and `gh pr create` / `gh pr edit` with the caller's body plus the provenance table. Propose branches are force-pushed with an explicit lease: `--force-with-lease=<branch>:<sha>` where `<sha>` is `meta.last_pushed`, the commit this workspace last pushed (empty when the branch is absent on the remote, e.g. auto-deleted after a merge). If the remote branch exists but differs from `last_pushed`, someone else pushed to it: propose stops ("review the PR, then re-run"), records the remote sha, and the next run overwrites it.
5. Remove the temp worktree via `trap` on success or failure.

## 8. Change routing (`lib/route.sh`)

Input: pending diff (`git diff --no-renames generated-merged HEAD`), excluding `repos/`, `worktrees/`, `.delphi/lock.tsv`. Lock read from `generated-merged`. Output: plan rows `kind<TAB>workspace-path<TAB>target[<TAB>reason]`. Checked in this order per file:

| # | Change | Result |
|---|---|---|
| 1 | `.delphi/manifest.yml` modified | layout manifest replace (whole file) |
| 2 | Binary | unresolved |
| 3 | Deleted | no-op if its source is no longer referenced by the workspace's `.delphi/manifest.yml` (dropped via the manifest); otherwise unresolved — blocks are dropped by editing `.delphi/manifest.yml` |
| 4 | Modified, in lock | per-hunk routing (below) |
| 5 | Added at `context/<p>` where `<p>` is `<scope>/blocks/…` and `<scope>` is an existing scope at `meta.compile_commit` | new block at `<p>` |
| 5a | Added at `docs/<d>/<f>` | new doc beside the compiled docs already in `docs/<d>/` (their source directory), else at `<layout-scope>/docs/<d>/<f>` |
| 6 | Added under `$HARNESS_SKILLS_DIR/<name>/` where `<name>` is a native skill in the lock | new file in that skill's source directory |
| 7 | Added under `$HARNESS_SKILLS_DIR/<name>/` where `<name>` is not in the lock | new native skill at `<layout-scope>/harness/skills/<name>/` |
| 8 | Anything else | unresolved |

**Hunk routing** (from `git diff -U0`; base-side range `a,n`; patches applied with `git apply --unidiff-zero`):

| Hunk | Result |
|---|---|
| All base lines `a..a+n-1` inside one block segment | patch that block (`block_line = base_line − seg.start + 1`) |
| Insertion (`n = 0`) after line `a`, where `seg.start ≤ a < seg.end` of a block segment | patch that block |
| Insertion after the last line of a block segment (`a = seg.end`), when the next line is end-of-file or a non-block segment | append to that block |
| Insertion at file start (`a = 0`), when the first segment is a block | prepend to that block |
| Insertion right after a `@glue`/`@gen` segment (`a = seg.end`), when the next segment is a block | prepend to that next block |
| Inside `@gen:<path>.skill`, touching only `name:`/`description:` lines | rewrite those keys in the `.skill` spec |
| Anything else: in `@glue`/other `@gen`, spanning segments, or `git apply` fails (e.g. the same block edited in two outputs) | unresolved |

**Replacing a block** needs no special case: swap the entry in `.delphi/manifest.yml` (old path → new path), delete the old compiled file, and add the new one under `context/<scope>/blocks/`. The deletion is a no-op (rule 3), the manifest edit routes by rule 1, and the new file by rule 5.

**Placement is strict by design:** a file not in a recognised location stays unresolved; Delphi never guesses where it belongs.

All routed hunks for one (output file, block) pair are combined into a single patch so line offsets stay consistent.

Unresolved items never block the PR; they are listed in it. They are resolved by changing the **workspace** so the change becomes routable (move text into a block's region, move a new file under `context/<scope>/blocks/`, edit `.delphi/manifest.yml`, or revert it), then proposing again.

## 9. Provenance

Every commit Delphi writes to the monorepo carries trailers; every PR body repeats them as a table.

```
Delphi-Harness: claude-code 2.4.1
Delphi-Model: claude-opus-5-5
Delphi-Effort: high
Delphi-Layout: software/application-software/argos/layouts/argos-dev
Delphi-Workspace: argos-dev--bug-612        # propose only
Delphi-Base: 0cdd375                        # propose only: meta.compile_commit
```

**Resolution order** (`lib/provenance.sh`), per field: CLI flag → `DELPHI_*` env (set by `workspace open`) → adapter's `harness_provenance` fallback. If still missing: prompt when interactive (accepting `none` for runs without an LLM); error when non-interactive. Never written as "unknown".

**Workspace commit hook:** `.git/hooks/commit-msg` appends `Delphi-Harness/Model/Effort` trailers from `DELPHI_*` env vars when set and not already present.

**Propose aggregation:** the PR table lists the proposing session's values plus each distinct trailer combination from non-merge workspace commits in `pending_since..HEAD` (all of `working` if `pending_since` is empty).

**Known gap:** if the model changes mid-session (e.g. `/model`), the env vars from `workspace open` go stale; flags on `propose` override.

## 10. Harness adapter contract

`lib/harness/<name>.sh` is sourced and must define:

| Name | Kind | claude-code value |
|---|---|---|
| `HARNESS_INSTRUCTIONS` | var | `CLAUDE.md` |
| `HARNESS_SKILLS_DIR` | var | `.claude/skills` |
| `HARNESS_MCP_FILE` | var | `.mcp.json` |
| `HARNESS_SETTINGS_FILE` | var | `.claude/settings.json` |
| `HARNESS_IGNORE` | var | `.claude/settings.local.json` |
| `harness_provenance` | fn | prints 3 lines: `claude-code <version>`, model, effort (from `CLAUDE_CODE_EFFORT_LEVEL` when set) |
| `harness_launch <model> <effort>` | fn | `exec claude` with `--model` when given and `CLAUDE_CODE_EFFORT_LEVEL` set |

The generic compiler does all file work; adapters only supply names and two functions. New harnesses = new adapter file.

## 11. LLM workflows (Delphi repo skills)

- **`delphi-new-layout`** (primary way to create layouts): interviews the user about the work, reads `scope.yml` recommendations up the scope chain and browses available blocks, drafts a manifest, shows it for approval, then runs `delphi layout new <scope> <name> --from <draft> --model … --effort … --yes`. Optionally follows with `delphi workspace new <name> --ref delphi/layout/<name>` to try it.
- **`delphi-propose`**: runs `delphi workspace propose --dry-run`, walks the user through each unresolved item with a suggested fix in the workspace (per §8's resolution list), applies and commits approved fixes, then runs `delphi workspace propose --model … --effort … --yes`.

Both are optional conveniences; every operation is available through the scripts alone.

## 12. Cross-cutting rules

- **Locating Delphi:** `bin/delphi` resolves its own real path (a `readlink` loop, no `readlink -f`) and uses its parent as the repo root, both in the Delphi checkout and inside workspaces. Install = put `Delphi/bin` on `PATH` or symlink `bin/delphi`.
- **Bash 3.2 compatible** (macOS default): no associative arrays, `mapfile`, `${x,,}`, etc. `set -euo pipefail` in every entry point.
- **Dependencies:** `git`, `awk` (POSIX features only), `sed`, `gh` (only for opening PRs). `jq` optional (check only). Blob ids and diff hashes via `git hash-object`.
- **Path safety:** every path from config, flags, lock, or `moves.tsv` goes through `safe_path <root> <rel>` (rejects absolute paths, `..` escapes, and symlinks resolving outside `<root>`) before any read, write, or delete. Deletes happen only via `git` or inside `mktemp -d` dirs. (Prior prototypes all failed this.)
- **Errors:** actionable messages naming the file/line or command to run next; temp worktrees cleaned via `trap`; multi-step operations are idempotent on re-run, never half-applied silently.

## 13. Out of scope for v1

- Automated tests and CI (deferred by decision until the working version has been used).
- Seed content (Argos scope and layout come next, separately).
- Harness adapters other than claude-code.
- Merging multiple settings files; recursive globs; automatic routing of deletions; moving/renaming layouts.
- Managing `worktrees/` beyond creating the directory (use `git worktree` directly).
- Mechanical, Electrical, and Business scopes.

## 14. Resolved decisions

- Default `workspace_root` is `../Delphi-workspaces` (sibling of the Delphi clone); configurable via `delphi.conf` or `DELPHI_WORKSPACE_ROOT`.
