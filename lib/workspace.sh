# workspace.sh — `delphi workspace new|open|refresh|propose|status` (alias: ws).
#
# A workspace is its own git repo outside Delphi. Refs: branch `generated` (renders only), tag
# `generated-merged` (latest render merged into `working`), branch `working` (the user's).
# Bookkeeping lives in .git/delphi/meta (key=value); meta.render_commit is authoritative.
. "$DELPHI_ROOT/lib/parse.sh"
. "$DELPHI_ROOT/lib/render.sh"
. "$DELPHI_ROOT/lib/provenance.sh"
. "$DELPHI_ROOT/lib/pr.sh"
. "$DELPHI_ROOT/lib/route.sh"
. "$DELPHI_ROOT/lib/check.sh"

workspace_main() {
  local verb=${1:-} flags
  [ $# -gt 0 ] && shift
  case $verb in
    new) flags="--as --ref" ;; open) flags="--model --effort --shell" ;; refresh) flags="--ref" ;;
    propose) flags="--model --effort --yes --dry-run" ;; status) flags="--offline" ;;
    *) die "usage: delphi workspace new|open|refresh|propose|status (see: delphi help)" ;;
  esac
  parse_args "$flags" "$@"; eval "set -- $ARGS"
  [ $# -le 1 ] || die "too many arguments (see: delphi help)"
  case $verb in
    new)     [ $# -eq 1 ] || die "usage: delphi workspace new <layout> [--as <ws>] [--ref <branch>]"; ws_new "$1" ;;
    open)    ws_resolve "${1:-}"; ws_open ;;
    refresh) ws_resolve "${1:-}"; delphi_fetch; ws_refresh ;;
    propose) ws_resolve "${1:-}"; ws_propose ;;
    status)  [ $# -eq 0 ] || die "usage: delphi workspace status [--offline]"; ws_status ;;
  esac
}

# ---- helpers ----
wgit() { git -c core.quotePath=false -C "$WS" "$@"; }
now() { date +%s; }
meta() { awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$WS/.git/delphi/meta"; }
meta_set() {
  local f="$WS/.git/delphi/meta"
  awk -F= -v k="$1" -v v="$2" '$1 == k { print k "=" v; d = 1; next } { print } END { if (!d) print k "=" v }' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f" || die "cannot write $f"
}
ws_names() { local d; for d in "$(workspace_root)"/*; do [ -f "$d/.git/delphi/meta" ] && printf '%s\n' "${d##*/}"; done; return 0; }
ws_name_ok() { case $1 in ""|.*|*[!A-Za-z0-9._-]*) die "invalid workspace name: '$1'" ;; esac; }

# _ws_pending [diff opts]: the pending diff (everything changed since the latest merged render).
_ws_pending() { wgit diff --no-renames --no-ext-diff --no-color "$@" generated-merged HEAD -- . ':(exclude).delphi/lock.tsv'; }
_ws_hash() { _ws_pending -U0 | sed '/^@@/d; /^index /d' | git hash-object --stdin; }

# ws_resolve [<name>]: sets WS/WS_NAME from the name, the current directory, or a picker.
ws_resolve() {
  local d n list
  if [ -n "$1" ]; then
    ws_name_ok "$1"; WS="$(workspace_root)/$1"
  else
    d=$PWD
    while [ "$d" != / ] && [ ! -f "$d/.git/delphi/meta" ]; do d=$(dirname "$d"); done
    if [ -f "$d/.git/delphi/meta" ]; then WS=$d
    else
      list=$(ws_names)
      [ -n "$list" ] || die "no workspaces in $(workspace_root) (create one: delphi workspace new <layout>)"
      is_tty || die "not inside a workspace; name one (see: delphi workspace status)"
      printf '%s\n' "$list" | awk '{ printf "  %d) %s\n", NR, $0 }' >&2
      n=$(ask "Workspace number?") || exit 1
      case $n in ""|*[!0-9]*) die "not a number: '$n'" ;; esac
      d=$(printf '%s\n' "$list" | sed -n "${n}p")
      [ -n "$d" ] || die "no workspace #$n"
      WS="$(workspace_root)/$d"
    fi
  fi
  [ -f "$WS/.git/delphi/meta" ] || die "not a Delphi workspace: $WS"
  WS_NAME=${WS##*/}
}

