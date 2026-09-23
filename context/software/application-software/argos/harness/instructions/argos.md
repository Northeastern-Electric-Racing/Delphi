# Argos

Argos is a real-time telemetry platform for Northeastern Electric Racing (NER). Angular 19 frontend (`angular-client/`) and Rust backend (`scylla-server/`), with schema tooling in `charybdis/` and MQTT broker config in `siren-base/`.

The Argos repo is checked out at `repos/argos/`. Paths below are relative to it. Run every workflow (commit, PR, run, test) in the checkout for the task: `repos/argos/`, or `worktrees/<branch>/` if it has its own worktree. The ticket number is the branch's leading number (`533-csv-upload` → `#533`).

## Local Development

- The backend stack (Postgres, MQTT, Scylla server, Calypso simulator) runs in Docker via the compose files in `compose/`, driven by `argos.sh`.
- Pick the compose profile by what changed:
  - Frontend-only changes: `./argos.sh client-dev up` runs everything in Docker, including scylla-server.
  - Changes to `scylla-server/`: `./argos.sh scylla-dev up` (everything except scylla-server) plus `cd scylla-server && cargo run` in a separate terminal, so you are not testing a stale binary.
- Frontend client: prefer the `run-local` skill (starts it on the next free port and checks the backend). Direct: `cd angular-client && npm run start` (default port 4200); first compile takes ~10-60s.
- The shell workflow (`argos.sh`, the `run-local` skill, and helpers like `lsof`/`pkill`) assumes a Unix shell. On Windows, run everything from WSL or Git Bash, not `cmd`/PowerShell.

## Testing

- Frontend: `cd angular-client && ng test` (Karma/Jasmine).
- Backend: `cd scylla-server && cargo test`.
- Lint and format (frontend): `npx prettier --check "src/**/*.{ts,html,scss}" && npx ng lint`.
- Build (backend): `cargo build`.

## Workflow

Idea to ship: `/grill-with-docs` → `/to-spec` → `/to-tickets` → `/implement` (test-first, then `/code-review` and `/commit`) → `/open-pr`. A trivial one-liner goes straight to `/implement`.

## PR Convention

- The `/commit` skill applies the commit message format.
- Open PRs against `develop` as drafts. The `/open-pr` skill runs the pre-PR checks (lint, conflict check), pushes, and opens the draft; `/update-pr` refreshes the description.
- Keep PR descriptions tight: at most three backtick usages in the body, and never commit screenshots (drag-drop them into the PR via the GitHub web UI).

## Screenshots

Save all Playwright screenshots under `pictures/<branch-name>/` at the repo root, using kebab-case descriptive filenames. The `pictures/` folder is git-ignored, so screenshots are never committed; drag-drop them into the PR via the GitHub web UI instead.

## Code Conventions

Frontend and backend conventions live alongside their code and auto-load when editing there:
- Angular / TypeScript: see `angular-client/CLAUDE.md`.
- Rust / Axum: see `scylla-server/CLAUDE.md`.

## Issue tracker

Issues live in GitHub Issues on `Northeastern-Electric-Racing/Argos` via the `gh` CLI. See `docs/agents/issue-tracker.md` for title, label, and assignment conventions, and `docs/agents/triage-labels.md` for labels. Specs and tickets avoid file paths and code snippets; they go stale.

## Domain docs

The glossary and ADRs are workspace docs, not files in `repos/argos/`: `docs/CONTEXT.md` and `docs/adr/` at the workspace root. Edit them there and they're proposed back to Delphi. Read `docs/CONTEXT.md` and the relevant ADRs before exploring, use the glossary's terms, and flag any conflict with an ADR. ADR filenames follow `repos/argos/docs/agents/domain.md` (`<NNNN>-<prefix>-<topic-slug>.md`).
