# Delphi CLI — Goals

What the CLI must achieve, not how it does it. Use this as the acceptance checklist for any
rewrite. The IDs are stable, so refer to goals by ID. The design spec is
`context/docs/delphi-design.md`. Where the spec and the bash implementation disagree, this file
follows the code and records the difference in section 5.

## 1. Purpose

Delphi stores NER's AI-harness context (instructions, knowledge blocks, docs, skills, MCP, settings)
once, in a compressed form organized by the org chart under `context/`. The CLI turns a chosen
combination of that context into a working directory where a harness (Claude Code) runs. It keeps
that directory current as Delphi changes. It sends edits made there back to Delphi as a pull
request, with each edit landing in the source file it came from and a record of the model, harness,
and effort that produced it.

## 2. Concepts

| Term | Meaning |
|---|---|
| Scope | A directory under `context/` for an org unit. It has a `scope.yml` and may contain `blocks/`, `docs/`, `harness/`, `layouts/`, and child scopes. |
| Block | A tracked source file, identified by its path relative to `context/`. It can be a basic block, a doc, an instruction fragment, a skill, an MCP fragment, or a settings file. |
| Layout | `<scope>/layouts/<name>/manifest.yml`. It selects blocks, a harness, and code repos. Its name is unique across the repo. |
| Workspace | A local git repo outside Delphi, compiled from a layout. One layout can have many workspaces. |
| Compile | A deterministic function from (Delphi commit, layout) to files plus a lock. |
| Lock | `.delphi/lock.tsv`. It maps every line range of every compiled file to its source block, or marks it as generated or separator text. |
| Pending diff | Everything the workspace has changed since its latest merged compile. This is what propose sends. |

## 3. Goals by command

### Compile
- **C1** The output is determined entirely by the Delphi commit and the layout. The same inputs give byte-identical files and lock.
- **C2** The instruction file is a short Delphi header, then the listed fragments in order, with one blank line between each. It is emitted even when no fragments are listed.
- **C3** Basic blocks are mirrored at `context/<same path>`. Docs go to `docs/<path below the scope's docs/>`. Native skill directories are copied 1:1, keeping the executable bit. The settings file is copied 1:1.
- **C4** A built skill (`.skill` spec) becomes one `SKILL.md`: generated frontmatter (`name`, `description`) followed by the listed body blocks. Its references are copied to `references/<basename>`.
- **C5** MCP fragments are wrapped into a single `{"mcpServers": {...}}` file with comma separators. The file is omitted when no fragments are listed.
- **C6** An editable copy of the layout manifest is always emitted at `.delphi/manifest.yml`.
- **C7** Every line of every output (except the lock itself) belongs to exactly one lock segment: a source block with its blob id, a separator (`@glue`), or generated text (`@gen:<origin>`). Each source ends with a newline, so segments never share a line.
- **C8** A trailing `/*` glob in `blocks`/`docs` expands to that directory's files, non-recursively and sorted.
- **C9** Compile fails with no partial output on any of these: a missing or empty source, an empty glob, a parse error, two sources mapping to one output, an unsafe path, or an entry under the wrong key (for example a `blocks:` entry outside `blocks/`).

### workspace new `<layout> [--as ws] [--ref branch]`
- **WN1** Fetches, then finds the layout by name in `origin/<ref>` (default `main`) and compiles it at that commit.
- **WN2** Creates `<workspace_root>/<ws>` (default name = layout name) as a new git repo with no Delphi history. It fails if the directory already exists.
- **WN3** Afterwards the user is on their own branch, with a clean tree equal to the compile. The compile is also recorded as the "latest merged compile" baseline.
- **WN4** Clones each manifest repo into `repos/<name>`. A failed clone produces a warning and a summary at the end, but the workspace is still created. `repos/`, `worktrees/`, and the harness's local-settings file are git-ignored locally.
- **WN5** Installs a commit hook that tags the user's commits with provenance (V3).
- **WN6** `--ref` lets a user try a layout before its PR merges. The workspace then tracks that branch.

