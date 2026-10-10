# Delphi workspace

You're in Delphi workspace `nero-experimental` (branch `ws/nero-experimental`); code repos are checked out as worktrees under `worktrees/<repo>/` (`.delphi/setup.sh` makes the default branch's). Make new branches as worktrees (`new-worktree` skill) unless the user says not to. Park rough notes with the `journal` skill. Work here unless the task clearly belongs to another project.

# NER Software conventions

## Branch & Commit Conventions

- Branch from `develop` unless told otherwise. Branch name format: `{issue-number}-{type}--{kebab-case-title}` (e.g. `251-feature--vcu-state-component`).
- Commit message format: `#{ticket-number} {concise description}` (e.g. `#251 add VCU state readout to nav home page header`).

## Safety Rules

- Never modify `.env` or secret files without explicit confirmation.
- Never delete files without explicit confirmation.
- Explain reasoning before making architectural changes.

# Nero

Nero is NER's in-car driver dashboard: Qt 6, QML, and C++ in `NERODevelopment/`. It runs on a Raspberry Pi CM5 with a fixed 800×480 display and reads telemetry and steering-wheel buttons over MQTT.

Nero's `develop` is checked out at `worktrees/nero/develop/`. Paths below are relative to any Nero worktree. The ticket number is the branch's leading number.

## Worktrees

- `worktrees/nero/develop/` is a clean reference: fetch and fast-forward only.
- Every ticket gets its own worktree, and all work for it happens there: `bash .delphi/new-worktree.sh nero <branch> origin/develop`.

## Build and run

- Build: `build-scripts/compile-qt-linux.sh`, or the `-mac.sh` or `-windows.bat` variant. The scripts expect Qt 6.8.3 under `~/Qt/6.8.3/`.
- Mock telemetry: `docker compose -f compose.nero-dev.yml up -d`, and `down` when done.
- There are no unit tests. Verify UI changes with Playwright (below).
- Format C++ with `git ls-files "*.cpp" "*.h" ":!deps/*" | xargs clang-format -i`; CI checks it. Format QML with the Qt install's `qmlformat -i`.

## Playwright

UI QA runs a dev-only WASM build in Chrome over the Docker mock. From `playwright/`:

- `npm test` checks the cases in `tests/screens.spec.ts` and saves each screen to `test-results/<case>/`. `npm run update` records baselines, which are local, so run it first in a new worktree.
- Cases inject only what the mock lacks or what they test, through `window.nero.publish`. Add one per changed page.
- To drive it live, run `npm run view` in the background and use the `playwright-cdp` MCP.

## Workflow

Per ticket, in its worktree: `/workflow` → `/commit` → `/open-pr`. Use `/to-tickets` to split large work.

## PR Convention

Open draft PRs against `develop` with `/open-pr`, and refresh them with `/update-pr`.

## Issue tracker

Issues live in GitHub Issues on `Northeastern-Electric-Racing/Nero-2.0` via the `gh` CLI.
