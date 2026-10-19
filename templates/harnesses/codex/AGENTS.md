# Delphi workspace

You're in Delphi workspace `{{name}}` (branch `ws/{{name}}`); code repos are cloned at `repos/<repo>/`, and separately checked out as worktrees under `worktrees/<repo>/` (`.delphi/setup.sh` makes the default branch's). Work in worktrees: make each new branch one under `worktrees/<repo>/<branch>` (`new-worktree` skill) unless the user says not to. Read-only dependency sources from `references-git:` are checked out under `references/<name>/` at the version the workspace pins: read them to learn how a dependency behaves (prefer them over web docs), and never edit, branch, or push them. Delphi workspaces (or `main`) under `workspaces:` in `workspace.yml` (`- <name>`, a workspace's dotted name like `s.app.argos.argos-dev`, or `- main`) are clones at `workspaces/<name>/`, each on its branch, for reading their context (don't edit them from here; setup switches each back to its branch and pulls it); change what's checked out with the `setup-workspace` skill. To work in another workspace, switch this clone to it (`switch-workspace` skill). Park rough notes with the `journal` skill. Work here unless the task clearly belongs to another project.


## Codex startup

For Codex CLI, run `bash .delphi/codex.sh` from this clone. In other Codex hosts, first read `workspace.yml` and run `bash .delphi/paths.sh` from this workspace root to learn its absolute path. Run `bash .delphi/setup.sh` when the repositories have not been set up.

Shell exports may not persist between commands or reach independently launched sub-agents. Run skill helpers through `bash <absolute-workspace-root>/.delphi/exec.sh bash <absolute-skill-folder>/scripts/<script>.sh <names>...`; this sets the layout on every invocation and preserves the caller's working directory. Pass the workspace's absolute path and this rule to sub-agents. Native skills live under `.agents/skills/`. After a workspace switch, start a fresh Codex session before further work.

Use the tools available in the current harness for browser verification and GitHub access. If a skill requires unavailable tooling or authentication, report the missing prerequisite and the verification that remains. Delphi does not configure Codex permissions, credentials, MCP servers or host dependencies.