### workspace open `[ws] [--model] [--effort] [--shell]`
- **WO1** Finds the workspace from the argument, then the current directory, then a numbered picker (TTY only).
- **WO2** Warns if the workspace is behind its ref, and if any workspace has been unproposed longer than `stale_days`.
- **WO3** Launches the harness in the workspace with `DELPHI_HARNESS/MODEL/EFFORT` exported. With `--shell`, it opens `$SHELL` instead.

### workspace refresh `[ws] [--ref branch]`
- **WR1** Brings the workspace up to date with `origin/<ref>` by merging the new compile into the user's branch. User edits are kept.
- **WR2** Refuses to run on a dirty tree or while a merge is in progress. `--ref` changes the tracked branch first.
- **WR3** Idempotent and resumable. Re-running picks up where it left off, and there is no `--continue`. A merge conflict exits with **2** and tells the user to resolve it, commit, and re-run.
- **WR4** If the compiled content is unchanged, refresh adds no commits. It still records the new Delphi commit as the baseline and reports "up to date".
- **WR5** Follows block and layout moves recorded since the last compile. The layout path is updated, and moved paths in `.delphi/manifest.yml` are rewritten and committed.
- **WR6** If the tracked branch no longer exists, refresh fails and tells the user to run `refresh --ref main`.
- **WR7** Delphi's own commits in the workspace never receive provenance trailers.

### workspace status `[--offline]`
- **WS1** Prints one row per workspace: name, layout, ref, dirty, state, age, behind, and a suggested next command. It ends with a summary line.
- **WS2** State is `clean` (empty pending diff), `proposed` (pending diff unchanged since the last push), or `unproposed`. A change that only shifts line numbers does not flip a workspace back to `unproposed`.
- **WS3** Behind means `origin/<ref>` has commits since the baseline that touch this workspace's sources, its layout manifest, or a globbed directory. If the branch is gone, the value is `gone`.
- **WS4** Age is shown only for unproposed workspaces. A workspace unproposed longer than `stale_days` is marked stale. `--offline` skips the fetch.

### workspace propose `[ws] [--dry-run] [--model] [--effort] [--yes]`
- **WP1** `--dry-run` changes nothing. It routes against the current baseline (warning if behind) and prints the plan and the unresolved items with their diffs.
- **WP2** Refuses unless the workspace tracks `main`. Refreshes first and continues only on success (exit 2 propagates).
- **WP3** Each workspace has one live PR, on branch `delphi/propose/<gh-user>/<ws>`. Every propose rebuilds that branch from the baseline commit with the entire pending diff and force-updates it. Proposing twice never duplicates, and merged changes drop out after the next refresh.
- **WP4** The PR is built in ordered commits: the layout manifest, then block edits, then new files. Each commit carries provenance trailers. `check` must pass, or nothing is pushed.
- **WP5** If there is nothing to propose, it says so and exits 0. It warns if a previously pushed PR is still open.
- **WP6** Refuses to overwrite a propose branch that someone else pushed to. It records what it saw, so the next run overwrites it deliberately. It also refuses when an open PR on the branch belongs to a different `gh` user.
- **WP7** The PR body contains the routed changes, an **Unresolved** section (path, reason, and fenced diff for each item), and the provenance table. Unresolved items never block the PR.
- **WP8** After a push, it records the date, the pending-diff hash (which drives WS2), and the pushed commit.

