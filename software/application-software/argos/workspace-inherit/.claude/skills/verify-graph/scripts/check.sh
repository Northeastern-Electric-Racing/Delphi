#!/usr/bin/env bash
# check.sh <branch> <base-url>: run the base verify-graph checks (check.js) in <branch>'s playwright-cli
# session, opening it if needed, against the seeded multi-day run. Prints one `[x]`/`[ ]` line per check
# and `look:` lines for screenshots in pictures/<branch>/verify-graph/; exits 1 if a check failed.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
branch=${1:?usage: check.sh <branch> <base-url>}; url=${2:?usage: check.sh <branch> <base-url>}; url=${url%/}
run=$(bash "$here/seed.sh")
out=${DELPHI_ROOT:?unset: start the session at the workspace root}/pictures/$branch/verify-graph
playwright-cli list | grep -q "^- $branch:" || bash "$here/open.sh" "$branch" "$url/graph" >/dev/null
code=$(sed -e "s|__URL__|$url|; s|__RUN__|$run|; s|__OUT__|$out|" "$here/check.js")
result=$(playwright-cli -s="$branch" --raw run-code "$code" | node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(0, "utf8")))')
echo "$result"
! grep -q '^\[ \]' <<<"$result"
