#!/usr/bin/env bash
# capture.sh <branch> <url> <name> <click|hover> <selector> [<window-ms> [<step-ms> [clock|live]]]: open the page in
# <branch>'s playwright-cli session (opening it if needed), perform the action on the selector, and save a
# screenshot every <step-ms> (default 10) over <window-ms> (default 100) to pictures/<branch>/<name>/NN-<ms>ms.png,
# gitignored. It pauses the page's running animations and steps their time, so the frames are the same on every
# run; with none running it takes screenshots in real time instead. `live` forces real time (for data drawing in,
# which pausing can't freeze); `clock` steps the page's fake clock, for timer or requestAnimationFrame animations.
# SETUP='<selector>;;<selector>' in the environment clicks those first, in order, to reach the trigger (open a
# tree, a menu). Prints how it captured; exits 1 if a click or selector fails.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
usage="usage: capture.sh <branch> <url> <name> <click|hover> <selector> [<window-ms> [<step-ms> [clock|live]]]"
branch=${1:?$usage}; url=${2:?$usage}; name=${3:?$usage}; action=${4:?$usage}; target=${5:?$usage}
window=${6:-100}; step=${7:-10}; mode=${8:-}
root=${DELPHI_ROOT:?unset: start the session at the workspace root}

# the name becomes a folder, so kebab-case only
[[ $name =~ ^[a-z0-9-]+$ ]] || { echo "capture: name must be kebab-case: $name" >&2; exit 1; }
[[ $action == click || $action == hover ]] || { echo "capture: action is click or hover: $action" >&2; exit 1; }
[[ $window =~ ^[0-9]+$ && $step =~ ^[1-9][0-9]*$ && $step -le $window && $((window / step)) -le 500 ]] ||
  { echo "capture: window-ms and step-ms are whole numbers, step at most the window, and at most 500 steps in it" >&2; exit 1; }
[[ -z $mode || $mode == clock || $mode == live ]] || { echo "capture: last argument is clock, live, or nothing: $mode" >&2; exit 1; }

# earlier frames of the same name are replaced; one browser session per branch, opened only if it isn't already
out=$root/pictures/$branch/$name scratch=$root/.playwright-cli/$branch
rm -rf "$out"; mkdir -p "$out" "$scratch"
if ! playwright-cli list | grep -q "^- $branch:"; then
  launch=; [ -x /opt/pw-browsers/chromium ] && launch=',"launchOptions":{"executablePath":"/opt/pw-browsers/chromium","headless":true}'
  printf '{"browser":{"browserName":"chromium"%s},"outputDir":"%s"}\n' "$launch" "$root/pictures/$branch" >"$scratch/cli.config.json"
  playwright-cli -s="$branch" open --config="$scratch/cli.config.json" "$url" >/dev/null
fi

# capture.js with its __ARGS__ filled in as JSON (node, not sed, so quotes in a selector survive)
code=$(node -e '
  const [file, url, out, action, target, windowMs, stepMs, mode, setup] = process.argv.slice(1);
  const args = { url, out, action, target, windowMs: +windowMs, stepMs: +stepMs, mode, setup: setup.split(";;").map((s) => s.trim()).filter(Boolean) };
  process.stdout.write(require("fs").readFileSync(file, "utf8").replace("__ARGS__", () => JSON.stringify(args)));
' "$here/capture.js" "${url%/}" "$out" "$action" "$target" "$window" "$step" "$mode" "${SETUP:-}")

# `|| true`: a failed step must still be reported below, not end the script here
raw=$(playwright-cli -s="$branch" --raw run-code "$code" 2>&1 || true)
result=$(node -e '
  const s = process.argv[1];
  try { process.stdout.write(JSON.parse(s)); } catch { process.stdout.write("FAIL " + (s.replace(/^### Error\n/, "") || "no output from playwright-cli")); }
' "$raw")
echo "$result"
if grep -q '^FAIL' <<<"$result"; then exit 1; fi
