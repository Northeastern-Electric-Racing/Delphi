#!/usr/bin/env bash
# seed.sh: make sure the local database holds verify-graph's multi-day run, and print its id. The run is
# 50 hours of BMS/Segment_Total_Volt/0, one point every 30s, from noon UTC four days ago, so it crosses
# two midnights in any time zone and stays out of the 24-hour Quick Select window. Parallel checks share
# one run: it is made once, under a lock, and found by its notes after that.
set -euo pipefail
db=$(docker ps --filter name=odyssey-db --format '{{.Names}}' | head -1)
[ -n "$db" ] || { echo "seed: no odyssey-db container; start the backend with run-local first" >&2 && exit 1; }
sql() { docker exec -i "$db" psql -U postgres -v ON_ERROR_STOP=1 -qAt "$@"; }
tag='verify-graph multi-day seed'
state=${TMPDIR:-/tmp}; state=${state%/}/argos-run-local; mkdir -p "$state"
lock=$state/seed.lock
n=0; until mkdir "$lock" 2>/dev/null; do n=$((n + 1)); [ $n -lt 600 ] || rm -rf "$lock"; sleep 0.1; done # stale after 60s
trap 'rmdir "$lock" 2>/dev/null || true' EXIT
id=$(sql -c "select \"runId\" from run where notes = '$tag' limit 1")
[ -n "$id" ] || id=$(sql <<SQL
insert into data_type (name, unit) values ('BMS/Segment_Total_Volt/0', 'V') on conflict do nothing;
with r as (
  insert into run ("driverName", "locationName", notes, time)
  values ('verify-graph', 'seed', '$tag', date_trunc('day', now()) - interval '84 hours')
  returning "runId", time
), d as (
  insert into data (values, time, "dataTypeName", "runId")
  select array[400 + 20 * sin(s / 3600.0)]::real[], (extract(epoch from r.time) * 1e6)::bigint + s * 1000000::bigint,
    'BMS/Segment_Total_Volt/0', r."runId"
  from r, generate_series(0, 50 * 3600, 30) s
)
select "runId" from r;
SQL
)
echo "$id"
