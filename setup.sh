#!/usr/bin/env bash
# setup.sh — put the `delphi` command on PATH by symlinking bin/delphi into a bin directory.
#   ./setup.sh [dir]    default dir: ~/.local/bin
set -euo pipefail

here=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dir=${1:-$HOME/.local/bin}
mkdir -p "$dir"
ln -sfn "$here/bin/delphi" "$dir/delphi"
echo "linked $dir/delphi -> $here/bin/delphi"
case ":$PATH:" in
  *":$dir:"*) ;;
  *) echo "note: $dir is not on your PATH; add this to your shell profile:"
     echo "  export PATH=\"$dir:\$PATH\"" ;;
esac
