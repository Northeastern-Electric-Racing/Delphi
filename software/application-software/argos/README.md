# Argos (project)

Shared context for every Argos workspace. Workspaces that list `main` under `links:` in
`workspace.yml` (the default for Argos) read it at `linked/main/software/application-software/argos/`.

Argos is NER's real-time telemetry platform: an Angular 19 frontend (`angular-client/`) and a Rust
backend (`scylla-server/`), with schema tooling in `charybdis/` and MQTT broker config in
`siren-base/`. Code: https://github.com/Northeastern-Electric-Racing/Argos (base branch `develop`).

| Path | What it is |
|---|---|
| `workspaces/<name>/` | One workspace per purpose; branch `ws/<name>` is its root |
| `workspaces/argos-dev/` | Day-to-day Argos development: tickets, specs, PRs |
| `defaults/` | What a new Argos workspace starts with (see `AUTHORING.md`) |
| `AUTHORING.md` | How to create and change Argos workspaces |

Shared facts that every Argos workspace needs belong here or in `defaults/`. Facts that one
workspace needs belong in that workspace.
