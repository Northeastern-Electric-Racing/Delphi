#!/usr/bin/env bash
# .delphi/version.sh [--files]: prints this checkout's Delphi version, `<version> <hash>`: the
# `version:` in .delphi/manifest.yml and a hash of the files it lists (their paths and contents as git
# stores them, so line endings don't change it; tracked files only). The last line of .delphi/versions
# must match it (ci/check.sh); setup.sh warns when it doesn't. --files: just the listed files, one per
# line (a listed path git doesn't track is printed as is). Keep it bash 3.2 (macOS) and Git Bash safe.
set -euo pipefail
cd "$(dirname "$0")/.."
m=.delphi/manifest.yml
files() {
  awk '/^[[:space:]]*#/ { next } /^files:/ { s = 1; next } /^[^[:space:]]/ { s = 0 }
    s && /^[[:space:]]+-/ { sub(/^[[:space:]]+-[[:space:]]+/, ""); sub(/[[:space:]]+#.*$/, ""); print }' "$m" |
    while IFS= read -r p; do
      l=$(git ls-files -- "$p")
      if [ -n "$l" ]; then echo "$l"; else echo "$p"; fi
    done | LC_ALL=C sort -u
}
[ "${1:-}" != --files ] || { files && exit; }
version=$(awk '/^version:/ { print $2; exit }' "$m")
hash=$(files | while IFS= read -r f; do
  echo "$(git hash-object -- "$f" 2>/dev/null || echo missing) $f"
done | git hash-object --stdin | cut -c1-12)
echo "${version:-none} $hash"
