# Working on Argos workspaces

A workspace is context (instructions, skills, docs), never code. Delphi's `docs/design.md` has the
full model; this is the Argos-specific short version.

## Change an existing workspace

1. Check out `ws/s.app.argos.<leaf>` (from another workspace: `bash .delphi/switch.sh s.app.argos.<leaf>`, the
   `switch-workspace` skill), then `git switch -c <branch>`.
2. Edit at normal harness paths: `CLAUDE.md`, `.claude/skills/<skill>/SKILL.md`, `docs/`.
3. Push the branch and open a PR into `ws/<name>`. After it merges, CI proposes it to `main`.

Don't edit `.delphi/`, `.github/workflows/delphi.yml`, or `.claude/settings.json`: Delphi manages
them (`.delphi/` comes from main's root and sync resets it; `settings.json` is generated from
`workspace.yml`'s `plugins:`, where CI lists any folder's `default` plugin set; add other sets below them), nor the skills
inherited from `workspace-inherit/` (sync overwrites them: change them on `main`, or list one under `opt-out:` to keep your own).
Personal settings go in `.claude/settings.local.json`.

## Create a new Argos workspace

From a Delphi checkout: `tools/new-workspace.sh application-software/argos <name>`. It copies
Delphi's template, then `workspace-defaults/` (its `CLAUDE.md` is appended after the Delphi section), and opens
a PR to `main`. Trim what the new workspace doesn't need before merging.

## Change the defaults or this folder

Edit on a branch of `main` and open a PR to `main` (from a workspace: `bash .delphi/switch.sh main`;
don't edit `workspaces/main/` from a workspace). `workspace-defaults/`
only affects workspaces created afterwards; to change existing ones, PR each workspace too. `workspace-inherit/` reaches
every Argos workspace on the next sync.

## Writing good workspace context

- Keep the Delphi section of `CLAUDE.md` as generated; put project rules below it.
- One skill per repeatable workflow, with a `description` that says when to use it.
- Agent context (glossary, conventions, skills) lives in the workspace; the glossary goes in `docs/`.
  Skills every Argos workspace needs go in `workspace-inherit/` here (`implement`, `run-local`,
  `verify-graph`, `verify-telemetry`, `pr-conventions`, `ticket-conventions`), and those shared with
  other application-software projects in `software/application-software/workspace-inherit/`
  (`commit`, `open-pr`, `update-pr`, `address-pr-comments`, `create-ticket`); Delphi's own
  (`new-worktree`, `journal`, `setup-workspace`, `switch-workspace`) come from
  `software/workspace-inherit/`. Sync puts them all on every Argos workspace's branch; change them by
  PR to `main`. Context only some workspaces need goes in the workspace, or in a plugin set
  (`plugins/claude/<set>/`) they list under `plugins:` (run `ci/plugins.sh`). Workspaces keep only
  skills tied to that workspace (the `workflow`, `review` and `to-tickets` trial in the experimental
  ones).
  ADRs about a code repo live in that repo, so `docs/` holds only ADRs about the workspace itself.
  Avoid file paths and code in specs and tickets.
- Make new branches as worktrees (`new-worktree` skill) unless told otherwise.