### Routing (how propose maps the pending diff back to Delphi)
The lock is read from the baseline. `repos/`, `worktrees/`, and the lock are excluded. Delphi never
guesses: anything it cannot place is unresolved.
- **R1** A modified `.delphi/manifest.yml` replaces the layout manifest. Any other `.delphi/` change is unresolved.
- **R2** Binary files and mode-only changes are unresolved.
- **R3** A deleted output is a no-op if its source was dropped from `.delphi/manifest.yml`, and unresolved otherwise. A file inside a built skill counts as dropped only when its `.skill` spec was dropped.
- **R4** A modified output is routed hunk by hunk (R8–R11).
- **R5** A new `context/<scope>/blocks/...` file under an existing scope becomes a new block and is added to the manifest's `blocks:` unless an entry or glob already covers it.
- **R6** A new `docs/<d>/<f>` file goes beside the compiled docs already in `docs/<d>/`, otherwise under `<layout-scope>/docs/`, and is added to `docs:` if not covered.
- **R7** A new file in a compiled native skill goes into that skill's source directory. A new skill directory becomes `<layout-scope>/harness/skills/<name>/` and is added to `skills:`. A new file in a built skill is unresolved. So is a new file whose target already exists upstream.
- **R8** A hunk entirely inside one block becomes a patch to that block. All hunks for one block are combined into a single patch. An insertion at a block's end appends to it. An insertion before a block that follows generated or separator lines prepends to it.
- **R9** **New sections in the instruction file become new fragments.** An insertion at a segment boundary that is set off from the neighbouring blocks by blank lines is written to `<layout-scope>/harness/instructions/<slug>.md`. The slug comes from the section's first line, with `-2`, `-3`, ... added when the name is taken. The fragment is listed in `instructions:` right after the preceding fragment (first if there is none), and several new fragments keep their file order. Lines that touch a neighbouring block with no blank line between them extend that block instead.
- **R10** Edits to only the `name:`/`description:` lines of a built skill's frontmatter rewrite those keys in the `.skill` spec.
- **R11** These are unresolved: hunks in generated or separator lines, hunks spanning segments, deletion of a whole block via hunks, a second patch to the same block (for example the same block edited in two outputs), and patches that fail to apply.

### layout new `<scope> <layout> [--from file]` / layout list
- **L1** Validates that `<scope>` is a scope on `origin/main` and that `<layout>` matches `[a-z0-9-]+` and is not already used.
- **L2** With `--from`, uses the given manifest as-is. Its `name` must equal `<layout>`, and it must name a harness.
- **L3** Without `--from` (TTY only), offers the scope's and its ancestors' recommendations plus the scope's own blocks, one y/n question each. Answers are sorted into the right key by path, keeping at most one settings file. It asks for the harness when there is more than one adapter, then for repos.
- **L4** Writes the manifest through the PR path on branch `delphi/layout/<layout>` after `check` passes, and prints the branch name.
- **L5** `layout list` prints `name<TAB>scope<TAB>harness` for every layout on `origin/main`.

### block mv `<old> <new>`
- **B1** Only paths under a scope's `blocks/`, `docs/`, or `harness/` can be moved. `old` must exist on `origin/main` and `new` must not.
- **B2** Moves the file or directory, appends `old<TAB>new<TAB>date` to `moves.tsv`, and rewrites exact and directory-prefix references in every manifest, `scope.yml`, and `.skill`.
- **B3** Runs `check`, then opens a PR on branch `delphi/mv/<basename>-<YYYYMMDD>` and prints the branch. Workspaces pick up the move on their next refresh (WR5).
- **B4** `moves.tsv` is append-only. Each consumer applies only the rows that are new to it, in order, once each. That means paths can be reused and moves can be reversed.

### check
- **K1** Lists every violation, then exits non-zero if there are any. It prints "ok" otherwise.
- **K2** Structure: every scope has a `scope.yml`, scopes contain no stray files, `context/` contains no symlinks, and no file is empty or missing its trailing newline.
- **K3** No file under `context/` is named after any adapter's instruction file (`CLAUDE.md`, ...).
- **K4** Every `.yml`/`.skill` parses. Recommendations and `.skill` body/reference paths exist. `.skill` specs have `name` and `description` and no unknown keys.
- **K5** Manifests: `name` equals the directory and is unique, the harness adapter exists, there are no unknown keys, there is at most one settings file, entries sit under the key that matches their location, and every layout compiles.
- **K6** `moves.tsv` rows have three fields. When a JSON tool is available, MCP fragments form valid JSON once wrapped.

