#!/usr/bin/env bash
# serve.sh <argos-worktree>: serve that worktree's Angular client with `ng serve` on the first free
# port in 4200-4210, in the background, and print `<branch> client=<url> pid=<pid> log=<file>` once
# it has compiled. Re-running for a worktree that is still being served prints its existing client.
# Runs `npm ci` first if node_modules lacks ng (missing or half-installed). Exits 1, with the log's
# tail, if the build fails.
set -euo pipefail
wt=$(cd "${1:?usage: serve.sh <argos-worktree>}" && pwd)
branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD)
state=${TMPDIR:-/tmp}; state=${state%/}/argos-run-local
mkdir -p "$state"
key=$state/$(printf %s "$wt" | tr -c 'A-Za-z0-9' _)
log=$key.log
up() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null || (exec 3<>"/dev/tcp/::1/$1") 2>/dev/null; } # ng serve binds ::1

if [ -f "$key.pid" ] && kill -0 "$(cat "$key.pid")" 2>/dev/null && up "$(cat "$key.port")"; then
  echo "$branch client=http://localhost:$(cat "$key.port") pid=$(cat "$key.pid") log=$log (already running)"
  exit 0
fi

port=
for p in $(seq 4200 4210); do up "$p" || { port=$p && break; }; done
[ -n "$port" ] || { echo "serve: no free port in 4200-4210" >&2 && exit 1; }

cd "$wt/angular-client"
[ -x node_modules/.bin/ng ] || npm ci --no-audit --no-fund >"$log" 2>&1 ||
  { echo "serve: npm ci failed in $wt/angular-client:" >&2 && tail -20 "$log" >&2 && exit 1; }
nohup npx ng serve --port "$port" >"$log" 2>&1 &
pid=$!
echo "$pid" >"$key.pid" && echo "$port" >"$key.port"

for _ in $(seq 180); do
  kill -0 "$pid" 2>/dev/null || { echo "serve: ng serve exited for $branch:" >&2 && tail -20 "$log" >&2 && exit 1; }
  if grep -q 'bundle generation failed\|\[ERROR\]' "$log"; then
    echo "serve: $branch failed to compile (still serving on $port, pid $pid):" >&2 && tail -30 "$log" >&2 && exit 1
  fi
  if up "$port" && grep -q 'bundle generation complete\|Compiled successfully' "$log"; then
    echo "$branch client=http://localhost:$port pid=$pid log=$log"
    exit 0
  fi
  sleep 1
done
echo "serve: $branch not up after 180s (pid $pid); see $log" >&2 && exit 1
