# Delphi

NER's AI-harness context (knowledge, instructions, skills, MCP, settings), stored compressed
by org chart under `context/`, plus a small bash CLI:

- **compile** a *layout* into a local, git-initialized *workspace* where Claude Code runs,
- **refresh** the workspace when `main` moves,
- **propose** workspace edits back as one PR, routed to the blocks they came from.

Design: `context/docs/delphi-design.md`.

## Quick start

```sh
./setup.sh                    # once: links `delphi` into ~/.local/bin (or pass a dir)

delphi ws new argos-dev       # create the workspace
delphi ws open argos-dev      # start Claude Code in it
delphi ws propose             # send context edits back as a PR (run inside the workspace)
delphi ws refresh             # pull in Delphi updates
```

Code changes go in `repos/argos` with its own PRs. Context changes (CLAUDE.md, skills, docs) are
committed in the workspace and sent back with `propose`.

## Commands

```
delphi layout new <scope> <layout> [--from <file>]   create a layout (branch + PR)
delphi layout list                                   list layouts on origin/main
delphi workspace new <layout> [--as <ws>] [--ref <branch>]
delphi workspace open|refresh|propose|status         (alias: ws)
delphi block mv <old> <new>                          move a block (branch + PR)
delphi check                                         validate the repo
```

Commands that write to Delphi accept `--model`, `--effort` (provenance) and `--yes`. Without
`--yes`, a non-interactive run fails fast instead of prompting.

## Developing Delphi

Test CLI changes in the sandbox, never against GitHub (see `CLAUDE.md`):
`eval "$(/bin/bash dev/sandbox.sh /tmp/delphi-sb)"`, then `d <command>`.
