#!/usr/bin/env bash
# tests/e2e.sh: end-to-end test of Delphi's scripts in a throwaway sandbox: a temp dir with a bare
# origin, a stub `gh` on PATH that logs its calls to gh.log, and a copy of this repo's scripts plus
# two workspaces in different org folders. Runs ci/sync.sh and friends as CI and people would.
# Never touches GitHub or this checkout's origin. Run: bash tests/e2e.sh
set -euo pipefail
src=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d)
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
chmod +x "$t/bin/gh"
export PATH=$t/bin:$PATH
touch "$t/gh.log"

pass=0
ok() { echo "ok - $*" && pass=$((pass + 1)); }
fail() { echo "FAIL - $*" >&2 && exit 1; }
A=software/application-software/argos/workspaces/argos-dev
B=software/electrical/workspaces/bms-dev

# --- sandbox: seed repo -> bare origin; "ci" is the clone CI runs in, "dev" a person's clone
git init -q "$t/seed"
cp -R "$src/ci" "$src/tools" "$src/templates" "$src/.github" "$src/README.md" "$t/seed/"
mkdir -p "$t/seed/$A" "$t/seed/$B"
cp -R "$src/$A/." "$t/seed/$A/"
cp -R "$src/templates/workspace/." "$t/seed/$B/"
FD=software/electrical/firmware/defaults # project defaults for new workspaces under electrical/firmware
mkdir -p "$t/seed/$FD/.claude/skills/fw"
printf 'harness: claude-code\nrepos:\n  fw: https://example.com/fw.git\n' >"$t/seed/$FD/workspace.yml"
printf '# Firmware for {{name}}\n' >"$t/seed/$FD/CLAUDE.md"
echo "fw skill" >"$t/seed/$FD/.claude/skills/fw/SKILL.md"
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
  n=${w##*/}
  [ "$(o rev-parse "ws/$n^{tree}")" = "$(o rev-parse "main:$w")" ] || fail "ws/$n root != $w"
  [ "$(o rev-parse "ws/$n^")" = "$main" ] || fail "ws/$n parent is not main"
  [ "$(o log -1 --format=%s "ws/$n")" = "delphi: create ws/$n from $w" ] || fail "ws/$n message"
  o cat-file -e "ws/$n:workspace.yml" || fail "ws/$n lacks workspace.yml"
  { ! o cat-file -e "ws/$n:README.md" 2>/dev/null && ! o cat-file -e "ws/$n:ci" 2>/dev/null; } ||
    fail "ws/$n has Delphi root files"
  [ "$(o rev-parse "ws/$n:.github/workflows/delphi.yml")" = "$(o rev-parse main:.github/workflows/delphi.yml)" ] ||
    fail "ws/$n root lacks main's workflow (pushes to ws/$n would trigger nothing)"
done
ok "sync creates ws/<name> rooted at its folder, parent main, no Delphi root files"
ok "ws/<name> root carries main's CI workflow, so GitHub runs sync on pushes to ws/**"
[ ! -s "$t/gh.log" ] || fail "gh called on creation"
before=$(o for-each-ref --format='%(objectname)' refs/heads)
sync >/dev/null
[ "$before" = "$(o for-each-ref --format='%(objectname)' refs/heads)" ] || fail "second sync changed refs"
ok "sync is a no-op when nothing changed"

# --- 2. an edit merged into ws/argos-dev becomes propose/argos-dev and a PR to main
commit_on ws/argos-dev docs/CONTEXT.md "ws edit one"
sync argos-dev >"$t/out"
o show "propose/argos-dev:$A/docs/CONTEXT.md" | grep -qx "ws edit one" || fail "propose/argos-dev lacks the edit"
[ "$(o diff --name-only main propose/argos-dev)" = "$A/docs/CONTEXT.md" ] || fail "propose diff not just the edit"
grep -q "gh pr create --base main --head propose/argos-dev --title ws/argos-dev → main" "$t/gh.log" ||
  fail "no PR created: $(cat "$t/gh.log")"
grep -q -- "- edit docs/CONTEXT.md on ws/argos-dev (tester)" "$t/gh.log" || fail "PR body lacks ws commit"
ok "ws edit -> propose/argos-dev with the change under the folder, PR opened with gh"
prop=$(o rev-parse propose/argos-dev)
sleep 1 # a re-built merge commit would get a new timestamp, hence a new id
: >"$t/gh.log"
sync argos-dev >/dev/null
{ [ "$(o rev-parse propose/argos-dev)" = "$prop" ] && [ ! -s "$t/gh.log" ]; } || fail "unchanged proposal re-pushed"
ok "an unchanged proposal is not re-pushed and its PR not touched"

# --- 3. merging propose/argos-dev into main, then sync: clean, ws unchanged, nothing to propose
(cd "$t/dev" && git fetch -q && git checkout -q -B main origin/main &&
  git merge -q --no-ff --no-edit origin/propose/argos-dev && git push -q origin main)
ws=$(o rev-parse ws/argos-dev)
: >"$t/gh.log"
sync >"$t/out" || fail "sync after merging propose failed"
[ "$(o rev-parse "ws/argos-dev^{tree}")" = "$(o rev-parse "$ws^{tree}")" ] || fail "ws tree changed"
[ ! -s "$t/gh.log" ] || fail "gh called after propose merged: $(cat "$t/gh.log")"
ok "after the propose PR merges into main, sync is clean and opens no PR"

# --- 4. a main change to another file refreshes into a ws branch with its own edits, then propose
commit_on ws/argos-dev docs/CONTEXT.md "ws edit two"
commit_on main "$A/CLAUDE.md" "main edit"
commit_on main README.md "root edit"
sync >"$t/out" || fail "sync with non-overlapping edits failed"
o show ws/argos-dev:CLAUDE.md | grep -qx "main edit" || fail "main edit not in ws"
o show ws/argos-dev:docs/CONTEXT.md | grep -qx "ws edit two" || fail "ws edit lost"
! o cat-file -e ws/argos-dev:README.md 2>/dev/null || fail "root file leaked into ws"
[ "$(o diff --name-only main propose/argos-dev)" = "$A/docs/CONTEXT.md" ] || fail "propose diff wrong after refresh"
ok "main-side edit refreshes cleanly alongside ws edits; propose carries only the ws edit"
[ "$(o rev-parse "ws/bms-dev^{tree}")" = "$(o rev-parse "main:$B")" ] || fail "bms-dev drifted"
ok "unrelated main changes leave other ws branches' trees alone"

# --- 5. a conflict on bms-dev is reported; argos-dev still syncs; exit 1
commit_on ws/bms-dev CLAUDE.md "ws side"
commit_on main "$B/CLAUDE.md" "main side"
commit_on main "$A/CLAUDE.md" "main edit two"
bms=$(o rev-parse ws/bms-dev)
if sync 2>"$t/err" >"$t/out"; then fail "conflicting sync exited 0"; fi
{ grep -q "ws/bms-dev: CONFLICT" "$t/err" && grep -q "  CLAUDE.md" "$t/err"; } || fail "conflict not reported: $(cat "$t/err")"
[ "$(o rev-parse ws/bms-dev)" = "$bms" ] || fail "conflicting ws/bms-dev was changed"
o show ws/argos-dev:CLAUDE.md | grep -qx "main edit two" || fail "argos-dev not synced"
ok "conflict: reported with files, exit 1, other workspaces still synced"

# resolve as documented: merge main into ws/bms-dev on a branch, PR into ws/bms-dev
(cd "$t/dev" && git fetch -q && git checkout -q -B fix origin/ws/bms-dev &&
  { git merge -q -Xsubtree="$B" origin/main >/dev/null 2>&1 || true; } &&
  git checkout -q --ours CLAUDE.md && git commit -qam "resolve" && git push -q origin HEAD:ws/bms-dev)
sync >"$t/out" 2>"$t/err" || fail "sync after resolving failed: $(cat "$t/err")"
grep -q "ws/bms-dev: proposed" "$t/out" || fail "resolved ws not proposed"
ok "conflict resolved by merging main into ws in a PR; sync then succeeds"

# --- 6. removed workspace folder: notice, branch kept
(cd "$t/dev" && git checkout -q -B main origin/main && git rm -rq "$B" && git commit -qm rm && git push -q origin main)
sync >"$t/out"
grep -q "notice: ws/bms-dev has no workspace folder on main" "$t/out" || fail "no removal notice"
o rev-parse -q --verify ws/bms-dev >/dev/null || fail "ws/bms-dev deleted"
ok "removed workspace: notice printed, branch kept"

# --- 7. check.sh: real layout passes; each bad layout fails
"$src/ci/check.sh" "$src" >/dev/null || fail "check fails on the real repo"
ok "check passes on the real repo"
expect_bad() { # <label> <expected message> <setup command...>: copy the real layout, break it, check fails
  local d=$t/chk-$1 label=$1 want=$2
  shift 2
  rm -rf "$d" && mkdir "$d" && cp -R "$src/software" "$src/templates" "$src/.github" "$d/"
  (cd "$d" && "$@")
  if "$src/ci/check.sh" "$d" 2>"$t/err" >/dev/null; then fail "check passed: $label"; fi
  grep -q -- "$want" "$t/err" || fail "check $label: no '$want' in: $(cat "$t/err")"
  ok "check fails: $label ($want)"
}
expect_bad no-harness "harness is missing" sed -i 's/^harness:.*//' "$A/workspace.yml"
expect_bad duplicate-harness "duplicate harness" sh -c "printf 'harness: x\n' >>$A/workspace.yml"
expect_bad bad-repo "bad repos entry" sh -c "printf '  ../x: y\n' >>$A/workspace.yml"
expect_bad bad-key "unexpected line" sh -c "printf 'name: x\n' >>$A/workspace.yml"
expect_bad duplicate "is also used by" sh -c "mkdir -p software/x/workspaces && cp -R $A software/x/workspaces/"
expect_bad nested "nested inside" sh -c "mkdir -p $A/docs/workspaces/inner && cp $A/workspace.yml $A/docs/workspaces/inner/"
expect_bad bad-name "name must be" sh -c "mkdir -p software/x/workspaces && cp -R $A software/x/workspaces/Bad_Name"
expect_bad symlink "symlinks are not allowed" ln -s ../CLAUDE.md "$A/docs/link.md"
expect_bad setup-drift "setup.sh: differs" sh -c "echo x >>$A/.delphi/setup.sh"
expect_bad workflow-drift "argos-dev/.github/workflows/delphi.yml: differs" sh -c "echo x >>$A/.github/workflows/delphi.yml"
expect_bad defaults-manifest "defaults/workspace.yml: unexpected line" sh -c "printf 'x: y\n' >>${A%/workspaces/*}/defaults/workspace.yml"
expect_bad defaults-named-workspace "defaults/.delphi/link.sh: differs" sh -c "mkdir -p software/x/workspaces && cp -R $A software/x/workspaces/defaults && echo x >>software/x/workspaces/defaults/.delphi/link.sh"
expect_bad template-workflow-drift "differs from .github/workflows/delphi.yml" sh -c "echo x >>.github/workflows/delphi.yml"

# --- 8. setup.sh clones workspace.yml repos into repos/ and is idempotent
for r in lib1 lib2; do
  git init -q "$t/$r" && git -C "$t/$r" commit -q --allow-empty -m "$r" && git clone -q --bare "$t/$r" "$t/$r.git"
done
git clone -q -b ws/argos-dev "$t/origin.git" "$t/ws"
printf 'harness: claude-code\nrepos:\n  # a comment\n  lib1: %s  # trailing\n  lib2: %s\n' \
  "$t/lib1.git" "$t/lib2.git" >"$t/ws/workspace.yml"
/bin/bash "$t/ws/.delphi/setup.sh" >/dev/null 2>&1 || fail "setup.sh failed"
/bin/bash "$t/ws/.delphi/setup.sh" >"$t/out" 2>&1 || fail "setup.sh re-run failed"
{ [ -d "$t/ws/repos/lib1/.git" ] && [ -d "$t/ws/repos/lib2/.git" ]; } || fail "repos not cloned"
grep -q "repos/lib1: already present" "$t/out" || fail "re-run did not skip"
[ "$(grep -cx /repos/ "$t/ws/.git/info/exclude")" = 1 ] || fail "exclude not exactly once"
[ "$(git -C "$t/ws" status --porcelain)" = " M workspace.yml" ] || fail "repos/ shows in status"
ok "setup.sh clones repos into repos/, excludes them once, and is idempotent"
git clone -q -c core.autocrlf=true -b ws/argos-dev "$t/origin.git" "$t/ws-crlf"
cp "$t/ws/workspace.yml" "$t/ws-crlf/"
/bin/bash "$t/ws-crlf/.delphi/setup.sh" >/dev/null 2>&1 || fail "setup.sh fails with core.autocrlf=true"
ok "setup.sh runs in a core.autocrlf=true clone (Git Bash default), thanks to .gitattributes"

# --- 9. new-workspace.sh creates the folder on a branch and opens a PR
: >"$t/gh.log"
git -C "$t/dev" branch -q new-workspace/fw-dev origin/main # left by an earlier failed run
(cd "$t/dev" && git checkout -q -B main origin/main && tools/new-workspace.sh electrical/firmware fw-dev >/dev/null) ||
  fail "new-workspace.sh failed (blocked by a leftover local branch?)"
F=software/electrical/firmware/workspaces/fw-dev
o cat-file -e "new-workspace/fw-dev:$F/workspace.yml" || fail "no workspace.yml on new-workspace/fw-dev"
o show "new-workspace/fw-dev:$F/CLAUDE.md" | grep -q "branch \`ws/fw-dev\`" || fail "CLAUDE.md not filled in"
! o show "new-workspace/fw-dev:$F/CLAUDE.md" | grep -q "{{" || fail "placeholder left"
o show "new-workspace/fw-dev:$F/CLAUDE.md" | grep -qx "# Firmware for fw-dev" || fail "defaults CLAUDE.md not appended"
[ "$(o rev-parse "new-workspace/fw-dev:$F/workspace.yml")" = "$(o rev-parse "main:$FD/workspace.yml")" ] ||
  fail "defaults workspace.yml not used"
o cat-file -e "new-workspace/fw-dev:$F/.claude/skills/fw/SKILL.md" || fail "defaults skill not copied"
o cat-file -e "new-workspace/fw-dev:$F/.claude/skills/link-workspace/SKILL.md" || fail "template skill lost"
grep -q "gh pr create --base main --head new-workspace/fw-dev" "$t/gh.log" || fail "no PR for new workspace"
(cd "$t/dev" && ! tools/new-workspace.sh x argos-dev 2>/dev/null) || fail "duplicate name accepted"
(cd "$t/dev" && ! tools/new-workspace.sh x Bad 2>/dev/null) || fail "bad name accepted"
(cd "$t/dev" && ! tools/new-workspace.sh ../x ok 2>/dev/null) || fail "bad org path accepted"
[ -z "$(git -C "$t/dev" status --porcelain)" ] || fail "new-workspace touched the checkout"
ok "new-workspace.sh opens a PR with the templated folder; rejects duplicates and bad input"
ok "new-workspace.sh adds the project's defaults/ (CLAUDE.md appended, placeholders filled)"
ok "new-workspace.sh works when a local new-workspace/<name> branch is left over"

# --- 10. one direction at a time: `sync refresh` only updates ws/, `sync propose` only updates propose/
sync argos-dev >/dev/null || fail "settling sync failed"
commit_on main "$A/CLAUDE.md" "one-way refresh"
prop_before=$(o rev-parse propose/argos-dev)
sync refresh argos-dev >/dev/null || fail "sync refresh failed"
o show ws/argos-dev:CLAUDE.md | grep -qx "one-way refresh" || fail "sync refresh did not merge main"
[ "$(o rev-parse propose/argos-dev)" = "$prop_before" ] || fail "sync refresh touched propose/argos-dev"
commit_on ws/argos-dev docs/CONTEXT.md "one-way propose"
ws_before=$(o rev-parse ws/argos-dev)
commit_on main "$A/CLAUDE.md" "not yet refreshed"
sync propose argos-dev >/dev/null || fail "sync propose failed"
o show "propose/argos-dev:$A/docs/CONTEXT.md" | grep -qx "one-way propose" || fail "sync propose lacks the ws edit"
[ "$(o rev-parse ws/argos-dev)" = "$ws_before" ] || fail "sync propose changed ws/argos-dev"
! o show ws/argos-dev:CLAUDE.md | grep -qx "not yet refreshed" || fail "sync propose merged main into ws"
ok "sync refresh / sync propose each move changes one way only"
prop_before=$(o rev-parse propose/argos-dev)
commit_on ws/argos-dev workspace.yml "bad: line"
if sync argos-dev 2>"$t/err" >/dev/null; then fail "sync proposed a workspace failing check"; fi
grep -q "ws/argos-dev: check failed" "$t/err" || fail "check failure not reported: $(cat "$t/err")"
[ "$(o rev-parse propose/argos-dev)" = "$prop_before" ] || fail "failing proposal was pushed"
ok "a proposal failing check.sh is reported and not pushed; exit 1"

# --- 11. new-worktree.sh: new branch from the default branch or <base>; existing branch checked out; reruns reuse
git init -q "$t/code" && git -C "$t/code" commit -q --allow-empty -m one && git -C "$t/code" branch feat &&
  git -C "$t/code" branch develop && git -C "$t/code" commit -q --allow-empty -m two
w=$t/nw && git clone -q -b ws/bms-dev "$t/origin.git" "$w" && git clone -q "$t/code" "$w/repos/code"
nw() { bash "$w/.delphi/new-worktree.sh" "$@"; }
[ "$(nw code 1-new)" = "$w/repos/worktrees/code/1-new" ] || fail "new-worktree path"
[ "$(git -C "$w/repos/worktrees/code/1-new" rev-parse HEAD)" = "$(git -C "$t/code" rev-parse main)" ] || fail "new branch not from default"
nw code feat >/dev/null && [ "$(git -C "$w/repos/worktrees/code/feat" rev-parse HEAD)" = "$(git -C "$t/code" rev-parse feat)" ] ||
  fail "existing branch not checked out"
nw code 2-dev origin/develop >/dev/null && [ "$(git -C "$w/repos/worktrees/code/2-dev" rev-parse HEAD)" = "$(git -C "$t/code" rev-parse develop)" ] ||
  fail "<base> ignored"
[ "$(nw code feat)" = "$w/repos/worktrees/code/feat" ] || fail "rerun did not reuse"
[ "$(git -C "$w/repos/code" branch --show-current)" = main ] || fail "repos/code left its branch"
ok "new-worktree.sh makes new branches from the default or <base>, checks out existing ones, reuses on rerun"

# --- 12. link.sh: other workspaces and main as detached worktrees under linked/, updated on re-run
lk() { bash "$w/.delphi/link.sh" "$@"; }
[ "$(lk argos-dev)" = "$w/linked/argos-dev" ] || fail "link.sh path"
[ "$(git -C "$w/linked/argos-dev" rev-parse HEAD)" = "$(o rev-parse ws/argos-dev)" ] || fail "link not at ws/argos-dev"
{ lk main >/dev/null && [ -f "$w/linked/main/ci/sync.sh" ]; } || fail "link main"
commit_on ws/argos-dev docs/CONTEXT.md "linked update"
{ lk argos-dev >/dev/null && grep -qx "linked update" "$w/linked/argos-dev/docs/CONTEXT.md"; } || fail "re-run did not update"
git -C "$w/linked/argos-dev" switch -q -c mine && commit_on ws/argos-dev docs/CONTEXT.md "after switch"
{ lk argos-dev 2>"$t/err" >/dev/null && grep -q "on a branch; not updated" "$t/err"; } || fail "branch not reported"
[ "$(git -C "$w/linked/argos-dev" branch --show-current)" = mine ] || fail "link moved a branch"
! lk ../x 2>/dev/null || fail "bad link name accepted"
[ "$(grep -cx /linked/ "$w/.git/info/exclude")" = 1 ] || fail "/linked/ not excluded exactly once"
! git -C "$w" status --porcelain | grep -q linked || fail "linked/ shows in status"
ok "link.sh checks out workspaces and main under linked/, updates detached ones, leaves branches"

# --- 13. shellcheck, if installed
if command -v shellcheck >/dev/null; then
  shellcheck "$src"/ci/*.sh "$src"/tools/*.sh "$src"/tests/*.sh "$src"/templates/workspace/.delphi/*.sh ||
    fail "shellcheck"
  ok "shellcheck clean"
fi
echo "all $pass checks passed"
