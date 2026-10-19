# Working on Argos workspaces

A workspace is context (instructions, skills, docs), never code. Delphi's `docs/design.md` has the
full model; this is the Argos-specific short version.

## Change an existing workspace

1. Check out `ws/s.app.argos.<leaf>` (from another workspace: `bash .delphi/switch.sh s.app.argos.<leaf>`, the
   `switch-workspace` skill), then `git switch -c <branch>`.
2. Edit at normal harness paths: the native instruction file and skill paths for its `harness:` (`AGENTS.md` and `.agents/skills/` for Codex), or `docs/`.
3. Push the branch and open a PR into `ws/<name>`. After it merges, CI proposes it to `main`.

Don't edit `.delphi/`, `.github/workflows/delphi.yml`, or `.claude/settings.json`: Delphi manages
them (`.delphi/` comes from main's root and sync resets it; `settings.json` is generated from
`workspace.yml`'s `plugins:`, where CI lists any folder's `default` plugin set; add other sets below them), nor the skills
inherited from `skills/` or `workspace-inherit/` (sync overwrites them: change them on `main`, or list one under `opt-out:` to keep your own).
Personal settings go in `.claude/settings.local.json`.

## Create a new Argos workspace

From a Delphi checkout: `tools/new-workspace.sh [--harness codex] application-software/argos <name>`. It copies
Delphi's template, then `workspace-defaults/` (its matching native instructions are appended after the Delphi section), and opens
a PR to `main`. Trim what the new workspace doesn't need before merging.

## Change the defaults or this folder

Edit on a branch of `main` and open a PR to `main` (from a workspace: `bash .delphi/switch.sh main`;
don't edit `workspaces/main/` from a workspace). `workspace-defaults/`
only affects workspaces created afterwards; to change existing ones, PR each workspace too. `skills/` and `workspace-inherit/` reach
every Argos workspace on the next sync.

## Writing good workspace context

- Keep the Delphi section of the native instruction file as generated; put project rules below it.
- One skill per repeatable workflow, with a `description` that says when to use it.
- Agent context (glossary, conventions, skills) lives in the workspace; the glossary goes in `docs/`.
  Shared skills go in this project's `skills/<name>/`, or the relevant org folder's `skills/`.
  Sync renders them into each workspace's native directory; change them through PRs to `main`.
  Ordinary inherited docs go in `workspace-inherit/`. Context only some workspaces need goes in
  the workspace, or in a supported plugin set selected under `plugins:`. Codex does not load the
  Claude plugin sets. Workspace-owned native skills remain editable and proposable; use a native
  destination under `opt-out:` when taking ownership of an inherited skill.
  ADRs about a code repo live in that repo, so `docs/` holds only ADRs about the workspace itself.
  Avoid file paths and code in specs and tickets.
- Make new branches as worktrees (`new-worktree` skill) unless told otherwise.

## Codex

The `default-codex` leaf is `ws/s.app.argos.default-codex`. Use `bash .delphi/codex.sh` to start
Codex CLI after setup. In another Codex host, follow `AGENTS.md` and use `.delphi/exec.sh` for skill
helpers in fresh shells and sub-agents. This workspace carries Argos workflows and dependency
references without prescribing a cloud environment, credentials or Codex permission settings.
Check required local tooling before running a workflow; use available browser/GitHub integrations
and report verification that could not run. Start a fresh Codex session after changing workspaces.
