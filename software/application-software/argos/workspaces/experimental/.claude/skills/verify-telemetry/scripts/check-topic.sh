#!/usr/bin/env bash
# check-topic.sh <topic>: check one MQTT topic end to end for verify-telemetry. Prints
# its CAN definition (file, message id, unit, value points) from worktrees/odyssey-definitions/main,
# whether the Calypso simulator image is current and running,
# and the topic's last scylla-server log lines. Exits 1 if the topic isn't defined. Needs jq; the
# docker checks are skipped without docker.
set -euo pipefail
usage="usage: check-topic.sh <topic>"
topic=${1:?$usage}
# shellcheck source=/dev/null
. "${DELPHI_ROOT:?source <workspace-root>/.delphi/paths.sh first}/.delphi/paths.sh"
defs=$DELPHI_WORKTREES/odyssey-definitions/main/can-messages
[ -d "$defs" ] || { echo "no CAN definitions at $defs; add odyssey-definitions under repos: and run .delphi/setup.sh" >&2; exit 2; }

echo "== CAN definition"
jq -ce --arg t "$topic" 'input_filename as $f | .[] | . as $m | .fields[]? | select(.name == $t) |
  {file: ($f | split("/")[-1]), id: $m.id, desc: $m.desc, unit, points: [.values[] | $m.points[. - 1].name]}' \
  "$defs"/*.json || { echo "not found: $topic"; exit 1; }

command -v docker >/dev/null || { echo "== docker not installed; skipping Calypso and logs"; exit 0; }
echo "== Calypso"
if docker pull -q ghcr.io/northeastern-electric-racing/calypso:Develop >/dev/null 2>&1; then
  echo "image pulled (restart the stack if it changed)"; else echo "pull failed"; fi
docker ps --filter name=calypso --format '{{.Names}} {{.Status}}' 2>/dev/null | grep . || echo "calypso not running"
echo "== scylla-server log"
c=$(docker ps --filter name=scylla-server --format '{{.Names}}' 2>/dev/null | head -1) # compose names it <project>-scylla-server-1
if [ -z "$c" ]; then echo "scylla-server not running in docker (local cargo run? check its log)"
else docker logs "$c" 2>&1 | grep -F "$topic" | tail -5 | grep . || echo "no log lines for $topic (not published?)"; fi
