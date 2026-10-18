# Argos (project)

Shared context for every Argos workspace. Workspaces that list `main` under `workspaces:` in
`workspace.yml` (the default for Argos) read it at `workspaces/main/software/application-software/argos/`.

Argos is NER's real-time telemetry platform: an Angular 19 frontend (`angular-client/`) and a Rust
backend (`scylla-server/`), with schema tooling in `charybdis/` and MQTT broker config in
`siren-base/`. Code: https://github.com/Northeastern-Electric-Racing/Argos (base branch `develop`).

| Path | What it is |
|---|---|
| `workspaces/<leaf>/` | One workspace per purpose; branch `ws/s.app.argos.<leaf>` is its root |
| `workspaces/argos-dev/` | Day-to-day Argos development: tickets, specs, PRs |
| `workspace-defaults/` | What a new Argos workspace starts with (see `AUTHORING.md`) |
| `workspace-inherit/` | Skills every Argos workspace gets on each sync: ticket and PR conventions, `implement`, `run-local`, `verify-graph`, `verify-telemetry` |
| `plugins/claude/<set>/` | Claude Code plugin sets a workspace lists under `plugins:` (none yet) |
| `AUTHORING.md` | How to create and change Argos workspaces |

Shared facts that every Argos workspace needs belong here, in `workspace-defaults/`, or in `workspace-inherit/`. Facts that one
workspace needs belong in that workspace.
