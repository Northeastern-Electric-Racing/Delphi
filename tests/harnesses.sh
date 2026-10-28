#!/usr/bin/env bash
# Focused translation regressions; runs without GitHub, a model or changes to the checkout.
set -euo pipefail
src=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL - $*" >&2; exit 1; }
header() { printf '%s\n' '---' 'name: fixture' 'description: Translation fixture.' '---'; }
render() { bash -euo pipefail -c 'source "$1"; harness_file "$2" "$3" "commit open-pr"' _ "$src/ci/harnesses.sh" "$1" "$t/SKILL.md"; }

cat >"$t/body.md" <<'SOURCE'
Read the code repo's CLAUDE.md; follow workspace CLAUDE.md.
Read CLAUDE.md from the repository.
Read the repository's own CLAUDE.md.
Keep `CLAUDE.md` and `grep -n rules CLAUDE.md` literal.
Keep ``printf '`CLAUDE.md`'`` literal; invoke ``/commit``.
Keep src/CLAUDE.md, ./CLAUDE.md, CLAUDE.md.backup and _CLAUDE.md.
Keep /tmp/commit, /tmp/open-pr, /commit.txt and /commit/README.
Keep https://example.invalid/commit and `cat /commit` literal.
Invoke /commit and (/open-pr); then `/commit`.
```sh
grep -n rules CLAUDE.md
cat /commit
```
~~~~sh
cat CLAUDE.md
```
~~~~
Use the pull_request_read tool.
Use slack_send_message if that integration is available.
SOURCE
cat >"$t/expected.md" <<'NATIVE'
Read the code repo's AGENTS.md; follow workspace AGENTS.md.
Read AGENTS.md from the repository.
Read the repository's own AGENTS.md.
Keep `CLAUDE.md` and `grep -n rules CLAUDE.md` literal.
Keep ``printf '`CLAUDE.md`'`` literal; invoke ``$commit``.
Keep src/CLAUDE.md, ./CLAUDE.md, CLAUDE.md.backup and _CLAUDE.md.
Keep /tmp/commit, /tmp/open-pr, /commit.txt and /commit/README.
Keep https://example.invalid/commit and `cat /commit` literal.
Invoke $commit and ($open-pr); then `$commit`.
```sh
grep -n rules CLAUDE.md
cat /commit
```
~~~~sh
cat CLAUDE.md
```
~~~~
Use the PR reader tool.
Use slack_send_message if that integration is available.
NATIVE
{ header; cat "$t/body.md"; } >"$t/SKILL.md"
render codex >"$t/native.md"
tail -n "$(wc -l <"$t/body.md")" "$t/native.md" >"$t/actual.md"
cmp -s "$t/expected.md" "$t/actual.md" || fail "literal references or native skill calls changed: $(diff -u "$t/expected.md" "$t/actual.md")"
render claude-code | cmp -s - "$t/SKILL.md" || fail "Claude source bytes changed"
echo 'ok - literal filenames, paths and commands survive; native skill calls and PR-tool wording translate'

while IFS= read -r identifier; do
  { header; printf 'Use %s.\n' "$identifier"; } >"$t/SKILL.md"
  if render codex >"$t/native.md" 2>"$t/errors"; then fail "accepted known Claude identifier: $identifier"; fi
  grep -qF 'missing Claude mapping' "$t/errors" || fail "no mapping diagnostic: $identifier"
  grep -qF '(translated line ' "$t/errors" || fail "misleading source line number: $identifier"
done <<'IDENTIFIERS'
~/.claude/settings.json
$HOME/.claude/CLAUDE.md
${HOME}/.claude/CLAUDE.md
subagent_type=Explore
WebFetch
claude plugin install
ultrathink
IDENTIFIERS
{ header; echo 'Use Claude Code and mcp__unmapped__action.'; } >"$t/SKILL.md"
if render codex >"$t/native.md" 2>"$t/errors"; then fail 'accepted unmapped identifiers'; fi
[ "$(grep -c 'missing Claude mapping' "$t/errors")" = 2 ] || fail 'diagnostics omitted a hit on the same line'
number=$(sed -n '1s/.*(translated line \([0-9]*\)).*/\1/p' "$t/errors")
sed -n "${number}p" "$t/native.md" | grep -qF 'Claude Code and mcp__unmapped__action' || fail 'translated line number points at the wrong line'
echo 'ok - known Claude paths and tools fail with every hit and accurate translated-line diagnostics'

# Exercise the real renderer, including owned skills and opt-outs, rather than injecting a catalog.
d=$t/main folder=software/project/workspaces/native
mkdir -p "$d/$folder/.agents/skills/local" "$d/software/project/workspace-inherit/.claude/skills/commit" \
  "$d/software/project/workspace-inherit/.claude/skills/retired"
cp -R "$src/ci" "$d/"
printf 'name: s.project.native\nharness: codex\nopt-out:\n  - .agents/skills/retired\n' >"$d/$folder/workspace.yml"
{ header; echo 'Invoke /commit, /local, /review, /plugin and /retired.'; } >"$d/software/project/workspace-inherit/.claude/skills/commit/SKILL.md"
header >"$d/software/project/workspace-inherit/.claude/skills/retired/SKILL.md"
header >"$d/$folder/.agents/skills/local/SKILL.md"
bash "$d/ci/render.sh" --workspace "$folder" "$d" "$t/before"
mkdir -p "$d/software/elsewhere/workspaces/other/.claude/skills/review" "$d/software/plugins/claude/extra/skills/plugin"
header >"$d/software/elsewhere/workspaces/other/.claude/skills/review/SKILL.md"
header >"$d/software/plugins/claude/extra/skills/plugin/SKILL.md"
bash "$d/ci/render.sh" --workspace "$folder" "$d" "$t/after"
diff -qr "$t/before" "$t/after" >/dev/null || fail 'unrelated skills changed native output'
# shellcheck disable=SC2016 # native skill syntax is literal assertion text
grep -qF 'Invoke $commit, $local, /review, /plugin and /retired.' "$t/after/$folder/.agents/skills/commit/SKILL.md" || fail 'workspace skill catalog omitted available skills or included unrelated/excluded ones'
echo 'ok - workspace rendering scopes names to selected inherited and owned native skills'
