#!/usr/bin/env bash
# ci/plugins.sh [--check] [<dir>]: write the generated harness files of a main checkout <dir> (default .):
#   .claude-plugin/marketplace.json: marketplace `delphi`, one plugin per set folder
#     software/**/plugins/claude/<set>/ outside workspaces, named after the folder holding plugins/
#     (its last part), plus -<set> unless the set is `default`; each plugin.json's description is copied.
#   each `harness: claude-code` workspace's .claude/settings.json: the shared settings below, plus the
#     `default` set of every folder above the workspace and each `- <folder>/<set>` under `plugins:`
#     in its workspace.yml, enabled from the delphi marketplace. Never edit it by hand: personal
#     settings go in .claude/settings.local.json, shared ones here or in workspace.yml.
#   --check writes nothing; it lists each out-of-date file or problem and exits 1 if any.
# ci/plugins.sh settings <folder> <workspace.yml>: print one workspace's settings.json, from <dir> = .
#   (sync uses it for ws/* branches, reading workspace.yml from the branch).
set -euo pipefail
repo=Northeastern-Electric-Racing/Delphi

sets() { # every set folder, sorted
  find software -path '*/workspaces/*' -prune -o -type f -name plugin.json -print 2>/dev/null |
    sed -nE 's#^(software(/[a-z0-9-]+)*/plugins/claude/[a-z0-9-]+)/\.claude-plugin/plugin\.json$#\1#p' | LC_ALL=C sort
}

name_of() { # <set folder>: the plugin's name in the marketplace
  local folder=${1%/plugins/claude/*} set=${1##*/}
  if [ "$set" = default ]; then echo "${folder##*/}"; else echo "${folder##*/}-$set"; fi
}

marketplace() {
  local s d sep=""
  printf '{\n  "name": "delphi",\n  "owner": {\n    "name": "Northeastern Electric Racing"\n  },\n'
  printf '  "description": "Delphi%ss Claude Code plugins: context shared by the workspaces under a folder.",\n  "plugins": [' "'"
  for s in $(sets); do
    d=$(sed -nE 's/^[[:space:]]*"description":[[:space:]]*("([^"\\]|\\.)*")[[:space:]]*,?[[:space:]]*$/\1/p' "$s/.claude-plugin/plugin.json" | head -n 1)
    printf '%s\n    {\n      "name": "%s",\n      "source": "./%s"' "$sep" "$(name_of "$s")" "$s"
    [ -z "$d" ] || printf ',\n      "description": %s' "$d"
    printf '\n    }'
    sep=,
  done
  printf '\n  ]\n}\n'
}

settings() { # <folder> <workspace.yml>
  local folder=$1 p="" part e s list="" sep=""
  [ -f "$2" ] || { echo "plugins: no $2" >&2 && return 1; }
  for part in $(echo "${folder%/workspaces/*}" | tr / ' '); do
    p=${p:+$p/}$part
    [ ! -f "$p/plugins/claude/default/.claude-plugin/plugin.json" ] || list="$list $p/plugins/claude/default"
  done
  while IFS= read -r e; do
    s=${e%/*}/plugins/claude/${e##*/}
    [ -f "$s/.claude-plugin/plugin.json" ] || { echo "plugins: $2 lists $e, but $s/ has no plugin" >&2 && return 1; }
    case "$list " in *" $s "*) ;; *) list="$list $s" ;; esac
  done < <(awk '/^plugins:/ { s = 1; next } /^[^[:space:]#]/ { s = 0 }
    s && /^[[:space:]]+-/ { sub(/^[[:space:]]+-[[:space:]]+/, ""); sub(/[[:space:]]*#.*$/, ""); print }' "$2")
  printf '{\n  "attribution": {\n    "sessionUrl": false\n  }'
  if [ -n "$list" ]; then
    printf ',\n  "extraKnownMarketplaces": {\n    "delphi": {\n      "source": {\n        "source": "github",\n'
    printf '        "repo": "%s"\n      },\n      "autoUpdate": true\n    }\n  },\n  "enabledPlugins": {' "$repo"
    for s in $list; do printf '%s\n    "%s@delphi": true' "$sep" "$(name_of "$s")" && sep=,; done
    printf '\n  }'
  fi
  printf '\n}\n'
}

if [ "${1:-}" = settings ]; then
  [ $# -eq 3 ] || { echo "usage: ci/plugins.sh settings <folder> <workspace.yml>" >&2 && exit 2; }
  settings "$2" "$3"
  exit
fi
check=0
[ "${1:-}" != --check ] || { check=1 && shift; }
cd "${1:-.}"
problems=0
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

put() { # <file> <command...>: write <command>'s output to <file> (with --check, report if it differs)
  local f=$1
  shift
  "$@" >"$tmp" || { problems=$((problems + 1)) && return; }
  cmp -s "$tmp" "$f" && return
  if [ "$check" = 1 ]; then
    echo "plugins: $f is generated and out of date; run ci/plugins.sh instead of editing it" >&2
    problems=$((problems + 1))
  else
    mkdir -p "$(dirname "$f")" && cp "$tmp" "$f" && echo "plugins: wrote $f"
  fi
}

for n in $(for s in $(sets); do name_of "$s"; done | sort | uniq -d); do
  echo "plugins: two plugin sets are both named $n; rename a folder or set" >&2 && problems=$((problems + 1))
done
put .claude-plugin/marketplace.json marketplace
for y in $(find software -path '*/workspaces/*/workspace.yml' -type f 2>/dev/null | LC_ALL=C sort); do
  folder=${y%/workspace.yml}
  case "$(dirname "$folder")" in */workspaces) ;; *) continue ;; esac
  [ "$(awk '/^harness:/ { print $2; exit }' "$y")" = claude-code ] || continue
  put "$folder/.claude/settings.json" settings "$folder" "$y"
done
[ "$problems" = 0 ] || exit 1
