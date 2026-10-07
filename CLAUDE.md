# Delphi workspace

You're in Delphi workspace `experimental` (branch `ws/experimental`); code repos are checked out as worktrees under `worktrees/<repo>/` (`.delphi/setup.sh` makes the default branch's). Make new branches as worktrees (`new-worktree` skill) unless the user says not to. Park rough notes with the `journal` skill. Work here unless the task clearly belongs to another project.

# NER Software conventions

## Branch & Commit Conventions

- Branch from `develop` (not `main`) unless told otherwise. Branch name format: `{issue-number}-{kebab-case-title}` (e.g. `533-csv-upload-download-rules`).
- Commit message format: `#{ticket-number} - {concise description}` (e.g. `#533 - add CSV upload endpoint`).

## Safety Rules

- Never modify `.env` or secret files without explicit confirmation.
- Never delete files without explicit confirmation.
- Explain reasoning before making architectural changes.

# Argos

Argos is a real-time telemetry platform for Northeastern Electric Racing (NER). Angular 19 frontend (`angular-client/`) and Rust backend (`scylla-server/`), with schema tooling in `charybdis/` and MQTT broker config in `siren-base/`.

The Argos repo's `develop` is checked out at `worktrees/argos/develop/`. Paths below are relative to any Argos worktree. The ticket number is the branch's leading number (`533-csv-upload` → `#533`).

## Worktrees

- `worktrees/argos/develop/` is a clean reference: fetch and fast-forward only.
- Every ticket gets its own worktree, and all work for it happens there: `bash .delphi/new-worktree.sh argos <branch> origin/develop`.
- A new worktree has no `node_modules`: run `npm ci` in its `angular-client/` before testing or running the client.

## Local Development

- The backend stack (Postgres, MQTT, Scylla server, Calypso simulator) runs in Docker via the compose files in `compose/`, driven by `argos.sh`.
- Pick the compose profile by what changed:
  - Frontend-only changes: `./argos.sh client-dev up` runs everything in Docker, including scylla-server.
  - Changes to `scylla-server/`: `./argos.sh scylla-dev up` (everything except scylla-server) plus `cd scylla-server && cargo run` in a separate terminal, so you are not testing a stale binary.
- Frontend client: use the `run-local` skill.
- On Windows, run everything from WSL or Git Bash.

## Testing

- Frontend: `cd angular-client && ng test` (Karma/Jasmine).
- Backend: `cd scylla-server && cargo test`.
- Lint and format (frontend): `npx prettier --check "src/**/*.{ts,html,scss}" && npx ng lint`.
- Build (backend): `cargo build`.

## Workflow

Per ticket, in its worktree: `/workflow` → `/commit` → `/open-pr`. Use `/to-tickets` to split large work.

## PR Convention

Open draft PRs against `develop` with `/open-pr`, and refresh them with `/update-pr`.

## Screenshots

Save Playwright screenshots to `pictures/<branch>/` at the repo root, with kebab-case names. The folder is git-ignored; never commit screenshots.

## Issue tracker

Issues live in GitHub Issues on `Northeastern-Electric-Racing/Argos` via the `gh` CLI. See Argos's `docs/agents/issue-tracker.md` for ticket types, labels, and conventions.

## Domain docs

The glossary `docs/CONTEXT.md` lives at the workspace root. ADRs live in the Argos repo at `docs/adr/` and land through Argos PRs; filenames follow the Conventions section of `docs/CONTEXT.md`. Read both before exploring, use the glossary's terms, and flag conflicts with an ADR.
