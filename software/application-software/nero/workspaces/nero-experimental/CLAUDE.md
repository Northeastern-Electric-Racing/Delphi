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
- There are no unit tests. Verify by building, running against mock telemetry, and taking screenshots.
- Format C++ with `git ls-files "*.cpp" "*.h" ":!deps/*" | xargs clang-format -i`; CI checks it. Format QML with the Qt install's `qmlformat -i`.

## Screenshots

The app's dev screenshot tool is off unless its env vars are set. `NERO_SCREENSHOT=<page> NERO_SCREENSHOT_OUT=<file>` opens that top-level page, saves a PNG, and quits; an unknown page logs "unknown page". Save shots to `/tmp/nero-shots/<branch>/`, never in the repo.

## Workflow

Per ticket, in its worktree: `/workflow` → `/commit` → `/open-pr`. Use `/to-tickets` to split large work.

## PR Convention

Open draft PRs against `develop` with `/open-pr`, and refresh them with `/update-pr`.

## Issue tracker

Issues live in GitHub Issues on `Northeastern-Electric-Racing/Nero-2.0` via the `gh` CLI.