# ---- rendering into the workspace ----
# _ws_render <src-root> <layout-path>: render into a temp dir; path in REPLY.
_ws_render() {
  make_tmp; mkdir "$REPLY/out" || die "mkdir failed"
  render "$1" "$2" "$REPLY/out"
  REPLY="$REPLY/out"
}

# _ws_commit_render <outdir> <delphi-commit>: commit outdir as the next `generated` commit
# (plumbing, so no worktree or hooks). Returns 1 when content equals the current `generated`.
_ws_commit_render() {
  local idx tree parent c
  make_tmp; idx="$REPLY/index"
  GIT_INDEX_FILE=$idx git -C "$1" --git-dir="$WS/.git" --work-tree=. add -A -f || die "cannot stage render"
  tree=$(GIT_INDEX_FILE=$idx git --git-dir="$WS/.git" write-tree) || die "cannot write render tree"
  if parent=$(wgit rev-parse -q --verify 'generated^{commit}'); then
    [ "$tree" = "$(wgit rev-parse 'generated^{tree}')" ] && return 1
    parent="-p $parent"
  fi
  c=$(printf 'delphi: render %s@%.7s\n\nDelphi-Render: %s\n' "$(meta layout)" "$2" "$2" | wgit commit-tree $parent "$tree") ||
    die "cannot commit render"
  wgit update-ref refs/heads/generated "$c" || die "cannot update generated"
}

_ws_hook() {
  cat > "$WS/.git/hooks/commit-msg" <<'EOF'
#!/bin/sh
# Delphi: append provenance trailers from DELPHI_* env vars when set and not already present.
for kv in "Delphi-Harness=$DELPHI_HARNESS" "Delphi-Model=$DELPHI_MODEL" "Delphi-Effort=$DELPHI_EFFORT"; do
  k=${kv%%=*} v=${kv#*=}
  if [ -n "$v" ] && ! grep -q "^$k:" "$1"; then git interpret-trailers --in-place --trailer "$k: $v" "$1"; fi
done
exit 0
EOF
  chmod +x "$WS/.git/hooks/commit-msg"
}

ws_new() {
  local layout=$1 ref=${OPT_REF:-main} c src lp out recs name url failed=""
  WS_NAME=${OPT_AS:-$1}; ws_name_ok "$WS_NAME"
  WS="$(workspace_root)/$WS_NAME"
  [ -e "$WS" ] && die "workspace already exists: $WS"
  delphi_fetch
  c=$(delphi_commit "$ref") || exit 1
  delphi_worktree_at "$c"; src=$REPLY
  lp=$(find_layout "$src" "$layout") || exit 1
  recs=$(parse_yaml "$src/context/$lp/manifest.yml") || exit 1
  _ws_render "$src" "$lp"; out=$REPLY

  mkdir -p "$WS" && git init -q "$WS" || die "git init failed: $WS"
  mkdir -p "$WS/.git/delphi" "$WS/repos" "$WS/worktrees"
  printf 'repos/\nworktrees/\n%s\n' "$HARNESS_IGNORE" >> "$WS/.git/info/exclude"
  _ws_hook
  printf 'layout=%s\nlayout_path=%s\nref=%s\nharness=%s\ncreated=%s\nlast_proposed=\nlast_proposed_hash=\npending_since=\nrender_commit=%s\n' \
    "$layout" "$lp" "$ref" "$R_HARNESS" "$(now)" "$c" > "$WS/.git/delphi/meta"
  _ws_commit_render "$out" "$c" || die "empty render"
  wgit tag generated-merged generated && wgit checkout -q -B working generated || die "cannot create working branch"

  while IFS='	' read -r name url; do
    [ -n "$name" ] || continue
    case $name in *[!A-Za-z0-9._-]*|.*) warn "skipping repo with invalid name '$name'"; continue ;; esac
    info "cloning ${name}…"
    git clone -q "$url" "$WS/repos/$name" || { warn "clone failed: $name ($url)"; failed="$failed $name"; }
  done <<EOF
$(yaml_map "$recs" repos)
EOF
  info "workspace ready: $WS"
  [ -z "$failed" ] || warn "repos not cloned:$failed (clone them into repos/ yourself)"
  info "next: delphi workspace open $WS_NAME"
}

