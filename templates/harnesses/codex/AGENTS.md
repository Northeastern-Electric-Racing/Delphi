

## Workspace setup

Work from the checked-out workspace root, where `workspace.yml` is. Run `bash .delphi/paths.sh` from this root to learn its absolute path, and run `bash .delphi/setup.sh` when the repositories have not been set up.

Shell exports may not persist between commands or reach independently launched sub-agents. Run skill helpers through `bash <absolute-workspace-root>/.delphi/exec.sh bash <absolute-skill-folder>/scripts/<script>.sh <names>...`; this sets the layout on every invocation and preserves the caller's working directory. Pass the workspace's absolute path and this rule to sub-agents. Native skills live under `.agents/skills/`. After a workspace switch, start a fresh Codex session before further work.

Use the tools available in the current harness for browser verification and GitHub access. If a skill requires unavailable tooling or authentication, report the missing prerequisite and the verification that remains. Delphi does not configure Codex permissions, credentials, MCP servers or host dependencies.
