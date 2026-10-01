#!/usr/bin/env bash
# check-topic.sh <topic>: check one MQTT topic end to end for verify-telemetry. Prints its CAN
# definition (file, message id, unit, value points) from worktrees/odyssey-definitions/main, whether
# the Calypso simulator image is current and running, and the topic's last scylla-server log lines.
# Exits 1 if the topic isn't in the CAN definitions. Needs jq; docker checks are skipped without it.
set -euo pipefail
topic=${1:?usage: check-topic.sh <topic>}
root=$(cd "$(dirname "$0")/../../../.." && pwd)
defs=$root/worktrees/odyssey-definitions/main/can-messages
[ -d "$defs" ] || { echo "no CAN definitions at $defs; run .delphi/setup.sh" >&2; exit 2; }

echo "== CAN definition"
found=$(for f in "$defs"/*.json; do
  jq -c --arg t "$topic" --arg f "${f##*/}" '.[] | . as $m | .fields[]? | select(.name == $t) |
    {file: $f, id: $m.id, desc: $m.desc, unit, points: [.values[] as $i | $m.points[$i - 1].name]}' "$f"
done)
[ -n "$found" ] || { echo "not found: $topic"; exit 1; }
echo "$found"

command -v docker >/dev/null || { echo "== docker not installed; skipping Calypso and log checks"; exit 0; }
echo "== Calypso"
docker pull -q ghcr.io/northeastern-electric-racing/calypso:Develop >/dev/null 2>&1 &&
  echo "image pulled (restart the stack if it changed)" || echo "pull failed"
docker ps --filter name=calypso --format '{{.Names}} {{.Status}}' 2>/dev/null | grep . || echo "calypso not running"
echo "== scylla-server log"
docker logs scylla-server 2>&1 | grep -F "$topic" | tail -5 | grep . || echo "no log lines for $topic (not published?)"
