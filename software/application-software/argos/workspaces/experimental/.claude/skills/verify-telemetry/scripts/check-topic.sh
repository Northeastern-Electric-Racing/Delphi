#!/usr/bin/env bash
# check-topic.sh <topic>: check one MQTT topic end to end for verify-telemetry. Prints its CAN
# definition (file, message id, unit, value points) from worktrees/odyssey-definitions/main, whether
# the Calypso simulator image is current and running, and the topic's last scylla-server log lines.
# Exits 1 if the topic isn't defined. Needs jq; the docker checks are skipped without docker.
set -euo pipefail
topic=${1:?usage: check-topic.sh <topic>}
defs=$(cd "$(dirname "$0")/../../../.." && pwd)/worktrees/odyssey-definitions/main/can-messages
[ -d "$defs" ] || { echo "no CAN definitions at $defs; run .delphi/setup.sh" >&2; exit 2; }

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
docker logs scylla-server 2>&1 | grep -F "$topic" | tail -5 | grep . || echo "no log lines for $topic (not published?)"
