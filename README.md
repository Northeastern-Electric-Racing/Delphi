# Delphi

NER's AI-harness context (instructions, docs, skills, settings), stored by org chart under
`context/`, plus a small Rust CLI.

Every **workspace** is a self-contained folder on `main`, `context/<scope>/workspaces/<name>/`,
with every file at its normal harness location (`CLAUDE.md`, `.claude/skills/…`, `docs/…`). Each
workspace owns its files: nothing is shared or generated.

For each workspace, CI keeps a branch **`ws/<name>`** whose repo root *is* that folder (a
deterministic `git subtree split`, re-run on every push to `main`). So:

- **any agent or person** can work with plain git: check out `ws/<name>`, branch, edit, push, and
  open a PR into `ws/<name>`; CI mirrors it into a PR to `main` and comments the link,
- **with the CLI**, `delphi checkout` clones `ws/<name>` on your own branch (code repos cloned into
  `repos/`), `delphi refresh` merges the latest `ws/<name>`, and `delphi propose` sends your
  branch's changes as one PR to `main`, re-rooted under the folder.

`main` stays the one source of truth; `ws/*` are derived and written only by CI.

Design: `docs/design.md`. Goals: `docs/goals.md`.

## Quick start

```sh
cargo install --path .        # once: puts `delphi` on PATH
delphi setup                  # once, inside this checkout: remember where Delphi lives

delphi list                   # workspaces on main
delphi checkout argos-dev     # clone ws/argos-dev into ../Delphi-workspaces/argos-dev
delphi open argos-dev         # start Claude Code at the workspace root
delphi diff                   # what you changed vs ws/argos-dev
delphi propose                # one PR to main with your branch's changes
delphi refresh                # merge the latest ws/argos-dev into your branch
```

Code changes go in `repos/<name>` with that repo's own PRs. Context changes are committed in the
checkout and sent with `propose`.

## Workspaces

`context/<scope>/workspaces/<name>/workspace.yml`:

```yaml
name: argos-dev                       # = the folder name, unique
harness: claude-code                  # adapter: launch + provenance
repos:                                # cloned into repos/ in a checkout, git-ignored
  argos: https://github.com/Northeastern-Electric-Racing/Argos.git
```

Everything else in the folder is the workspace's own files.

## Commands

```
delphi create <scope> <name> [--from <dir>]           new workspace folder (PR to main)
delphi list                                           workspaces on origin/main
delphi checkout <workspace> [--as <checkout>]         clone ws/<workspace> on edit/<you>/<checkout>
delphi open|refresh|diff [<checkout>]                 work in a checkout (diff --upstream)
delphi propose [<checkout>] [--dry-run]               the checkout's changes as one PR to main
delphi propose [<workspace>] --branch <b>             the same for a branch on origin (CI mirror)
delphi status                                         every local checkout: dirty, ahead, behind
delphi split [--check] [--push]                       ws/<name> for every workspace
delphi check                                          validate the repo
delphi setup [dir]                                    remember this Delphi checkout
```

Commands that write to Delphi accept `--model`, `--effort` (provenance) and `--yes`. Without
`--yes`, a non-interactive run fails fast instead of prompting. `propose` exits 1 listing files when
`main` changed the same lines: refresh, resolve, re-run. CI (`.github/workflows/delphi.yml`) runs
`check` on PRs to `main`, `split --push` on pushes to `main`, and mirrors PRs into `ws/*` with
`propose --branch`. Protect `ws/*` so only CI writes them.

## Developing Delphi

`cargo test` runs the end-to-end tests in throwaway sandboxes (stub `gh`, local bare origin);
never test against GitHub. See `CLAUDE.md`.
