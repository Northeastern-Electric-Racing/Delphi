# Delphi workspace

You're in Delphi workspace `argos-dev` (branch `ws/argos-dev`); code repos are checked out as worktrees under `worktrees/<repo>/` (`.delphi/setup.sh` makes the default branch's). Make new branches as worktrees (`new-worktree` skill) unless the user says not to. Park rough notes with the `journal` skill. Work here unless the task clearly belongs to another project.

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

- `worktrees/argos/develop/` is a clean reference to `develop`. Never edit, branch, commit, or run dev servers there; only fetch and fast-forward it.
- Every ticket gets its own worktree at `worktrees/argos/<branch>/`, and every workflow (implement, test, run, commit, PR) runs there. Create or reuse one with the `new-worktree` skill, based on `origin/develop`: `bash .delphi/new-worktree.sh argos <branch> origin/develop`.
- A new worktree has no `node_modules`: run `npm ci` in its `angular-client/` before testing or running the client.

## Local Development

- The backend stack (Postgres, MQTT, Scylla server, Calypso simulator) runs in Docker via the compose files in `compose/`, driven by `argos.sh`.
- Pick the compose profile by what changed:
  - Frontend-only changes: `./argos.sh client-dev up` runs everything in Docker, including scylla-server.
  - Changes to `scylla-server/`: `./argos.sh scylla-dev up` (everything except scylla-server) plus `cd scylla-server && cargo run` in a separate terminal, so you are not testing a stale binary.
- Frontend client: prefer the `run-local` skill (starts it on the next free port and checks the backend). Direct: `cd angular-client && npm run start` (default port 4200); first compile takes ~10-60s.
- The shell workflow (`argos.sh`, the `run-local`/`verify-*` skills, and helpers like `lsof`/`pkill`) assumes a Unix shell. On Windows, run everything from WSL or Git Bash, not `cmd`/PowerShell.

## Testing

- Frontend: `cd angular-client && ng test` (Karma/Jasmine).
- Backend: `cd scylla-server && cargo test`.
- Lint and format (frontend): `npx prettier --check "src/**/*.{ts,html,scss}" && npx ng lint`.
- Build (backend): `cargo build`.

## Workflow

Per ticket: `/implement` (worktree, test-first, `/commit`) → `/open-pr`.

## PR Convention

- The `/commit` skill applies the commit message format.
- Open PRs against `develop` as drafts. PR titles carry no ticket number; the body ends with `Closes #{ticket}`. The `/open-pr` skill runs the pre-PR checks (lint, conflict check), pushes, and opens the draft; `/update-pr` refreshes the description.
- Keep PR descriptions tight: at most three backtick usages in the body, and never commit screenshots (drag-drop them into the PR via the GitHub web UI).

## Screenshots

Save all Playwright screenshots under `pictures/<branch-name>/` at the repo root, using kebab-case descriptive filenames. The `pictures/` folder is git-ignored, so screenshots are never committed; drag-drop them into the PR via the GitHub web UI instead.

## Code Conventions

Code and ADR conventions worth stating are in the Conventions section of `docs/CONTEXT.md`; everything else follows current Angular and Rust defaults.

## Issue tracker

Issues live in GitHub Issues on `Northeastern-Electric-Racing/Argos` via the `gh` CLI. Conventions live in Argos's `docs/agents/issue-tracker.md`; file tickets with the `create-ticket` skill, which follows the issue templates (idea, spike, epic, dev work). When an out-of-scope but worthwhile idea comes up mid-work, offer to log it with `log-future-addition`; park rough notes with `journal`.

## Domain docs

The glossary is a workspace doc: `docs/CONTEXT.md` at the workspace root. Edit it there and it's proposed back to Delphi. ADRs live in the Argos repo at `docs/adr/` and land through Argos PRs like any other change; filenames follow the Conventions section of `docs/CONTEXT.md`. Read `docs/CONTEXT.md` and the relevant ADRs before exploring, use the glossary's terms, and flag any conflict with an ADR.