# ---- refresh ----
# _ws_render_ref: render origin/<meta.ref> onto `generated`. REPLY=changed|same.
_ws_render_ref() {
  local ref c src lp out
  ref=$(meta ref)
  c=$(dgit rev-parse -q --verify "origin/$ref^{commit}") || die "branch '$ref' is gone — run: delphi workspace refresh --ref main"
  delphi_worktree_at "$c"; src=$REPLY
  moves_since "$(meta render_commit)" "$c"
  lp=$(move_path "$REPLY" "$(meta layout_path)") || exit 1
  meta_set layout_path "$lp"
  _ws_render "$src" "$lp"; out=$REPLY
  meta_set harness "$R_HARNESS"
  if _ws_commit_render "$out" "$c"; then REPLY=changed; else _ws_apply_moves "$c"; REPLY=same; fi
}

_ws_merge() {
  wgit merge -q --no-verify --no-edit generated > /dev/null 2>&1 && return 0
  [ -f "$WS/.git/MERGE_HEAD" ] || die "merge of generated failed in $WS"
  info "conflicts in $WS_NAME:"
  wgit diff --name-only --diff-filter=U | sed 's/^/  /' >&2
  info "resolve them, commit, then re-run: delphi workspace refresh $WS_NAME"
  exit 2
}

# _ws_apply_moves <commit>: rewrite paths moved since render_commit in .delphi/manifest.yml; the
# workspace's render now corresponds to <commit>.
_ws_apply_moves() {
  moves_since "$(meta render_commit)" "$1"
  meta_set render_commit "$1"
  if rewrite_moves "$REPLY" "$WS/.delphi/manifest.yml"; then
    wgit commit -q --no-verify -am "delphi: apply moves" || die "cannot commit moved paths"
  fi
}

_ws_finalize() {
  wgit tag -f generated-merged generated > /dev/null || die "cannot move generated-merged"
  _ws_apply_moves "$(wgit log -1 --format='%(trailers:key=Delphi-Render,valueonly)' generated | sed '/^$/d')"
  info "$WS_NAME: merged render of origin/$(meta ref) ($(printf %.7s "$(meta render_commit)"))"
}

# _ws_catch_up: merge a pending render into HEAD (exits 2 on conflicts), then finalize it.
_ws_catch_up() {
  wgit merge-base --is-ancestor generated HEAD || _ws_merge
  [ "$(wgit rev-parse generated)" = "$(wgit rev-parse 'generated-merged^{commit}')" ] || _ws_finalize
}

# ws_refresh: idempotent. Returns 0 when up to date or finalized; exits 2 on conflicts.
ws_refresh() {
  wgit worktree prune
  [ -f "$WS/.git/MERGE_HEAD" ] && die "merge in progress in $WS: resolve conflicts, commit, then re-run 'delphi workspace refresh'"
  [ -z "$(wgit status --porcelain)" ] || die "$WS has uncommitted changes; commit or stash them first"
  [ -z "$OPT_REF" ] || meta_set ref "$OPT_REF"
  _ws_catch_up
  _ws_render_ref
  if [ "$REPLY" = same ]; then info "$WS_NAME: up to date with origin/$(meta ref)"; else _ws_catch_up; fi
  if [ -z "$(_ws_pending --name-only)" ]; then meta_set pending_since "$(wgit rev-parse HEAD)"; fi
}

# ---- status ----
# _ws_behind: yes if origin/<ref> has commits since render_commit touching this workspace's sources.
_ws_behind() {
  local rc tip IFS='
'
  rc=$(meta render_commit)
  tip=$(dgit rev-parse -q --verify "origin/$(meta ref)^{commit}") || { echo gone; return 0; }
  [ "$tip" = "$rc" ] && { echo no; return 0; }
  set -- $( { wgit show generated-merged:.delphi/lock.tsv |
                awk -F'\t' '!/^#/ { s = $4; if (s ~ /^@gen:.*\//) s = substr(s, 6); if (s !~ /^@/) print "context/" s }'
              echo "context/$(meta layout_path)/manifest.yml"
              wgit show generated-merged:.delphi/manifest.yml | sed -n 's#^  - \(.*\)/\*$#context/\1#p'; } | sort -u)
  if [ -n "$(dgit log -1 --format=x "$rc..$tip" -- "$@" 2>/dev/null || echo x)" ]; then echo yes; else echo no; fi
}

