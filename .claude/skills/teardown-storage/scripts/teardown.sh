#!/usr/bin/env bash
# teardown.sh [in <minutes> | auto [<minutes>|off]]: tear down what run-local brought up on this
# machine, and nothing else: the processes in its state (clients, `cargo run`, a pending timer), the
# compose projects it started (its state's `projects`) with their containers, volumes (the database
# too), networks and the images only they used, then its state; prints the space freed. With Docker
# stopped it stops the processes, keeps the record and exits 1. `in <minutes>` does it later, in the
# background, replacing an earlier timer. `auto` prints or sets the minutes run-local arms that timer
# with when it brings the stack up (git config argos.teardown in the workspace; off: never).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
state=${TMPDIR:-/tmp}; state=${state%/}/argos-run-local
usage() { echo "usage: teardown.sh [in <minutes> | auto [<minutes>|off]]" >&2 && exit 2; }
minutes() { [ -n "$1" ] && [ -z "${1//[0-9]/}" ] && [ "$1" -gt 0 ]; }
case ${1:-now} in
  auto)
    root=${DELPHI_ROOT:?unset: start the session at the workspace root}
    if [ $# -ge 2 ]; then
      [ "$2" = off ] || minutes "$2" || usage
      git -C "$root" config argos.teardown "$2"
    fi
    git -C "$root" config argos.teardown || echo unset
    exit 0 ;;
  in)
    minutes "${2:-}" || usage
    mkdir -p "$state"
    [ ! -f "$state/timer.pid" ] || { pkill -P "$(cat "$state/timer.pid")" 2>/dev/null || true; }
    # shellcheck disable=SC2016 # expanded by the inner bash
    nohup bash -c 'sleep "$1" && exec bash "$2"' _ $(($2 * 60)) "$here/teardown.sh" >"$state.log" 2>&1 &
    echo $! >"$state/timer.pid"
    echo "teardown in $2m (pid $!, log $state.log)"
    exit 0 ;;
  now) ;;
  *) usage ;;
esac

[ -d "$state" ] || { echo "teardown: run-local brought nothing up" && exit 0; }
for f in "$state"/*.pid; do # children first: npx and cargo leave their servers behind otherwise
  [ -f "$f" ] && pid=$(cat "$f") && [ "$pid" != $$ ] || continue
  pkill -P "$pid" 2>/dev/null || true; kill "$pid" 2>/dev/null || true
done
rm -f "$state"/*.pid
if [ -s "$state/projects" ] && ! docker info >/dev/null 2>&1; then
  echo "teardown: stopped run-local's processes; start Docker and re-run for $(tr '\n' ' ' <"$state/projects")" >&2
  exit 1
fi
total() { docker system df --format '{{.Size}}' | awk '{ s = $1; u = s; sub(/^[0-9.]+/, "", u)
  t += s * (u ~ /^[kK]B$/ ? 1e3 : u == "MB" ? 1e6 : u == "GB" ? 1e9 : u == "TB" ? 1e12 : 1) } END { printf "%.0f\n", t }'; }
if [ -s "$state/projects" ]; then
  before=$(total)
  while IFS= read -r proj; do
    l=label=com.docker.compose.project=$proj
    images=$(docker ps -a --filter "$l" --format '{{.Image}}' | sort -u)
    for c in $(docker ps -aq --filter "$l"); do docker rm -f "$c" >/dev/null; done
    for v in $(docker volume ls -q --filter "$l"); do docker volume rm "$v" >/dev/null; done
    for n in $(docker network ls -q --filter "$l"); do docker network rm "$n" >/dev/null; done
    for i in $images; do docker image rm "$i" >/dev/null 2>&1 || echo "kept image $i (another container uses it)"; done
    echo "removed $proj"
  done <"$state/projects"
  awk -v n=$((before - $(total))) 'BEGIN { print "freed " (n >= 1e9 ? sprintf("%.2fGB", n / 1e9) : sprintf("%.1fMB", n / 1e6)) }'
fi
rm -rf "$state"
