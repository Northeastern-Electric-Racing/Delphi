#!/usr/bin/env bash
# find-app.sh: report the local Argos stack as one line of key=value pairs:
#   client=<url|none> backend=<url|none> scylla=<docker|local|none> free_client_port=<port|none>
# The client is the first listener on 4200-4210; the backend the first on 8000-8090 in steps of 10
# (8000 + 10*STACK_OFFSET). scylla=docker when a scylla-server container is running.
set -euo pipefail
up() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
client=none free=none backend=none scylla=none
for p in $(seq 4200 4210); do
  if up "$p"; then [ "$client" = none ] && client=http://localhost:$p
  elif [ "$free" = none ]; then free=$p; fi
done
for p in $(seq 8000 10 8090); do up "$p" && backend=http://localhost:$p && break; done
if docker ps --filter name=scylla-server --format '{{.Names}}' 2>/dev/null | grep -q .; then scylla=docker
elif [ "$backend" != none ]; then scylla=local; fi
echo "client=$client backend=$backend scylla=$scylla free_client_port=$free"