# _ws_state: S_DIRTY S_STATE S_AGE S_STALE for $WS.
_ws_state() {
  local base days
  S_DIRTY=no; [ -z "$(wgit status --porcelain)" ] || S_DIRTY=yes
  if [ -z "$(_ws_pending --name-only)" ]; then S_STATE=clean
  elif [ "$(_ws_hash)" = "$(meta last_proposed_hash)" ]; then S_STATE=proposed
  else S_STATE=unproposed; fi
  S_AGE=- S_STALE=0
  if [ "$S_STATE" = unproposed ]; then
    base=$(meta last_proposed); base=${base:-$(meta created)}
    days=$(( ($(now) - base) / 86400 )); S_AGE="${days}d"
    [ "$days" -gt "$(conf_get stale_days 14)" ] && S_STALE=1
  fi
  return 0
}

ws_status() {
  local behind next n=0 c=0 p=0 u=0 s=0 fmt='%-22s %-16s %-8s %-5s %-10s %-5s %-6s %s\n'
  delphi_fetch
  printf "$fmt" WORKSPACE LAYOUT REF DIRTY STATE AGE BEHIND NEXT
  for WS_NAME in $(ws_names); do
    WS="$(workspace_root)/$WS_NAME"
    _ws_state; behind=$(_ws_behind)
    if [ -f "$WS/.git/MERGE_HEAD" ]; then next="resolve conflicts, commit, then: delphi ws refresh $WS_NAME"
    elif [ "$S_DIRTY" = yes ]; then next="commit your changes in $WS"
    elif [ "$behind" = gone ]; then next="delphi ws refresh $WS_NAME --ref main"
    elif [ "$behind" = yes ]; then next="delphi ws refresh $WS_NAME"
    elif [ "$S_STATE" = unproposed ]; then next="delphi ws propose $WS_NAME"
    else next="delphi ws open $WS_NAME"; fi
    [ "$S_STALE" = 1 ] && S_AGE="$S_AGE!" && s=$((s + 1))
    printf "$fmt" "$WS_NAME" "$(meta layout)" "$(meta ref)" "$S_DIRTY" "$S_STATE" "$S_AGE" "$behind" "$next"
    n=$((n + 1))
    case $S_STATE in clean) c=$((c + 1)) ;; proposed) p=$((p + 1)) ;; *) u=$((u + 1)) ;; esac
  done
  printf '%d workspace(s): %d clean, %d proposed, %d unproposed (%d stale: unproposed > %s days)\n' \
    "$n" "$c" "$p" "$u" "$s" "$(conf_get stale_days 14)"
}

# ---- open ----
ws_open() {
  local me=$WS_NAME
  delphi_fetch
  for WS_NAME in $(ws_names); do
    WS="$(workspace_root)/$WS_NAME"; _ws_state
    [ "$S_STALE" = 1 ] && warn "$WS_NAME has been unproposed for $S_AGE; run: delphi ws propose $WS_NAME"
  done
  WS_NAME=$me WS="$(workspace_root)/$me"
  [ "$(_ws_behind)" = no ] || warn "$me is behind origin/$(meta ref) (or its branch is gone); run: delphi ws refresh $me"
  load_harness "$(meta harness)"
  DELPHI_HARNESS=$(harness_provenance 2>/dev/null | sed -n 1p)
  DELPHI_MODEL=${OPT_MODEL:-${DELPHI_MODEL:-}} DELPHI_EFFORT=${OPT_EFFORT:-${DELPHI_EFFORT:-}}
  export DELPHI_HARNESS DELPHI_MODEL DELPHI_EFFORT
  cd "$WS" || die "cannot cd to $WS"
  _run_deferred; trap - EXIT
  [ -n "$OPT_SHELL" ] && exec "${SHELL:-/bin/sh}"
  harness_launch "$DELPHI_MODEL" "$DELPHI_EFFORT"
}

