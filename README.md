# Delphi

NER's AI-harness context (instructions, docs, skills, settings), stored once by org chart under
`context/`, plus a small Rust CLI:

- **compile** a *layout* into a local, git-initialized *workspace* where every file sits at its
  normal harness location (`CLAUDE.md`, `.claude/skills/…`, `docs/…`),
- **refresh** the workspace when `main` moves (synced files update; your edits are merged),
- **propose** workspace edits back as one PR: each edit to a synced file lands on its source.

Each workspace file is either **synced** (linked to its source) or **copied** (yours after the
first copy). Design: `docs/design.md`. Goals: `docs/goals.md`.

## Quick start

```sh
cargo install --path .        # once: puts `delphi` on PATH
delphi setup                  # once, inside this checkout: remember where Delphi lives

delphi ws new argos-dev       # create the workspace
delphi ws open argos-dev      # start Claude Code in it
delphi ws diff                # what you changed, and where each change would go
delphi ws propose             # send context edits back as a PR (run inside the workspace)
delphi ws refresh             # pull in Delphi updates
```

Code changes go in `repos/argos` with its own PRs. Context changes (skills, docs, synced files)
are committed in the workspace and sent back with `propose`.

## Layouts

`context/<scope>/layouts/<name>/manifest.yml` (plus an optional `files/` dir of the layout's own
files):

```yaml
name: argos-dev
harness: claude-code
instructions:                         # optional: assembled into CLAUDE.md (generated)
  - software/harness/instructions/base.md
sync:                                 # linked to their source
  - software/application-software/argos/harness/skills/run-local
  - software/application-software/argos/blocks/pr-body.md -> .claude/skills/open-pr/pr-body.md
copy:                                 # copied once, then yours
  - software/harness/settings/claude.json -> .claude/settings.json
repos:
  argos: https://github.com/Northeastern-Electric-Racing/Argos.git
```

## Commands

```
delphi layout new <scope> <layout> --from <manifest>   create a layout (branch + PR)
delphi layout list                                     list layouts on origin/main
delphi workspace new <layout> [--as <ws>] [--ref <branch>]
delphi workspace open|refresh|diff|propose|status      (alias: ws)
delphi block mv <old> <new>                            move a source (branch + PR)
delphi check                                           validate the repo
delphi setup [dir]                                     remember this Delphi checkout
```

Commands that write to Delphi accept `--model`, `--effort` (provenance) and `--yes`. Without
`--yes`, a non-interactive run fails fast instead of prompting.

## Developing Delphi

`cargo test` runs the end-to-end tests in throwaway sandboxes (stub `gh`, local bare origin);
never test against GitHub. See `CLAUDE.md`.
