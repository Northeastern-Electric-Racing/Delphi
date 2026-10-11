# .delphi/paths.sh: the workspace layout, in one place. Source it from the workspace root you were
# given (`. "$root/.delphi/paths.sh"`; skills pass the root as ${CLAUDE_PROJECT_DIR}), never by
# searching for it. Sets DELPHI_ROOT (this clone's top, from this file's place) and the folders under
# it. Bash 3.2 and Git Bash safe.
# shellcheck shell=bash disable=SC2034
DELPHI_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DELPHI_REPOS=$DELPHI_ROOT/repos               # bare stores: repos/<repo>
DELPHI_WORKTREES=$DELPHI_ROOT/worktrees       # checkouts: worktrees/<repo>/<branch>
DELPHI_REFERENCES=$DELPHI_ROOT/references     # read-only dependency sources: references/<name>
DELPHI_LINKED=$DELPHI_ROOT/linked             # read-only Delphi copies: linked/<branch>
