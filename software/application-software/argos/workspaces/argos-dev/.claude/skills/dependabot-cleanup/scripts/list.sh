#!/usr/bin/env bash
# list.sh: open Dependabot PRs on Argos, Angular upgrades left out (they need their own migration
# work). Prints one line per PR: #<n> <ecosystem> <branch> <title>.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
gh pr list -R "$R" --author app/dependabot --state open --limit 100 --json number,headRefName,title \
  -q '.[] | select((.title + .headRefName) | test("angular"; "i") | not)
       | "#\(.number) \(.headRefName | split("/")[1]) \(.headRefName) \(.title)"'
