#!/usr/bin/env bash
# Run a command with this clone's layout, even in hosts whose fresh shells discard session exports.
set -euo pipefail
# shellcheck source=.delphi/paths.sh
source "$(dirname "$0")/paths.sh"
[ "$#" -gt 0 ] || { echo "usage: bash .delphi/exec.sh <command> [<arg>...]" >&2; exit 2; }
exec "$@"