### setup `[dir]`
- **S1** Puts a `delphi` launcher in `dir` (default `~/.local/bin`) that runs this checkout's CLI. It warns if `dir` is not on `PATH`.

### Harness adapters
- **H1** An adapter supplies only names (instruction file, skills directory, MCP file, settings file, locally ignored file), a provenance fallback (harness+version, model, effort), and a launch action (model, effort). All file logic is generic.
- **H2** Adding a harness means adding one adapter. The `claude-code` adapter uses `CLAUDE.md`, `.claude/skills`, `.mcp.json`, `.claude/settings.json`, and `.claude/settings.local.json`.

### Provenance
- **V1** Every commit Delphi writes to Delphi carries `Delphi-Harness`, `Delphi-Model`, and `Delphi-Effort` trailers. A propose commit also carries `Delphi-Layout`, `Delphi-Workspace`, and `Delphi-Base`.
- **V2** Each field is resolved from the CLI flag, then the `DELPHI_*` env var, then the adapter fallback, then a prompt (TTY only; `none` is accepted). With no TTY it is an error. A field is never recorded as "unknown".
- **V3** Workspace commits made by the user are tagged from `DELPHI_*` env vars when those are set and the trailers are not already present.
- **V4** The PR body's provenance table lists the proposing session plus each distinct trailer combination from non-merge workspace commits since the workspace was last clean.

### Writing to Delphi (PR path)
- **P1** Every write to Delphi goes through one path: a temporary worktree on the command's branch, starting from a given commit (default `origin/main`). The user's own Delphi checkout (working tree, index, HEAD) is never modified.
- **P2** Shows the title and body, then asks `Push ... ? [y/N]` unless `--yes` or `DELPHI_YES=1` is set. A non-interactive run without `--yes` fails before doing any work.
- **P3** Pushes the branch, then updates the open PR for it with `gh pr edit`, or creates one against `main` with `gh pr create`. Propose branches are force-pushed with a lease on the last pushed commit.
- **P4** Temporary worktrees and directories are removed on success and on failure. If the user declines, the branch stays committed locally and nothing is pushed.

## 4. Cross-cutting invariants

- **X1 Path safety.** Every path from config, flags, the lock, manifests, or `moves.tsv` is rejected if it is absolute, contains `..` or `.` components, or resolves through a symlink to a location outside its root. This check runs before any read, write, or delete.
- **X2 Determinism.** Compile (C1), routing, and the pending-diff hash depend only on git content, never on time or the environment. The only exceptions are dates in `moves.tsv` rows and branch names.
- **X3 Idempotence.** Refresh, propose, and re-running after a failure converge on the same result. Nothing is left half-applied without a message.
- **X4 Hands off the user's checkout.** Delphi is read through `origin/*` refs and temporary worktrees. Workspaces live outside the repo, so Delphi's own `CLAUDE.md` is never an ancestor file of a workspace.
- **X5 Workspace bookkeeping stays inside `.git/`.** It never dirties the working tree or appears in the pending diff.
- **X6 gh is stubbable.** `gh` is used only for identity (`api user`) and PR list/create/edit, so a stub plus a bare origin exercises everything end to end (`dev/sandbox.sh`).
- **X7 Exit codes.** 0 means success or up to date, 1 means error, and 2 means a refresh (or the refresh inside propose) stopped on merge conflicts.
- **X8 Actionable errors.** Messages name the file or line and the command to run next. A non-interactive session never hangs on a prompt.
- **X9 Config.** `delphi.conf` holds `key=value` lines and is never executed. `workspace_root` defaults to `../Delphi-workspaces` relative to the repo, and `DELPHI_WORKSPACE_ROOT` overrides it. `stale_days` defaults to 14.
- **X10 Offline tolerance.** A failed fetch produces a warning, and the command continues with local `origin/*` refs.

