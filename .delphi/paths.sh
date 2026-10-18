# .delphi/paths.sh: the workspace layout, in one place. Sourced, it sets and exports DELPHI_ROOT (this
# clone's top, from this file's place, never by searching) and the folders under it; run, it prints
# them as one export line. Each harness's session-start hook writes that line into every shell (Claude
# Code's is in the generated .claude/settings.json), so skill scripts read the workspace from
# $DELPHI_ROOT and take only names; in a terminal, `. .delphi/paths.sh` from the root. Bash 3.2, Git
# Bash and zsh safe.
# shellcheck shell=bash
DELPHI_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)
DELPHI_REPOS=$DELPHI_ROOT/repos               # bare stores: repos/<repo>
DELPHI_WORKTREES=$DELPHI_ROOT/worktrees       # checkouts: worktrees/<repo>/<branch>
DELPHI_REFERENCES=$DELPHI_ROOT/references     # read-only dependency sources: references/<name>
DELPHI_LINKED=$DELPHI_ROOT/linked             # Delphi clones to read: linked/<workspace>, linked/main
export DELPHI_ROOT DELPHI_REPOS DELPHI_WORKTREES DELPHI_REFERENCES DELPHI_LINKED
[ "${BASH_SOURCE[0]:-}" != "$0" ] || printf 'export DELPHI_ROOT=%q DELPHI_REPOS=%q DELPHI_WORKTREES=%q DELPHI_REFERENCES=%q DELPHI_LINKED=%q\n' \
  "$DELPHI_ROOT" "$DELPHI_REPOS" "$DELPHI_WORKTREES" "$DELPHI_REFERENCES" "$DELPHI_LINKED"
