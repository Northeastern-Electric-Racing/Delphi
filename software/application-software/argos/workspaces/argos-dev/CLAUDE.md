# Delphi workspace

You're in Delphi workspace `software/application-software/argos/argos-dev` (branch `ws/software/application-software/argos/argos-dev`); code repos are checked out as worktrees under `worktrees/<repo>/` (`.delphi/setup.sh` makes the default branch's). Make new branches as worktrees (`new-worktree` skill) unless the user says not to. Delphi workspaces (or `main`) under `workspaces:` in `workspace.yml` (`- ws/<name>`, a workspace's place in the tree, or `- main`) are read-only copies at `linked/<branch>/` for reading their context; change what's checked out with the `setup-workspace` skill. To work in another workspace, switch this clone to it (`switch-workspace` skill). Park rough notes with the `journal` skill. If a skill named here is missing, this workspace's plugins (`plugins:` in `workspace.yml`) aren't installed on this machine: tell the user, and with their go-ahead run `claude plugin install <plugin>@delphi --scope local` for each (local scope leaves the generated `.claude/settings.json` alone), then have them restart the session. Work here unless the task clearly belongs to another project.

Always work from the workspace root (this clone's top, where `workspace.yml` is); the layout exists so one session can reach every worktree from there. Name worktrees by path: `git -C worktrees/argos/<branch> …` runs git there without moving, and a one-off subshell like `(cd worktrees/argos/<branch>/angular-client && npx ng lint)` runs anything else. If you `cd` into a worktree to look closely at something, `cd` back to the root as soon as you're done. Skill scripts take only names (repo, branch) and find the rest from `$DELPHI_ROOT`, which a session hook sets in every shell (`$DELPHI_WORKTREES` and the other `.delphi/paths.sh` folders too).

# NER Software conventions

## Branch & Commit Conventions

- Branch from `develop` (not `main`) unless told otherwise. Branch name format: `{issue-number}-{kebab-case-title}` (e.g. `533-csv-upload-download-rules`), or `throwaway-{kebab-case-title}` to try something without a ticket.
- Commit message format: `#{ticket-number} - {concise description}` (e.g. `#533 - add CSV upload endpoint`). Throwaway branches have no ticket, so any short message works.

## Safety Rules

- Never modify `.env` or secret files without explicit confirmation.
- Never delete files without explicit confirmation.
- Explain reasoning before making architectural changes.

# Argos

Argos is a real-time telemetry platform for Northeastern Electric Racing (NER). Angular 19 frontend (`angular-client/`) and Rust backend (`scylla-server/`), with schema tooling in `charybdis/` and MQTT broker config in `siren-base/`.

The Argos repo's `develop` is checked out at `worktrees/argos/develop/`. Repo paths below (`angular-client/`, `scylla-server/`, `compose/`) are inside an Argos worktree. The ticket number is the branch's leading number (`533-csv-upload` → `#533`).

## Worktrees

- `worktrees/argos/develop/` mirrors `develop`: run anything there (`npm ci`, tests, the backend, `/run-local`), but never edit code, branch, or commit there. The only git operations there are fetch and fast-forward.
- To change code, make a worktree on its own branch with the `new-worktree` skill, based on `origin/develop`. Use the ticket's branch, or a `throwaway-{kebab-case-title}` branch to experiment without one. If a throwaway turns into real work, file a ticket (`create-ticket`), make the ticket's worktree from `origin/develop`, run `git -C worktrees/argos/<ticket-branch> merge --squash throwaway-{kebab-case-title}`, then `/commit`, so the work lands as one commit in the ticket format.
- A new worktree has no `node_modules`; `run-local` and `/implement` install them.

## Local Development

- Run the app with the `run-local` skill, passing the branches you're looking at (a PR's or ticket's, with a worktree from `new-worktree`; not `develop` unless asked). It starts the backend if it's down, on the right compose profile (`client-dev` runs everything in Docker; `scylla-dev` plus `cargo run` when a target changes `scylla-server/`), and serves each worktree's client on its own port.
- The shell workflow (`argos.sh`, the `run-local`/`verify-*` skills, and helpers like `lsof`/`pkill`) assumes a Unix shell. On Windows, run everything from WSL or Git Bash, not `cmd`/PowerShell.

## Testing

The checks (frontend tests, lint and format; backend build and tests) and how to run them from the root are in `/implement`; `/open-pr` reruns lint and format before a PR.

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

Issues live in GitHub Issues on `Northeastern-Electric-Racing/Argos` via the `gh` CLI. File tickets with the `create-ticket` skill from Delphi's `app` plugin; it holds the ticket conventions and follows the repo's issue templates (idea, spike, epic, dev work), with Argos's specifics in the `argos` plugin. When an out-of-scope but worthwhile idea comes up mid-work, offer to file it as an idea with `create-ticket`; park rough notes with `journal`.

## Domain docs

The glossary is a workspace doc: `docs/CONTEXT.md` at the workspace root. Edit it there and it's proposed back to Delphi. ADRs live in the Argos repo at `docs/adr/` and land through Argos PRs like any other change; filenames follow the Conventions section of `docs/CONTEXT.md`. Read `docs/CONTEXT.md` and the relevant ADRs before exploring, use the glossary's terms, and flag any conflict with an ADR.
