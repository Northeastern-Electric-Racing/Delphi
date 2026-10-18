#!/usr/bin/env bash
# open.sh <branch> <url>: open a playwright-cli session named <branch> on <url>, so parallel checks don't
# share a browser. Its snapshot and console files go to pictures/<branch>/verify-graph/playwright-cli/
# (gitignored), not .playwright-cli/ wherever it runs. Uses the preinstalled Chromium in cloud
# containers (/opt/pw-browsers); elsewhere, Playwright's own (`playwright-cli install-browser`).
set -euo pipefail
branch=${1:?usage: open.sh <branch> <url>}; url=${2:?usage: open.sh <branch> <url>}
out=${DELPHI_ROOT:?unset: start the session at the workspace root}/pictures/$branch/verify-graph/playwright-cli
mkdir -p "$out"
launch=; [ -x /opt/pw-browsers/chromium ] && launch=',"launchOptions":{"executablePath":"/opt/pw-browsers/chromium","headless":true}'
printf '{"browser":{"browserName":"chromium"%s},"outputDir":"%s"}\n' "$launch" "$out" >"$out/cli.config.json"
playwright-cli -s="$branch" open --config="$out/cli.config.json" "$url"
