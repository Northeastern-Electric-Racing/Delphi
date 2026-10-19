#!/usr/bin/env bash
# perf.sh <branch> <base-url> [<topic>,…]: measure the graph page live in <branch>'s playwright-cli session
# (perf.js: JS heap, allocation rate, frames; about a minute), then its browser's GPU-process memory, where
# a WebGL chart's buffers show up. Default topics: four BMS ones. Numbers are relative: compare branches.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
branch=${1:?usage: perf.sh <branch> <base-url> [<topic>,…]}; url=${2:?usage: perf.sh <branch> <base-url> [<topic>,…]}; url=${url%/}
topics=${3:-BMS/Segment_Total_Volt/0,BMS/PerCell/Alpha/3/Volts/5,BMS/PerCell/Alpha/3/Volts/4,BMS/PerCell/Alpha/4/Therms/0}
playwright-cli list | grep -q "^- $branch:" || bash "$here/open.sh" "$branch" "$url/graph" >/dev/null
code=$(sed -e "s|__URL__|$url|; s|__TOPICS__|$topics|g" "$here/perf.js")
playwright-cli -s="$branch" --raw run-code "$code" | node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(0, "utf8")) + "\n")'
# The session's daemon runs its browser; the browser's --type=gpu-process child holds GPU memory.
ps -axo pid=,ppid=,rss=,command= | awk -v s=" $branch " '
  { pid[NR] = $1; ppid[NR] = $2; rss[NR] = $3; cmd[NR] = $0 }
  index($0, "cliDaemon") && index($0 " ", s) { daemon[$1] = 1 }
  END {
    for (i = 1; i <= NR; i++) if (daemon[ppid[i]]) browser[pid[i]] = 1
    for (i = 1; i <= NR; i++) if (browser[ppid[i]] && index(cmd[i], "--type=gpu-process")) printf "GPU process %d MB\n", rss[i] / 1024
  }'
