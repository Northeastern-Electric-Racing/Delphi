#!/usr/bin/env bash
# Start Codex CLI at this workspace with the layout inherited by commands and child processes.
set -euo pipefail
# shellcheck source=.delphi/paths.sh
source "$(dirname "$0")/paths.sh"
exec codex -C "$DELPHI_ROOT" "$@"
