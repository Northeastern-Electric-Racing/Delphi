#!/usr/bin/env bash
# file-idea.sh <repo> <title> <body-file> [<label>...]: file a raw idea as an issue on a workspace
# repo, labelled needs-triage plus any <label>s and assigned to you; print its URL. Exits 3 on any
# GitHub failure (see .claude/scripts/github.sh).
# shellcheck source-path=SCRIPTDIR source=../../../scripts/github.sh
set -euo pipefail
. "$(dirname "$0")/../../../scripts/github.sh"
repo=${1:?usage: file-idea.sh <repo> <title> <body-file> [<label>...]} title=${2:?title} body=${3:?body file}
shift 3
gh_init file-idea "$repo"
me=$(get user | jq -r .login)
jq -n --arg t "$title" --rawfile b "$body" --arg me "$me" --args \
  '{title: $t, body: $b, labels: (["needs-triage"] + $ARGS.positional), assignees: [$me]}' "$@" |
  post "repos/$SLUG/issues" | jq -r .html_url
