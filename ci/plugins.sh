#!/usr/bin/env bash
# ci/plugins.sh [--check] [<dir>]: write the generated harness files of a main checkout <dir> (default .):
#   .claude-plugin/marketplace.json: marketplace `delphi`, one plugin per set folder
#     software/**/plugins/claude/<set>/ outside workspaces, named <scope>, or <scope>.<set> unless the
#     set is `default`. A folder's scope is the one line in its plugins/scope, else its short-name
#     file (as in workspace names, .delphi/names.sh), else its own name (software/application-software/
#     short-name says `app`: app, app.testing); scopes are
#     lowercase letters, digits and '-', and unique. Each plugin.json's description is copied, and its
#     name must be that name.
#   each `harness: claude-code` workspace's workspace.yml `plugins:`: the `default` set of every
#     folder above the workspace, listed first (`# default, from <folder>/`; a removed line comes
#     back), then the sets listed by hand.
#   each `harness: claude-code` workspace's .claude/settings.json: the shared settings below, plus the
#     sets under `plugins:`, enabled from the delphi marketplace. Never edit it by hand: personal
#     settings go in .claude/settings.local.json, shared ones here or in workspace.yml.
#   --check writes nothing; it lists each out-of-date file or problem and exits 1 if any.
# ci/plugins.sh yml|settings <folder> <workspace.yml>: print one workspace's workspace.yml or
#   settings.json, from <dir> = . (sync uses them for ws/* branches, reading workspace.yml from the branch).
set -euo pipefail
repo=Northeastern-Electric-Racing/Delphi

sets() { # every set folder, sorted
  find software -path '*/workspaces/*' -prune -o -type f -name plugin.json -print 2>/dev/null |
    sed -nE 's#^(software(/[a-z0-9-]+)*/plugins/claude/[a-z0-9-]+)/\.claude-plugin/plugin\.json$#\1#p' | LC_ALL=C sort
}

scope_of() { # <folder holding plugins/>: its scope
  if [ -f "$1/plugins/scope" ]; then tr -d '[:space:]' <"$1/plugins/scope" && echo
  elif [ -f "$1/short-name" ]; then tr -d '[:space:]' <"$1/short-name" && echo
  else echo "${1##*/}"; fi
}

