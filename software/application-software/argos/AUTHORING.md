# Working on Argos workspaces

A workspace is context (instructions, skills, docs), never code. Delphi's `docs/design.md` has the
full model; this is the Argos-specific short version.

## Change an existing workspace

1. Check out `ws/s.app.argos.<leaf>` (from another workspace: `bash .delphi/switch.sh s.app.argos.<leaf>`, the
   `switch-workspace` skill), then `git switch -c <branch>`.
2. Edit at normal harness paths: the native instruction file and skill paths for its `harness:` (`AGENTS.md` and `.agents/skills/` for Codex), or `docs/`.
3. Push the branch and open a PR into `ws/<name>`. After it merges, CI proposes it to `main`.

Delphi manages `.delphi/`, the workflow and generated settings. Edit shared skills through their
`workspace-inherit/` sources on main. To keep an editable workspace copy, list its native path
under `opt-out:`. Claude personal settings belong in `.claude/settings.local.json`.

## Create a new Argos workspace

From a Delphi checkout: `tools/new-workspace.sh [--harness codex] application-software/argos <name>`. It copies
the resolved harness instructions and translated `workspace-defaults/`, then opens a PR to `main`.

## Change the defaults or this folder

Edit on a branch of `main` and open a PR to `main` (from a workspace: `bash .delphi/switch.sh main`;
don't edit `workspaces/main/` from a workspace). `workspace-defaults/`
only affects workspaces created afterwards; to change existing ones, PR each workspace too.
Seeded instruction files are owned snapshots. For context that should stay current across
workspaces, use inheritance or a read-only reference through `workspaces/main/`.
`workspace-inherit/` reaches every Argos workspace through temporary CI preparation and refresh.
Commit its sources, never generated skill copies or `workspace.generated`, to main. Run
`bash ci/render.sh` for plugin output and `bash ci/check.sh` before opening the PR.

## Writing good workspace context

- Keep the Delphi section of the native instruction file as generated; put project rules below it.
- One skill per repeatable workflow, with a `description` that says when to use it.
- Agent context (glossary, conventions, skills) lives in the workspace; the glossary goes in `docs/`.
  Shared Claude skills stay in `workspace-inherit/.claude/skills/<name>/` at the project or org level.
  CI preserves Claude metadata and translates Codex copies into its native directory only on
  workspace branches; change sources through PRs to `main`. Ordinary inherited docs go in `workspace-inherit/`.
  Write skills once in Claude format; harness descriptors translate identifiers and native metadata.
  Fix missing mappings in the translator. Generated Codex skills carry their helper bootstrap command.
  Optional `source.yml` selects a different authoring format. Context only some workspaces need goes in
  the workspace, or in a supported plugin set selected under `plugins:`. Codex does not load the
  Claude plugin sets. Workspace-owned native skills remain editable and proposable; use a native
  destination under `opt-out:` when taking ownership of an inherited skill. Proposals return that
  owned copy to main and strip other managed inheritance.
  A source-native opt-out can exclude a harness-only file before translation. Shared-source and
  opt-out paths follow the portable ASCII rule in Delphi's `docs/design.md`; spaces are unsupported.
  ADRs about a code repo live in that repo, so `docs/` holds only ADRs about the workspace itself.
  Avoid file paths and code in specs and tickets.
- Make new branches as worktrees (`new-worktree` skill) unless told otherwise.

## Codex

Open `ws/s.app.argos.default-codex` in Codex and follow `AGENTS.md`. Use `.delphi/exec.sh` for skill
helpers in fresh shells and sub-agents. The host supplies tooling and credentials. Restart the
Codex session after switching workspaces.
Its project rules and glossary point to the existing Argos development context in the read-only
main link; edit those canonical files through PRs to main, not through the link.
