# Delphi

NER's AI-harness context (instructions, blocks, docs, skills, MCP, settings), stored once by org chart under
`context/`, plus a small Rust CLI.

Every **workspace** is a folder in Delphi, `context/<scope>/workspaces/<name>/`, fully
materialized on `main`: its `CLAUDE.md`, `.claude/skills/…`, and `docs/…` are real files. Some
files are **linked** to a shared source elsewhere in `context/` (a skill several teams use);
`delphi sync` keeps the source and every linked copy identical. `CLAUDE.md` and `.mcp.json` can be
generated from shared parts, and a skill's `SKILL.md` can be composed from shared blocks
(`skill.yml`). The rest are the workspace's own.

- **checkout** a workspace: a sparse clone holding just that folder, on your own branch, with
  its code repos cloned into `repos/`,
- **refresh** it by merging `main` (plain git),
- **propose** your changes as one PR: shared edits are synced to the source and every other
  workspace that links them first.

Design: `docs/design.md`. Goals: `docs/goals.md`.

## Quick start

```sh
cargo install --path .        # once: puts `delphi` on PATH
delphi setup                  # once, inside this checkout: remember where Delphi lives

delphi list                   # workspaces on main
delphi checkout argos-dev     # sparse clone into ../Delphi-workspaces/argos-dev
delphi open argos-dev         # start Claude Code in the workspace folder
delphi diff                   # what you changed (own / linked, and who shares it)
delphi propose                # refresh, sync, check, push, open/update the PR
delphi refresh                # merge main into your branch
```

Code changes go in `repos/<name>` with that repo's own PRs. Context changes are committed in the
checkout and sent with `propose`.

## Workspaces

`context/<scope>/workspaces/<name>/workspace.yml`:

```yaml
name: argos-dev
harness: claude-code
instructions:                         # optional: CLAUDE.md is generated from these parts
  - harness/instructions/workspace.md
  - software/harness/instructions/base.md
skills:                               # linked: <source> [-> <dest>], kept in sync
  - software/harness/skills/commit    # default dest: .claude/skills/commit
blocks:                               # default dest: context/<source>
  - software/application-software/argos/blocks/glossary.md          # default dest: context/<same path>
docs:                                 # default dest: docs/<path below docs/>
  - software/application-software/argos/docs/CONTEXT.md
mcp:                                  # optional: .mcp.json is generated from these fragments
  - software/harness/mcp/github.json
settings: software/harness/settings/default.json   # linked to .claude/settings.json
repos:                                # cloned into repos/ in a checkout, git-ignored
  argos: https://github.com/Northeastern-Electric-Racing/Argos.git
```

A skill directory (shared or the workspace's own) may hold a `skill.yml`; `delphi sync` then
generates its `SKILL.md` from blocks (don't hand-edit it; edit a block):

```yaml
name: open-pr
description: Run pre-PR checks and open a draft pull request
body:                                 # blocks under a scope's blocks/, joined by a blank line
  - software/application-software/argos/blocks/open-pr.md
  - software/application-software/argos/blocks/pr-body.md
```

## Commands

```
delphi create <scope> <name> --from <workspace.yml>   new workspace folder (PR)
delphi list                                           workspaces on origin/main
delphi checkout <workspace> [--as <checkout>]         sparse clone of the folder on ws/<you>/<checkout>
delphi open|refresh|diff|propose [<checkout>]         work in a checkout (diff --upstream, propose --dry-run)
delphi status                                         every local checkout: dirty, ahead, behind
delphi mv <old> <new>                                 move a source or workspace (PR)
delphi sync [--check] [--base <rev>]                  reconcile linked files in this Delphi checkout
delphi check                                          validate the repo
delphi setup [dir]                                    remember this Delphi checkout
```

Commands that write to Delphi accept `--model`, `--effort` (provenance) and `--yes`. Without
`--yes`, a non-interactive run fails fast instead of prompting. CI
(`.github/workflows/delphi.yml`) runs `check` and `sync --check` on PRs and `sync` on `main`.

## Developing Delphi

`cargo test` runs the end-to-end tests in throwaway sandboxes (stub `gh`, local bare origin);
never test against GitHub. See `CLAUDE.md`.