## 5. Open questions / candidates to drop or simplify

These are flagged, not decided.

1. **Three records of the baseline.** The `generated` branch, the `generated-merged` tag, and `meta.compile_commit` (with `Delphi-Compile` trailers) overlap. Could one ref plus meta suffice?
2. **Three overlapping push guards.** The `last_pushed` lease pre-check via `ls-remote`, `--force-with-lease`, and the "open PR authored by someone else" check. Is one enough?
3. **Proposing with only unresolved items.** The spec says unresolved items are listed in the PR. The code opens no PR when nothing is routable; it prints the items and exits 0.
4. **The `$USER` fallback in propose branch names.** When origin is not on github.com, the branch uses `$USER` instead of the `gh` login. This is not in the spec and exists for the sandbox.
5. **`block mv` hardcodes the `claude-code` adapter for provenance fallback.** The spec is silent on this.
6. **Local branches in the user's Delphi repo.** The PR path creates a local branch there (and force-resets a same-named branch; it fails if that branch is checked out elsewhere). This leaves `delphi/*` branches behind, which strains P1/X4.
7. **Built `.skill` specs as a second skill mechanism.** They need their own routing (R3 special case, R7 unresolved, R10 key rewriting). Is reusing a block as a skill worth that?
8. **The `moves.tsv` machinery.** Rows are counted by line number since `compile_commit`, prefix-rewritten, and applied during refresh. Could `block mv` just rewrite manifests and let workspaces re-resolve? Rewriting also silently drops trailing comments on changed lines.
9. **Fragment routing (R9).** Blank-line splitting, slug generation, `-2` suffixes, and ordering are a lot of rules. Could a new section simply be a hunk that falls outside all blocks and becomes one fragment?
10. **Edge hunk rules.** Prepend after glue, append at a block end when the next segment is not a block, and "one patch per block per propose". Each adds a case; which ones do users actually rely on?
11. **Pending-diff hash normalization** (strip `@@`/`index` lines) plus a `proposed` state that cannot see closed PRs. Would asking `gh` for PR state be simpler and more truthful?
12. **The interactive `layout new` picker duplicates the `delphi-new-layout` skill (`--from`).** The code also offers every file in the scope's own `blocks/`, which the spec does not mention. The spec says a second settings file triggers a re-ask; the code keeps the first.
13. **The numbered workspace picker in WO1,** and the `open` behavior of scanning every workspace for staleness. Both are conveniences with unclear value.
14. **Status extras not in the spec:** the NEXT column, the summary line, the `!` stale marker, and `gone` as a behind value.
15. **`delphi setup` exists because of Git Bash symlink behavior.** A compiled binary may not need it.
16. **The jq-optional MCP check is a bash workaround.** A native implementation can always validate the JSON.
17. **The strict YAML-subset parser.** Should a rewrite keep rejecting everything outside the subset (tabs, flow style, nesting) or accept real YAML?
18. **Adapters as sourced shell files.** Check also has to source every adapter to collect instruction file names. In Rust this could be a built-in table.
19. **Check rules missing from the spec:** stray files in scopes, no symlinks, no empty files, a required trailing newline. Compile also rejects empty sources, which the spec does not mention.
20. **Undocumented meta keys.** Meta stores `harness` and `last_pushed`, and `created`/`last_proposed` are stored as epoch seconds (the spec says dates).
21. **Creating an empty `worktrees/` in every workspace** has no other behavior attached.
22. **Rejected changes reappear.** A closed (rejected) PR's change keeps reappearing in every propose until it is reverted in the workspace. Is that the desired UX, or should rejected hunks be suppressible?
23. **The workspace commit hook (V3) and the `DELPHI_*` env vars go stale** when the model changes mid-session, a known gap. Is per-commit tagging worth it compared with a propose-time flag only?
