#!/usr/bin/env bash
# open.sh <branch> <url>: open a playwright-cli session named <branch> on <url>, so parallel checks don't
# share a browser. Its output (snapshots, console logs, unnamed screenshots) goes to pictures/<branch>/;
# its config, and any throwaway Playwright code, to .playwright-cli/<branch>/. Both are gitignored. Uses
# the preinstalled Chromium in cloud containers (/opt/pw-browsers); elsewhere, Playwright's own
# (`playwright-cli install-browser`).
set -euo pipefail
branch=${1:?usage: open.sh <branch> <url>}; url=${2:?usage: open.sh <branch> <url>}
root=${DELPHI_ROOT:?unset: start the session at the workspace root}
out=$root/pictures/$branch scratch=$root/.playwright-cli/$branch
mkdir -p "$out" "$scratch"
launch=; [ -x /opt/pw-browsers/chromium ] && launch=',"launchOptions":{"executablePath":"/opt/pw-browsers/chromium","headless":true}'
printf '{"browser":{"browserName":"chromium"%s},"outputDir":"%s"}\n' "$launch" "$out" >"$scratch/cli.config.json"
playwright-cli -s="$branch" open --config="$scratch/cli.config.json" "$url"
