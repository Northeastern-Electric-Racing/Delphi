#!/usr/bin/env bash
# run-local.sh [<branch>...]: bring up the local Argos stack for those branches'
# worktrees (worktrees/argos/<branch>, made beforehand with new-worktree) and print one line per
# piece. The backend (first listener on 8000-8090, step 10) is started if down:
# ./argos.sh client-dev when no target changes scylla-server/, else scylla-dev plus `cargo run` in the
# one worktree that does. Each target's client is then served by serve.sh on its own port. With no
# branches, reports what is running.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=/dev/null
. "${DELPHI_ROOT:?source <workspace-root>/.delphi/paths.sh first}/.delphi/paths.sh"
state=${TMPDIR:-/tmp}; state=${state%/}/argos-run-local
up() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null || (exec 3<>"/dev/tcp/::1/$1") 2>/dev/null; } # ng serve binds ::1
backend() { for p in $(seq 8000 10 8090); do up "$p" && echo "http://localhost:$p" && return; done; echo none; }
scylla() {
  if docker ps --filter name=scylla-server --format '{{.Names}}' 2>/dev/null | grep -q .; then echo docker
  elif [ "$(backend)" != none ]; then echo local
  else echo none; fi
}

if [ $# = 0 ]; then
  clients=
  for p in $(seq 4200 4210); do up "$p" && clients="$clients http://localhost:$p"; done
  echo "backend=$(backend) scylla=$(scylla) clients=${clients# }"
  exit 0
fi

wts=() rust=()
for b in "$@"; do
  wt=$DELPHI_WORKTREES/argos/$b
  [ -f "$wt/argos.sh" ] && [ -d "$wt/angular-client" ] ||
    { echo "run-local: no Argos worktree for '$b' at $wt (make it with new-worktree)" >&2 && exit 1; }
  wts+=("$wt")
done
git -C "${wts[0]}" fetch -q origin # the worktrees share one store
for wt in "${wts[@]}"; do
  if ! git -C "$wt" diff --quiet origin/develop... -- scylla-server || ! git -C "$wt" diff --quiet HEAD -- scylla-server; then
    rust+=("$wt")
  fi
done
[ ${#rust[@]} -le 1 ] || { echo "run-local: several targets change scylla-server/; run them one at a time" >&2 && exit 1; }

if [ "$(backend)" = none ]; then
  mkdir -p "$state"
  if [ ${#rust[@]} = 0 ]; then
    (cd "${wts[0]}" && ./argos.sh client-dev up -d) >"$state/compose.log" 2>&1 ||
      { echo "run-local: ./argos.sh client-dev up failed:" >&2 && tail -20 "$state/compose.log" >&2 && exit 1; }
  else
    (cd "${rust[0]}" && ./argos.sh scylla-dev up -d) >"$state/compose.log" 2>&1 ||
      { echo "run-local: ./argos.sh scylla-dev up failed:" >&2 && tail -20 "$state/compose.log" >&2 && exit 1; }
    (cd "${rust[0]}/scylla-server" &&
      DATABASE_URL=${DATABASE_URL:-postgresql://postgres:password@127.0.0.1:${ODYSSEY_DB_PORT:-5432}/postgres} \
        nohup cargo run >"$state/scylla.log" 2>&1 &)
    echo "run-local: cargo run started for $(basename "${rust[0]}"); log $state/scylla.log"
  fi
  for _ in $(seq 600); do [ "$(backend)" != none ] && break; sleep 1; done
  [ "$(backend)" != none ] || { echo "run-local: backend not up after 600s; see $state/" >&2 && exit 1; }
elif [ ${#rust[@]} = 1 ] && [ "$(scylla)" = docker ]; then
  echo "run-local: warning: backend is the scylla-server image but $(basename "${rust[0]}") changes scylla-server/;" \
    "stop it (./argos.sh client-dev down) and re-run to test that branch's backend" >&2
fi
echo "backend=$(backend) scylla=$(scylla)"

status=0
for wt in "${wts[@]}"; do bash "$here/serve.sh" "$wt" || status=1; done
exit $status
