# lib.sh: sourced by dependabot-cleanup's scripts. Sets R (the Argos repo on GitHub), loads the
# workspace layout from $DELPHI_ROOT, and puts each PR's logs in $LOGS/<pr>/.
# shellcheck shell=bash source=/dev/null
. "${DELPHI_ROOT:?unset: start the session at the workspace root, on Delphi 0.2.0+ (pull its ws/ branch), or source <root>/.delphi/paths.sh}/.delphi/paths.sh"
R=Northeastern-Electric-Racing/Argos
LOGS=${TMPDIR:-/tmp} && export LOGS=${LOGS%/}/argos-dependabot
# pr_branch <pr>: the PR's head branch
pr_branch() { gh pr view "$1" -R "$R" --json headRefName -q .headRefName; }
