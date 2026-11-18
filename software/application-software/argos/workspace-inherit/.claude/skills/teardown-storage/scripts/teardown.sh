#!/usr/bin/env bash
# teardown.sh [remove]: list, with sizes, the storage the Argos skills leave on this machine: the dev
# compose stacks (project odyssey_<dev profile>[_<offset>]) with their containers, volumes (the database
# too) and networks, unused Argos images (argos*, calypso*, odyssey*), Docker's unused build cache and
# run-local's state. `remove` removes them and prints the space freed. Other compose projects (router,
# brick, tpu) are left alone; nothing is removed if a dev-named stack came from a production compose
# file or a run-local client still serves. With Docker stopped, only run-local's state is handled.
set -euo pipefail
mode=${1:-list}
case $mode in list | remove) ;; *) echo "usage: teardown.sh [remove]" >&2 && exit 2 ;; esac
state=${TMPDIR:-/tmp}; state=${state%/}/argos-run-local
p=com.docker.compose.project
units='function b(s, u) { u = s; sub(/^[0-9.]+/, "", u); sub(/[ (].*/, "", u)
    return (s + 0) * (u ~ /^[kK]B$/ ? 1e3 : u == "MB" ? 1e6 : u == "GB" ? 1e9 : u == "TB" ? 1e12 : 1) }
  function h(n) { return n >= 1e9 ? sprintf("%.2fGB", n / 1e9) : n >= 1e6 ? sprintf("%.1fMB", n / 1e6) : sprintf("%.0fkB", n / 1e3) }'
dev() { printf %s "$1" | grep -Eqx 'odyssey_(client-dev|scylla-dev|db|fake-data)(_.+)?'; }
docker=0; docker info >/dev/null 2>&1 && docker=1
plan='' keep='' used='' busy='' wrong=''
add() { plan="$plan$1|$2|$3|$4"$'\n'; } # <kind> <name> <size> <project>
inuse() { case "$used" in *" $1 "* | *" $2"*) return 0 ;; esac; return 1; } # <ref> <id>: a kept container's image
total() { # bytes Docker and run-local's state use now
  { [ $docker = 0 ] || docker system df --format '{{.Size}}'; [ ! -d "$state" ] || du -sk "$state" | awk '{ printf "%.0fB\n", $1 * 1024 }'; } |
    awk "$units"'{ t += b($1) } END { printf "%.0f\n", t }'
}

if [ $docker = 1 ]; then
  while IFS='|' read -r name proj files size image; do
    if dev "$proj"; then
      case $files in *compose.router.yml* | *compose.brick.yml* | *compose.tpu.yml*) wrong="$wrong  $name ($proj) came from $files"$'\n' ;; esac
      add container "$name" "${size%% (*}" "$proj"
    else
      used="$used $image "
      case $proj in odyssey*) case "$keep " in *" $proj "*) ;; *) keep="$keep $proj" ;; esac ;; esac
    fi
  done < <(docker ps -a --size --format "{{.Names}}|{{.Label \"$p\"}}|{{.Label \"$p.config_files\"}}|{{.Size}}|{{.Image}}")
  sizes=$(docker system df -v | awk '/^VOLUME NAME/ { v = 1; next } v && NF == 0 { v = 0 } v { print $1 "|" $NF }')
  while IFS='|' read -r name proj; do
    if dev "$proj"; then add volume "$name" "$(echo "$sizes" | awk -F'|' -v n="$name" '$1 == n { print $2 }')" "$proj"; fi
  done < <(docker volume ls --filter "label=$p" --format "{{.Name}}|{{.Label \"$p\"}}")
  while IFS='|' read -r name proj; do
    if dev "$proj"; then add network "$name" "" "$proj"; fi
  done < <(docker network ls --filter "label=$p" --format "{{.Name}}|{{.Label \"$p\"}}")
  while IFS='|' read -r repo tag id size; do
    case ${repo##*/} in argos* | calypso* | odyssey*) ;; *) continue ;; esac
    ref=$repo:$tag; [ "$tag" != "<none>" ] || ref=$id
    if ! inuse "$ref" "$id" && { [ "$tag" != latest ] || ! inuse "$repo" "$id"; }; then add image "$ref" "$size" ""; fi
  done < <(docker images --format '{{.Repository}}|{{.Tag}}|{{.ID}}|{{.Size}}')
  cache=$(docker system df --format '{{.Type}}|{{.Reclaimable}}' | awk -F'|' '$1 == "Build Cache" { print $2 }')
  [ "$(echo "$cache" | awk "$units"'{ print (b($0) > 0) }')" != 1 ] || add build-cache "every project's unused cache" "$cache" ""
fi
if [ -d "$state" ]; then
  for f in "$state"/*.pid; do
    if [ -f "$f" ] && kill -0 "$(cat "$f")" 2>/dev/null; then
      busy="$busy  run-local client on port $(cat "${f%.pid}.port" 2>/dev/null): kill $(cat "$f")"$'\n'
    fi
  done
  add state "$state" "$(du -sk "$state" | awk '{ printf "%.0fB", $1 * 1024 }')" run-local
fi

printf %s "$plan" | awk -F'|' "$units"'{ printf "%-11s %s%s  %s\n", $1, $2, $4 == "" ? "" : " (" $4 ")", $3 == "" ? "" : h(b($3)); t += b($3) }
  END { print (NR ? "about " h(t) " in all" : "nothing to remove") }'
[ $docker = 1 ] || echo "Docker isn't running: start it and re-run to free its storage"
[ -z "$keep" ] || echo "left alone (not dev stacks):$keep"
[ -z "$busy" ] || printf 'in use (stop first):\n%s' "$busy"
[ -z "$wrong" ] || { printf 'teardown: refusing; these dev-named stacks came from a production compose file:\n%s' "$wrong" >&2 && exit 1; }
[ "$mode" = remove ] || exit 0
[ -z "$busy" ] || { echo "teardown: stop the clients in use first" >&2 && exit 1; }

before=$(total)
del() { # <kind> <docker command>...: run it on each listed item of that kind
  local kind=$1 n; shift
  printf %s "$plan" | awk -F'|' -v k="$kind" '$1 == k { print $2 }' |
    while IFS= read -r n; do docker "$@" "$n" >/dev/null || echo "kept $kind $n"; done
}
del container rm -f && del volume volume rm && del network network rm && del image image rm
case $plan in *build-cache\|*) docker builder prune -af >/dev/null ;; esac
rm -rf "$state"
echo "freed $(awk "$units"' BEGIN { print h('"$before"' - '"$(total)"') }')"
[ $docker = 0 ] || echo "(Docker Desktop's disk image can take a while to shrink)"