# ---- propose ----
_ws_print_plan() {
  awk -F'\t' '$1 != "unresolved" { printf "  %-9s %s -> %s\n", $1, $2, $3 }' "$RT/plan" >&2
  if [ -s "$RT/unresolved.md" ]; then info "Unresolved:"; cat "$RT/unresolved.md" >&2; fi
}

# _ws_prov_rows: distinct harness|model|effort trailers from workspace commits since pending_since.
_ws_prov_rows() {
  local since f='%(trailers:key=Delphi-Harness,valueonly,separator=)|%(trailers:key=Delphi-Model,valueonly,separator=)|%(trailers:key=Delphi-Effort,valueonly,separator=)'
  since=$(meta pending_since)
  wgit log --no-merges --format="$f" "${since:+$since..}HEAD" |
    awk -v s="$PROV_HARNESS|$PROV_MODEL|$PROV_EFFORT" '$0 != "||" && $0 != s && !seen[$0]++'
}

# _ws_warn_open_pr <branch>: after an earlier push, warn if that PR is still open.
_ws_warn_open_pr() {
  local n=""
  [ -n "$(meta last_pushed)" ] || return 0
  n=$(cd "$DELPHI_ROOT" && gh pr list --head "$1" --state open --json number --jq '.[0].number // empty' 2>/dev/null) || true
  [ -z "$n" ] || warn "PR #$n still contains earlier changes; close it with: gh pr close $n"
}

ws_propose() {
  local user="" branch remote body
  if [ -n "$OPT_DRY" ]; then
    delphi_fetch
    [ "$(_ws_behind)" = no ] || warn "$WS_NAME is behind origin/$(meta ref); planning against the last render"
    route_plan; _ws_print_plan
    return 0
  fi
  [ "$(meta ref)" = main ] || die "layout not on main yet — merge its PR, then run: delphi workspace refresh --ref main"
  delphi_fetch
  ws_refresh
  route_plan
  case $(dgit remote get-url origin 2>/dev/null) in *github.com*) user=$(gh api user --jq .login 2>/dev/null || true) ;; esac
  branch="delphi/propose/${user:-${USER:-me}}/$WS_NAME"
  if [ -z "$(sed '/^noop	/d' "$RT/plan")" ]; then info "nothing to propose"; _ws_warn_open_pr "$branch"; return 0; fi
  # lease: the branch must be absent or exactly what we last pushed
  remote=$(dgit ls-remote --heads origin "refs/heads/$branch" | cut -f1) || die "cannot reach origin"
  if [ -n "$remote" ] && [ "$remote" != "$(meta last_pushed)" ]; then
    meta_set last_pushed "$remote"
    die "the propose branch changed on GitHub (someone pushed to it); review the PR, then re-run to overwrite it"
  fi
  provenance_resolve "$OPT_MODEL" "$OPT_EFFORT" "$(meta harness)"
  PROV_EXTRA=$(printf 'Delphi-Layout: %s\nDelphi-Workspace: %s\nDelphi-Base: %.7s' "$(meta layout_path)" "$WS_NAME" "$(meta render_commit)")
  PROV_ROWS=$(_ws_prov_rows)
  pr_begin "$branch" "$(meta render_commit)"
  route_apply
  if ! pr_has_commits; then
    _ws_print_plan; info "nothing routable to propose; resolve the items above in the workspace"
    _ws_warn_open_pr "$branch"; return 0
  fi
  check_tree "$PR_WT" || die "check failed on the proposed tree; not pushed (branch $PR_BRANCH kept locally)"
  body=$(printf '## Routed changes\n\n'
         awk -F'\t' '{ printf "- %s: `%s` (from workspace `%s`)\n", $1, $3, $2 }' "$RT/applied"
         printf '\n## Unresolved\n\n'
         if [ -s "$RT/unresolved.md" ]; then cat "$RT/unresolved.md"; else echo None.; fi)
  pr_finish "delphi: changes from workspace $WS_NAME ($(meta layout))" "$body" "$remote"
  if [ "$PR_PUSHED" = 1 ]; then
    meta_set last_proposed "$(now)"; meta_set last_proposed_hash "$(_ws_hash)"
    meta_set last_pushed "$(git -C "$PR_WT" rev-parse HEAD)"
  fi
}