name_of() { # <set folder>: the plugin's name in the marketplace
  local scope set=${1##*/}
  scope=$(scope_of "${1%/plugins/claude/*}")
  if [ "$set" = default ]; then echo "$scope"; else echo "$scope.$set"; fi
}

field() { # <set folder> <key>: a top-level string field of its plugin.json, as written (quoted)
  sed -nE 's/^[[:space:]]*"'"$2"'":[[:space:]]*("([^"\\]|\\.)*")[[:space:]]*,?[[:space:]]*$/\1/p' "$1/.claude-plugin/plugin.json" | head -n 1
}

marketplace() {
  local s d sep=""
  printf '{\n  "name": "delphi",\n  "owner": {\n    "name": "Northeastern Electric Racing"\n  },\n'
  printf '  "description": "Delphi%ss Claude Code plugins: context shared by the workspaces under a folder.",\n  "plugins": [' "'"
  for s in $(sets); do
    d=$(field "$s" description)
    printf '%s\n    {\n      "name": "%s",\n      "source": "./%s"' "$sep" "$(name_of "$s")" "$s"
    [ -z "$d" ] || printf ',\n      "description": %s' "$d"
    printf '\n    }'
    sep=,
  done
  printf '\n  ]\n}\n'
}

defaults() { # <workspace folder>: the default set of every folder above it, top first
  local p="" part
  for part in $(echo "${1%/workspaces/*}" | tr / ' '); do
    p=${p:+$p/}$part
    [ ! -f "$p/plugins/claude/default/.claude-plugin/plugin.json" ] || echo "$p/plugins/claude/default"
  done
}

yml() { # <folder> <workspace.yml>: the yml with its defaults first under plugins: (added after harness: if missing)
  local s gen="" names=""
  [ -f "$2" ] || { echo "plugins: no $2" >&2 && return 1; }
  for s in $(defaults "$1"); do
    gen="$gen$(printf '  - %-14s # default, from %s/' "$(name_of "$s")" "${s%/plugins/claude/default}")\\n"
    names="$names $(name_of "$s")"
  done
  awk -v gen="$gen" -v names="$names" -v has="$(grep -c '^plugins:' "$2" || true)" '
    BEGIN { n = split(names, a, " "); for (i = 1; i <= n; i++) d[a[i]] = 1 }
    /^plugins:/ { print; if (!done++) printf "%s", gen; s = 1; next }
    /^[^[:space:]#]/ { s = 0 }
    s && /^[[:space:]]+-/ { v = $0; sub(/^[[:space:]]+-[[:space:]]+/, "", v); sub(/[[:space:]]*#.*$/, "", v)
      if ((v in d) || $0 ~ /# default, from /) next }
    { print }
    /^harness:/ && !has && gen != "" && !done++ {
      printf "plugins:                  # `- <scope>[.<set>]`: plugin sets to enable; CI lists the `default` set of every folder above first and generates .claude/settings.json\n%s", gen }' "$2"
}

settings() { # <folder> <workspace.yml>
  local e s list="" sep="" index
  [ -f "$2" ] || { echo "plugins: no $2" >&2 && return 1; }
  index=$(for s in $(sets); do echo "$(name_of "$s") $s"; done)
  list=" $(defaults "$1" | tr '\n' ' ')"
  while IFS= read -r e; do
    s=$(echo "$index" | awk -v n="$e" '$1 == n { print $2; exit }')
    [ -n "$s" ] || { echo "plugins: $2 lists $e, which isn't a plugin set" >&2 && return 1; }
    case "$list " in *" $s "*) ;; *) list="$list $s" ;; esac
  done < <(awk '/^plugins:/ { s = 1; next } /^[^[:space:]#]/ { s = 0 }
    s && /^[[:space:]]+-/ { sub(/^[[:space:]]+-[[:space:]]+/, ""); sub(/[[:space:]]*#.*$/, ""); print }' "$2")
  printf '{\n  "attribution": {\n    "sessionUrl": false\n  }'
  # every shell (the model's, subagents', skill scripts') gets $DELPHI_ROOT and the layout from paths.sh
  printf ',\n  "hooks": {\n    "SessionStart": [\n      {\n        "hooks": [\n          {\n            "type": "command",\n'
  # shellcheck disable=SC2016 # the hook expands them, not this script
  printf '            "command": "bash \\"$CLAUDE_PROJECT_DIR/.delphi/paths.sh\\" >> \\"$CLAUDE_ENV_FILE\\""\n'
  printf '          }\n        ]\n      }\n    ]\n  }'
  if [ -n "${list// /}" ]; then
    printf ',\n  "extraKnownMarketplaces": {\n    "delphi": {\n      "source": {\n        "source": "github",\n'
    printf '        "repo": "%s"\n      },\n      "autoUpdate": true\n    }\n  },\n  "enabledPlugins": {' "$repo"
    for s in $list; do printf '%s\n    "%s@delphi": true' "$sep" "$(name_of "$s")" && sep=,; done
    printf '\n  }'
  fi
  printf '\n}\n'
}

case "${1:-}" in yml | settings)
  [ $# -eq 3 ] || { echo "usage: ci/plugins.sh yml|settings <folder> <workspace.yml>" >&2 && exit 2; }
  "$1" "$2" "$3"
  exit ;;
esac
check=0
[ "${1:-}" != --check ] || { check=1 && shift; }
cd "${1:-.}"
problems=0
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

put() { # <file> <what's stale> <command...>: write <command>'s output to <file> (with --check, report if it differs)
  local f=$1 what=$2
  shift 2
  "$@" >"$tmp" || { problems=$((problems + 1)) && return; }
  cmp -s "$tmp" "$f" && return
  if [ "$check" = 1 ]; then
    echo "plugins: $f $what; run ci/plugins.sh" >&2
    problems=$((problems + 1))
  else
    mkdir -p "$(dirname "$f")" && cp "$tmp" "$f" && echo "plugins: wrote $f"
  fi
}

folders=$(for s in $(sets); do echo "${s%/plugins/claude/*}"; done | uniq)
for f in $folders; do
  case "$(scope_of "$f")" in "" | -* | *[!a-z0-9-]*)
    echo "plugins: $f: scope '$(scope_of "$f")' must be lowercase letters, digits and '-' (set it in $f/plugins/scope or $f/short-name)" >&2
    problems=$((problems + 1)) ;;
  esac
done
for n in $(for f in $folders; do scope_of "$f"; done | sort | uniq -d); do
  echo "plugins: two folders both have scope $n; give one a plugins/scope file with another" >&2 && problems=$((problems + 1))
done
for s in $(sets); do
  [ "$(field "$s" name)" = "\"$(name_of "$s")\"" ] ||
    { echo "plugins: $s/.claude-plugin/plugin.json: name must be \"$(name_of "$s")\"" >&2 && problems=$((problems + 1)); }
done
put .claude-plugin/marketplace.json "is generated and out of date (don't edit it)" marketplace
for y in $(find software -path '*/workspaces/*/workspace.yml' -type f 2>/dev/null | LC_ALL=C sort); do
  folder=${y%/workspace.yml}
  case "$(dirname "$folder")" in */workspaces) ;; *) continue ;; esac
  [ "$(awk '/^harness:/ { print $2; exit }' "$y")" = claude-code ] || continue
  put "$y" "doesn't list the default set of every folder above first under plugins:" yml "$folder" "$y"
  put "$folder/.claude/settings.json" "is generated and out of date (don't edit it)" settings "$folder" "$y"
done
[ "$problems" = 0 ] || exit 1
