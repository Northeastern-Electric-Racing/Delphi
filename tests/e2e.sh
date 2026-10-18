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
AN=software/application-software/argos/argos-dev BN=software/electrical/bms-dev # their names: folder path without workspaces/
V=$(awk '/^version:/ { print $2 }' "$src/.delphi/manifest.yml") # the current version; VN, the patch after it, is what the test releases
VN=${V%.*}.$((${V##*.} + 1))

# --- sandbox: seed repo -> bare origin; "ci" is the clone CI runs in, "dev" a person's clone
git init -q "$t/seed"
cp -R "$src/ci" "$src/tools" "$src/templates" "$src/.github" "$src/.delphi" "$src/README.md" "$t/seed/"
mkdir -p "$t/seed/$A" "$t/seed/$B"
cp -R "$src/$A/." "$t/seed/$A/"
cp -R "$src/templates/workspace/." "$t/seed/$B/"
sed -i.bak "s|{{name}}|$BN|" "$t/seed/$B/workspace.yml" && rm "$t/seed/$B/workspace.yml.bak"
FD=software/electrical/firmware/workspace-defaults # project defaults for new workspaces under electrical/firmware
mkdir -p "$t/seed/$FD/.claude/skills/fw"
printf 'harness: claude-code\nrepos:\n  fw: https://example.com/fw.git\n' >"$t/seed/$FD/workspace.yml"
printf '# Firmware for {{name}}\n' >"$t/seed/$FD/CLAUDE.md"
echo "fw skill" >"$t/seed/$FD/.claude/skills/fw/SKILL.md"
set_json() { # <folder> <set> <name>: a minimal plugin set
  mkdir -p "$1/plugins/claude/$2/.claude-plugin" && printf '{\n  "name": "%s"\n}\n' "$3" >"$1/plugins/claude/$2/.claude-plugin/plugin.json"
}
set_json "$t/seed/software/application-software" default app && echo app >"$t/seed/software/application-software/plugins/scope"
set_json "$t/seed/software/application-software/argos" default argos # default sets above argos-dev
TS=software/application-software/argos/plugins/claude/testing # an extra set a workspace can list under plugins:
mkdir -p "$t/seed/$TS/.claude-plugin" && printf '{\n  "name": "argos.testing"\n}\n' >"$t/seed/$TS/.claude-plugin/plugin.json"
(cd "$t/seed" && bash ci/plugins.sh >/dev/null) # the marketplace and each workspace's .claude/settings.json
git -C "$t/seed" add -A && git -C "$t/seed" commit -qm init
git clone -q --bare "$t/seed" "$t/origin.git"
git clone -q "$t/origin.git" "$t/ci"
git clone -q "$t/origin.git" "$t/dev"
sync() { (cd "$t/ci" && ci/sync.sh "$@"); }
o() { git -C "$t/origin.git" "$@"; }
# commit_on <branch> <file> <text>: a person's PR into <branch>, merged (edit on a branch, merge --no-ff)
commit_on() {
  (cd "$t/dev" && git fetch -q && git checkout -q -B "edit" "origin/$1" && printf '%s\n' "$3" >>"$2" &&
    git commit -qam "edit $2 on $1" && git checkout -q -B "tmp-$1" "origin/$1" &&
    git merge -q --no-ff --no-edit edit && git push -q origin "HEAD:$1")
}

# --- 1. first sync creates ws branches rooted at the folder, joined to main
sync >"$t/out"
main=$(o rev-parse main)
for w in "$A" "$B"; do
  n=${w%/workspaces/*}/${w##*/}
  o diff --quiet "main:$w" "ws/$n" -- ':!.delphi' || fail "ws/$n root != $w"
  [ "$(o rev-parse "ws/$n:.delphi")" = "$(o rev-parse main:.delphi)" ] || fail "ws/$n lacks main's .delphi/"
  [ "$(o rev-parse "ws/$n^")" = "$main" ] || fail "ws/$n parent is not main"
  [ "$(o log -1 --format=%s "ws/$n")" = "delphi: create ws/$n from $w" ] || fail "ws/$n message"
  o cat-file -e "ws/$n:workspace.yml" || fail "ws/$n lacks workspace.yml"
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
o diff --quiet "main:$B" ws/$BN -- ":!.delphi" || fail "bms-dev drifted"
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

# --- 4c. .claude/settings.json is generated: refresh writes it from the ws branch's workspace.yml
for p in app argos; do
  o show "ws/$AN:.claude/settings.json" | grep -q "\"$p@delphi\": true" || fail "argos-dev lacks the $p default set"
done
! o show "ws/$BN:.claude/settings.json" | grep -q enabledPlugins || fail "bms-dev enables plugins with none above it"
# shellcheck disable=SC2016 # the hook expands them
o show "ws/$BN:.claude/settings.json" | grep -qF '"command": "bash \"$CLAUDE_PROJECT_DIR/.delphi/paths.sh\" >> \"$CLAUDE_ENV_FILE\""' ||
  fail "bms-dev's settings.json lacks the SessionStart hook that sets DELPHI_ROOT"
ok "each workspace's settings.json enables the default set of every folder above it"
for p in app argos; do
  o show "ws/$AN:workspace.yml" | grep -Eq "^  - $p +# default, from " || fail "argos-dev's workspace.yml doesn't list the $p default"
done
commit_on ws/$AN workspace.yml "$(printf 'plugins:\n  - app   # by hand')"
(cd "$t/dev" && git fetch -q && git checkout -q -B drop origin/ws/$AN && sed -i.bak '/^  - argos .*# default, from /d' workspace.yml &&
  rm workspace.yml.bak && git commit -qam "drop the argos default" && git push -q origin HEAD:ws/$AN)
sync "$AN" >"$t/out" 2>&1 || fail "sync after dropping a default failed: $(cat "$t/out")"
o show "ws/$AN:workspace.yml" | grep -Eq "^  - argos +# default, from " || fail "dropped default not listed again"
[ "$(o show "ws/$AN:workspace.yml" | grep -c '^  - app ')" = 1 ] || fail "hand-listed default not folded into the generated line"
[ "$(o log -1 --format=%s ws/$AN)" = "delphi: generate plugins: defaults and .claude/settings.json" ] || fail "no generate commit for the yml"
ok "refresh lists every default set first under plugins: on ws/*, restoring a removed one and folding in a hand-listed one"
commit_on ws/$AN workspace.yml "$(printf 'plugins:\n  - argos.testing')"
sync "$AN" >"$t/out" 2>&1 || fail "sync after listing a plugin set failed: $(cat "$t/out")"
o show "ws/$AN:.claude/settings.json" | grep -q '"argos.testing@delphi": true' || fail "listed set not enabled"
[ "$(o log -1 --format=%s ws/$AN)" = "delphi: generate plugins: defaults and .claude/settings.json" ] || fail "no generate commit"
o show "propose/$AN:$A/.claude/settings.json" | grep -q argos.testing || fail "proposal lacks the generated settings"
ok "a set listed under plugins: on ws/* is enabled by refresh's generated settings.json and proposed with it"
commit_on ws/$AN .claude/settings.json "hand edit"
sync "$AN" >"$t/out" 2>&1 || fail "sync after a settings.json hand edit failed: $(cat "$t/out")"
! o show "ws/$AN:.claude/settings.json" | grep -qx "hand edit" || fail "hand edit to settings.json kept"
ok "a hand edit to .claude/settings.json on ws/* is reset by refresh"
commit_on ws/$AN workspace.yml "  - argos.nope"
ws=$(o rev-parse ws/$AN)
if sync "$AN" >"$t/out" 2>"$t/err"; then fail "sync with an unknown plugin set exited 0"; fi
grep -q "ws/$AN: plugins: .* lists argos.nope, which isn't a plugin set" "$t/err" || fail "unknown set not reported: $(cat "$t/err")"
(cd "$t/dev" && git fetch -q && git checkout -q -B fix origin/ws/$AN && sed -i.bak '/nope/d' workspace.yml && rm workspace.yml.bak &&
  git commit -qam "drop unknown set" && git push -q origin HEAD:ws/$AN)
sync "$AN" >/dev/null 2>&1 || fail "sync after dropping the unknown set failed"
ok "an unknown set under plugins: is reported, exit 1, until fixed"

# --- 4d. workspace-inherit/: every workspace below a folder gets its files on refresh, never proposes them, and can opt out
on_main() { # <message> <command...>: a change on main, pushed
  local m=$1 && shift
  (cd "$t/dev" && git fetch -q && git checkout -q -B tmp-main origin/main && "$@" && git add -A && git commit -qm "$m" && git push -q origin HEAD:main)
}
TI=software/workspace-inherit/.claude/skills/top AI=software/application-software/workspace-inherit/notes
on_main "inherit" sh -c "mkdir -p $TI $AI && echo 'top v1' >$TI/SKILL.md && echo 'app v1' >$AI/app.md"
sync >"$t/out" 2>&1 || fail "sync after adding workspace-inherit/ failed: $(cat "$t/out")"
for n in "$AN" "$BN"; do o show "ws/$n:.claude/skills/top/SKILL.md" | grep -qx "top v1" || fail "ws/$n lacks software/workspace-inherit/"; done
o show "ws/$AN:notes/app.md" | grep -qx "app v1" || fail "ws/$AN lacks application-software/workspace-inherit/"
! o cat-file -e "ws/$BN:notes/app.md" 2>/dev/null || fail "ws/$BN inherited from a folder it isn't under"
[ "$(o log -1 --format=%s ws/$BN)" = "delphi: sync inherited files from main" ] || fail "no inherit commit on ws/$BN"
! o cat-file -e "propose/$AN:$A/.claude/skills/top/SKILL.md" 2>/dev/null || fail "inherited file proposed"
ok "refresh writes every workspace-inherit/ folder above a workspace onto ws/<name>, and only those"
commit_on ws/$AN .claude/skills/top/SKILL.md "ws edit"
sync "$AN" >"$t/out" 2>&1 || fail "sync after a ws edit to an inherited file failed: $(cat "$t/out")"
[ "$(o show "ws/$AN:.claude/skills/top/SKILL.md")" = "top v1" ] || fail "ws edit to an inherited file not reset"
! o cat-file -e "propose/$AN:$A/.claude/skills/top/SKILL.md" 2>/dev/null || fail "ws edit to an inherited file proposed"
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
expect_bad no-harness "harness is missing" sh -c "sed -i.bak 's/^harness:.*//' $A/workspace.yml && rm $A/workspace.yml.bak"
expect_bad duplicate-harness "duplicate harness" sh -c "printf 'harness: x\n' >>$A/workspace.yml"
expect_bad bad-repo "bad repos entry" sh -c "awk '{ print } /^repos:/ { print \"  ../x: y\" }' $A/workspace.yml >$A/y && mv $A/y $A/workspace.yml"
expect_bad bad-reference "bad references-git entry" sh -c "printf 'references-git:\n  x: url ref extra\n' >>$A/workspace.yml"
expect_bad reference-repo-clash "duplicate repo: argos" sh -c "printf 'references-git:\n  argos: https://example.com/a.git\n' >>$A/workspace.yml"
expect_bad bad-key "unexpected line" sh -c "printf 'color: x\n' >>$A/workspace.yml"
expect_bad wrong-name "the folder path without workspaces/" sh -c "sed -i.bak 's/^name:.*/name: other/' $A/workspace.yml && rm $A/workspace.yml.bak"
expect_bad no-name "name is missing" sh -c "sed -i.bak '/^name:/d' $A/workspace.yml && rm $A/workspace.yml.bak"
expect_bad defaults-name "workspace-defaults/workspace.yml: unexpected line: name:" sh -c "printf 'name: x\n' >>${A%/workspaces/*}/workspace-defaults/workspace.yml"
expect_bad park-list-path ".delphi/park.list: 'a/b' must be a folder name" sh -c "echo a/b >>.delphi/park.list"
expect_bad park-list-core ".delphi/park.list: must list linked" sh -c "grep -v '^linked' .delphi/park.list >p && mv p .delphi/park.list"
expect_bad folder-delphi "$A/.delphi: managed in the root" sh -c "mkdir $A/.delphi && cp .delphi/park.sh $A/.delphi/"
expect_bad ref-clash "can't be a branch while ws/$AN is" sh -c "mkdir -p software/application-software/workspaces && cp -R $A software/application-software/workspaces/argos &&
  sed -i.bak 's|^name:.*|name: software/application-software/argos|' software/application-software/workspaces/argos/workspace.yml"
expect_bad nested "nested inside" sh -c "mkdir -p $A/docs/workspaces/inner && cp $A/workspace.yml $A/docs/workspaces/inner/"
expect_bad bad-name "must be lowercase letters, digits, '-' and '/'" sh -c "mkdir -p software/x/workspaces && cp -R $A software/x/workspaces/Bad_Name"
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
expect_bad migration-patch "$VN has a migration, so it must bump MINOR" release "$VN" x
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
expect_bad inherited-file-kept "$A/.claude/skills/journal/SKILL.md: inherited from software/workspace-inherit/" sh -c "mkdir -p $A/.claude/skills/journal && echo x >$A/.claude/skills/journal/SKILL.md"
expect_bad inherited-twice "also inherits it from a folder above" sh -c "mkdir -p software/application-software/workspace-inherit/.claude/skills/journal && echo x >software/application-software/workspace-inherit/.claude/skills/journal/SKILL.md"
expect_bad inherited-claude-md "software/workspace-inherit/CLAUDE.md: each workspace has its own" sh -c "echo x >software/workspace-inherit/CLAUDE.md"
expect_bad inherit-in-workspace "belongs in an org or project folder" sh -c "mkdir -p $A/workspace-inherit && echo x >$A/workspace-inherit/f"
expect_bad bad-opt-out "bad opt-out entry" sh -c "printf 'opt-out:\n  - ../x\n' >>$A/workspace.yml"
expect_bad opt-out-nothing "opt-out: nope is nothing it inherits" sh -c "printf 'opt-out:\n  - nope\n' >>$A/workspace.yml"
d=$t/chk-opt-out && rm -rf "$d" && mkdir "$d" && cp -R "$src/software" "$src/templates" "$src/.github" "$src/.delphi" "$src/.claude-plugin" "$d/"
(cd "$d" && git init -q && mkdir -p $A/.claude/skills/journal && echo x >$A/.claude/skills/journal/SKILL.md &&
  printf 'opt-out:\n  - .claude/skills/journal/\n' >>$A/workspace.yml && git add -A && git commit -qm base)
"$src/ci/check.sh" "$d" >/dev/null 2>&1 || fail "check fails on a workspace keeping an inherited path it opts out of"
ok "a workspace may keep its own copy of an inherited path it lists under opt-out:"
expect_bad links-renamed "links: is now workspaces:" sh -c "sed -i.bak 's/^workspaces:/links:/' $A/workspace.yml && rm $A/workspace.yml.bak"
expect_bad bad-workspaces-entry "bad workspaces entry" sh -c "printf '  - argos-dev\n' >>$A/workspace.yml"
expect_bad duplicate-workspace "duplicate workspace: main" sh -c "printf '  - main\n' >>$A/workspace.yml"
expect_bad lists-itself "lists itself: ws/$AN" sh -c "printf '  - ws/$AN\n' >>$A/workspace.yml"
expect_bad unknown-workspace "lists ws/software/nope/x, which isn't a workspace on main" sh -c "printf '  - ws/software/nope/x\n' >>$A/workspace.yml"
expect_bad template-delphi "templates/workspace/.delphi: scripts live only" mkdir templates/workspace/.delphi
expect_bad template-workflow-drift "differs from .github/workflows/delphi.yml" sh -c "echo x >>.github/workflows/delphi.yml"
d=$t/chk-same-leaf && rm -rf "$d" && mkdir "$d" && cp -R "$src/software" "$src/templates" "$src/.github" "$src/.delphi" "$src/.claude-plugin" "$d/"
mkdir -p "$d/software/x/workspaces" && cp -R "$d/$A" "$d/software/x/workspaces/"
sed -i.bak 's|^name:.*|name: software/x/argos-dev|' "$d/software/x/workspaces/argos-dev/workspace.yml" && rm "$d/software/x/workspaces/argos-dev/workspace.yml.bak"
bash "$src/ci/plugins.sh" "$d" >/dev/null # its settings.json: no plugin sets above software/x
{ (cd "$d" && git init -q && git add -A) && "$src/ci/check.sh" "$d" >/dev/null; } || fail "two workspaces ending in the same name failed check"
ok "workspaces in different places may end in the same name (software/x/argos-dev beside $AN)"

# --- 8. setup.sh fetches workspace.yml repos into repos/<repo>, checks out the default branch under worktrees/, and is idempotent
for r in lib1 lib2; do
  git init -q "$t/$r" && git -C "$t/$r" commit -q --allow-empty -m "$r" && git clone -q --bare "$t/$r" "$t/$r.git"
done
def=$(git -C "$t/lib1" branch --show-current)
git clone -q -b ws/$AN "$t/origin.git" "$t/ws"
printf 'name: software/application-software/argos/argos-dev\nharness: claude-code\nplugins:\n  - x.y\nrepos:\n  # a comment\n  lib1: %s  # trailing\n  lib2: %s\n' \
  "$t/lib1.git" "$t/lib2.git" >"$t/ws/workspace.yml"
/bin/bash "$t/ws/.delphi/setup.sh" >/dev/null 2>&1 || fail "setup.sh failed"
/bin/bash "$t/ws/.delphi/setup.sh" >"$t/out" 2>&1 || fail "setup.sh re-run failed"
for r in lib1 lib2; do
  [ "$(git -C "$t/ws/worktrees/$r/$def" rev-parse HEAD)" = "$(git -C "$t/$r" rev-parse HEAD)" ] || fail "$r default worktree missing"
  [ "$(git -C "$t/ws/worktrees/$r/$def" branch --show-current)" = "$def" ] || fail "$r default worktree not on $def"
done
[ "$(git -C "$t/ws/repos/lib1" rev-parse --is-bare-repository)" = true ] || fail "repos/lib1 not a bare store"
grep -q "repos/lib1: already present" "$t/out" || fail "re-run did not skip"
for d in /repos/ /worktrees/ /.journal/ /.playwright-mcp/ /pictures/ .DS_Store; do [ "$(grep -cx "$d" "$t/ws/.git/info/exclude")" = 1 ] || fail "$d not excluded exactly once"; done
mkdir -p "$t/ws/.playwright-mcp" "$t/ws/pictures/b" "$t/ws/docs" && touch "$t/ws/.playwright-mcp/p.yml" "$t/ws/pictures/b/s.png" "$t/ws/.DS_Store" "$t/ws/docs/.DS_Store"
[ "$(git -C "$t/ws" status --porcelain)" = " M workspace.yml" ] || fail "repos/, worktrees/ or a tool's files show in status: $(git -C "$t/ws" status --porcelain)"
rm -rf "$t/ws/worktrees/lib2" && git -C "$t/ws/repos/lib2" worktree prune && /bin/bash "$t/ws/.delphi/setup.sh" >/dev/null 2>&1 &&
  [ -d "$t/ws/worktrees/lib2/$def" ] || fail "re-run did not restore a missing default worktree"
ok "setup.sh makes a bare store in repos/ plus a default-branch worktree in worktrees/, excludes both (and tools' files) once, and is idempotent"
w=$t/legacy && git clone -q -b ws/$AN "$t/origin.git" "$w" && cp "$t/ws/workspace.yml" "$w/" && git clone -q "$t/lib1.git" "$w/repos/lib1"
/bin/bash "$w/.delphi/setup.sh" >/dev/null 2>"$t/err" || fail "setup.sh failed on a pre-existing clone"
{ grep -q "could not check out worktrees/lib1/$def" "$t/err" && [ -d "$w/worktrees/lib2/$def" ]; } || fail "pre-existing clone not reported"
ok "setup.sh warns and carries on when repos/<repo> is an older plain clone"
git clone -q -c core.autocrlf=true -b ws/$AN "$t/origin.git" "$t/ws-crlf"
cp "$t/ws/workspace.yml" "$t/ws-crlf/"
/bin/bash "$t/ws-crlf/.delphi/setup.sh" >/dev/null 2>"$t/err" || fail "setup.sh fails with core.autocrlf=true"
! grep -q "as released" "$t/err" || fail "core.autocrlf=true changed .delphi/'s version hash"
ok "setup.sh runs in a core.autocrlf=true clone (Git Bash default), thanks to .gitattributes"

# --- 8b. references-git: shallow, detached, push-disabled checkouts under references/, refreshed on re-run
git -C "$t/lib2" tag lib2@v1 && git -C "$t/lib2" commit -q --allow-empty -m "after v1" && git -C "$t/lib2" push -q "$t/lib2.git" --all && git -C "$t/lib2" push -q "$t/lib2.git" --tags
git -C "$t/lib1" commit -q --allow-empty -m "lib1 two" && git -C "$t/lib1" push -q "$t/lib1.git" --all
w=$t/refs && git clone -q -b ws/$AN "$t/origin.git" "$w"
printf 'name: software/application-software/argos/argos-dev\nharness: claude-code\nreferences-git:\n  lib1: file://%s\n  lib2: file://%s lib2@v1  # pinned, monorepo-style tag\n' "$t/lib1.git" "$t/lib2.git" >"$w/workspace.yml"
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

# --- 8c. park.sh: switching to another workspace or main parks repos/, worktrees/, references/, linked/ in the
# git-ignored .delphi/parked/ and restores them, same paths, when the workspace comes back; same-workspace branches don't move
w=$t/park && git clone -q -b ws/$AN "$t/origin.git" "$w"
local_ws() { # <branch> <ws branch> <name> <repo>: a local branch of <ws branch> whose workspace.yml lists <repo>
  git -C "$w" checkout -q -b "$1" "origin/$2" && printf 'name: %s\nharness: claude-code\nrepos:\n  %s: %s\nreferences-git:\n  %s-ref: file://%s\nworkspaces:\n  - main\n' \
    "$3" "$4" "$t/$4.git" "$4" "$t/$4.git" >"$w/workspace.yml" && git -C "$w" commit -qam "$1" && /bin/bash "$w/.delphi/setup.sh" >/dev/null 2>&1
}
live() { [ -d "$w/worktrees/$1/$def" ] && [ "$(git -C "$w/worktrees/$1/$def" branch --show-current)" = "$def" ] &&
  ! git -C "$w/repos/$1" worktree list --porcelain | grep -q prunable && git -C "$w/references/$1-ref" rev-parse -q HEAD >/dev/null &&
  [ -f "$w/linked/main/ci/sync.sh" ]; }
local_ws a1 "ws/$AN" "$AN" lib1 || fail "park: setup on argos-dev failed"
ours() { [ ! -L "$w/.git/hooks/post-checkout" ] && grep -qx '\[ ! -f .delphi/park.sh \] || exec bash .delphi/park.sh "$@"' "$w/.git/hooks/post-checkout"; }
ours || fail "setup.sh did not write the hook that runs .delphi/park.sh"
{ git -C "$w" checkout -q -b a2 && live lib1 && [ ! -e "$w/.delphi/parked" ]; } || fail "park: same-workspace branch moved clones"
mkdir -p "$w/.journal/ideas" "$w/pictures/a2" && touch "$w/.journal/ideas/n.md" "$w/pictures/a2/s.png"
local_ws b1 "ws/$BN" "$BN" lib2 || fail "park: setup on bms-dev failed"
{ [ ! -e "$w/.journal" ] && [ ! -e "$w/pictures" ] && [ -f "$w/.delphi/parked/$AN/.journal/ideas/n.md" ] &&
  [ -f "$w/.delphi/parked/$AN/pictures/a2/s.png" ]; } || fail "park: .journal/ and pictures/ not parked with argos-dev"
{ [ ! -e "$w/worktrees/lib1" ] && [ ! -e "$w/references/lib1-ref" ] && [ -d "$w/.delphi/parked/$AN/worktrees/lib1/$def" ] &&
  [ -d "$w/.delphi/parked/$AN/linked/main/.git" ] && live lib2; } ||
  fail "park: argos-dev not parked on bms-dev"
[ -z "$(git -C "$w" status --porcelain)" ] || fail "park: parked clones show in status: $(git -C "$w" status --porcelain)"
{ git -C "$w" checkout -q main && [ ! -e "$w/repos" ] && [ ! -e "$w/worktrees" ] && [ ! -e "$w/references" ] && [ ! -e "$w/linked" ]; } ||
  fail "park: clones visible on main: $(ls -A "$w")"
[ -z "$(git -C "$w" status --porcelain)" ] || fail "park: main not clean"
{ git -C "$w" checkout -q a2 && live lib1 && [ ! -e "$w/worktrees/lib2" ] && [ -d "$w/.delphi/parked/$BN/repos/lib2" ] &&
  [ ! -e "$w/.delphi/parked/$AN" ]; } ||
  fail "park: argos-dev not restored"
{ [ -f "$w/.journal/ideas/n.md" ] && [ -f "$w/pictures/a2/s.png" ]; } || fail "park: .journal/ and pictures/ not restored"
git -C "$w/worktrees/lib1/$def" commit -q --allow-empty -m "after restore" || fail "park: restored worktree unusable"
{ git -C "$w" checkout -q b1 && live lib2 && git -C "$w" checkout -q a1 && live lib1; } || fail "park: second round trip"
git -C "$w" checkout -q main && mkdir "$w/worktrees" && git -C "$w" checkout -q a1 2>"$t/err"
{ grep -q "worktrees/ is in the way" "$t/err" && [ -d "$w/repos/lib1" ] && [ -d "$w/.delphi/parked/$AN/worktrees" ]; } ||
  fail "park: a folder in the way was not reported and kept: $(cat "$t/err")"
{ rmdir "$w/worktrees" && git -C "$w" checkout -q main && git -C "$w" checkout -q a1 && live lib1; } || fail "park: no recovery once cleared"
ok "park.sh parks a workspace's clones on switching to another workspace or main and restores them at the same paths"
ok "parked clones sit git-ignored in .delphi/parked/<name>/, the workspace's place in the tree"
ok "park.sh moves every folder .delphi/park.list names (.journal/, pictures/ too), not a fixed set"
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
F=software/electrical/firmware/workspaces/fw-dev
o cat-file -e "new-workspace/electrical/firmware/fw-dev:$F/workspace.yml" || fail "no workspace.yml on new-workspace/electrical/firmware/fw-dev"
o show "new-workspace/electrical/firmware/fw-dev:$F/CLAUDE.md" | grep -q "branch \`ws/software/electrical/firmware/fw-dev\`" || fail "CLAUDE.md not filled in"
! o show "new-workspace/electrical/firmware/fw-dev:$F/CLAUDE.md" | grep -q "{{" || fail "placeholder left"
o show "new-workspace/electrical/firmware/fw-dev:$F/CLAUDE.md" | grep -qx "# Firmware for software/electrical/firmware/fw-dev" || fail "defaults CLAUDE.md not appended"
[ "$(o show "new-workspace/electrical/firmware/fw-dev:$F/workspace.yml")" = "$(printf 'name: software/electrical/firmware/fw-dev\n'; o show "main:$FD/workspace.yml")" ] ||
  fail "defaults workspace.yml not used, or name: not set"
o cat-file -e "new-workspace/electrical/firmware/fw-dev:$F/.claude/skills/fw/SKILL.md" || fail "defaults skill not copied"
o cat-file -e "new-workspace/electrical/firmware/fw-dev:$F/.claude/settings.json" || fail "new workspace has no generated settings.json"
! o cat-file -e "new-workspace/electrical/firmware/fw-dev:$F/.claude/skills/top/SKILL.md" 2>/dev/null || fail "an inherited skill was copied into the folder"
grep -q "gh pr create --base main --head new-workspace/electrical/firmware/fw-dev --title Add workspace software/electrical/firmware/fw-dev --label by: ai --body ## Changes" "$t/gh.log" ||
  fail "no PR for new workspace, or not labelled by: ai with the template's sections: $(cat "$t/gh.log")"
(cd "$t/dev" && tools/new-workspace.sh --by ai-assisted electrical/firmware fw-two >/dev/null) || fail "new-workspace.sh --by failed"
grep -q "fw-two --label by: ai-assisted " "$t/gh.log" || fail "--by ai-assisted not used for the label"
(cd "$t/dev" && ! tools/new-workspace.sh --by bot electrical/firmware fw-three 2>/dev/null) || fail "bad --by accepted"
(cd "$t/dev" && ! tools/new-workspace.sh application-software/argos argos-dev 2>/dev/null) || fail "duplicate workspace accepted"
(cd "$t/dev" && ! tools/new-workspace.sh x Bad 2>/dev/null) || fail "bad name accepted"
(cd "$t/dev" && ! tools/new-workspace.sh ../x ok 2>/dev/null) || fail "bad org path accepted"
[ -z "$(git -C "$t/dev" status --porcelain)" ] || fail "new-workspace touched the checkout"
ok "new-workspace.sh opens a PR with the templated folder; rejects duplicates and bad input"
ok "new-workspace.sh adds the project's workspace-defaults/ (CLAUDE.md appended, placeholders filled), not inherited files"
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
printf 'name: software/electrical/bms-dev\nharness: claude-code\nrepos:\n  code: %s\n' "$t/code" >"$w/workspace.yml"
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
ok "new-worktree.sh makes new branches from the default or <base>, checks out existing ones, reuses on rerun"
# skill scripts read the workspace from $DELPHI_ROOT (the session hook evals paths.sh's export line) and every folder from paths.sh
(. "$w/.delphi/paths.sh" && [ "$DELPHI_ROOT" = "$w" ] && [ "$DELPHI_REPOS" = "$w/repos" ] &&
  [ "$DELPHI_WORKTREES" = "$w/worktrees" ] && [ "$DELPHI_REFERENCES" = "$w/references" ] && [ "$DELPHI_LINKED" = "$w/linked" ]) ||
  fail "paths.sh layout"
[ "$(cd "$t" && eval "$(bash "$w/.delphi/paths.sh")" && echo "$(printenv DELPHI_ROOT) $(printenv DELPHI_LINKED)")" = "$w $w/linked" ] ||
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

# --- 12. workspaces: setup.sh checks out listed workspaces and main read-only at linked/<branch>, refreshed on re-run;
# migrations: setup.sh runs the pending ones (0.0.1 replaces old link.sh worktrees), stopping where one can't go on safely
printf 'name: software/electrical/bms-dev\nharness: claude-code\nrepos:\n  code: %s\nworkspaces:\n  - ws/software/application-software/argos/argos-dev  # a comment\n  - main\n  - ws/software/electrical/bms-dev\n  - Bad\n' \
  "$t/code" >"$w/workspace.yml"
bash "$w/.delphi/setup.sh" >/dev/null 2>"$t/err" || fail "setup.sh failed with links: $(cat "$t/err")"
[ "$(git -C "$w/linked/ws/$AN" rev-parse HEAD)" = "$(o rev-parse "ws/$AN")" ] || fail "copy not at ws/$AN"
[ -f "$w/linked/main/ci/sync.sh" ] || fail "link main"
{ [ ! -e "$w/linked/ws/$BN" ] && [ ! -e "$w/linked/Bad" ] && grep -q "skipping bad workspaces: entry 'Bad'" "$t/err"; } || fail "copied itself or a bad entry"
! git -C "$w/linked/ws/$AN" push -q origin HEAD:refs/heads/x 2>/dev/null || fail "push from a link succeeded"
commit_on ws/$AN docs/CONTEXT.md "linked update"
{ bash "$w/.delphi/setup.sh" >/dev/null 2>&1 && grep -qx "linked update" "$w/linked/ws/$AN/docs/CONTEXT.md"; } || fail "re-run did not refresh a link"
[ "$(grep -cx /linked/ "$w/.git/info/exclude")" = 1 ] || fail "/linked/ not excluded exactly once"
! git -C "$w" status --porcelain | grep -q linked || fail "linked/ shows in status"
ok "setup.sh checks out workspaces: read-only at linked/<branch>, skips itself and bad entries, refreshes on re-run"
[ "$(git -C "$w" config delphi.$BN.version)" = "$VN" ] || fail "setup.sh did not record the version"
old_link() { rm -rf "$w/linked/main" && git -C "$w" worktree add -q --detach "$w/linked/main" origin/main && git -C "$w" config --unset delphi.$BN.version; }
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
{ /bin/bash "$w/.delphi/setup.sh" >/dev/null 2>"$t/err" && [ -f "$w/linked/main/.git" ] && grep -q "linked/main is a worktree" "$t/err"; } ||
  fail "a migration ran again, or setup.sh wrote into a worktree: $(cat "$t/err")"
ok "a recorded version's migrations don't run again; setup.sh never writes into a worktree in linked/"
git -C "$w" config --unset delphi.$BN.version
{ /bin/bash "$w/.delphi/setup.sh" >"$t/out" 2>&1 && grep -q "migrating $BN to 0.0.1" "$t/out" && [ -d "$w/linked/main/.git" ] &&
  [ -f "$w/linked/main/ci/sync.sh" ] && ! git -C "$w" worktree list | grep -q linked &&
  [ "$(git -C "$w" config delphi.$BN.version)" = "$VN" ]; } || fail "0.0.1 did not replace an old link.sh worktree: $(cat "$t/out")"
ok "setup.sh runs pending migrations (0.0.1: an old link.sh worktree in linked/ becomes a read-only copy) and records the version"
echo "# local" >>"$w/.delphi/switch.sh"
{ /bin/bash "$w/.delphi/setup.sh" >/dev/null 2>"$t/err" && grep -q "not Delphi $VN as released" "$t/err"; } || fail "setup.sh did not warn about an edited .delphi/"
git -C "$w" checkout -q .delphi/switch.sh
ok "setup.sh warns when .delphi/ isn't the version it says"

# --- 12b. switch.sh: refuses a dirty root; switches workspaces (parking and restoring), fast-forwards, sets up; main too
(cd "$t/dev" && git fetch -q && git checkout -q -B sw origin/ws/$AN &&
  printf 'name: software/application-software/argos/argos-dev\nharness: claude-code\nrepos:\n  lib1: %s\nworkspaces:\n  - main\n' "$t/lib1.git" >workspace.yml &&
  git commit -qam "local repos" && git push -q origin HEAD:ws/$AN)
w=$t/sw && git clone -q -b ws/$AN "$t/origin.git" "$w"
/bin/bash "$w/.delphi/setup.sh" >/dev/null 2>&1 || fail "switch: setup failed"
sw() { /bin/bash "$w/.delphi/switch.sh" "$@"; }
echo x >>"$w/CLAUDE.md"
{ ! sw bms-dev 2>"$t/err" >/dev/null && grep -q "commit or set aside" "$t/err" && [ "$(git -C "$w" branch --show-current)" = ws/$AN ]; } ||
  fail "switch: dirty root not refused"
git -C "$w" checkout -q CLAUDE.md
sw bms-dev >"$t/out" 2>&1 || fail "switch to bms-dev (by its last part) failed: $(cat "$t/out")"
{ [ "$(git -C "$w" branch --show-current)" = ws/$BN ] && [ ! -e "$w/worktrees" ] && [ ! -e "$w/linked" ] &&
  [ -d "$w/.delphi/parked/$AN/linked/main" ]; } || fail "switch: argos-dev not parked on bms-dev"
commit_on ws/$AN docs/CONTEXT.md "while away"
sw "ws/$AN" >"$t/out" 2>&1 || fail "switch back (by branch) failed: $(cat "$t/out")"
{ [ "$(git -C "$w" branch --show-current)" = ws/$AN ] && grep -qx "while away" "$w/docs/CONTEXT.md" &&
  [ -d "$w/worktrees/lib1/$def" ] && [ -f "$w/linked/main/ci/sync.sh" ]; } || fail "switch: argos-dev not restored and fast-forwarded"
{ sw main >/dev/null 2>&1 && [ "$(git -C "$w" branch --show-current)" = main ] && [ ! -e "$w/repos" ] && [ -f "$w/ci/sync.sh" ]; } ||
  fail "switch to main"
git -C "$w" switch -q ws/$AN
{ ! sw ../x 2>/dev/null && ! sw nope 2>/dev/null && ! sw software/nope/x 2>/dev/null && [ "$(git -C "$w" branch --show-current)" = ws/$AN ]; } || fail "switch accepted a bad or missing workspace"
ok "switch.sh refuses a dirty root, parks and restores workspaces, fast-forwards, runs setup, and switches to main"
ok "switch.sh takes a workspace's name, its branch, or its last part alone"
git -C "$w" branch -q -f ws/old-leaf origin/ws/$AN && git -C "$w" push -q origin ws/old-leaf # a workspace's old ws/<leaf> name
[ "$(sw --list)" = "$(printf '  main\n* %s\n  %s' "$AN" "$BN")" ] || fail "switch.sh --list: $(sw --list 2>&1)"
git -C "$w" push -q origin :ws/old-leaf && git -C "$w" branch -q -D ws/old-leaf
ok "switch.sh --list prints main and each workspace (not old ws/<leaf> names), marking this clone's"

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
  { [ "$(get "$url")" = 200 ] && curl -s "$url" | grep -q "<title>Delphi workspaces</title>" &&
    [ "$(get "http://127.0.0.1:$port/")" = 404 ] && [ "$(get "http://127.0.0.1:$port/wrong/api/state")" = 404 ] &&
    [ "$(get -H "Host: evil.example:$port" "${url}api/state")" = 403 ]; } || fail "web/server.py let a request without its token or a local Host through"
  curl -s "${url}api/state" | python3 -c 'import json, sys; s = json.load(sys.stdin); sys.exit(not (s["here"] == sys.argv[1] and s["workspaces"] == ["main", sys.argv[1], sys.argv[2]] and not s["isDirty"]))' "$AN" "$BN" ||
    fail "web/server.py api/state: $(curl -s "${url}api/state")"
  commit_on ws/$AN docs/CONTEXT.md "for the browser's pull"
  { [ "$(get -X POST -d '{}' "${url}api/pull")" = 415 ] &&
    curl -s -X POST -H 'Content-Type: application/json' -d '{}' "${url}api/pull" | grep -Eq '"Pulled [0-9]+ commits? into argos-dev"' &&
    [ "$(git -C "$w" rev-parse HEAD)" = "$(git -C "$t/origin.git" rev-parse "ws/$AN")" ] && grep -Eqx "pulled Pulled [0-9]+ commits? into argos-dev" "$t/web.out" &&
    curl -s -X POST -H 'Content-Type: application/json' -d '{}' "${url}api/pull" | grep -q '"argos-dev is up to date with origin"'; } ||
    fail "web/server.py pull: $(cat "$t/web.out" "$t/web.err")"
  { [ "$(get -X POST -d '{"name":"bms-dev"}' "${url}api/switch")" = 415 ] && [ "$(git -C "$w" branch --show-current)" = "ws/$AN" ]; } ||
    fail "web/server.py switched without a JSON body"
  { curl -s -X POST -H 'Content-Type: application/json' -d '{"name":"bms-dev"}' "${url}api/switch" | grep -q '"ok": true' &&
    [ "$(git -C "$w" branch --show-current)" = "ws/$BN" ] && grep -qx "switched bms-dev" "$t/web.out"; } ||
    fail "web/server.py switch to bms-dev: $(cat "$t/web.out" "$t/web.err")"
  kill "$web" && wait "$web" 2>/dev/null || true
  git -C "$w" switch -q "ws/$AN"
  ok "the browser view answers only its own page, pulls and switches through switch.sh, printing what it did"
else
  echo "skip - the delphi mod's browser view: no python3 or curl"
fi

# --- 14. named by path: a workspace's old ws/<leaf> branch carries over into ws/<name>; moving a clone onto the
# renamed branch moves nothing; 0.1.0 renames what the clone keeps under old names
C=software/electrical/workspaces/vcu-dev CN=software/electrical/vcu-dev D=software/electrical/workspaces/hv-dev DN=software/electrical/hv-dev
(cd "$t/dev" && git fetch -q && git checkout -q -B main origin/main && mkdir -p "$C" "$D" && cp -R templates/workspace/. "$C/" &&
  cp -R templates/workspace/. "$D/" && sed -i.bak "s|{{name}}|vcu-dev|" "$C/workspace.yml" && sed -i.bak "s|{{name}}|$DN|" "$D/workspace.yml" &&
  rm "$C/workspace.yml.bak" "$D/workspace.yml.bak" && bash ci/plugins.sh >/dev/null && git add -A && git commit -qm "vcu-dev, still named the old way" && git push -q origin main &&
  i=$t/legacy.index && GIT_INDEX_FILE=$i git read-tree "main:$C" && GIT_INDEX_FILE=$i git read-tree --prefix=.delphi/ main:.delphi &&
  git push -q origin "$(git commit-tree -p main -m "delphi: create ws/vcu-dev" "$(GIT_INDEX_FILE=$i git write-tree)"):refs/heads/ws/vcu-dev" &&
  rm "$i" && sed -i.bak "s|^name:.*|name: $CN|" "$C/workspace.yml" && rm "$C/workspace.yml.bak" && git commit -qam "vcu-dev named by path" && git push -q origin main)
commit_on ws/vcu-dev CLAUDE.md "on the old branch"
legacy=$(o rev-parse ws/vcu-dev)
sync >"$t/out" 2>&1 || fail "sync after a rename failed: $(cat "$t/out")"
{ grep -q "ws/$CN: created from ws/vcu-dev, its old name" "$t/out" && o merge-base --is-ancestor "$legacy" "ws/$CN" &&
  o show "ws/$CN:CLAUDE.md" | grep -qx "on the old branch" && [ "$(o show "ws/$CN:workspace.yml" | sed -n 1p)" = "name: $CN" ] &&
  grep -q "notice: ws/vcu-dev is a workspace's old name; it's now ws/$CN" "$t/out" && o show "propose/$CN:$C/CLAUDE.md" | grep -qx "on the old branch"; } ||
  fail "ws/$CN did not carry over ws/vcu-dev: $(cat "$t/out")"
ok "a workspace renamed by path starts its ws/<name> from its old ws/<leaf>, history and unproposed edits included"
w=$t/rename && git clone -q -b ws/vcu-dev "$t/origin.git" "$w" && /bin/bash "$w/.delphi/setup.sh" >/dev/null 2>&1 && mkdir -p "$w/repos/keep"
{ git -C "$w" checkout -q "ws/$CN" && [ -d "$w/repos/keep" ] && [ ! -e "$w/.delphi/parked" ]; } || fail "moving onto the renamed branch parked the workspace"
ok "checking out a workspace's renamed branch over its old one moves nothing"
mkdir -p "$w/.delphi/parked/argos-dev/linked/vcu-dev" "$w/.git/delphi/hv-dev/repos/r" "$w/linked/argos-dev" && git -C "$w" config delphi.argos-dev.version 0.0.1
/bin/bash "$w/.delphi/setup.sh" >"$t/out" 2>&1 || fail "setup.sh failed running 0.1.0: $(cat "$t/out")"
{ [ -d "$w/.delphi/parked/$AN/linked/ws/$CN" ] && [ -d "$w/.delphi/parked/$DN/repos/r" ] && [ ! -e "$w/.git/delphi" ] &&
  [ -d "$w/linked/ws/$AN" ] && [ ! -e "$w/linked/argos-dev" ] && ! git -C "$w" config delphi.argos-dev.version >/dev/null &&
  [ "$(git -C "$w" config "delphi.$CN.version")" = "$VN" ]; } || fail "0.1.0 did not rename by path: $(cat "$t/out"); $(find "$w/.delphi/parked" "$w/linked")"
{ /bin/bash "$w/.delphi/setup.sh" >"$t/out" 2>&1 && ! grep -q moved "$t/out"; } || fail "setup.sh re-ran 0.1.0"
{ git -C "$w" config --unset "delphi.$CN.version" && /bin/bash "$w/.delphi/setup.sh" >"$t/out" 2>&1 && ! grep -q moved "$t/out"; } || fail "0.1.0 is not safe to re-run"
ok "0.1.0 moves parked slots (.delphi/parked/<leaf>, .git/delphi/<leaf>), old copies in linked/ and old version records to path names, once"
git -C "$w" checkout -q ws/vcu-dev && /bin/bash "$w/.delphi/switch.sh" vcu-dev >"$t/out" 2>&1 && [ "$(git -C "$w" branch --show-current)" = "ws/$CN" ] ||
  fail "switch.sh by last part picked the old ws/vcu-dev: $(cat "$t/out")"
ok "switch.sh by a workspace's last part ignores its old ws/<leaf> branch"

# --- 13. shellcheck, if installed
if command -v shellcheck >/dev/null; then
  shellcheck "$src"/ci/*.sh "$src"/tools/*.sh "$src"/tests/*.sh "$src"/.delphi/*.sh "$src"/.delphi/migrations/*.sh ||
    fail "shellcheck"
  ok "shellcheck clean"
fi
echo "all $pass checks passed"
