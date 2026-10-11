# Working on Argos workspaces

A workspace is context (instructions, skills, docs), never code. Delphi's `docs/design.md` has the
full model; this is the Argos-specific short version.

## Change an existing workspace

1. Check out `ws/software/application-software/argos/<leaf>` (from another workspace: `bash .delphi/switch.sh <leaf>`, the
   `switch-workspace` skill), then `git switch -c <branch>`.
2. Edit at normal harness paths: `CLAUDE.md`, `.claude/skills/<skill>/SKILL.md`, `docs/`.
3. Push the branch and open a PR into `ws/<name>`. After it merges, CI proposes it to `main`.

Don't edit `.delphi/`, `.github/workflows/delphi.yml`, or `.claude/settings.json`: Delphi manages
them (`.delphi/` comes from main's root and sync resets it; `settings.json` is generated from
`workspace.yml`'s `plugins:`, where CI lists the `app` and `argos` defaults; add other sets below them). Personal settings go in
`.claude/settings.local.json`.

## Create a new Argos workspace

From a Delphi checkout: `tools/new-workspace.sh application-software/argos <name>`. It copies
Delphi's template, then `defaults/` (its `CLAUDE.md` is appended after the Delphi section), and opens
a PR to `main`. Trim what the new workspace doesn't need before merging.

## Change the defaults or this folder

Edit on a branch of `main` and open a PR to `main` (from a workspace: `bash .delphi/switch.sh main`;
`linked/main/` is read-only). Defaults only
affect workspaces created afterwards; to change existing ones, PR each workspace too.

## Writing good workspace context

- Keep the Delphi section of `CLAUDE.md` as generated; put project rules below it.
- One skill per repeatable workflow, with a `description` that says when to use it.
- Agent context (glossary, conventions, skills) lives in the workspace; the glossary goes in `docs/`.
  Context every Argos workspace needs goes in the `argos` plugin (`plugins/claude/default/` here), and
  context shared with other application-software projects in the `app` plugin. Context
  only some workspaces need goes in another set (`plugins/claude/<set>/`) that they list under
  `plugins:`. Change them like the defaults, by PR to `main`, and run `ci/plugins.sh` in it.
  Workspaces keep only Delphi's own skills (`new-worktree`, `journal`, `setup-workspace`,
  `switch-workspace`); `commit`, `open-pr`, `update-pr`, `address-pr-comments` and `create-ticket` are
  in `app`, the workflow skills in `app.workflow`, and the Argos ones in `argos`.
  ADRs about a code repo live in that repo, so `docs/` holds only ADRs about the workspace itself.
  Avoid file paths and code in specs and tickets.
- Make new branches as worktrees (`new-worktree` skill) unless told otherwise.
