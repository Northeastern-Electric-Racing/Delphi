# block.sh — `delphi block mv <old> <new>`: move a block, log it in moves.tsv, rewrite references.
. "$DELPHI_ROOT/lib/parse.sh"
. "$DELPHI_ROOT/lib/provenance.sh"
. "$DELPHI_ROOT/lib/pr.sh"
. "$DELPHI_ROOT/lib/check.sh"

block_main() {
  local verb=${1:-}
  [ $# -gt 0 ] && shift
  parse_args "$@"; eval "set -- $ARGS"
  [ "$verb" = mv ] && [ $# -eq 2 ] || die "usage: delphi block mv <old> <new>"
  block_mv "${1%/}" "${2%/}"
}

block_mv() {
  local old=$1 new=$2 p src dst f
  for p in "$old" "$new"; do
    path_ok "$p" || die "unsafe path: '$p'"
    case "/$p" in */blocks/?*|*/harness/?*) ;; *) die "'$p' is not under a scope's blocks/ or harness/" ;; esac
  done
  delphi_fetch
  p=$(delphi_commit main) || exit 1
  provenance_resolve "$OPT_MODEL" "$OPT_EFFORT" claude-code
  pr_begin "delphi/mv/${old##*/}-$(date +%Y%m%d)" "$p"
  src=$(safe_path "$PR_WT/context" "$old") || exit 1
  dst=$(safe_path "$PR_WT/context" "$new") || exit 1
  [ -e "$src" ] || die "no such block on origin/main: $old"
  [ -e "$dst" ] && die "already exists on origin/main: $new"
  mkdir -p "$(dirname "$dst")" && git -C "$PR_WT" mv "context/$old" "context/$new" || die "git mv failed"
  printf '%s\t%s\t%s\n' "$old" "$new" "$(date +%Y-%m-%d)" >> "$PR_WT/moves.tsv"
  while IFS= read -r f; do rewrite_moves "$PR_WT/moves.tsv" "$f" || true; done <<EOF
$(find "$PR_WT/context" -type f \( -name manifest.yml -o -name scope.yml -o -name '*.skill' \))
EOF
  check_tree "$PR_WT" || die "check failed after the move; nothing pushed"
  pr_commit "delphi: move $old -> $new" || die "nothing to commit"
  pr_finish "delphi: move $old -> $new" "Moves \`$old\` to \`$new\` and rewrites references. Workspaces follow on their next refresh." 0
  printf '%s\n' "$PR_BRANCH"
}
