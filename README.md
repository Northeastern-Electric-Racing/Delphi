# Delphi

NER's AI-harness context (knowledge, instructions, skills, MCP, settings), stored compressed
by org chart under `context/`, plus a small bash CLI:

- **compile** a *layout* into a local, git-initialized *workspace* where Claude Code runs,
- **refresh** the workspace when `main` moves,
- **propose** workspace edits back as one PR, routed to the blocks they came from.

Design: `docs/superpowers/specs/2026-09-23-delphi-context-repo-design.md`.

## Quick start (sandbox, no GitHub)

```sh
eval "$(/bin/bash dev/sandbox.sh /tmp/delphi-sb)"   # defines `d` (CLI under /bin/bash); stubs `gh`
d check                                              # validate the sample repo
d workspace new argos-dev                            # compile into ../Delphi-workspaces/argos-dev
d ws status                                          # state, staleness, next command
d ws open argos-dev                                  # launch Claude Code there (--shell for a shell)
# … edit files in the workspace and commit …
d ws propose --dry-run                               # see how edits route; unresolved items listed
d ws propose --yes                                   # refresh, build the PR branch, push to the sandbox origin
```

For real use, put `bin/` on `PATH` and run `delphi …` from a clone whose `origin` is the GitHub repo.

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
