#!/usr/bin/env bash
# tests/e2e.sh: end-to-end test of Delphi's scripts in a throwaway sandbox: a temp dir with a bare
# origin, a stub `gh` on PATH that logs its calls to gh.log (and a stub `claude`), and a copy of this repo's scripts plus
# two workspaces in different org folders. Runs ci/sync.sh and friends as CI and people would.
# Never touches GitHub or this checkout's origin. Run: bash tests/e2e.sh
set -euo pipefail
src=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d)
real_path=$PATH real_home=$HOME # the real claude, for the delphi mod's own tests (section 12c)
trap 'rm -rf "$t"' EXIT
export HOME=$t GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=tester GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=tester GIT_COMMITTER_EMAIL=t@example.com
git config --global init.defaultBranch main
git config --global advice.detachedHead false
mkdir "$t/bin"
cat >"$t/bin/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >>"$t/gh.log"
EOF
cat >"$t/bin/claude" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "plugin list --json") cat "$t/plugins.json" 2>/dev/null || echo "[]" ;;
  "plugin marketplace update delphi") echo "claude \$*" >>"$t/claude.log" && [ ! -e "$t/offline" ] ;; # touch offline: no network
  "plugin install "* | "plugin uninstall "*) echo "claude \$*" >>"$t/claude.log" ;;
esac
EOF
chmod +x "$t/bin/gh" "$t/bin/claude"
export PATH=$t/bin:$PATH
touch "$t/gh.log"

