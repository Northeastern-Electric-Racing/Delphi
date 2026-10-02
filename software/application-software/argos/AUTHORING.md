# Working on Argos workspaces

A workspace is context (instructions, skills, docs), never code. Delphi's `docs/design.md` has the
full model; this is the Argos-specific short version.

## Change an existing workspace

1. Check out `ws/<name>` (or `bash .delphi/link.sh <name>` from another workspace, then
   `git -C linked/<name> switch -c <branch>`).
2. Edit at normal harness paths: `CLAUDE.md`, `.claude/skills/<skill>/SKILL.md`, `docs/`.
3. Push the branch and open a PR into `ws/<name>`. After it merges, CI proposes it to `main`.

Don't edit `.delphi/*.sh` or `.github/workflows/delphi.yml`: Delphi manages them.

## Create a new Argos workspace

From a Delphi checkout: `tools/new-workspace.sh application-software/argos <name>`. It copies
Delphi's template, then `defaults/` (its `CLAUDE.md` is appended after the Delphi section), and opens
a PR to `main`. Trim what the new workspace doesn't need before merging.

## Change the defaults or this folder

Edit on a branch of `main` and open a PR to `main` (from a workspace: `linked/main/`). Defaults only
affect workspaces created afterwards; to change existing ones, PR each workspace too.

## Writing good workspace context

- Keep the Delphi section of `CLAUDE.md` as generated; put project rules below it.
- One skill per repeatable workflow, with a `description` that says when to use it.
- A project's glossary (`CONTEXT.md`) and ADRs (`docs/adr/`) live in its code repo; a workspace's
  `docs/` points at them and holds only docs about the workspace itself. Avoid file paths and code
  in specs and tickets.
- Make new branches as worktrees (`new-worktree` skill) unless told otherwise.