pass=0
ok() { echo "ok - $*" && pass=$((pass + 1)); }
fail() { echo "FAIL - $*" >&2 && exit 1; }
A=software/application-software/argos/workspaces/argos-dev
B=software/electrical/workspaces/bms-dev
AN=s.app.argos.argos-dev BN=s.electrical.bms-dev # their names (.delphi/names.sh): software/ is s, application-software/ app
AO=software/application-software/argos/argos-dev # A's old name (before 0.8.0): its folder's path without workspaces/
V=$(awk '/^version:/ { print $2 }' "$src/.delphi/manifest.yml") # the current version; VN, the patch after it, is what the test releases
VN=${V%.*}.$((${V##*.} + 1))

# --- sandbox: seed repo -> bare origin; "ci" is the clone CI runs in, "dev" a person's clone
git init -q "$t/seed"
cp -R "$src/ci" "$src/tools" "$src/templates" "$src/.github" "$src/.delphi" "$src/README.md" "$t/seed/"
mkdir -p "$t/seed/$A" "$t/seed/$B"
cp "$src/software/short-name" "$t/seed/software/" && cp "$src/software/application-software/short-name" "$t/seed/software/application-software/"
cp -R "$src/$A/." "$t/seed/$A/"
cp -R "$src/templates/workspace/." "$t/seed/$B/"
sed -i.bak "s|{{name}}|$BN|" "$t/seed/$B/workspace.yml" && rm "$t/seed/$B/workspace.yml.bak"
FD=software/electrical/firmware/workspace-defaults # project defaults for new workspaces under electrical/firmware
mkdir -p "$t/seed/$FD/.claude/skills/fw"
printf "format: claude-code\n" >"$t/seed/$FD/source.yml"
printf 'harness: claude-code\nrepos:\n  fw: https://example.com/fw.git\n' >"$t/seed/$FD/workspace.yml"
printf '# Firmware for {{name}}\n' >"$t/seed/$FD/CLAUDE.md"
echo "fw skill" >"$t/seed/$FD/.claude/skills/fw/SKILL.md"
set_json() { # <folder> <set> <name>: a minimal plugin set
  mkdir -p "$1/plugins/claude/$2/.claude-plugin" && printf '{\n  "name": "%s"\n}\n' "$3" >"$1/plugins/claude/$2/.claude-plugin/plugin.json"
}
set_json "$t/seed/software/application-software" default app # its scope: its short-name
set_json "$t/seed/software/application-software/argos" default argos # default sets above argos-dev
TS=software/application-software/argos/plugins/claude/testing # an extra set a workspace can list under plugins:
mkdir -p "$t/seed/$TS/.claude-plugin" && printf '{\n  "name": "argos.testing"\n}\n' >"$t/seed/$TS/.claude-plugin/plugin.json"
(cd "$t/seed" && bash ci/render.sh >/dev/null) # the marketplace and each workspace's .claude/settings.json
git -C "$t/seed" add -A && git -C "$t/seed" commit -qm init
git clone -q --bare "$t/seed" "$t/origin.git"
git clone -q "$t/origin.git" "$t/ci"
git clone -q "$t/origin.git" "$t/dev"
sync() { (cd "$t/ci" && ci/sync.sh "$@"); }
o() { git -C "$t/origin.git" "$@"; }
# commit_on <branch> <file> <text>: a person's PR into <branch>, merged (edit on a branch, merge --no-ff)
commit_on() {
  (cd "$t/dev" && git fetch -q && git checkout -q -B "edit" "origin/$1" && printf '%s\n' "$3" >>"$2" &&
    { [ "$1" != main ] || bash ci/render.sh >/dev/null; } && git add -A && git commit -qm "edit $2 on $1" && git checkout -q -B "tmp-$1" "origin/$1" &&
    git merge -q --no-ff --no-edit edit && git push -q origin "HEAD:$1")
}

# --- 1. first sync creates ws branches rooted at the folder, joined to main
sync >"$t/out"
main=$(o rev-parse main)
for w in "$A" "$B"; do
  n=$BN && [ "$w" != "$A" ] || n=$AN
  o diff --quiet "main:$w" "ws/$n" -- ':!.delphi' ':!workspace.generated' || fail "ws/$n root != $w"
  [ "$(o rev-parse "ws/$n:.delphi")" = "$(o rev-parse main:.delphi)" ] || fail "ws/$n lacks main's .delphi/"
  [ "$(o rev-parse "ws/$n^")" = "$main" ] || fail "ws/$n parent is not main"
  [ "$(o log -1 --format=%s "ws/$n")" = "delphi: create ws/$n from $w" ] || fail "ws/$n message"
  o cat-file -e "ws/$n:workspace.yml" || fail "ws/$n lacks workspace.yml"
  o cat-file -e "ws/$n:workspace.generated" || fail "ws/$n lacks staged ownership metadata"
  ! o cat-file -e "main:$w/workspace.generated" 2>/dev/null || fail "main contains branch ownership metadata"
  { ! o cat-file -e "ws/$n:README.md" 2>/dev/null && ! o cat-file -e "ws/$n:ci" 2>/dev/null; } ||
    fail "ws/$n has Delphi root files"
  [ "$(o rev-parse "ws/$n:.github/workflows/delphi.yml")" = "$(o rev-parse main:.github/workflows/delphi.yml)" ] ||
    fail "ws/$n root lacks main's workflow (pushes to ws/$n would trigger nothing)"
done
ok "sync creates ws/<name> rooted at its folder plus main's .delphi/, parent main, no other Delphi root files"
ok "ws/<name> root carries main's CI workflow, so GitHub runs sync on pushes to ws/**"
[ ! -s "$t/gh.log" ] || fail "gh called on creation"
before=$(o for-each-ref --format='%(objectname)' refs/heads)
sync >/dev/null
[ "$before" = "$(o for-each-ref --format='%(objectname)' refs/heads)" ] || fail "second sync changed refs"
ok "sync is a no-op when nothing changed"

# --- 2. an edit merged into ws/$AN becomes propose/$AN and a PR to main
commit_on ws/$AN docs/CONTEXT.md "ws edit one"
sync "$AN" >"$t/out"
o show "propose/$AN:$A/docs/CONTEXT.md" | grep -qx "ws edit one" || fail "propose/$AN lacks the edit"
[ "$(o diff --name-only main propose/$AN)" = "$A/docs/CONTEXT.md" ] || fail "propose diff not just the edit"
grep -q "gh pr create --base main --head propose/$AN --title ws/$AN → main" "$t/gh.log" ||
  fail "no PR created: $(cat "$t/gh.log")"
grep -q -- "- edit docs/CONTEXT.md on ws/$AN (tester)" "$t/gh.log" || fail "PR body lacks ws commit"
{ grep -q -- "--body ## Changes$" "$t/gh.log" && grep -qx "## Checklist" "$t/gh.log"; } || fail "propose PR body doesn't follow the PR template"
grep -q -- "--label by: ai$" "$t/gh.log" || fail "propose PR not labelled by: ai"
ok "ws edit -> propose/$AN with the change under the folder, PR opened with gh"
ok "a propose PR's body follows the PR template, labelled by: ai when opened"
prop=$(o rev-parse propose/$AN)
sleep 1 # a re-built merge commit would get a new timestamp, hence a new id
: >"$t/gh.log"
sync "$AN" >/dev/null
{ [ "$(o rev-parse propose/$AN)" = "$prop" ] && [ ! -s "$t/gh.log" ]; } || fail "unchanged proposal re-pushed"
ok "an unchanged proposal is not re-pushed and its PR not touched"

# --- 3. merging propose/$AN into main, then sync: clean, ws unchanged, nothing to propose
(cd "$t/dev" && git fetch -q && git checkout -q -B main origin/main &&
  git merge -q --no-ff --no-edit origin/propose/$AN && git push -q origin main)
ws=$(o rev-parse ws/$AN)
: >"$t/gh.log"
sync >"$t/out" || fail "sync after merging propose failed"
[ "$(o rev-parse "ws/$AN^{tree}")" = "$(o rev-parse "$ws^{tree}")" ] || fail "ws tree changed"
[ ! -s "$t/gh.log" ] || fail "gh called after propose merged: $(cat "$t/gh.log")"
ok "after the propose PR merges into main, sync is clean and opens no PR"

# --- 4. a main change to another file refreshes into a ws branch with its own edits, then propose
commit_on ws/$AN docs/CONTEXT.md "ws edit two"
commit_on main "$A/CLAUDE.md" "main edit"
commit_on main README.md "root edit"
sync >"$t/out" || fail "sync with non-overlapping edits failed"
o show ws/$AN:CLAUDE.md | grep -qx "main edit" || fail "main edit not in ws"
o show ws/$AN:docs/CONTEXT.md | grep -qx "ws edit two" || fail "ws edit lost"
! o cat-file -e ws/$AN:README.md 2>/dev/null || fail "root file leaked into ws"
[ "$(o diff --name-only main propose/$AN)" = "$A/docs/CONTEXT.md" ] || fail "propose diff wrong after refresh"
ok "main-side edit refreshes cleanly alongside ws edits; propose carries only the ws edit"
o diff --quiet "main:$B" ws/$BN -- ":!.delphi" ":!workspace.generated" || fail "bms-dev drifted"
ok "unrelated main changes leave other ws branches' trees alone"

# --- 4b. .delphi/ lives only at main's root: refresh syncs it onto every ws/*, propose never carries it
(cd "$t/dev" && git fetch -q && git checkout -q -B release origin/main && echo "# main edit" >>.delphi/new-worktree.sh &&
  sed -i.bak "s/^version: .*/version: $VN/" .delphi/manifest.yml && rm .delphi/manifest.yml.bak &&
  echo "$(bash .delphi/version.sh) a main edit" >>.delphi/versions && git commit -qam "release $VN" &&
  ci/check.sh . origin/main >/dev/null && git push -q origin HEAD:main) || fail "releasing $VN failed"
sync >"$t/out" 2>&1 || fail "sync after a .delphi/ change failed: $(cat "$t/out")"
for n in "$AN" "$BN"; do
  [ "$(o rev-parse "ws/$n:.delphi")" = "$(o rev-parse main:.delphi)" ] || fail "ws/$n .delphi/ not synced from main"
done
[ "$(o log -1 --format=%s ws/$AN)" = "delphi: sync .delphi/ from main" ] || fail "no sync commit on ws/$AN"
ok "a main change to .delphi/, released as a new version, reaches every ws/* branch on refresh"
commit_on ws/$AN .delphi/setup.sh "# ws edit"
sync "$AN" >"$t/out" 2>&1 || fail "sync after a ws .delphi/ edit failed: $(cat "$t/out")"
[ "$(o rev-parse ws/$AN:.delphi)" = "$(o rev-parse main:.delphi)" ] || fail "ws edit to .delphi/ not reset"
[ "$(o diff --name-only main propose/$AN)" = "$A/docs/CONTEXT.md" ] || fail "propose carries .delphi/: $(o diff --name-only main propose/$AN)"
ok "a ws/* edit to .delphi/ is reset by refresh and never proposed into the folder"

# --- 4c. native settings are reviewed on main; branch edits are rendered in a main-side proposal
for p in app argos; do
  o show "main:$A/.claude/settings.json" | grep -q "\"$p@delphi\": true" || fail "main lacks the $p default set"
done
[ "$(o rev-parse "main:$A/.claude/settings.json")" = "$(o rev-parse "ws/$AN:.claude/settings.json")" ] || fail "settings differ from main"
# shellcheck disable=SC2016 # the hook expands them
o show "ws/$BN:.claude/settings.json" | grep -qF '"command": "bash \"$CLAUDE_PROJECT_DIR/.delphi/paths.sh\" >> \"$CLAUDE_ENV_FILE\""' || fail "SessionStart hook missing"
ok "native settings already exist on main and refresh copies them unchanged"
commit_on ws/$AN workspace.yml "$(printf 'plugins:\n  - argos.testing')"
sync "$AN" >"$t/out" 2>&1 || fail "main-side plugin proposal failed: $(cat "$t/out")"
! o show "ws/$AN:.claude/settings.json" | grep -q argos.testing || fail "refresh generated settings on the workspace branch"
o show "propose/$AN:$A/.claude/settings.json" | grep -q argos.testing || fail "main proposal lacks generated settings"
ok "workspace configuration changes generate native settings in the main-side proposal, then wait for merge"
commit_on ws/$AN .claude/settings.json "hand edit"
sync "$AN" >"$t/out" 2>&1 || fail "settings reset failed: $(cat "$t/out")"
[ "$(o rev-parse "main:$A/.claude/settings.json")" = "$(o rev-parse "ws/$AN:.claude/settings.json")" ] || fail "hand edit kept"
ok "refresh resets managed native settings to main's current plugin configuration"
commit_on ws/$AN workspace.yml "  - argos.nope"
if sync "$AN" >"$t/out" 2>"$t/err"; then fail "unknown plugin set accepted"; fi
grep -q "lists argos.nope, which isn't a plugin set" "$t/err" || fail "unknown set not reported: $(cat "$t/err")"
(cd "$t/dev" && git fetch -q && git checkout -q -B fix origin/ws/$AN && sed -i.bak '/nope/d' workspace.yml && rm workspace.yml.bak &&
  git commit -qam "drop unknown set" && git push -q origin HEAD:ws/$AN)
sync "$AN" >/dev/null 2>&1 || fail "sync after dropping unknown set failed"
ok "a failed main-side render prevents publication of the proposal"

# --- 4d. inherited copies exist only on workspace branches; opt-outs transfer ownership
on_main() { # <message> <command...>: a change on main, pushed
  local m=$1 && shift
  (cd "$t/dev" && git fetch -q && git checkout -q -B tmp-main origin/main && "$@" && bash ci/render.sh >/dev/null && git add -A && git commit -qm "$m" && git push -q origin HEAD:main)
}
TI=software/workspace-inherit/.claude/skills/top AI=software/application-software/workspace-inherit/notes
on_main "inherit" sh -c "mkdir -p $TI $AI && echo 'top v1' >$TI/SKILL.md && echo 'app v1' >$AI/app.md && printf 'format: claude-code\\n' >software/application-software/workspace-inherit/source.yml"
sync >"$t/out" 2>&1 || fail "sync after adding workspace-inherit/ failed: $(cat "$t/out")"
for n in "$AN" "$BN"; do o show "ws/$n:.claude/skills/top/SKILL.md" | grep -qx "top v1" || fail "ws/$n lacks software/workspace-inherit/"; done
o show "ws/$AN:notes/app.md" | grep -qx "app v1" || fail "ws/$AN lacks application-software/workspace-inherit/"
! o cat-file -e "ws/$BN:notes/app.md" 2>/dev/null || fail "ws/$BN inherited from a folder it isn't under"
! o cat-file -e "main:$A/.claude/skills/top/SKILL.md" 2>/dev/null || fail "main contains inherited output"
! o cat-file -e "propose/$AN:$A/.claude/skills/top/SKILL.md" 2>/dev/null || fail "proposal contains inherited output"
! o cat-file -e "propose/$AN:$A/workspace.generated" 2>/dev/null || fail "proposal contains branch ownership metadata"
ok "canonical sources stay on main while applicable native inheritance and ledgers exist only on workspace branches"
commit_on ws/$AN .claude/skills/top/SKILL.md "ws edit"
sync "$AN" >"$t/out" 2>&1 || fail "sync after a ws edit to an inherited file failed: $(cat "$t/out")"
[ "$(o show "ws/$AN:.claude/skills/top/SKILL.md")" = "top v1" ] || fail "ws edit to an inherited file not reset"
! o cat-file -e "propose/$AN:$A/.claude/skills/top/SKILL.md" 2>/dev/null || fail "ws edit to managed output proposed"
on_main "inherit v2, drop app.md" sh -c "echo 'top v2' >$TI/SKILL.md && git rm -q $AI/app.md"
sync >"$t/out" 2>&1 || fail "sync after changing workspace-inherit/ failed: $(cat "$t/out")"
o show "ws/$AN:.claude/skills/top/SKILL.md" | grep -qx "top v2" || fail "inherited change not refreshed"
! o cat-file -e "ws/$AN:notes/app.md" 2>/dev/null || fail "a file no longer inherited stayed on ws/$AN"
ok "a ws edit to an inherited file is reset and never proposed; main's changes and removals reach ws/<name>"
commit_on ws/$BN workspace.yml "$(printf 'opt-out:\n  - .claude/skills/top')"
commit_on ws/$BN .claude/skills/top/SKILL.md "bms own"
on_main "inherit v3" sh -c "echo 'top v3' >$TI/SKILL.md"
sync >"$t/out" 2>&1 || fail "sync after an opt-out failed: $(cat "$t/out")"
[ "$(o show "ws/$BN:.claude/skills/top/SKILL.md")" = "$(printf 'top v2\nbms own')" ] || fail "opted-out file overwritten: $(o show "ws/$BN:.claude/skills/top/SKILL.md")"
o show "propose/$BN:$B/.claude/skills/top/SKILL.md" | grep -qx "bms own" || fail "opted-out copy not proposed as the workspace's own"
o show "ws/$AN:.claude/skills/top/SKILL.md" | grep -qx "top v3" || fail "argos-dev lost the inherited file"
ok "a workspace that lists a path under opt-out: keeps and proposes its own copy, and refresh leaves it alone"

on_main "inherited file fixture" sh -c "mkdir -p $AI && echo before >$AI/layout"
sync refresh "$AN" >/dev/null
on_main "replace inherited file with directory" sh -c "rm $AI/layout && mkdir $AI/layout && echo after >$AI/layout/guide.md"
sync refresh "$AN" >"$t/out" 2>&1 || fail "managed file-to-directory refresh: $(cat "$t/out")"
! o cat-file -e "main:$A/notes/layout/guide.md" 2>/dev/null || fail "main contains native nested output"
o show "ws/$AN:notes/layout/guide.md" | grep -qx after || fail "refresh lost nested output"
ok "native managed paths can change from files to directories without creating sparse-index entries"
on_main "replace inherited directory with file" sh -c "rm -r $AI/layout && echo final >$AI/layout"
sync "$AN" >"$t/out" 2>&1 || fail "managed directory-to-file round trip: $(cat "$t/out")"
o show "ws/$AN:notes/layout" | grep -qx final || fail "refresh lost replacement file"
ok "native managed paths can change back from directories to files in refresh and propose"

# Ancestor files and owned directory siblings must be reported before any index writes.
NI=software/workspace-inherit/docs
commit_on "ws/$AN" docs/blocked "owned ancestor"
on_main "inherited descendant collision" sh -c "mkdir -p $NI/blocked && echo shared >$NI/blocked/guide.md"
owned_head=$(o rev-parse "ws/$AN")
for direction in refresh propose; do
  if sync "$direction" >"$t/out" 2>"$t/err"; then fail "$direction replaced an owned ancestor"; fi
  grep -q 'workspace-owned docs/blocked collides' "$t/err" || fail "$direction did not report the owned ancestor"
  [ "$(o rev-parse "ws/$AN")" = "$owned_head" ] || fail "$direction changed the owned ancestor"
done
o show "ws/$BN:docs/blocked/guide.md" | grep -qx shared || fail "ancestor collision blocked another workspace"
(cd "$t/dev" && git fetch -q && git checkout -q -B accept-descendant "origin/ws/$AN" &&
  git rm -q docs/blocked && git commit -qm "accept managed descendant" && git push -q origin "HEAD:ws/$AN")
sync refresh "$AN" >/dev/null
commit_on "ws/$AN" docs/blocked/own.md "owned sibling"
on_main "replace inherited directory around an owned sibling" sh -c "rm -r $NI/blocked && echo replacement >$NI/blocked"
owned_head=$(o rev-parse "ws/$AN")
for direction in refresh propose; do
  if sync "$direction" "$AN" >"$t/out" 2>"$t/err"; then fail "$direction replaced an owned sibling"; fi
  grep -q 'workspace-owned docs/blocked/own.md collides' "$t/err" || fail "$direction did not report the owned sibling"
  [ "$(o rev-parse "ws/$AN")" = "$owned_head" ] || fail "$direction changed the owned sibling"
done
o show "ws/$AN:docs/blocked/own.md" | grep -qx 'owned sibling' || fail "owned sibling was lost"
(cd "$t/dev" && git fetch -q && git checkout -q -B accept-replacement "origin/ws/$AN" &&
  git rm -q docs/blocked/own.md && git commit -qm "accept managed replacement" && git push -q origin "HEAD:ws/$AN")
sync refresh "$AN" >/dev/null
ok "owned ancestors and directory siblings conflict explicitly while other workspaces keep refreshing"

# New inheritance must not replace a file owned only on the workspace branch.
commit_on "ws/$AN" notes/collision.txt "workspace-owned"
on_main "new inherited collision" sh -c "echo shared >$AI/collision.txt"
owned_head=$(o rev-parse "ws/$AN") proposal_head=$(o rev-parse "propose/$AN")
for direction in refresh propose; do
  if sync "$direction" "$AN" >"$t/out" 2>"$t/err"; then fail "$direction replaced an owned collision"; fi
  grep -q 'workspace-owned notes/collision.txt collides' "$t/err" || fail "$direction did not report ownership"
  [ "$(o rev-parse "ws/$AN")" = "$owned_head" ] || fail "$direction changed the workspace branch"
  [ "$(o rev-parse "propose/$AN")" = "$proposal_head" ] || fail "$direction published the collision"
done
o show "ws/$AN:notes/collision.txt" | grep -qx workspace-owned || fail "owned content was lost"
ok "refresh and propose report new inherited collisions without changing workspace-owned content"
(cd "$t/dev" && git fetch -q && git checkout -q -B accept-inheritance "origin/ws/$AN" &&
  git rm -q notes/collision.txt && git commit -qm "accept shared note" && git push -q origin "HEAD:ws/$AN")
sync refresh "$AN" >/dev/null


# Source retirement must preserve ownership claimed on a workspace branch before its proposal merges.
on_main "unmerged ownership fixture" sh -c 'mkdir -p software/workspace-inherit/.claude/skills/unmerged; echo shared >software/workspace-inherit/.claude/skills/unmerged/SKILL.md'
sync refresh "$BN" >/dev/null
commit_on "ws/$BN" workspace.yml "  - .claude/skills/unmerged"
commit_on "ws/$BN" .claude/skills/unmerged/SKILL.md "workspace-owned unmerged"
sync refresh "$BN" >/dev/null
on_main "retire unmerged source" git rm -rq software/workspace-inherit/.claude/skills/unmerged
sync refresh "$BN" >"$t/out" 2>&1 || fail "retiring an unmerged opt-out conflicted: $(cat "$t/out")"
(cd "$t/dev" && git fetch -q && git checkout -q -B retire-owned "origin/ws/$BN" &&
  sed -i.bak '\|^  - .claude/skills/unmerged$|d' workspace.yml && rm workspace.yml.bak &&
  git commit -qam "drop obsolete opt-out" && git push -q origin "HEAD:ws/$BN")
sync "$BN" >"$t/out" 2>&1 || fail "unmerged owned copy proposal: $(cat "$t/out")"
o show "ws/$BN:.claude/skills/unmerged/SKILL.md" | grep -qx 'workspace-owned unmerged' || fail "unmerged ownership was deleted"
o show "propose/$BN:$B/.claude/skills/unmerged/SKILL.md" | grep -qx 'workspace-owned unmerged' || fail "unmerged ownership not proposed"
ok "retiring a source and obsolete opt-out preserves workspace ownership before its proposal merges"

# Retirement compares against reviewed provenance, even if the branch edits its ledger hash.
RI=software/workspace-inherit/.claude/skills/retire-safety
on_main "retirement safety fixture" sh -c "mkdir -p $RI && echo shared >$RI/SKILL.md"
sync refresh >/dev/null
(cd "$t/dev" && git fetch -q && git checkout -q -B edited-retirement "origin/ws/$AN" &&
  echo owned >>.claude/skills/retire-safety/SKILL.md &&
  blob=$(git hash-object .claude/skills/retire-safety/SKILL.md) &&
  awk -F'\t' -v OFS='\t' -v blob="$blob" '$2 == ".claude/skills/retire-safety/SKILL.md" { $1 = "100644 " blob } { print }' workspace.generated >ledger.tmp &&
  mv ledger.tmp workspace.generated && git add -A && git commit -qm "edit retired payload and ledger hash" && git push -q origin "HEAD:ws/$AN")
on_main "retire safety source" git rm -rq "$RI"
owned_head=$(o rev-parse "ws/$AN")
for direction in refresh propose; do
  if sync "$direction" >"$t/out" 2>"$t/err"; then fail "$direction deleted edited retired output"; fi
  grep -q 'retired managed .claude/skills/retire-safety/SKILL.md has local edits' "$t/err" || fail "$direction did not report retired edits"
  [ "$(o rev-parse "ws/$AN")" = "$owned_head" ] || fail "$direction changed edited retired output"
done
o show "ws/$AN:.claude/skills/retire-safety/SKILL.md" | grep -qx owned || fail "edited retired payload was lost"
! o cat-file -e "ws/$BN:.claude/skills/retire-safety/SKILL.md" 2>/dev/null || fail "retirement failure blocked another workspace"
(cd "$t/dev" && git fetch -q && git checkout -q -B accept-retirement "origin/ws/$AN" &&
  git rm -q .claude/skills/retire-safety/SKILL.md && git commit -qm "accept retirement" && git push -q origin "HEAD:ws/$AN")
sync refresh "$AN" >/dev/null
ok "retired edits refuse refresh and propose against trusted hashes while other workspaces continue"

RI=software/workspace-inherit/.claude/skills/retire-mode
on_main "retirement mode fixture" sh -c "mkdir -p $RI && echo shared >$RI/SKILL.md && chmod +x $RI/SKILL.md"
sync refresh "$AN" >/dev/null
(cd "$t/dev" && git fetch -q && git checkout -q -B edited-retirement-mode "origin/ws/$AN" &&
  chmod -x .claude/skills/retire-mode/SKILL.md && git commit -qam "edit retired executable mode" && git push -q origin "HEAD:ws/$AN")
on_main "retire mode source" git rm -rq "$RI"
owned_head=$(o rev-parse "ws/$AN")
for direction in refresh propose; do
  if sync "$direction" "$AN" >"$t/out" 2>"$t/err"; then fail "$direction deleted a mode-edited retired file"; fi
  grep -q 'retired managed .claude/skills/retire-mode/SKILL.md has local edits' "$t/err" || fail "$direction did not report retired mode edit"
  [ "$(o rev-parse "ws/$AN")" = "$owned_head" ] || fail "$direction changed a mode-edited retired file"
done
[ "$(o ls-tree "ws/$AN" .claude/skills/retire-mode/SKILL.md | cut -d' ' -f1)" = 100644 ] || fail "retired local mode was lost"
(cd "$t/dev" && git fetch -q && git checkout -q -B accept-mode-retirement "origin/ws/$AN" &&
  git rm -q .claude/skills/retire-mode/SKILL.md && git commit -qm "accept mode retirement" && git push -q origin "HEAD:ws/$AN")
sync refresh "$AN" >/dev/null
ok "branch retirement preserves executable-mode-only edits in both refresh and propose"

RI=software/workspace-inherit/.claude/skills/retire-optout
on_main "unsynced opt-out fixture" sh -c "mkdir -p $RI && echo shared >$RI/SKILL.md"
sync refresh "$BN" >/dev/null
commit_on "ws/$BN" workspace.yml "  - .claude/skills/retire-optout"
commit_on "ws/$BN" .claude/skills/retire-optout/SKILL.md "owned before sync"
on_main "retire unsynced opt-out source" git rm -rq "$RI"
(cd "$t/dev" && git fetch -q && git checkout -q -B obsolete-optout "origin/ws/$BN" &&
  sed -i.bak '\|^  - .claude/skills/retire-optout$|d' workspace.yml && rm workspace.yml.bak &&
  git commit -qam "drop obsolete opt-out before syncing" && git push -q origin "HEAD:ws/$BN")
owned_head=$(o rev-parse "ws/$BN")
if sync refresh "$BN" >"$t/out" 2>"$t/err"; then fail "retirement deleted unsynced ownership"; fi
[ "$(o rev-parse "ws/$BN")" = "$owned_head" ] || fail "unsynced owned output changed"
o show "ws/$BN:.claude/skills/retire-optout/SKILL.md" | grep -qx 'owned before sync' || fail "unsynced ownership was lost"
(cd "$t/dev" && git fetch -q && git checkout -q -B accept-optout-retirement "origin/ws/$BN" &&
  git rm -q .claude/skills/retire-optout/SKILL.md && git commit -qm "accept retirement" && git push -q origin "HEAD:ws/$BN")
sync refresh "$BN" >/dev/null
ok "retirement preserves an opt-out rescinded before any intermediate sync by reporting the ambiguity"

# --- 5. a conflict on bms-dev is reported; argos-dev still syncs; exit 1
commit_on ws/$BN CLAUDE.md "ws side"
commit_on main "$B/CLAUDE.md" "main side"
commit_on main "$A/CLAUDE.md" "main edit two"
bms=$(o rev-parse ws/$BN)
if sync 2>"$t/err" >"$t/out"; then fail "conflicting sync exited 0"; fi
{ grep -q "ws/$BN: CONFLICT" "$t/err" && grep -q "  CLAUDE.md" "$t/err"; } || fail "conflict not reported: $(cat "$t/err")"
[ "$(o rev-parse ws/$BN)" = "$bms" ] || fail "conflicting ws/$BN was changed"
o show ws/$AN:CLAUDE.md | grep -qx "main edit two" || fail "argos-dev not synced"
ok "conflict: reported with files, exit 1, other workspaces still synced"

# resolve as documented: merge main into ws/$BN on a branch, PR into ws/$BN
(cd "$t/dev" && git fetch -q && git checkout -q -B fix origin/ws/$BN &&
  { git merge -q -Xsubtree="$B" origin/main >/dev/null 2>&1 || true; } &&
  git checkout -q --ours CLAUDE.md && git commit -qam "resolve" && git push -q origin HEAD:ws/$BN)
sync >"$t/out" 2>"$t/err" || fail "sync after resolving failed: $(cat "$t/err")"
grep -q "ws/$BN: proposed" "$t/out" || fail "resolved ws not proposed"
ok "conflict resolved by merging main into ws in a PR; sync then succeeds"

# --- 6. removed workspace folder: notice, branch kept
(cd "$t/dev" && git checkout -q -B main origin/main && git rm -rq "$B" && git commit -qm rm && git push -q origin main)
sync >"$t/out"
grep -q "notice: ws/$BN has no workspace folder on main" "$t/out" || fail "no removal notice"
o rev-parse -q --verify ws/$BN >/dev/null || fail "ws/$BN deleted"
ok "removed workspace: notice printed, branch kept"

# --- 7. check.sh: real layout passes; each bad layout fails
"$src/ci/check.sh" "$src" >/dev/null || fail "check fails on the real repo"
ok "check passes on the real repo"
expect_bad() { # <label> <expected message> <setup command...>: copy the real layout, commit it, break it, check fails against that commit
  local d=$t/chk-$1 label=$1 want=$2
  shift 2
  rm -rf "$d" && mkdir "$d" && cp -R "$src/software" "$src/templates" "$src/.github" "$src/.delphi" "$src/.claude-plugin" "$d/"
  (cd "$d" && git init -q && git add -A && git commit -qm base && "$@" && git add -A)
  if "$src/ci/check.sh" "$d" HEAD 2>"$t/err" >/dev/null; then fail "check passed: $label"; fi
  grep -q -- "$want" "$t/err" || fail "check $label: no '$want' in: $(cat "$t/err")"
  ok "check fails: $label ($want)"
}
CX=software/application-software/argos/workspaces/default-codex
expect_bad unknown-harness "unknown harness 'unknown'" sed -i.bak 's/harness: codex/harness: unknown/' "$CX/workspace.yml"
expect_bad codex-plugin "codex does not support Delphi plugin sets" sh -c "printf 'plugins:\n  - delphi\n' >>$CX/workspace.yml"
expect_bad codex-no-instructions "AGENTS.md: required for codex" rm "$CX/AGENTS.md"
expect_bad codex-wrong-native "CLAUDE.md: belongs to a different harness" touch "$CX/CLAUDE.md"
expect_bad codex-inherited-wrong-native "has no mapping to codex" sh -c "mkdir -p software/workspace-inherit/.claude && printf 'format: claude-code\\n' >software/workspace-inherit/source.yml && echo x >software/workspace-inherit/.claude/extra.json"
expect_bad inherited-collision "also inherits it from a folder above" sh -c "mkdir -p software/application-software/workspace-inherit/.claude/skills/journal && echo x >software/application-software/workspace-inherit/.claude/skills/journal/SKILL.md"
expect_bad main-inherited-copy "workspace-owned file collides" sh -c "mkdir -p $CX/.agents/skills/journal && cp software/workspace-inherit/.claude/skills/journal/SKILL.md $CX/.agents/skills/journal/SKILL.md"
expect_bad main-ownership-record "ownership records belong only on workspace branches" touch "$CX/workspace.generated"
expect_bad unknown-source-format "declare one supported source format" sh -c "echo 'format: unknown' >${A%/workspaces/*}/workspace-defaults/source.yml"
expect_bad mixed-source-formats "AGENTS.md does not belong to the declared claude-code format" touch "${A%/workspaces/*}/workspace-defaults/AGENTS.md"
expect_bad owned-output-collision "workspace-owned file collides" sh -c "mkdir -p software/workspace-inherit/.claude/skills/collision $CX/.agents/skills/collision && echo shared >software/workspace-inherit/.claude/skills/collision/SKILL.md && echo own >$CX/.agents/skills/collision/SKILL.md"

d=$t/chk-owned-output-collision
if "$src/ci/render.sh" "$d" >"$t/out" 2>"$t/err"; then fail "renderer overwrote an owned collision"; fi
[ "$(cat "$d/$CX/.agents/skills/collision/SKILL.md")" = own ] || fail "renderer changed the workspace-owned file"
ok "main-side generation refuses an owned collision and preserves its content"

expect_bad no-harness "harness is missing" sh -c "sed -i.bak 's/^harness:.*//' $A/workspace.yml && rm $A/workspace.yml.bak"
expect_bad duplicate-harness "duplicate harness" sh -c "printf 'harness: x\n' >>$A/workspace.yml"
expect_bad bad-repo "bad repos entry" sh -c "awk '{ print } /^repos:/ { print \"  ../x: y\" }' $A/workspace.yml >$A/y && mv $A/y $A/workspace.yml"
expect_bad bad-reference "bad references-git entry" sh -c "printf 'references-git:\n  x: url ref extra\n' >>$A/workspace.yml"
expect_bad reference-repo-clash "duplicate repo: argos" sh -c "printf 'references-git:\n  argos: https://example.com/a.git\n' >>$A/workspace.yml"
expect_bad bad-key "unexpected line" sh -c "printf 'color: x\n' >>$A/workspace.yml"
expect_bad wrong-name "(.delphi/names.sh)" sh -c "sed -i.bak 's/^name:.*/name: other/' $A/workspace.yml && rm $A/workspace.yml.bak"
expect_bad no-name "name is missing" sh -c "sed -i.bak '/^name:/d' $A/workspace.yml && rm $A/workspace.yml.bak"
expect_bad defaults-name "workspace-defaults/workspace.yml: unexpected line: name:" sh -c "printf 'name: x\n' >>${A%/workspaces/*}/workspace-defaults/workspace.yml"
expect_bad park-path "bad park entry" sh -c "printf 'park:\n  - a/b\n' >>$A/workspace.yml"
expect_bad park-git "bad park entry" sh -c "printf 'park:\n  - .git\n' >>$A/workspace.yml"
expect_bad park-duplicate "duplicate park entry: pictures" sh -c "printf 'park:\n  - pictures\n  - pictures\n' >>$A/workspace.yml"
expect_bad folder-delphi "$A/.delphi: managed in the root" sh -c "mkdir $A/.delphi && cp .delphi/park.sh $A/.delphi/"
expect_bad same-name "is named $AN too (names are unique)" sh -c "mkdir -p software/x/argos/workspaces && cp -R $A software/x/argos/workspaces/ && echo app >software/x/short-name"
expect_bad bad-short-name "software/application-software/short-name: want one line of lowercase" sh -c "echo A_pp >software/application-software/short-name"
expect_bad nested "nested inside" sh -c "mkdir -p $A/docs/workspaces/inner && cp $A/workspace.yml $A/docs/workspaces/inner/"
expect_bad bad-name "must be lowercase letters, digits and '-'" sh -c "mkdir -p software/x/workspaces && cp -R $A software/x/workspaces/Bad_Name"
expect_bad symlink "symlinks are not allowed" ln -s ../CLAUDE.md "$A/docs/link.md"
expect_bad settings-hand-edit "$A/.claude/settings.json is generated" sh -c "echo x >>$A/.claude/settings.json"
expect_bad marketplace-stale ".claude-plugin/marketplace.json is generated" sh -c "mkdir -p software/x/plugins/claude/default/.claude-plugin && echo '{}' >software/x/plugins/claude/default/.claude-plugin/plugin.json"
expect_bad scope-clash "two folders both have scope argos" sh -c "$(declare -f set_json); set_json software/x/argos default argos && set_json software/y/argos default argos"
expect_bad bad-scope "scope 'A_pp' must be lowercase" sh -c "$(declare -f set_json); set_json software/application-software default x && echo A_pp >software/application-software/plugins/scope"
expect_bad plugin-json-name "plugin.json: name must be \"argos\"" sh -c "$(declare -f set_json); set_json software/application-software/argos default x"
expect_bad plugins-defaults "workspace.yml doesn't list the default set" sh -c "$(declare -f set_json); set_json software/application-software default app"
expect_bad plugins-unknown "lists argos.nope, which isn't a plugin set" sh -c "printf 'plugins:\n  - argos.nope\n' >>$A/workspace.yml"
expect_bad plugins-entry "bad plugins entry" sh -c "printf 'plugins:\n  - a.b.c\n' >>$A/workspace.yml"
expect_bad plugins-duplicate "duplicate plugin set" sh -c "printf 'plugins:\n  - a.b\n  - a.b\n' >>$A/workspace.yml"
expect_bad root-script-missing ".delphi/switch.sh: listed in .delphi/manifest.yml but missing" rm .delphi/switch.sh
expect_bad unlisted ".delphi/extra.sh: in .delphi/ but not listed" touch .delphi/extra.sh
expect_bad manifest-not-self "must list itself" sed -i.bak '/- .delphi\/manifest.yml/d' .delphi/manifest.yml
expect_bad not-bumped "changed since $V: bump version" sh -c "echo '# x' >>.delphi/setup.sh"
expect_bad bumped-no-line "add \`$VN " sed -i.bak "s/^version: .*/version: $VN/" .delphi/manifest.yml
release() { # <version> [<migration slug>]: bump to <version> (with an empty migration) and add its line, as a release would
  [ -z "${2:-}" ] || printf '#!/usr/bin/env bash\nset -euo pipefail\n' >".delphi/migrations/$1-$2.sh"
  sed -i.bak "s/^version: .*/version: $1/" .delphi/manifest.yml && rm .delphi/manifest.yml.bak && git add -A &&
    echo "$(bash .delphi/version.sh) release $1" >>.delphi/versions
}
expect_bad migration-patch "$VN has a migration, so it must bump $([ "${V%%.*}" = 0 ] && echo MINOR || echo MAJOR)" release "$VN" x
expect_bad version-down "0.0.9 is not above $V" release 0.0.9
expect_bad migration-no-line "no line for migrations/9.0.0" sh -c "printf '#!/usr/bin/env bash\nset -euo pipefail\n' >.delphi/migrations/9.0.0-x.sh"
expect_bad migration-name "name it <MAJOR.MINOR.PATCH>-<slug>.sh" touch .delphi/migrations/x.sh
expect_bad migration-header "start it with" sh -c "echo 'echo hi' >.delphi/migrations/$V-x.sh"
expect_bad history-rewritten "only add lines" sed -i.bak 's/linked/LINKED/' .delphi/versions
expect_bad released-migration-changed "add a new version's migration instead" sh -c "echo '# x' >>.delphi/migrations/0.0.1-linked-worktrees-to-clones.sh"
expect_bad workflow-drift "argos-dev/.github/workflows/delphi.yml: differs" sh -c "echo x >>$A/.github/workflows/delphi.yml"
expect_bad defaults-manifest "workspace-defaults/workspace.yml: unexpected line" sh -c "printf 'x: y\n' >>${A%/workspaces/*}/workspace-defaults/workspace.yml"
expect_bad defaults-named-workspace "workspace-defaults/.delphi: managed" sh -c "mkdir -p software/x/workspaces/workspace-defaults/.delphi && cp -R $A/. software/x/workspaces/workspace-defaults/"
expect_bad old-defaults "defaults: renamed workspace-defaults/" mkdir -p "${A%/workspaces/*}/defaults"
expect_bad inherited-file-kept "workspace-owned file collides" sh -c "mkdir -p $A/.claude/skills/journal && echo x >$A/.claude/skills/journal/SKILL.md"
d=$t/chk-inherited-file-kept
if "$src/ci/render.sh" "$d" >"$t/out" 2>"$t/err"; then fail "renderer overwrote main-owned output"; fi
[ "$(cat "$d/$A/.claude/skills/journal/SKILL.md")" = x ] || fail "main-owned output changed"
ok "main rejects inherited copies and preserves conflicting owned content"

expect_bad managed-file-to-owned-directory 'workspace-owned file collides' sh -c "mkdir -p $A/.claude/skills/journal/SKILL.md && echo owned >$A/.claude/skills/journal/SKILL.md/own"
d=$t/chk-managed-file-to-owned-directory
if "$src/ci/render.sh" "$d" >"$t/out" 2>"$t/err"; then fail "renderer wrote managed output into an owned directory"; fi
[ "$(cat "$d/$A/.claude/skills/journal/SKILL.md/own")" = owned ] || fail "owned directory contents changed"
[ -n "$(find "$d/$A/.claude/skills/journal/SKILL.md" -prune -perm -100)" ] || fail "owned directory traversal mode changed"
ok "staging refuses an inherited destination occupied by an owned directory without chmod or copy"

expect_bad topology-empty-directory 'workspace-owned file collides' sh -c "mkdir -p $A/.claude/skills/journal/empty && rm -r software/workspace-inherit/.claude/skills/journal && echo replacement >software/workspace-inherit/.claude/skills/journal"
d=$t/chk-topology-empty-directory
if "$src/ci/render.sh" "$d" >"$t/out" 2>"$t/err"; then fail "renderer replaced an untracked empty directory"; fi
[ -d "$d/$A/.claude/skills/journal/empty" ] || fail "untracked empty directory was removed"
ok "staging preserves untracked empty directories at inherited destinations"

expect_bad render-symlink 'symlinks are not allowed' sh -c "mkdir -p $A/.claude/skills/journal && cp software/workspace-inherit/.claude/skills/journal/SKILL.md outside-symlink-target && ln -s ../../../../../../../../outside-symlink-target $A/.claude/skills/journal/SKILL.md && echo changed >>software/workspace-inherit/.claude/skills/journal/SKILL.md"
d=$t/chk-render-symlink
cp "$d/outside-symlink-target" "$t/symlink-target-before"
if "$src/ci/render.sh" "$d" >"$t/out" 2>"$t/err"; then fail "renderer followed a symlink"; fi
cmp -s "$d/outside-symlink-target" "$t/symlink-target-before" || fail "renderer changed a symlink target"
ok "render refuses symlinks before changing any generated output"

d=$t/staging
mkdir "$d"
cp -R "$src/ci" "$src/software" "$src/templates" "$src/.github" "$src/.delphi" "$src/.claude-plugin" "$d/"
(cd "$d" && git init -q && chmod +x software/workspace-inherit/.claude/skills/journal/scripts/capture.sh &&
  echo changed >>software/workspace-inherit/.claude/skills/journal/SKILL.md && git add -A && git commit -qm source-change &&
  bash ci/check.sh . && bash ci/render.sh --check . "$t/staged-native" &&
  bash ci/render.sh . "$t/staged-native-again" && [ -z "$(git status --porcelain)" ]) >"$t/out" 2>"$t/err" || fail "read-only staging: $(cat "$t/err")"
diff -qr "$t/staged-native" "$t/staged-native-again" >/dev/null || fail "repeated staging changed native output"
for folder in "$A" "$CX"; do
  [ -f "$t/staged-native/$folder/workspace.generated" ] || fail "staging lacks ownership metadata"
  [ ! -e "$d/$folder/workspace.generated" ] || fail "staging wrote a ledger to main"
done
[ ! -e "$d/$CX/.agents/skills/journal/SKILL.md" ] || fail "staging wrote inherited skills to main"
while IFS=$'\t' read -r meta path _; do
  case "$meta" in '' | '#'* ) continue ;; esac
  [ "$(git -C "$d" hash-object -- "$t/staged-native/$CX/$path")" = "${meta#* }" ] || fail "staged ledger hash differs from native bytes"
  if [ "${meta%% *}" = 100755 ]; then [ -x "$t/staged-native/$CX/$path" ] || fail "staged executable mode lost"; fi
done <"$t/staged-native/$CX/workspace.generated"
[ -x "$t/staged-native/$CX/.agents/skills/journal/scripts/capture.sh" ] || fail "staged helper lost executable mode"
ok "source edits validate without main copies; staged native hashes, modes and repeat output are stable and leave main unchanged"
echo stale-marker >>"$d/$A/.claude/settings.json"
"$d/ci/render.sh" --workspace "$CX" "$d" "$t/staged-one" >"$t/out" 2>"$t/err" || fail "workspace-only staging: $(cat "$t/err")"
grep -q stale-marker "$d/$A/.claude/settings.json" || fail "workspace-only staging rewrote global plugin output"
[ -f "$t/staged-one/$CX/workspace.generated" ] && [ ! -e "$t/staged-one/$A" ] || fail "workspace-only staging included another workspace"
if "$d/ci/render.sh" --workspace "$CX" "$d" >"$t/out" 2>"$t/err"; then fail "workspace-only staging accepted no output directory"; fi
if "$d/ci/render.sh" "$d" "$d/staging" >"$t/out" 2>"$t/err"; then fail "staging output inside main was accepted"; fi
ok "workspace-only staging requires an external output directory and skips global plugin generation"
git -C "$d" checkout -q -- "$A/.claude/settings.json"
mkdir "$t/staged-symlink"
ln -s "$d/software" "$t/staged-symlink/software"
owned_instruction=$(git -C "$d" hash-object "$CX/AGENTS.md")
if "$d/ci/render.sh" --workspace "$CX" "$d" "$t/staged-symlink" >"$t/out" 2>"$t/err"; then fail "staging followed an output symlink into main"; fi
grep -q 'symlink' "$t/err" || fail "unsafe staging symlink was not reported"
[ "$(git -C "$d" hash-object "$CX/AGENTS.md")" = "$owned_instruction" ] || fail "staging output symlink changed main-owned instructions"
[ -z "$(git -C "$d" status --porcelain)" ] || fail "refused staging output changed main"
ok "staging refuses output symlinks before touching main-owned workspace data"

expect_bad inherited-twice "also inherits it from a folder above" sh -c "mkdir -p software/application-software/workspace-inherit/.claude/skills/journal && printf 'format: claude-code\\n' >software/application-software/workspace-inherit/source.yml && echo x >software/application-software/workspace-inherit/.claude/skills/journal/SKILL.md"
expect_bad inherited-claude-md "software/workspace-inherit/CLAUDE.md: each workspace has its own" sh -c "mkdir -p software/workspace-inherit && printf 'format: claude-code\\n' >software/workspace-inherit/source.yml && echo x >software/workspace-inherit/CLAUDE.md"
expect_bad inherit-in-workspace "belongs in an org or project folder" sh -c "mkdir -p $A/workspace-inherit && echo x >$A/workspace-inherit/f"
expect_bad bad-opt-out "bad opt-out entry" sh -c "printf 'opt-out:\n  - ../x\n' >>$A/workspace.yml"
expect_bad opt-out-nothing "opt-out: nope is nothing it inherits" sh -c "printf 'opt-out:\n  - nope\n' >>$A/workspace.yml"
d=$t/chk-opt-out && rm -rf "$d" && mkdir "$d" && cp -R "$src/software" "$src/templates" "$src/.github" "$src/.delphi" "$src/.claude-plugin" "$d/"
(cd "$d" && git init -q && mkdir -p $A/.claude/skills/journal && echo x >$A/.claude/skills/journal/SKILL.md &&
  printf 'opt-out:\n  - .claude/skills/journal/\n' >>$A/workspace.yml && git add -A && git commit -qm base)
"$src/ci/render.sh" "$d" >/dev/null 2>&1 || fail "opt-out rendering failed"
"$src/ci/check.sh" "$d" >/dev/null 2>&1 || fail "check fails on a workspace keeping an inherited path it opts out of"
ok "a workspace may keep its own copy of an inherited path it lists under opt-out:"
expect_bad links-renamed "links: is now workspaces:" sh -c "sed -i.bak 's/^workspaces:/links:/' $A/workspace.yml && rm $A/workspace.yml.bak"
expect_bad bad-workspaces-entry "bad workspaces entry" sh -c "printf '  - ws/argos-dev\n' >>$A/workspace.yml"
expect_bad duplicate-workspace "duplicate workspace: main" sh -c "printf '  - main\n' >>$A/workspace.yml"
expect_bad lists-itself "lists itself: $AN" sh -c "printf '  - $AN\n' >>$A/workspace.yml"
expect_bad unknown-workspace "lists nope, which isn't a workspace on main" sh -c "printf '  - nope\n' >>$A/workspace.yml"
expect_bad template-delphi "templates/workspace/.delphi: scripts live only" mkdir templates/workspace/.delphi
expect_bad template-workflow-drift "differs from .github/workflows/delphi.yml" sh -c "echo x >>.github/workflows/delphi.yml"

# --- 8. setup.sh clones workspace.yml repos at repos/<repo>; separately, a bare store and the default branch under worktrees/; idempotent
for r in lib1 lib2; do
  git init -q "$t/$r" && git -C "$t/$r" commit -q --allow-empty -m "$r" && git clone -q --bare "$t/$r" "$t/$r.git"
done
def=$(git -C "$t/lib1" branch --show-current)
git clone -q -b ws/$AN "$t/origin.git" "$t/ws"
printf 'name: s.app.argos.argos-dev\nharness: claude-code\nplugins:\n  - x.y\npark:\n  - pictures  # screenshots\n  - .playwright-mcp\nrepos:\n  # a comment\n  lib1: %s  # trailing\n  lib2: %s\n' \
  "$t/lib1.git" "$t/lib2.git" >"$t/ws/workspace.yml"
/bin/bash "$t/ws/.delphi/setup.sh" >/dev/null 2>&1 || fail "setup.sh failed"
/bin/bash "$t/ws/.delphi/setup.sh" >"$t/out" 2>&1 || fail "setup.sh re-run failed"
for r in lib1 lib2; do
  [ "$(git -C "$t/ws/repos/$r" rev-parse HEAD)" = "$(git -C "$t/$r" rev-parse HEAD)" ] || fail "repos/$r not cloned"
  [ "$(git -C "$t/ws/repos/$r" branch --show-current)" = "$def" ] || fail "repos/$r not on $def"
  [ "$(git -C "$t/ws/worktrees/$r/$def" branch --show-current)" = "$def" ] || fail "$r default worktree not on $def"
  [ "$(git -C "$t/ws/worktrees/$r/.bare" rev-parse --is-bare-repository)" = true ] || fail "worktrees/$r/.bare not a bare store"
  [ "$(git -C "$t/ws/repos/$r" worktree list | wc -l | tr -d " ")" = 1 ] || fail "repos/$r has worktrees"
done
[ "$(git -C "$t/ws/repos/lib1" rev-parse --is-bare-repository)" = false ] || fail "repos/lib1 is a bare store"
grep -q "repos/lib1: already present" "$t/out" || fail "re-run did not skip"
for d in /repos/ /worktrees/ /.journal/ /.playwright-mcp/ /pictures/ .DS_Store; do [ "$(grep -cx "$d" "$t/ws/.git/info/exclude")" = 1 ] || fail "$d not excluded exactly once"; done
mkdir -p "$t/ws/.playwright-mcp" "$t/ws/pictures/b" "$t/ws/docs" && touch "$t/ws/.playwright-mcp/p.yml" "$t/ws/pictures/b/s.png" "$t/ws/.DS_Store" "$t/ws/docs/.DS_Store"
[ "$(git -C "$t/ws" status --porcelain)" = " M workspace.yml" ] || fail "repos/, worktrees/ or a tool's files show in status: $(git -C "$t/ws" status --porcelain)"
rm -rf "$t/ws/worktrees/lib2/$def" && git -C "$t/ws/worktrees/lib2/.bare" worktree prune && /bin/bash "$t/ws/.delphi/setup.sh" >/dev/null 2>&1 &&
  [ -d "$t/ws/worktrees/lib2/$def" ] || fail "re-run did not restore a missing default worktree"
ok "setup.sh clones repos: at repos/<repo> and, separately, makes a bare store and the default-branch worktree in worktrees/<repo>/; excludes both (and tools' files) once; idempotent"
w=$t/legacy && git clone -q -b ws/$AN "$t/origin.git" "$w" && cp "$t/ws/workspace.yml" "$w/" &&
  git clone -q "$t/lib1.git" "$w/repos/lib1" && echo wip >"$w/repos/lib1/wip" &&
  git init -q --bare "$w/repos/lib2" && git -C "$w/repos/lib2" remote add origin "$t/lib2.git" && git -C "$w/repos/lib2" fetch -q origin &&
  git -C "$w/repos/lib2" worktree add -q -b "$def" "$w/worktrees/lib2/$def" "origin/$def" && echo wip >"$w/worktrees/lib2/$def/wip"
/bin/bash "$w/.delphi/setup.sh" >"$t/out" 2>&1 || fail "setup.sh failed on older clones: $(cat "$t/out")"
{ [ "$(git -C "$w/repos/lib2" rev-parse --is-bare-repository)" = false ] && [ "$(git -C "$w/worktrees/lib2/$def" status --porcelain)" = "?? wip" ] &&
  [ "$(git -C "$w/worktrees/lib2/.bare" rev-parse --is-bare-repository)" = true ] && [ "$(git -C "$w/repos/lib1" branch --show-current)" = "$def" ] && [ -f "$w/repos/lib1/wip" ] &&
  [ -d "$w/worktrees/lib1/$def" ]; } || fail "an older plain clone in repos/ was not left as it is, or an older bare store was not moved (2.0.0): $(cat "$t/out")"
ok "setup.sh leaves an older plain clone in repos/ as it is; 2.0.0 moves an older bare store there to worktrees/ (worktrees intact)"
git clone -q -c core.autocrlf=true -b ws/$AN "$t/origin.git" "$t/ws-crlf"
cp "$t/ws/workspace.yml" "$t/ws-crlf/"
/bin/bash "$t/ws-crlf/.delphi/setup.sh" >/dev/null 2>"$t/err" || fail "setup.sh fails with core.autocrlf=true"
! grep -q "as released" "$t/err" || fail "core.autocrlf=true changed .delphi/'s version hash"
ok "setup.sh runs in a core.autocrlf=true clone (Git Bash default), thanks to .gitattributes"

# --- 8b. references-git: shallow, detached, push-disabled checkouts under references/, refreshed on re-run
git -C "$t/lib2" tag lib2@v1 && git -C "$t/lib2" commit -q --allow-empty -m "after v1" && git -C "$t/lib2" push -q "$t/lib2.git" --all && git -C "$t/lib2" push -q "$t/lib2.git" --tags
git -C "$t/lib1" commit -q --allow-empty -m "lib1 two" && git -C "$t/lib1" push -q "$t/lib1.git" --all
w=$t/refs && git clone -q -b ws/$AN "$t/origin.git" "$w"
printf 'name: s.app.argos.argos-dev\nharness: claude-code\nreferences-git:\n  lib1: file://%s\n  lib2: file://%s lib2@v1  # pinned, monorepo-style tag\n' "$t/lib1.git" "$t/lib2.git" >"$w/workspace.yml"
/bin/bash "$w/.delphi/setup.sh" >"$t/out" 2>&1 || fail "setup.sh failed with references-git: $(cat "$t/out")"
[ "$(git -C "$w/references/lib1" rev-parse HEAD)" = "$(git -C "$t/lib1" rev-parse HEAD)" ] || fail "lib1 reference not at default branch"
[ "$(git -C "$w/references/lib2" rev-parse HEAD)" = "$(git -C "$t/lib2" rev-parse 'lib2@v1^{commit}')" ] || fail "lib2 reference not at its pin"
[ "$(git -C "$w/references/lib1" rev-list --count HEAD)" = 1 ] || fail "reference is not shallow"
! git -C "$w/references/lib1" symbolic-ref -q HEAD >/dev/null || fail "reference is on a branch"
! git -C "$w/references/lib1" push -q origin HEAD:refs/heads/x 2>/dev/null || fail "push from a reference succeeded"
[ ! -e "$w/repos/lib1" ] && [ ! -e "$w/worktrees/lib1" ] || fail "reference got a repos/ store or worktree"
[ "$(grep -cx /references/ "$w/.git/info/exclude")" = 1 ] || fail "/references/ not excluded exactly once"
! bash "$w/.delphi/new-worktree.sh" lib1 1-x 2>"$t/err" >/dev/null || fail "new-worktree accepted a reference"
grep -q "references are read-only" "$t/err" || fail "new-worktree refusal unexplained: $(cat "$t/err")"
git -C "$t/lib1" commit -q --allow-empty -m "lib1 three" && git -C "$t/lib1" push -q "$t/lib1.git" --all
/bin/bash "$w/.delphi/setup.sh" >/dev/null 2>&1 || fail "setup.sh re-run failed with references-git"
[ "$(git -C "$w/references/lib1" rev-parse HEAD)" = "$(git -C "$t/lib1" rev-parse HEAD)" ] || fail "re-run did not refresh lib1"
[ "$(grep -cx /references/ "$w/.git/info/exclude")" = 1 ] || fail "/references/ excluded twice after re-run"
ok "setup.sh checks out references-git: repos shallow, detached, at their pin, push disabled, refreshed on re-run"
ok "new-worktree.sh refuses a reference repo"

# --- 8c. park.sh: switching to another workspace or main parks repos/, worktrees/, references/, workspaces/ in the
# git-ignored .delphi/parked/ and restores them, same paths, when the workspace comes back; same-workspace branches don't move
w=$t/park && git clone -q -b ws/$AN "$t/origin.git" "$w"
local_ws() { # <branch> <ws branch> <name> <repo>: a local branch of <ws branch> whose workspace.yml lists <repo>
  git -C "$w" checkout -q -b "$1" "origin/$2" && printf 'name: %s\nharness: claude-code\npark:\n  - pictures\nrepos:\n  %s: %s\nreferences-git:\n  %s-ref: file://%s\nworkspaces:\n  - main\n' \
    "$3" "$4" "$t/$4.git" "$4" "$t/$4.git" >"$w/workspace.yml" && git -C "$w" commit -qam "$1" && /bin/bash "$w/.delphi/setup.sh" >/dev/null 2>&1
}
live() { [ "$(git -C "$w/worktrees/$1/$def" branch --show-current 2>/dev/null)" = "$def" ] &&
  ! git -C "$w/worktrees/$1/.bare" worktree list --porcelain | grep -q prunable && git -C "$w/references/$1-ref" rev-parse -q HEAD >/dev/null &&
  [ -f "$w/workspaces/main/ci/sync.sh" ]; }
local_ws a1 "ws/$AN" "$AN" lib1 || fail "park: setup on argos-dev failed"
ours() { [ ! -L "$w/.git/hooks/post-checkout" ] && grep -qx '\[ ! -f .delphi/park.sh \] || exec bash .delphi/park.sh "$@"' "$w/.git/hooks/post-checkout"; }
ours || fail "setup.sh did not write the hook that runs .delphi/park.sh"
{ git -C "$w" checkout -q -b a2 && live lib1 && [ ! -e "$w/.delphi/parked" ]; } || fail "park: same-workspace branch moved clones"
mkdir -p "$w/.journal/ideas" "$w/pictures/a2" "$w/notes" && touch "$w/.journal/ideas/n.md" "$w/pictures/a2/s.png" "$w/notes/x"
local_ws b1 "ws/$BN" "$BN" lib2 || fail "park: setup on bms-dev failed"
{ [ ! -e "$w/.journal" ] && [ ! -e "$w/pictures" ] && [ -f "$w/.delphi/parked/$AN/.journal/ideas/n.md" ] &&
  [ -f "$w/.delphi/parked/$AN/pictures/a2/s.png" ] && [ -f "$w/notes/x" ]; } ||
  fail "park: .journal/ and park: folders not parked with argos-dev, or an unlisted folder moved"
rm -r "$w/notes"
{ [ ! -e "$w/repos/lib1" ] && [ ! -e "$w/references/lib1-ref" ] && [ -d "$w/.delphi/parked/$AN/repos/lib1/.git" ] &&
  [ -d "$w/.delphi/parked/$AN/workspaces/main/.git" ] && live lib2; } ||
  fail "park: argos-dev not parked on bms-dev"
[ -z "$(git -C "$w" status --porcelain)" ] || fail "park: parked clones show in status: $(git -C "$w" status --porcelain)"
{ git -C "$w" checkout -q main && [ ! -e "$w/repos" ] && [ ! -e "$w/worktrees" ] && [ ! -e "$w/references" ] && [ ! -e "$w/workspaces" ]; } ||
  fail "park: clones visible on main: $(ls -A "$w")"
[ -z "$(git -C "$w" status --porcelain)" ] || fail "park: main not clean"
{ git -C "$w" checkout -q a2 && live lib1 && [ ! -e "$w/repos/lib2" ] && [ -d "$w/.delphi/parked/$BN/repos/lib2" ] &&
  [ ! -e "$w/.delphi/parked/$AN" ]; } ||
  fail "park: argos-dev not restored"
{ [ -f "$w/.journal/ideas/n.md" ] && [ -f "$w/pictures/a2/s.png" ]; } || fail "park: .journal/ and pictures/ not restored"
git -C "$w" checkout -q -b a4 a2 && printf 'name: %s\nharness: claude-code\npark:\n  - .git\n  - ../up\n' "$AN" >"$w/workspace.yml" &&
  git -C "$w" commit -qam a4 && git -C "$w" checkout -q b1 2>"$t/err"
{ [ -d "$w/.git" ] && grep -q "won't park '.git'" "$t/err" && grep -q "won't park '../up'" "$t/err" && git -C "$w" checkout -q a2 && live lib1; } ||
  fail "park: a bad park: entry was not skipped: $(cat "$t/err")"
ok "park.sh skips a park: entry that isn't a folder name at the root (.git, ../x)"
git -C "$w/worktrees/lib1/$def" commit -q --allow-empty -m "after restore" || fail "park: restored worktree unusable"
{ git -C "$w" checkout -q b1 && live lib2 && git -C "$w" checkout -q a1 && live lib1; } || fail "park: second round trip"
git -C "$w" checkout -q main && mkdir "$w/references" && git -C "$w" checkout -q a1 2>"$t/err"
{ grep -q "references/ is in the way" "$t/err" && [ -d "$w/repos/lib1" ] && [ -d "$w/.delphi/parked/$AN/references" ]; } ||
  fail "park: a folder in the way was not reported and kept: $(cat "$t/err")"
{ rmdir "$w/references" && git -C "$w" checkout -q main && git -C "$w" checkout -q a1 && live lib1; } || fail "park: no recovery once cleared"
ok "park.sh parks a workspace's clones on switching to another workspace or main and restores them at the same paths"
ok "parked clones sit git-ignored in .delphi/parked/<name>/, the workspace's name"
ok "park.sh also parks .journal/ and the folders under the leaving workspace's park:, and restores all a workspace parked"
ok "park.sh leaves same-workspace branches alone and reports, never overwrites, a folder in the way"
git -C "$w" checkout -q -b a3 a1 && echo 'echo "park.sh from a3" >&2' >>"$w/.delphi/park.sh" && git -C "$w" commit -qam a3
{ git -C "$w" checkout -q b1 2>"$t/err" && ! grep -q "from a3" "$t/err" && git -C "$w" checkout -q a3 2>"$t/err" &&
  grep -q "from a3" "$t/err" && live lib1; } || fail "hook did not run the checked-out branch's park.sh"
{ git -C "$w" checkout -q main 2>"$t/err" && ! grep -q "from a3" "$t/err" && [ ! -e "$w/repos" ]; } ||
  fail "hook did not run main's own park.sh"
{ git -C "$w" checkout -q a1 && live lib1; } || fail "park: back to a1"
ok "the hook runs .delphi/park.sh as just checked out, on main too"
rm "$w/.git/hooks/post-checkout" && cp "$w/.delphi/park.sh" "$w/.git/hooks/post-checkout" && /bin/bash "$w/.delphi/setup.sh" >/dev/null 2>&1
ours || fail "setup.sh did not replace an old copied hook"
rm "$w/.git/hooks/post-checkout" && ln -s "$t/elsewhere/.delphi/park.sh" "$w/.git/hooks/post-checkout" && /bin/bash "$w/.delphi/setup.sh" >/dev/null 2>&1
ours || fail "setup.sh did not replace an old link to another checkout's park.sh"
ok "setup.sh replaces an old copied or linked park.sh hook with its script"
{ git -C "$w" worktree add -q "$t/park-wt" b1 && git -C "$t/park-wt" checkout -q a3 2>"$t/err" && grep -q "from a3" "$t/err" &&
  git -C "$w" worktree remove --force "$t/park-wt"; } || fail "a worktree of the clone did not run its own park.sh"
ok "each worktree of the clone runs the park.sh it just checked out, not the main checkout's"
rm "$w/.git/hooks/post-checkout" && printf '#!/bin/sh\n' >"$w/.git/hooks/post-checkout" && /bin/bash "$w/.delphi/setup.sh" >/dev/null 2>"$t/err"
{ grep -q "another hook" "$t/err" && [ "$(cat "$w/.git/hooks/post-checkout")" = "#!/bin/sh" ]; } || fail "setup.sh replaced another post-checkout hook"
ok "setup.sh keeps someone else's post-checkout hook and says so"

# --- 9. new-workspace.sh creates the folder on a branch and opens a PR
: >"$t/gh.log"
git -C "$t/dev" branch -q new-workspace/electrical/firmware/fw-dev origin/main # left by an earlier failed run
(cd "$t/dev" && git checkout -q -B main origin/main && tools/new-workspace.sh electrical/firmware fw-dev >/dev/null) ||
  fail "new-workspace.sh failed (blocked by a leftover local branch?)"
F=software/electrical/firmware/workspaces/fw-dev FN=s.electrical.firmware.fw-dev
o cat-file -e "new-workspace/electrical/firmware/fw-dev:$F/workspace.yml" || fail "no workspace.yml on new-workspace/electrical/firmware/fw-dev"
o show "new-workspace/electrical/firmware/fw-dev:$F/CLAUDE.md" | grep -q "branch \`ws/$FN\`" || fail "CLAUDE.md not filled in"
! o show "new-workspace/electrical/firmware/fw-dev:$F/CLAUDE.md" | grep -q "{{" || fail "placeholder left"
o show "new-workspace/electrical/firmware/fw-dev:$F/CLAUDE.md" | grep -qx "# Firmware for $FN" || fail "defaults CLAUDE.md not appended"
[ "$(o show "new-workspace/electrical/firmware/fw-dev:$F/workspace.yml")" = "$(printf 'name: %s\n' "$FN"; o show "main:$FD/workspace.yml")" ] ||
  fail "defaults workspace.yml not used, or name: not set"
o cat-file -e "new-workspace/electrical/firmware/fw-dev:$F/.claude/skills/fw/SKILL.md" || fail "defaults skill not copied"
o cat-file -e "new-workspace/electrical/firmware/fw-dev:$F/.claude/settings.json" || fail "new workspace has no generated settings.json"
! o cat-file -e "new-workspace/electrical/firmware/fw-dev:$F/.claude/skills/top/SKILL.md" 2>/dev/null || fail "new workspace PR contains inherited output"
! o cat-file -e "new-workspace/electrical/firmware/fw-dev:$F/workspace.generated" 2>/dev/null || fail "new workspace PR contains branch ownership metadata"
grep -q "gh pr create --base main --head new-workspace/electrical/firmware/fw-dev --title Add workspace $FN --label by: ai --body ## Changes" "$t/gh.log" ||
  fail "no PR for new workspace, or not labelled by: ai with the template's sections: $(cat "$t/gh.log")"
(cd "$t/dev" && tools/new-workspace.sh --by ai-assisted electrical/firmware fw-two >/dev/null) || fail "new-workspace.sh --by failed"
grep -q "s.electrical.firmware.fw-two --label by: ai-assisted " "$t/gh.log" || fail "--by ai-assisted not used for the label"
(cd "$t/dev" && ! tools/new-workspace.sh --by bot electrical/firmware fw-three 2>/dev/null) || fail "bad --by accepted"
(cd "$t/dev" && ! tools/new-workspace.sh application-software/argos argos-dev 2>/dev/null) || fail "duplicate workspace accepted"
(cd "$t/dev" && ! tools/new-workspace.sh app/argos argos-dev 2>"$t/err" && grep -q "is already named $AN (names are unique)" "$t/err") || fail "a name taken elsewhere in the tree accepted"
(cd "$t/dev" && ! tools/new-workspace.sh x Bad 2>/dev/null) || fail "bad name accepted"
(cd "$t/dev" && ! tools/new-workspace.sh ../x ok 2>/dev/null) || fail "bad org path accepted"
[ -z "$(git -C "$t/dev" status --porcelain)" ] || fail "new-workspace touched the checkout"
ok "new-workspace.sh opens a PR with the templated folder; rejects duplicates and bad input"
ok "new-workspace.sh adds the project's workspace-defaults/ (CLAUDE.md appended, placeholders filled), without inherited copies or ledgers on main"
ok "new-workspace.sh works when a local new-workspace/<name> branch is left over"
ok "new-workspace.sh's PR follows the PR template, labelled by: ai unless --by says otherwise"

# --- 10. one direction at a time: `sync refresh` only updates ws/, `sync propose` only updates propose/
sync "$AN" >/dev/null || fail "settling sync failed"
commit_on main "$A/CLAUDE.md" "one-way refresh"
prop_before=$(o rev-parse propose/$AN)
sync refresh "$AN" >/dev/null || fail "sync refresh failed"
o show ws/$AN:CLAUDE.md | grep -qx "one-way refresh" || fail "sync refresh did not merge main"
[ "$(o rev-parse propose/$AN)" = "$prop_before" ] || fail "sync refresh touched propose/$AN"
commit_on ws/$AN docs/CONTEXT.md "one-way propose"
ws_before=$(o rev-parse ws/$AN)
commit_on main "$A/CLAUDE.md" "not yet refreshed"
sync propose "$AN" >/dev/null || fail "sync propose failed"
o show "propose/$AN:$A/docs/CONTEXT.md" | grep -qx "one-way propose" || fail "sync propose lacks the ws edit"
[ "$(o rev-parse ws/$AN)" = "$ws_before" ] || fail "sync propose changed ws/$AN"
! o show ws/$AN:CLAUDE.md | grep -qx "not yet refreshed" || fail "sync propose merged main into ws"
ok "sync refresh / sync propose each move changes one way only"
prop_before=$(o rev-parse propose/$AN)
commit_on ws/$AN workspace.yml "bad: line"
if sync "$AN" 2>"$t/err" >/dev/null; then fail "sync proposed a workspace failing check"; fi
grep -q "ws/$AN: check failed" "$t/err" || fail "check failure not reported: $(cat "$t/err")"
[ "$(o rev-parse propose/$AN)" = "$prop_before" ] || fail "failing proposal was pushed"
ok "a proposal failing check.sh is reported and not pushed; exit 1"

# --- 11. new-worktree.sh: new branch from the default branch or <base>; existing branch checked out; reruns reuse
git init -q "$t/code" && git -C "$t/code" commit -q --allow-empty -m one && git -C "$t/code" branch feat &&
  git -C "$t/code" branch develop && git -C "$t/code" commit -q --allow-empty -m two
def=$(git -C "$t/code" branch --show-current)
w=$t/nw && git clone -q -b ws/$BN "$t/origin.git" "$w"
printf 'name: s.electrical.bms-dev\nharness: claude-code\nrepos:\n  code: %s\n' "$t/code" >"$w/workspace.yml"
bash "$w/.delphi/setup.sh" >/dev/null 2>&1 || fail "setup.sh failed for new-worktree test"
nw() { bash "$w/.delphi/new-worktree.sh" "$@"; }
[ "$(nw code 1-new)" = "$w/worktrees/code/1-new" ] || fail "new-worktree path"
[ "$(git -C "$w/worktrees/code/1-new" rev-parse HEAD)" = "$(git -C "$t/code" rev-parse "$def")" ] || fail "new branch not from default"
nw code feat >/dev/null && [ "$(git -C "$w/worktrees/code/feat" rev-parse HEAD)" = "$(git -C "$t/code" rev-parse feat)" ] ||
  fail "existing branch not checked out"
[ "$(git -C "$w/worktrees/code/feat" rev-parse --abbrev-ref '@{u}')" = origin/feat ] || fail "existing branch not tracking origin"
nw code 2-dev origin/develop >/dev/null && [ "$(git -C "$w/worktrees/code/2-dev" rev-parse HEAD)" = "$(git -C "$t/code" rev-parse develop)" ] ||
  fail "<base> ignored"
[ "$(nw code feat)" = "$w/worktrees/code/feat" ] || fail "rerun did not reuse"
[ "$(git -C "$w/worktrees/code/$def" branch --show-current)" = "$def" ] || fail "default worktree left its branch"
{ [ "$(git -C "$w/repos/code" branch --show-current)" = "$def" ] && [ "$(git -C "$w/repos/code" worktree list | wc -l | tr -d " ")" = 1 ] &&
  ! git -C "$w/repos/code" rev-parse -q --verify refs/heads/1-new >/dev/null; } || fail "new-worktree touched the clone at repos/code"
ok "new-worktree.sh makes new branches from the default or <base>, checks out existing ones, reuses on rerun, never touching repos/<repo>"
# skill scripts read the workspace from $DELPHI_ROOT (the session hook evals paths.sh's export line) and every folder from paths.sh
(. "$w/.delphi/paths.sh" && [ "$DELPHI_ROOT" = "$w" ] && [ "$DELPHI_REPOS" = "$w/repos" ] &&
  [ "$DELPHI_WORKTREES" = "$w/worktrees" ] && [ "$DELPHI_REFERENCES" = "$w/references" ] && [ "$DELPHI_WORKSPACES" = "$w/workspaces" ]) ||
  fail "paths.sh layout"
[ "$(cd "$t" && eval "$(bash "$w/.delphi/paths.sh")" && echo "$(printenv DELPHI_ROOT) $(printenv DELPHI_WORKSPACES)")" = "$w $w/workspaces" ] ||
  fail "paths.sh's export line doesn't reach child processes"
cap=$src/software/workspace-inherit/.claude/skills/journal/scripts/capture.sh
{ e=$(cd "$t" && DELPHI_ROOT=$w bash "$cap" -c ideas "a note") && [ "${e#"$w/.journal/ideas/"}" != "$e" ] && grep -q "a note" "$e"; } ||
  fail "capture.sh from \$DELPHI_ROOT: $e"
! (unset DELPHI_ROOT && bash "$cap" "a note") >/dev/null 2>&1 || fail "capture.sh ran without DELPHI_ROOT"
! DELPHI_ROOT=$t bash "$cap" "a note" >/dev/null 2>&1 || fail "capture.sh accepted a DELPHI_ROOT that is not a workspace root"
ok "paths.sh gives the layout, sourced or as an export line; capture.sh reads \$DELPHI_ROOT, refusing it unset or not a root"
# plugins.sh: setup.sh installs the @delphi plugins this workspace enables but this clone hasn't,
# uninstalls this clone's local ones it doesn't enable and ones the marketplace dropped, leaves other
# clones' and user-scope ones alone, and only warns about other marketplaces' or offline
printf '{\n  "extraKnownMarketplaces": {\n    "delphi": {\n      "source": {\n        "source": "github",\n        "repo": "o/Delphi"\n      },\n      "autoUpdate": true\n    }\n  },\n  "enabledPlugins": {\n    "app@delphi": true,\n    "argos@delphi": true,\n    "x@other": true\n  }\n}\n' >"$w/.claude/settings.json"
pl() { # <id> <scope> <projectPath or -> <gone 0/1>...: what `claude plugin list --json` reports
  local sep=""
  printf '[' && while [ $# -ge 4 ]; do
    printf '%s\n  {\n    "id": "%s",\n    "scope": "%s",\n' "$sep" "$1" "$2"
    [ "$3" = - ] || printf '    "projectPath": "%s",\n' "$3"
    [ "$4" = 0 ] || printf '    "errorDetails": [\n      {\n        "type": "plugin-not-found",\n        "plugin": "%s"\n      }\n    ],\n' "${1%@*}"
    printf '    "enabled": true\n  }' && sep=, && shift 4
  done && printf '\n]\n'
}
plugins() { : >"$t/claude.log" && bash "$w/.delphi/plugins.sh"; } # its output; what it ran is in claude.log
rm -f "$t/plugins.json" && touch "$t/offline"
{ out=$(plugins) && echo "$out" | grep -qF "plugins app@delphi argos@delphi x@other aren't installed" && ! grep -q install "$t/claude.log"; } ||
  fail "plugins.sh offline didn't just warn: $out $(cat "$t/claude.log")"
rm "$t/offline"
{ out=$(plugins) && echo "$out" | grep -qF "delphi: plugins: installed app@delphi; installed argos@delphi; run /reload-plugins" &&
  echo "$out" | grep -qF "plugins x@other aren't installed" && grep -qx "claude plugin marketplace update delphi" "$t/claude.log" &&
  grep -qx "claude plugin install app@delphi --scope local" "$t/claude.log" && ! grep -q "install x@other" "$t/claude.log"; } ||
  fail "plugins.sh with none installed: $out $(cat "$t/claude.log")"
pl app@delphi user - 0 argos@delphi local "$t/elsewhere" 0 x@other user - 0 >"$t/plugins.json"
{ out=$(plugins) && [ "$out" = "delphi: plugins: installed argos@delphi; run /reload-plugins in Claude Code (or restart it) to load the change" ]; } ||
  fail "plugins.sh counted another clone's install: $out"
pl app@delphi user - 0 argos@delphi local "$w" 0 x@other user - 0 old@delphi user - 1 gone@other user - 1 \
  extra@delphi local "$w" 0 theirs@delphi local "$t/elsewhere" 0 spare@delphi user - 0 >"$t/plugins.json"
{ : >"$t/claude.log" && err=$(bash "$w/.delphi/setup.sh" 2>&1 >/dev/null) &&
  echo "$err" | grep -qF "delphi: plugins: uninstalled old@delphi (gone from the Delphi marketplace); uninstalled extra@delphi (this workspace doesn't enable it)" &&
  grep -qx "claude plugin uninstall old@delphi --scope user" "$t/claude.log" && grep -qx "claude plugin uninstall extra@delphi --scope local" "$t/claude.log" &&
  ! grep -q "gone@other\|theirs@\|spare@\|install a" "$t/claude.log"; } ||
  fail "setup.sh doesn't uninstall what the marketplace dropped and this workspace's unenabled local installs (only): $err $(cat "$t/claude.log")"
touch "$t/offline"
{ out=$(plugins) && echo "$out" | grep -qF "plugins old@delphi are gone from the Delphi marketplace; uninstall each with" && ! grep -q "uninstall old" "$t/claude.log" &&
  grep -qx "claude plugin uninstall extra@delphi --scope local" "$t/claude.log"; } ||
  fail "plugins.sh offline uninstalled a dropped plugin, didn't warn, or kept an unenabled local install: $out $(cat "$t/claude.log")"
rm "$t/offline"
pl app@delphi user - 0 argos@delphi local "$w" 0 extra@delphi local "$w" 0 >"$t/plugins.json"
{ out=$(plugins) && echo "$out" | grep -qF "uninstalled extra@delphi" && ! grep -q "marketplace update" "$t/claude.log"; } ||
  fail "plugins.sh refreshed the marketplace just to uninstall a local plugin: $out $(cat "$t/claude.log")"
pl app@delphi user - 0 argos@delphi local "$w" 0 x@other user - 0 >"$t/plugins.json"
{ [ -z "$(plugins)" ] && [ ! -s "$t/claude.log" ]; } || fail "plugins.sh did something with every plugin in order: $(cat "$t/claude.log")"
ok "setup.sh (plugins.sh) makes this clone's @delphi plugins what the workspace enables and uninstalls ones the marketplace dropped; warns offline or for other marketplaces; quiet when all is in order"

# --- 12. workspaces: setup.sh clones listed workspaces and main at workspaces/<name>, on their branch, pulled on re-run;
# migrations: setup.sh runs the pending ones (0.0.1 replaces old link.sh worktrees), stopping where one can't go on safely
printf 'name: s.electrical.bms-dev\nharness: claude-code\nrepos:\n  code: %s\nworkspaces:\n  - s.app.argos.argos-dev  # a comment\n  - main\n  - s.electrical.bms-dev\n  - Bad\n  - ws/argos-dev\n' \
  "$t/code" >"$w/workspace.yml"
(cd "$t/dev" && git fetch -q && git checkout -q -B sandbox origin/ws/$AN && # its own setup (run by a link) uses sandbox repos only
  printf 'name: %s\nharness: claude-code\nrepos:\n  lib1: %s\nworkspaces:\n  - main\n  - %s\n' "$AN" "$t/lib1.git" "$BN" >workspace.yml &&
  git commit -qam "sandbox repos" && git push -q origin HEAD:ws/$AN)
bash "$w/.delphi/setup.sh" >/dev/null 2>"$t/err" || fail "setup.sh failed with links: $(cat "$t/err")"
{ [ -d "$w/workspaces/$AN/worktrees/lib1" ] && [ ! -e "$w/workspaces/$AN/workspaces" ]; } ||
  fail "setup.sh did not run a link's own setup, or that setup cloned its own workspaces: $(cat "$t/err")"
[ "$(git -C "$w/workspaces/$AN" rev-parse HEAD)" = "$(o rev-parse "ws/$AN")" ] || fail "copy not at ws/$AN"
{ [ "$(git -C "$w/workspaces/$AN" branch --show-current)" = "ws/$AN" ] && [ "$(git -C "$w/workspaces/main" branch --show-current)" = main ] &&
  [ "$(git -C "$w/workspaces/$AN" rev-parse --abbrev-ref '@{u}')" = "origin/ws/$AN" ] &&
  [ "$(git -C "$w/workspaces/main" rev-parse --is-shallow-repository)" = false ]; } || fail "a link is not a full clone on its branch, tracking origin"
[ -f "$w/workspaces/main/ci/sync.sh" ] || fail "link main"
{ [ ! -e "$w/workspaces/$BN" ] && [ ! -e "$w/workspaces/Bad" ] && [ ! -e "$w/workspaces/ws" ] && grep -q "skipping bad workspaces: entry 'Bad'" "$t/err" &&
  grep -q "skipping bad workspaces: entry 'ws/argos-dev'" "$t/err"; } || fail "copied itself or a bad entry"
git -C "$w/workspaces/$AN" push -q --dry-run origin HEAD:refs/heads/x 2>/dev/null || fail "pushes from a link are disabled"
commit_on ws/$AN docs/CONTEXT.md "linked update"
{ bash "$w/.delphi/setup.sh" >/dev/null 2>&1 && grep -qx "linked update" "$w/workspaces/$AN/docs/CONTEXT.md"; } || fail "re-run did not refresh a link"
git -C "$w/workspaces/main" switch -q -c scratch && commit_on main README.md "main update"
{ bash "$w/.delphi/setup.sh" >/dev/null 2>&1 && [ "$(git -C "$w/workspaces/main" branch --show-current)" = main ] &&
  grep -qx "main update" "$w/workspaces/main/README.md"; } || fail "re-run did not switch a link back to its branch and pull it"
git -C "$w/workspaces/main" switch -q scratch && echo x >>"$w/workspaces/main/README.md"
{ bash "$w/.delphi/setup.sh" >/dev/null 2>"$t/err" && grep -q "could not switch workspaces/main back to main" "$t/err" &&
  [ "$(git -C "$w/workspaces/main" branch --show-current)" = scratch ] && grep -qx x <(tail -n 1 "$w/workspaces/main/README.md"); } ||
  fail "re-run moved a link with uncommitted changes, or failed: $(cat "$t/err")"
git -C "$w/workspaces/main" checkout -q README.md && git -C "$w/workspaces/main" switch -q main && git -C "$w/workspaces/main" branch -q -D scratch
[ "$(grep -cx /workspaces/ "$w/.git/info/exclude")" = 1 ] || fail "/workspaces/ not excluded exactly once"
! git -C "$w" status --porcelain | grep -q workspaces || fail "workspaces/ shows in status"
ok "setup.sh clones workspaces: at workspaces/<name> on their branch and runs their setup (which skips its own workspaces:), skips itself and bad entries (old ws/<name> ones too), switches back and pulls on re-run, keeps local changes"
[ "$(git -C "$w" config delphi.$BN.version)" = "$VN" ] || fail "setup.sh did not record the version"
old_link() { rm -rf "$w/linked/main" "$w/workspaces/main" && git -C "$w" worktree add -q --detach "$w/linked/main" origin/main && git -C "$w" config --unset delphi.$BN.version; }
old_link && echo x >>"$w/linked/main/README.md"
{ ! /bin/bash "$w/.delphi/setup.sh" >/dev/null 2>"$t/err" && grep -q "linked/main has uncommitted changes" "$t/err" &&
  grep -qx x <(tail -n 1 "$w/linked/main/README.md") && ! git -C "$w" config delphi.$BN.version >/dev/null; } ||
  fail "a failing migration did not stop setup.sh with nothing lost: $(cat "$t/err")"
git -C "$w/linked/main" checkout -q README.md && git -C "$w/linked/main" commit -q --allow-empty -m "detached work"
{ ! /bin/bash "$w/.delphi/setup.sh" >/dev/null 2>"$t/err" && grep -q "linked/main has commits on no branch" "$t/err" &&
  [ "$(git -C "$w/linked/main" log -1 --format=%s)" = "detached work" ]; } || fail "0.0.1 deleted commits on no branch: $(cat "$t/err")"
git -C "$w/linked/main" checkout -q --detach origin/main
ok "a migration that can't finish safely stops setup.sh, keeps what it would lose, and records nothing"
git -C "$w" config delphi.$BN.version 0.0.1
{ /bin/bash "$w/.delphi/setup.sh" >/dev/null 2>"$t/err" && [ -f "$w/workspaces/main/.git" ] && grep -q "workspaces/main is a worktree" "$t/err"; } ||
  fail "a migration ran again, or setup.sh wrote into a worktree: $(cat "$t/err")"
ok "a recorded version's migrations don't run again; setup.sh never writes into a worktree in workspaces/"
mkdir -p "$w/linked" && mkdir -p "$w/linked" && git -C "$w" worktree move "$w/workspaces/main" "$w/linked/main" && git -C "$w" config --unset delphi.$BN.version
{ /bin/bash "$w/.delphi/setup.sh" >"$t/out" 2>&1 && grep -q "migrating $BN to 0.0.1" "$t/out" && [ -d "$w/workspaces/main/.git" ] &&
  [ -f "$w/workspaces/main/ci/sync.sh" ] && ! git -C "$w" worktree list | grep -q "linked\|workspaces" && [ ! -e "$w/linked" ] &&
  [ "$(git -C "$w" config delphi.$BN.version)" = "$VN" ]; } || fail "0.0.1 did not replace an old link.sh worktree: $(cat "$t/out")"
ok "setup.sh runs pending migrations (0.0.1: an old link.sh worktree in linked/ becomes a clone) and records the version"
old_copy() { # <dir> <ref>: a link as setup.sh made it before 0.9.0: shallow, detached, pushes disabled
  rm -rf "$1" && git init -q "$1" && git -C "$1" remote add origin "$t/origin.git" &&
    git -C "$1" remote set-url --push origin DISABLED-read-only-copy && git -C "$1" fetch -q --depth 1 origin "$2" &&
    git -C "$1" checkout -q --detach FETCH_HEAD
}
rm -rf "$w/workspaces" && old_copy "$w/linked/main" main && old_copy "$w/linked/$AN" "ws/$AN" && echo x >>"$w/linked/$AN/CLAUDE.md" && git -C "$w" config delphi.$BN.version 0.8.0
{ /bin/bash "$w/.delphi/setup.sh" >"$t/out" 2>&1 && grep -q "migrating $BN to 0.9.0" "$t/out" && grep -q "moved linked/main to workspaces/main" "$t/out" && [ ! -e "$w/linked" ] &&
  [ "$(git -C "$w/workspaces/main" branch --show-current)" = main ] && [ "$(git -C "$w/workspaces/$AN" branch --show-current)" = "ws/$AN" ] &&
  [ "$(git -C "$w/workspaces/main" rev-parse --is-shallow-repository)" = false ] && ! git -C "$w/workspaces/main" config remote.origin.pushurl >/dev/null &&
  [ "$(git -C "$w/workspaces/$AN" rev-parse --abbrev-ref '@{u}')" = "origin/ws/$AN" ] && grep -qx x <(tail -n 1 "$w/workspaces/$AN/CLAUDE.md"); } ||
  fail "0.9.0 did not turn old read-only copies into clones on their branch, keeping local changes: $(cat "$t/out")"
git -C "$w/workspaces/$AN" checkout -q CLAUDE.md
ok "0.9.0 turns old shallow, detached, push-disabled copies in linked/ into full clones on their branch, keeping what's in them; 1.0.0 moves them to workspaces/"
git -C "$w" config delphi.$BN.version 1.2.0
rm -rf "$w/repos/lib1" "$w/worktrees/lib1" && git clone -q --bare "$t/lib1.git" "$w/repos/lib1" && git -C "$w/repos/lib1" worktree add -q "$w/worktrees/lib1/old" -b old 2>/dev/null
git -C "$w/repos/lib1" worktree add -q --detach "$w/worktrees/lib1/det" && git -C "$w/worktrees/lib1/det" commit -q --allow-empty -m "unpushed"
{ /bin/bash "$w/.delphi/setup.sh" >/dev/null 2>"$t/err" && grep -q "repos/lib1 has branches or worktree commits not on origin" "$t/err" &&
  [ "$(git -C "$w/repos/lib1" rev-parse --is-bare-repository)" = true ]; } || fail "2.0.0 moved a bare repos/lib1 with unpushed commits: $(cat "$t/err")"
git -C "$w/repos/lib1" worktree remove --force "$w/worktrees/lib1/det"
git -C "$w" config delphi.$BN.version 1.2.0
/bin/bash "$w/.delphi/setup.sh" >"$t/out" 2>&1 || fail "2.0.0 failed on a bare repos/lib1: $(cat "$t/out")"
{ grep -q "moved repos/lib1 to worktrees/lib1/.bare" "$t/out" && [ "$(git -C "$w/worktrees/lib1/.bare" rev-parse --is-bare-repository)" = true ] &&
  [ ! -e "$w/repos/lib1" ] && git -C "$w/worktrees/lib1/old" status >/dev/null &&
  git -C "$w/worktrees/lib1/.bare" worktree list | grep -q "worktrees/lib1/old" &&
  git -C "$w/worktrees/lib1/.bare" symbolic-ref -q refs/remotes/origin/HEAD >/dev/null; } || fail "2.0.0 did not move a bare repos/lib1 to .bare, keeping its worktrees: $(cat "$t/out")"
git -C "$w" config delphi.$BN.version 1.2.0
{ /bin/bash "$w/.delphi/setup.sh" >"$t/out" 2>&1 && ! grep -q "migrate:" "$t/out"; } || fail "2.0.0 did something on a second run: $(cat "$t/out")"
ok "2.0.0 moves a bare repos/<name> to worktrees/<name>/.bare with its worktrees, vacating repos/<name> for setup's clone; skips one with unpushed work"
echo "# local" >>"$w/.delphi/switch.sh"
{ /bin/bash "$w/.delphi/setup.sh" >/dev/null 2>"$t/err" && grep -q "not Delphi $VN as released" "$t/err"; } || fail "setup.sh did not warn about an edited .delphi/"
git -C "$w" checkout -q .delphi/switch.sh
ok "setup.sh warns when .delphi/ isn't the version it says"

# --- 12b. switch.sh: refuses a dirty root; switches workspaces (parking and restoring), fast-forwards, sets up; main too
(cd "$t/dev" && git fetch -q && git checkout -q -B sw origin/ws/$AN &&
  printf 'name: s.app.argos.argos-dev\nharness: claude-code\nrepos:\n  lib1: %s\nworkspaces:\n  - main\n' "$t/lib1.git" >workspace.yml &&
  git commit -qam "local repos" && git push -q origin HEAD:ws/$AN)
w=$t/sw && git clone -q -b ws/$AN "$t/origin.git" "$w"
/bin/bash "$w/.delphi/setup.sh" >/dev/null 2>&1 || fail "switch: setup failed"
sw() { /bin/bash "$w/.delphi/switch.sh" "$@"; }
echo x >>"$w/CLAUDE.md"
{ ! sw $BN 2>"$t/err" >/dev/null && grep -q "commit or set aside" "$t/err" && [ "$(git -C "$w" branch --show-current)" = ws/$AN ]; } ||
  fail "switch: dirty root not refused"
git -C "$w" checkout -q CLAUDE.md
sw $BN >"$t/out" 2>&1 || fail "switch to bms-dev failed: $(cat "$t/out")"
{ [ "$(git -C "$w" branch --show-current)" = ws/$BN ] && [ ! -e "$w/worktrees" ] && [ ! -e "$w/workspaces" ] &&
  [ -d "$w/.delphi/parked/$AN/workspaces/main" ]; } || fail "switch: argos-dev not parked on bms-dev"
commit_on ws/$AN docs/CONTEXT.md "while away"
sw "ws/$AN" >"$t/out" 2>&1 || fail "switch back (by branch) failed: $(cat "$t/out")"
{ [ "$(git -C "$w" branch --show-current)" = ws/$AN ] && grep -qx "while away" "$w/docs/CONTEXT.md" &&
  [ -d "$w/worktrees/lib1/$def" ] && [ -f "$w/workspaces/main/ci/sync.sh" ]; } || fail "switch: argos-dev not restored and fast-forwarded"
{ sw main >/dev/null 2>&1 && [ "$(git -C "$w" branch --show-current)" = main ] && [ ! -e "$w/repos" ] && [ -f "$w/ci/sync.sh" ]; } ||
  fail "switch to main"
git -C "$w" switch -q ws/$AN
{ ! sw ../x 2>/dev/null && ! sw nope 2>/dev/null && ! sw software/nope/x 2>/dev/null && [ "$(git -C "$w" branch --show-current)" = ws/$AN ]; } || fail "switch accepted a bad or missing workspace"
ok "switch.sh refuses a dirty root, parks and restores workspaces, fast-forwards, runs setup, and switches to main"
ok "switch.sh takes a workspace's name or its branch"
git -C "$w" push -q origin "origin/ws/$AN:refs/heads/ws/$AO" # its old name, and bms-dev (gone from main): not listed
[ "$(sw --list)" = "$(printf '  main\n* %s software/application-software/argos' "$AN")" ] || fail "switch.sh --list: $(sw --list 2>&1)"
git -C "$w" push -q origin ":ws/$AO"
ok "switch.sh --list prints main and each workspace on main with its project folder (not old names), marking this clone's"

# --- 12c. the delphi mod (software/plugins/claude/default): /ws-delphi, a pane that switches through switch.sh.
# Its own tests stub every process; they need a real claude, which CI doesn't have.
mod=$src/software/plugins/claude/default
real() { PATH=$real_path HOME=$real_home "$@"; } # a claude wrapper may look itself up on PATH
if real command -v claude >/dev/null; then
  { out=$(real claude plugin validate "$mod" 2>&1) && echo "$out" | grep -q "hooks: session.start, prompt.submit, command.run{command=ws-delphi}"; } ||
    fail "the delphi mod doesn't validate: $out"
  out=$(cd "$mod" && real claude plugin test 2>&1) || fail "the delphi mod's tests failed: $out"
  ok "the delphi mod validates and its tests pass ($(echo "$out" | grep -E '^ *[0-9]+ pass$' | sed 's/^ *//'))"
else
  echo "skip - the delphi mod's tests: no claude on PATH"
fi

# --- 12d. the mod's browser view (web/server.py): serves the page and the list only with its token and a local
# Host, pulls and switches only on a JSON POST, through switch.sh, and says so on stdout for the mod
if command -v python3 >/dev/null && command -v curl >/dev/null; then
  python3 "$mod/web/server.py" "$w" >"$t/web.out" 2>"$t/web.err" &
  web=$!
  for _ in $(seq 50); do [ -s "$t/web.out" ] && break; sleep 0.1; done
  url=$(head -1 "$t/web.out") port=${url#http://127.0.0.1:} port=${port%%/*}
  get() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
  # Consume the whole HTML response: grep -q can make curl fail with SIGPIPE under pipefail.
  { [ "$(get "$url")" = 200 ] && curl -s "$url" | grep "<title>Delphi workspaces</title>" >/dev/null &&
    [ "$(get "http://127.0.0.1:$port/")" = 404 ] && [ "$(get "http://127.0.0.1:$port/wrong/api/state")" = 404 ] &&
    [ "$(get -H "Host: evil.example:$port" "${url}api/state")" = 403 ]; } || fail "web/server.py let a request without its token or a local Host through"
  curl -s "${url}api/state" | python3 -c 'import json, sys; s = json.load(sys.stdin); sys.exit(not (s["here"] == sys.argv[1] and s["workspaces"] == ["main", sys.argv[1] + " software/application-software/argos"] and not s["isDirty"]))' "$AN" ||
    fail "web/server.py api/state: $(curl -s "${url}api/state")"
  commit_on ws/$AN docs/CONTEXT.md "for the browser's pull"
  { [ "$(get -X POST -d '{}' "${url}api/pull")" = 415 ] &&
    curl -s -X POST -H 'Content-Type: application/json' -d '{}' "${url}api/pull" | grep -Eq '"Pulled [0-9]+ commits? into argos-dev"' &&
    [ "$(git -C "$w" rev-parse HEAD)" = "$(git -C "$t/origin.git" rev-parse "ws/$AN")" ] && grep -Eqx "pulled Pulled [0-9]+ commits? into argos-dev" "$t/web.out" &&
    curl -s -X POST -H 'Content-Type: application/json' -d '{}' "${url}api/pull" | grep -q '"argos-dev is up to date with origin"'; } ||
    fail "web/server.py pull: $(cat "$t/web.out" "$t/web.err")"
  { [ "$(get -X POST -d '{"name":"s.electrical.bms-dev"}' "${url}api/switch")" = 415 ] && [ "$(git -C "$w" branch --show-current)" = "ws/$AN" ]; } ||
    fail "web/server.py switched without a JSON body"
  { curl -s -X POST -H 'Content-Type: application/json' -d '{"name":"s.electrical.bms-dev"}' "${url}api/switch" | grep -q '"ok": true' &&
    [ "$(git -C "$w" branch --show-current)" = "ws/$BN" ] && grep -qx "switched $BN" "$t/web.out"; } ||
    fail "web/server.py switch to bms-dev: $(cat "$t/web.out" "$t/web.err")"
  kill "$web" && wait "$web" 2>/dev/null || true
  git -C "$w" switch -q "ws/$AN"
  ok "the browser view answers only its own page, pulls and switches through switch.sh, printing what it did"
else
  echo "skip - the delphi mod's browser view: no python3 or curl"
fi

# --- 14. dotted names: a workspace's old path-named ws/<old> branch carries over into ws/<name> (pushed to both once);
# moving a clone between the old and new names moves nothing; 0.8.0 renames what a clone keeps under old names
C=software/electrical/workspaces/vcu-dev CN=s.electrical.vcu-dev CO=software/electrical/vcu-dev
(cd "$t/dev" && git fetch -q && git checkout -q -B main origin/main && mkdir -p "$C" && cp -R templates/workspace/. "$C/" &&
  sed -i.bak "s|{{name}}|$CO|" "$C/workspace.yml" && rm "$C/workspace.yml.bak" && bash ci/plugins.sh >/dev/null &&
  git add -A && git commit -qm "vcu-dev, still named the old way" && git push -q origin main &&
  bash ci/render.sh --workspace "$C" . "$t/rename-stage" &&
  i=$t/legacy.index && GIT_INDEX_FILE=$i git read-tree "main:$C" && GIT_INDEX_FILE=$i git read-tree --prefix=.delphi/ main:.delphi &&
  while IFS= read -r stage_file; do
    stage_mode=100644; [ ! -x "$stage_file" ] || stage_mode=100755
    stage_blob=$(git hash-object -w -- "$stage_file") &&
      GIT_INDEX_FILE=$i git update-index --add --cacheinfo "$stage_mode,$stage_blob,${stage_file#"$t/rename-stage/$C/"}" || exit 1
  done < <(find "$t/rename-stage/$C" -type f | LC_ALL=C sort) &&
  git push -q origin "$(git commit-tree -p main -m "delphi: create ws/$CO" "$(GIT_INDEX_FILE=$i git write-tree)"):refs/heads/ws/$CO" &&
  git push -q origin "origin/main:refs/heads/ws/$CN" && # a stale ws/<name> behind it
  rm "$i" && sed -i.bak "s|^name:.*|name: $CN|" "$C/workspace.yml" && rm "$C/workspace.yml.bak" && git commit -qam "vcu-dev named with dots" && git push -q origin main)
o merge-base --is-ancestor "ws/$CN" "ws/$CO" || fail "sandbox: ws/$CN is not behind ws/$CO"
commit_on "ws/$CO" CLAUDE.md "on the old branch"
legacy=$(o rev-parse "ws/$CO")
sync >"$t/out" 2>&1 || fail "sync after a rename failed: $(cat "$t/out")"
{ grep -q "ws/$CN: from ws/$CO, its old name (pushed to both)" "$t/out" && o merge-base --is-ancestor "$legacy" "ws/$CN" &&
  [ "$(o rev-parse "ws/$CO")" = "$(o rev-parse "ws/$CN")" ] && o show "ws/$CN:CLAUDE.md" | grep -qx "on the old branch" &&
  [ "$(o show "ws/$CN:workspace.yml" | sed -n 1p)" = "name: $CN" ] && o show "propose/$CN:$C/CLAUDE.md" | grep -qx "on the old branch"; } ||
  fail "ws/$CN did not carry over ws/$CO: $(cat "$t/out")"
ok "a workspace's ws/<name> starts from its path-named ws/<old> while that's ahead, history and unproposed edits included, and both get the result"
{ sync >"$t/out" 2>&1 && grep -q "notice: ws/$CO is ws/$CN's old name (kept" "$t/out" && ! grep -q "ws/$CN: from" "$t/out"; } ||
  fail "a caught-up old name was carried over again, or no notice: $(cat "$t/out")"
ok "once ws/<name> has it, ws/<old> is left alone with a notice"
w=$t/rename && git clone -q -b "ws/$CO" "$t/origin.git" "$w"
mkdir -p "$w/.delphi/parked/$AO/linked/ws/$CO" "$w/linked/ws/$AO" && git -C "$w" config "delphi.$CO.version" 0.7.0 && git -C "$w" config "delphi.$AO.version" 0.7.0
/bin/bash "$w/.delphi/setup.sh" >"$t/out" 2>&1 || fail "setup.sh failed running 0.8.0: $(cat "$t/out")"
{ grep -q "migrating $CN to 0.8.0" "$t/out" && ! grep -q "to 0.1.0" "$t/out" && [ -d "$w/.delphi/parked/$AN/linked/$CN" ] &&
  [ ! -e "$w/.delphi/parked/software" ] && [ -d "$w/workspaces/$AN" ] && [ ! -e "$w/linked" ] &&
  [ "$(git -C "$w" config "delphi.$AN.version")" = 0.7.0 ] && ! git -C "$w" config "delphi.$AO.version" >/dev/null &&
  ! git -C "$w" config "delphi.$CO.version" >/dev/null && [ "$(git -C "$w" config "delphi.$CN.version")" = "$VN" ] &&
  [ "$(git -C "$w" branch --show-current)" = "ws/$CN" ] && [ "$(git -C "$w" rev-parse --abbrev-ref '@{u}')" = "origin/ws/$CN" ]; } ||
  fail "0.8.0 did not rename to dotted names: $(cat "$t/out"); $(find "$w/.delphi/parked" "$w/workspaces"); $(git -C "$w" config --get-regexp '^delphi\.')"
{ /bin/bash "$w/.delphi/setup.sh" >"$t/out" 2>&1 && ! grep -q "moved\|renamed" "$t/out"; } || fail "setup.sh re-ran 0.8.0: $(cat "$t/out")"
{ git -C "$w" config "delphi.$CN.version" 0.7.0 && /bin/bash "$w/.delphi/setup.sh" >"$t/out" 2>&1 && ! grep -q "moved\|renamed" "$t/out"; } || fail "0.8.0 is not safe to re-run: $(cat "$t/out")"
ok "0.8.0 moves parked slots, linked/ws/<old> copies and version records to dotted names, and renames a clone's ws/<old> branch to ws/<name>, once"
mkdir -p "$w/repos/keep"
{ git -C "$w" checkout -q "$legacy" && [ -d "$w/repos/keep" ] && [ ! -e "$w/.delphi/parked/$CN" ] &&
  git -C "$w" checkout -q "ws/$CN" && [ -d "$w/repos/keep" ]; } || fail "moving between a workspace's old and new names parked it"
ok "checking out a workspace's old-named commit or its renamed branch moves nothing"
commit_on "ws/$CO" CLAUDE.md "old side" && commit_on "ws/$CN" .gitattributes "# new side"
{ sync >"$t/out" 2>&1 && grep -q "notice: ws/$CO, ws/$CN's old name, has commits ws/$CN lacks" "$t/out" &&
  ! o show "ws/$CN:CLAUDE.md" | grep -qx "old side"; } || fail "a diverged old name was merged or not reported: $(cat "$t/out")"
ok "an old name with commits of its own is reported, never merged"

# --- 13. portable harnesses: staged native output, round trips, transitions, bootstrap and authoring
mkdir -p "$t/metadata-variants"
cat >"$t/metadata-variants/source.md" <<'SKILL'
---
name: metadata-variants
allowed-tools:
- Read
- Bash
# A comment within the omitted value.
"user-invocable" : false
'disable-model-invocation': true
metadata:
  allowed-tools: preserve nested metadata
description: |-
  First line: useful
  Second line
---
Read CLAUDE.md.
SKILL
cat >"$t/metadata-variants/expected.md" <<'SKILL'
---
name: metadata-variants
metadata:
  allowed-tools: preserve nested metadata
description: |-
  First line: useful
  Second line
---
Read AGENTS.md.
SKILL
for indent in '' '  '; do
  sed "/^---$/!s/^/$indent/" "$t/metadata-variants/source.md" >"$t/metadata-variants/lf.md"
  sed "/^---$/!s/^/$indent/" "$t/metadata-variants/expected.md" >"$t/metadata-variants/want.md"
  for eol in lf crlf; do
    if [ "$eol" = crlf ]; then awk '{ printf "%s\r\n", $0 }' "$t/metadata-variants/lf.md" >"$t/metadata-variants/SKILL.md"
    else cp "$t/metadata-variants/lf.md" "$t/metadata-variants/SKILL.md"; fi
    bash -c 'source "$1"; harness_file codex "$2"' _ "$src/ci/harnesses.sh" "$t/metadata-variants/SKILL.md" >"$t/metadata-variants/actual.md"
    cmp -s "$t/metadata-variants/want.md" "$t/metadata-variants/actual.md" || fail "Codex metadata indentation/quotes/$eol"
    bash -c 'source "$1"; harness_file claude-code "$2"' _ "$src/ci/harnesses.sh" "$t/metadata-variants/SKILL.md" |
      cmp -s - "$t/metadata-variants/SKILL.md" || fail "Claude metadata bytes changed"
  done
done
ok "Codex metadata handles CRLF, quoted keys, indentless lists and root indentation; Claude stays byte-identical"
cat >"$t/native-metadata.md" <<'SKILL'
---
name: native-metadata
description: "Preserve: existing tool permissions and invocation settings."
allowed-tools:
  - Bash(git:*)
  - Bash(bash ${CLAUDE_SKILL_DIR}/scripts/helper.sh *)
user-invocable: false
disable-model-invocation: true
metadata:
  custom-setting: unchanged
---
Read CLAUDE.md before making changes.
SKILL
C=software/application-software/argos/workspaces/sandbox-codex CN=s.app.argos.sandbox-codex
# shellcheck disable=SC2016 # child shell expands its positional arguments
on_main "add Codex and inherited Claude skills" bash -c '
  mkdir -p "$1" software/workspace-inherit/.claude/skills/portable/scripts software/workspace-inherit/.claude/skills/native-metadata software/workspace-inherit/.claude/skills/switch-workspace
  cp "$2/templates/harnesses/codex/AGENTS.md" "$1/AGENTS.md"
  cp "$2/templates/workspace/.gitattributes" "$1/.gitattributes"
  mkdir -p "$1/.github/workflows"
  cp .github/workflows/delphi.yml "$1/.github/workflows/delphi.yml"
  printf "name: %s\nharness: codex\n" "$3" >"$1/workspace.yml"
  printf "portable v1\n" >software/workspace-inherit/.claude/skills/portable/SKILL.md
  printf "helper v1\n" >software/workspace-inherit/.claude/skills/portable/scripts/helper.sh
  cp "$4" software/workspace-inherit/.claude/skills/native-metadata/SKILL.md
  cp "$2/software/workspace-inherit/.claude/skills/switch-workspace/SKILL.md" software/workspace-inherit/.claude/skills/switch-workspace/SKILL.md
' _ "$C" "$src" "$CN" "$t/native-metadata.md"
sync "$CN" >"$t/out" 2>&1 || fail "Codex creation: $(cat "$t/out")"
for skill in top portable; do
  o cat-file -e "ws/$CN:.agents/skills/$skill/SKILL.md" || fail "Codex lacks native $skill"
done
! o cat-file -e "ws/$CN:.claude" 2>/dev/null || fail "Codex inherited Claude files"
[ "$(o rev-parse "ws/$CN^")" = "$(o rev-parse main)" ] || fail "Codex creation parent"
ok "refresh translates existing inherited Claude skills to Codex native paths only on the workspace branch"
! o cat-file -e "main:$C/.agents/skills" 2>/dev/null || fail "main contains inherited Codex skills"
! o cat-file -e "main:$C/workspace.generated" 2>/dev/null || fail "main contains Codex ownership metadata"
[ "$(o rev-parse "main:$C/AGENTS.md")" = "$(o rev-parse "ws/$CN:AGENTS.md")" ] || fail "Codex owned instructions changed"
ok "main keeps owned native instructions while refresh adds inherited output and ownership only to the branch"

sync refresh "$AN" >/dev/null
! o cat-file -e "main:$A/.claude/skills/native-metadata/SKILL.md" 2>/dev/null || fail "main contains an inherited Claude metadata copy"
cmp -s "$t/native-metadata.md" <(o show "ws/$AN:.claude/skills/native-metadata/SKILL.md") || fail "refresh changed Claude metadata"
cmp -s "$t/native-metadata.md" <(o show "main:software/workspace-inherit/.claude/skills/native-metadata/SKILL.md") || fail "translation changed the inherited Claude source"
ok "Claude source metadata, allowed-tools and invocation flags reach the branch byte for byte and remain canonical on main"
cat >"$t/codex-metadata.md" <<'SKILL'
---
name: native-metadata
description: "Preserve: existing tool permissions and invocation settings."
metadata:
  custom-setting: unchanged
---
Read AGENTS.md before making changes.
SKILL
cmp -s "$t/codex-metadata.md" <(o show "ws/$CN:.agents/skills/native-metadata/SKILL.md") || fail "Codex translation changed portable metadata or retained Claude-only fields"
ok "Codex translation omits Claude-only fields and block values while preserving portable metadata"
cmp -s "$src/software/workspace-inherit/.claude/skills/switch-workspace/SKILL.md" <(o show "ws/$AN:.claude/skills/switch-workspace/SKILL.md") || fail "Claude switching instructions changed"
o show "ws/$AN:.claude/skills/switch-workspace/SKILL.md" | grep -q 'No restart needed' || fail "Claude lost its hot reload workflow"
o show "ws/$CN:.agents/skills/switch-workspace/SKILL.md" | grep -q 'Start a fresh Codex session' || fail "Codex lacks native restart guidance"
! o show "ws/$CN:.agents/skills/switch-workspace/SKILL.md" | grep -q 'No restart needed' || fail "Claude reload behavior leaked into Codex"
ok "existing Claude plugin and hot reload guidance stays intact while Codex gets its own switch guidance"

# A workspace's target can change before its proposal merges; ownership must use that native recipe on every refresh.
for branch_target in claude-code codex; do
  if [ "$branch_target" = claude-code ]; then
    branch_instruction=CLAUDE.md; branch_previous=AGENTS.md; branch_skills=.claude/skills
  else
    branch_instruction=AGENTS.md; branch_previous=CLAUDE.md; branch_skills=.agents/skills
  fi
  (cd "$t/dev" && git fetch -q && git checkout -q -B branch-target "origin/ws/$CN" &&
    git mv "$branch_previous" "$branch_instruction" &&
    sed -i.bak "s/^harness:.*/harness: $branch_target/" workspace.yml && rm workspace.yml.bak &&
    printf '\nbranch-only target %s\n' "$branch_target" >>"$branch_instruction" &&
    git commit -qam "select branch-only $branch_target" && git push -q origin "HEAD:ws/$CN")
  sync refresh "$CN" >"$t/out" 2>&1 || fail "branch-only $branch_target refresh: $(cat "$t/out")"
  target_head=$(o rev-parse "ws/$CN")
  sync refresh "$CN" >"$t/out" 2>&1 || fail "repeated branch-only $branch_target refresh: $(cat "$t/out")"
  [ "$(o rev-parse "ws/$CN")" = "$target_head" ] || fail "repeated branch-only target refresh changed refs"
  commit_on "ws/$CN" "$branch_skills/portable/SKILL.md" "reset generated target edit"
  sync refresh "$CN" >"$t/out" 2>&1 || fail "branch-only target reset: $(cat "$t/out")"
  [ "$(o show "ws/$CN:$branch_skills/portable/SKILL.md")" = "portable v1" ] || fail "branch-only target lost trusted native ownership"
  sync propose "$CN" >"$t/out" 2>&1 || fail "branch-only $branch_target proposal: $(cat "$t/out")"
  ! o cat-file -e "propose/$CN:$C/$branch_skills/portable/SKILL.md" 2>/dev/null || fail "branch-only target proposed inherited output"
  ! o cat-file -e "propose/$CN:$C/workspace.generated" 2>/dev/null || fail "branch-only target proposed ownership metadata"
  o show "propose/$CN:$C/workspace.yml" | grep -qx "harness: $branch_target" || fail "branch-only target selection not proposed"
done
o show "main:$C/workspace.yml" | grep -qx 'harness: codex' || fail "branch-only target changed main before merge"
ok "unmerged harness changes survive repeated refresh, reset inherited edits and propose only owned native files in both directions"

commit_on "ws/$CN" .agents/skills/portable/SKILL.md "workspace edit"
commit_on "ws/$CN" AGENTS.md "workspace-owned instructions"
sync propose "$CN" >"$t/out" 2>&1 || fail "Codex proposal: $(cat "$t/out")"
! o cat-file -e "propose/$CN:$C/.agents/skills/portable/SKILL.md" 2>/dev/null || fail "managed skill edit proposed"
! o cat-file -e "propose/$CN:$C/workspace.generated" 2>/dev/null || fail "Codex ownership metadata proposed"
o show "propose/$CN:$C/AGENTS.md" | grep -qx "workspace-owned instructions" || fail "AGENTS.md not proposed"
sync refresh "$CN" >/dev/null
[ "$(o show "ws/$CN:.agents/skills/portable/SKILL.md")" = "portable v1" ] || fail "Codex inherited edit not reset"
ok "Codex proposals preserve native instructions and omit inherited skills and ledgers; refresh resets inherited edits"
on_main "remove shared helper" git rm -q software/workspace-inherit/.claude/skills/portable/scripts/helper.sh
sync refresh "$CN" >"$t/out" 2>&1 || fail "shared source update: $(cat "$t/out")"
! o cat-file -e "main:$C/.agents/skills/portable/SKILL.md" 2>/dev/null || fail "source update materialized inherited output on main"
ok "refresh reads canonical sources and adapters to stage changed native branch output"

! o cat-file -e "ws/$CN:.agents/skills/portable/scripts/helper.sh" 2>/dev/null || fail "stale inherited helper survived"
o show "ws/$CN:.agents/skills/top/SKILL.md" | grep -qx "top v3" || fail "shared source update lost skill"
ok "shared source updates keep native paths stable and remove obsolete inherited files"
# shellcheck disable=SC2016 # child shell expands its positional arguments
on_main "switch Codex workspace to Claude" bash -c '
  git mv "$1/AGENTS.md" "$1/CLAUDE.md"
  sed -i.bak "s/harness: codex/harness: claude-code/" "$1/workspace.yml"
  rm "$1/workspace.yml.bak"
  bash ci/plugins.sh >/dev/null
' _ "$C"
# The ws-owned AGENTS edit would conflict with main renaming it: resolve via a normal workspace PR first.
# Undo the test-only instruction change before the harness transition.
(cd "$t/dev" && git fetch -q && git checkout -q -B transition "origin/ws/$CN" &&
  git show "origin/main:$C/CLAUDE.md" >AGENTS.md && git commit -qam "prepare native instruction transition" &&
  git push -q origin "HEAD:ws/$CN")
sync refresh "$CN" >"$t/out" 2>&1 || fail "Codex to Claude: $(cat "$t/out")"
{ o cat-file -e "ws/$CN:.claude/skills/portable/SKILL.md" &&
  ! o cat-file -e "ws/$CN:.agents/skills/portable/SKILL.md" 2>/dev/null; } || fail "old native skill destination survived"
# shellcheck disable=SC2016 # child shell expands its positional arguments
on_main "switch workspace back to Codex" bash -c '
  git mv "$1/CLAUDE.md" "$1/AGENTS.md"
  git rm -q "$1/.claude/settings.json"
  printf "name: %s\nharness: codex\n" "$2" >"$1/workspace.yml"
' _ "$C" "$CN"
sync "$CN" >"$t/out" 2>&1 || fail "Claude to Codex: $(cat "$t/out")"
{ o cat-file -e "ws/$CN:.agents/skills/portable/SKILL.md" &&
  ! o cat-file -e "ws/$CN:.claude/settings.json" 2>/dev/null &&
  ! o cat-file -e "ws/$CN:.claude/skills/portable/SKILL.md" 2>/dev/null; } || fail "Claude files survived harness transition"
ok "harness transitions remove old native skill destinations and generated settings in both directions"
(cd "$t/dev" && git fetch -q && git checkout -q -B stale-settings "origin/ws/$CN" &&
  mkdir -p .claude && echo '{}' >.claude/settings.json && git add .claude/settings.json &&
  git commit -qm "stale settings from previous harness" && git push -q origin "HEAD:ws/$CN")
if sync "$CN" >"$t/out" 2>"$t/err"; then fail "unrecorded foreign native file proposed"; fi
grep -q 'belongs to a different harness' "$t/err" || fail "foreign native file not reported"
o cat-file -e "ws/$CN:.claude/settings.json" || fail "unrecorded file silently deleted"
(cd "$t/dev" && git fetch -q && git checkout -q -B remove-foreign "origin/ws/$CN" &&
  git rm -q .claude/settings.json && git commit -qm "remove foreign native configuration" && git push -q origin "HEAD:ws/$CN")
sync "$CN" >/dev/null 2>&1 || fail "sync after explicit foreign-file removal"
ok "unrecorded foreign files fail validation and require an explicit workspace edit"
commit_on "ws/$CN" workspace.yml "$(printf 'opt-out:\n  - .agents/skills/portable')"
commit_on "ws/$CN" .agents/skills/portable/SKILL.md "Codex own"
commit_on "ws/$CN" .agents/skills/portable/OWN.md "workspace-owned native file"
sync "$CN" >"$t/out" 2>&1 || fail "Codex opt-out: $(cat "$t/out")"
o show "propose/$CN:$C/.agents/skills/portable/OWN.md" | grep -qx "workspace-owned native file" || fail "Codex owned skill not proposed"
o show "ws/$CN:.agents/skills/portable/SKILL.md" | grep -qx "Codex own" || fail "Codex opt-out overwritten"
ok "Codex native opt-outs preserve editable and proposable workspace-owned skills"

(cd "$t/dev" && git fetch -q && git checkout -q -B tmp-main origin/main &&
  git merge -q --no-ff --no-edit "origin/propose/$CN" && git push -q origin HEAD:main)
sync refresh "$CN" >/dev/null
# A formerly opted-out skill is workspace-owned even after its shared source and opt-out are removed.
# shellcheck disable=SC2016 # child expands its arguments
on_main "retire shared skill without deleting owned copy" bash -c '
  git rm -rq software/workspace-inherit/.claude/skills/portable
  printf "name: %s\nharness: codex\n" "$2" >"$1/workspace.yml"
' _ "$C" "$CN"
sync "$CN" >"$t/out" 2>&1 || fail "retire owned skill source: $(cat "$t/out")"
o show "ws/$CN:.agents/skills/portable/SKILL.md" | grep -qx "Codex own" || fail "former opt-out owned skill was deleted"
ok "removing a shared source and old opt-out preserves the former workspace-owned skill"

# Helper commands initialize their layout independently of Codex or the caller's shell exports.
w=$t/codex && git clone -q -b "ws/$CN" "$t/origin.git" "$w"
# shellcheck disable=SC2016 # fresh shell must receive the exports
(cd "$t" && env -u DELPHI_ROOT -u DELPHI_REPOS -u DELPHI_WORKTREES bash "$w/.delphi/exec.sh" bash -c '
  set -e
  [ "$1" = "argument with spaces" ]
  [ "$PWD" != "$DELPHI_ROOT" ]
  [ -f "$DELPHI_ROOT/AGENTS.md" ]
  [ "$DELPHI_REPOS" = "$DELPHI_ROOT/repos" ]
  bash -c '\''[ "$DELPHI_WORKTREES" = "$DELPHI_ROOT/worktrees" ]'\''
' _ "argument with spaces") || fail "fresh host command wrapper"
ok "per-command bootstrap propagates layout to fresh shells and children while preserving arguments/cwd"
# Proxy capability selection uses stubs only, without GitHub/network access.
mkdir -p "$t/proxy-bin"
printf '#!/usr/bin/env bash\nexit 1\n' >"$t/proxy-bin/gh"
printf '#!/usr/bin/env bash\nprintf "proxy-response"\n' >"$t/proxy-bin/curl"
printf '#!/usr/bin/env bash\nexit 0\n' >"$t/proxy-bin/jq"
chmod +x "$t/proxy-bin/"*
provider=$src/software/application-software/workspace-inherit/.claude/skills/address-pr-comments/scripts/github.sh
# shellcheck disable=SC2016 # isolated shell sources helper and expands its variables
proxy=$(PATH="$t/proxy-bin:$PATH" DELPHI_GITHUB_REST_PROXY=1 CLAUDE_CODE_REMOTE='' bash -c '
  source "$1"; gh_init test "$2"; [ "$MODE" = rest ]; get repos/example/example
' _ "$provider" "$w") || fail "explicit REST proxy capability selection"
[ "$proxy" = proxy-response ] || fail "REST proxy did not use stubbed provider"
ok "shared GitHub helpers support an explicit REST-proxy capability without harness-specific environment detection"
# A Codex target consumes the single Claude-authored defaults bundle.
(cd "$t/dev" && git fetch -q && git checkout -q -B main origin/main &&
  tools/new-workspace.sh --harness codex electrical/firmware fw-codex >/dev/null) || fail "Codex new workspace"
F=software/electrical/firmware/workspaces/fw-codex
created=new-workspace/electrical/firmware/fw-codex
o show "$created:$F/workspace.yml" | grep -qx 'harness: codex' || fail "default harness not overridden"
o show "$created:$F/workspace.yml" | grep -q 'fw: https://example.com/fw.git' || fail "project repos lost"
o show "$created:$F/AGENTS.md" | grep -qx '# Firmware for s.electrical.firmware.fw-codex' || fail "Claude-authored instructions not translated"
o cat-file -e "$created:$F/.agents/skills/fw/SKILL.md" || fail "Claude-authored default skill not translated"
! o cat-file -e "$created:$F/.agents/skills/top/SKILL.md" 2>/dev/null || fail "main PR contains inherited native skill"
! o cat-file -e "$created:$F/workspace.generated" 2>/dev/null || fail "main PR contains branch ownership metadata"
{ ! o cat-file -e "$created:$F/CLAUDE.md" 2>/dev/null && ! o cat-file -e "$created:$F/.claude" 2>/dev/null; } || fail "Claude defaults leaked into Codex workspace"
(cd "$t/dev" && ! tools/new-workspace.sh --harness unknown electrical/firmware bad-harness >/dev/null 2>&1) || fail "unknown authoring harness accepted"
ok "Codex creation translates one Claude-authored defaults bundle into native files before its main PR"

# Changing a creation suggestion does not change the source format or any existing workspace.
# shellcheck disable=SC2016 # child shell edits the sandbox project's defaults
on_main "project suggests Codex" bash -c '
  sed -i.bak "s/harness: claude-code/harness: codex/" "$1/workspace.yml"
  rm "$1/workspace.yml.bak"
' _ "$FD"
(cd "$t/dev" && git fetch -q && git checkout -q -B main origin/main &&
  tools/new-workspace.sh electrical/firmware fw-project-codex >/dev/null) || fail "project-default Codex workspace"
F=software/electrical/firmware/workspaces/fw-project-codex
created=new-workspace/electrical/firmware/fw-project-codex
o show "$created:$F/workspace.yml" | grep -qx 'harness: codex' || fail "project suggestion ignored"
o show "$created:$F/AGENTS.md" | grep -qx '# Firmware for s.electrical.firmware.fw-project-codex' || fail "translated defaults lost"
o show "main:$FD/source.yml" | grep -qx 'format: claude-code' || fail "creation suggestion changed source format"
o show "main:$A/workspace.yml" | grep -qx 'harness: claude-code' || fail "existing workspace harness changed"
ok "creation suggestions stay independent of source format and existing workspace harnesses"

# A different source format feeds the same target adapters and unchanged branch model.
# shellcheck disable=SC2016 # child shell migrates the source bundle
on_main "author defaults in Codex format" bash -c '
  printf "format: codex\n" >"$1/source.yml"
  git mv "$1/CLAUDE.md" "$1/AGENTS.md"
  mkdir -p "$1/.agents/skills"
  git mv "$1/.claude/skills/fw" "$1/.agents/skills/fw"
' _ "$FD"
(cd "$t/dev" && git fetch -q && git checkout -q -B main origin/main &&
  tools/new-workspace.sh --harness claude-code electrical/firmware fw-project-claude >/dev/null) || fail "Claude target from Codex source"
F=software/electrical/firmware/workspaces/fw-project-claude
created=new-workspace/electrical/firmware/fw-project-claude
o show "$created:$F/workspace.yml" | grep -qx 'harness: claude-code' || fail "explicit harness did not override suggestion"
o show "$created:$F/workspace.yml" | grep -q 'fw: https://example.com/fw.git' || fail "project repos lost"
o show "$created:$F/CLAUDE.md" | grep -qx '# Firmware for s.electrical.firmware.fw-project-claude' || fail "Codex source instructions not translated"
o cat-file -e "$created:$F/.claude/skills/fw/SKILL.md" || fail "Codex source skill not translated"
{ ! o cat-file -e "$created:$F/AGENTS.md" 2>/dev/null && ! o cat-file -e "$created:$F/.agents" 2>/dev/null; } || fail "Codex files leaked into Claude target"
ok "changing source format preserves target adapters, owned native defaults and explicit workspace harnesses"

# Native settings require an explicit mapping, never silent removal.
# shellcheck disable=SC2016 # child shell adds a source-native configuration
on_main "Codex-native configuration default" bash -c 'mkdir -p "$1/.codex"; echo "# native settings" >"$1/.codex/config.toml"' _ "$FD"
(cd "$t/dev" && git fetch -q && git checkout -q -B main origin/main &&
  ! tools/new-workspace.sh --harness claude-code electrical/firmware unsupported >/dev/null 2>"$t/err") || fail "unsupported native settings silently accepted"
grep -q 'has no mapping to claude-code' "$t/err" || fail "unsupported mapping not reported"
[ -z "$(git -C "$t/dev" status --porcelain)" ] || fail "failed generation changed caller checkout"
ok "unsupported native settings fail explicitly and leave the caller checkout untouched"

(cd "$t/dev" && git fetch -q && git checkout -q -B main origin/main &&
  bash ci/render.sh --check && [ -z "$(git status --porcelain)" ] &&
  bash ci/render.sh >/dev/null && [ -z "$(git status --porcelain)" ]) || fail "main-side render was not idempotent"
ok "render checks do not write and repeated rendering leaves a valid main checkout unchanged"

# A pre-render branch has native copies but no ledger. Prove their old source provenance.
legacy_dev=$t/legacy-dev legacy_origin=$t/legacy-origin.git
git clone -q "$t/seed" "$legacy_dev"
(cd "$legacy_dev" && git rm -q ci/render.sh &&
  mkdir -p software/workspace-inherit/notes && echo old >software/workspace-inherit/notes/adoption.txt &&
  git add -A && git commit -qm "legacy main without managed ledgers")
legacy_base=$(git -C "$legacy_dev" rev-parse HEAD)
git clone -q --bare "$legacy_dev" "$legacy_origin"
git -C "$legacy_dev" remote set-url origin "$legacy_origin"
for legacy_name in "$AN" "$BN"; do
  legacy_folder=$A; [ "$legacy_name" != "$BN" ] || legacy_folder=$B
  legacy_blob=$(printf 'old\n' | git -C "$legacy_dev" hash-object -w --stdin)
  [ "$legacy_name" != "$BN" ] || legacy_blob=$(printf 'owned edit\n' | git -C "$legacy_dev" hash-object -w --stdin)
  GIT_INDEX_FILE=$t/legacy.index git -C "$legacy_dev" read-tree "$legacy_base:$legacy_folder"
  GIT_INDEX_FILE=$t/legacy.index git -C "$legacy_dev" read-tree --prefix=.delphi/ "$legacy_base:.delphi"
  GIT_INDEX_FILE=$t/legacy.index git -C "$legacy_dev" update-index --add --cacheinfo "100644,$legacy_blob,notes/adoption.txt"
  legacy_tree=$(GIT_INDEX_FILE=$t/legacy.index git -C "$legacy_dev" write-tree)
  legacy_head=$(printf 'legacy workspace\n' | git -C "$legacy_dev" commit-tree -p "$legacy_base" "$legacy_tree")
  git -C "$legacy_dev" push -q origin "$legacy_head:refs/heads/ws/$legacy_name"
done
(cd "$legacy_dev" && cp "$src/ci/render.sh" ci/render.sh && echo new >software/workspace-inherit/notes/adoption.txt &&
  bash ci/render.sh && git add -A && git commit -qm "prepare native output" && git push -q origin main &&
  bash ci/sync.sh refresh "$AN") >"$t/out" 2>"$t/err" || fail "legacy adoption: $(cat "$t/err")"
git -C "$legacy_origin" show "ws/$AN:notes/adoption.txt" | grep -qx new || fail "legacy source was not refreshed"
git -C "$legacy_origin" cat-file -e "ws/$AN:workspace.generated" || fail "legacy branch lacks ownership metadata"
ok "pre-ledger branches adopt unchanged old source copies before applying reviewed updates"
if (cd "$legacy_dev" && bash ci/sync.sh refresh "$BN") >"$t/out" 2>"$t/err"; then fail "ambiguous legacy edit overwritten"; fi
git -C "$legacy_origin" show "ws/$BN:notes/adoption.txt" | grep -qx 'owned edit' || fail "legacy edit was lost"
ok "ambiguous pre-ledger edits report a conflict and retain their content"

# Add a target only in its registry/template; adaptations of helpers must also be hashed natively.
d=$t/adapter-extension
mkdir "$d"
cp -R "$src/ci" "$src/software" "$src/templates" "$src/.github" "$src/.delphi" "$src/.claude-plugin" "$d/"
(cd "$d" && git init -q && git add -A && git commit -qm base)
cat >>"$d/ci/harnesses.sh" <<'ADAPTER'
eval "$(declare -f harness | sed '1s/harness/base_harness/')"
harness() {
  if [ "$1" = fixture ]; then
    instruction=TASKS.md; instruction_template=templates/harnesses/fixture/TASKS.md
    skills=.fixture/skills; plugins=none; foreign="CLAUDE.md .claude AGENTS.md .agents .codex"
  else base_harness "$1"; fi
}
eval "$(declare -f harness_file | sed '1s/harness_file/base_harness_file/')"
harness_file() {
  if [ "$1" = fixture ]; then
    cat "$2"
    case "$2" in */SKILL.md | */scripts/*.sh) printf '\n# fixture output\n' ;; esac
  else base_harness_file "$@"; fi
}
ADAPTER
F=software/application-software/argos/workspaces/fixture
mkdir -p "$d/$F" "$d/templates/harnesses/fixture"
cp -R "$d/templates/workspace/." "$d/$F/"
rm "$d/$F/CLAUDE.md"
printf 'Fixture instructions\n' >"$d/templates/harnesses/fixture/TASKS.md"
cp "$d/templates/harnesses/fixture/TASKS.md" "$d/$F/TASKS.md"
printf 'name: s.app.argos.fixture\nharness: fixture\n' >"$d/$F/workspace.yml"
chmod +x "$d/software/workspace-inherit/.claude/skills/journal/scripts/capture.sh"
(cd "$d" && bash ci/render.sh . "$t/fixture-stage" && git add -A && bash ci/check.sh . HEAD &&
  bash ci/render.sh . "$t/fixture-stage-again" && git diff --quiet) >"$t/out" 2>"$t/err" || fail "adapter extension: $(cat "$t/err")"
grep -qx '# fixture output' "$t/fixture-stage/$F/.fixture/skills/journal/SKILL.md" || fail "new target skill was not adapted"
grep -qx '# fixture output' "$t/fixture-stage/$F/.fixture/skills/journal/scripts/capture.sh" || fail "new target helper was not adapted"
[ -x "$t/fixture-stage/$F/.fixture/skills/journal/scripts/capture.sh" ] || fail "new target lost executable mode"
diff -qr "$t/fixture-stage" "$t/fixture-stage-again" >/dev/null || fail "new target staging was not deterministic"
[ ! -e "$d/$F/.fixture" ] && [ ! -e "$d/$F/workspace.generated" ] || fail "new target generated files on main"
while IFS=$'\t' read -r meta path _; do
  case "$meta" in '' | '#'* ) continue ;; esac
  [ "$(git -C "$d" hash-object -- "$t/fixture-stage/$F/$path")" = "${meta#* }" ] || fail "new target ledger did not hash native bytes"
done <"$t/fixture-stage/$F/workspace.generated"
ok "registry-only targets stage adapted skills and helpers with native hashes and modes without generating copies on main"
rm "$d/$F/TASKS.md"
echo 'must remain workspace-owned' >"$d/software/workspace-inherit/TASKS.md"
if (cd "$d" && bash ci/render.sh) >"$t/out" 2>"$t/err"; then fail "new target inherited its root instructions"; fi
grep -q "each workspace has its own TASKS.md" "$t/err" || fail "new target root protection not reported"
[ ! -e "$d/$F/TASKS.md" ] || fail "new target wrote inherited root instructions"
ok "registry-only targets protect their own instruction path even when its workspace file is missing"


# --- 14. shellcheck, if installed
if command -v shellcheck >/dev/null; then
  shellcheck "$src"/ci/*.sh "$src"/tools/*.sh "$src"/tests/*.sh "$src"/.delphi/*.sh "$src"/.delphi/migrations/*.sh ||
    fail "shellcheck"
  ok "shellcheck clean"
fi
echo "all $pass checks passed"
