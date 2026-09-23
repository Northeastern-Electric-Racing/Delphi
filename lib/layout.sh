# layout.sh — `delphi layout new|list`. `new` is a basic y/n picker; the delphi-new-layout skill
# drafts richer manifests and passes them with --from.
. "$DELPHI_ROOT/lib/parse.sh"
. "$DELPHI_ROOT/lib/provenance.sh"
. "$DELPHI_ROOT/lib/pr.sh"
. "$DELPHI_ROOT/lib/check.sh"

layout_main() {
  local verb=${1:-}
  [ $# -gt 0 ] && shift
  if [ "$verb" = new ]; then parse_args "--from --model --effort --yes" "$@"; else parse_args "" "$@"; fi
  eval "set -- $ARGS"
  case "$verb:$#" in
    new:2)  layout_new "${1%/}" "$2" ;;
    list:0) layout_list ;;
    *) die "usage: delphi layout new <scope> <layout> [--from <file>] | delphi layout list" ;;
  esac
}

layout_list() {
  local c f recs scope
  delphi_fetch
  c=$(delphi_commit main) || exit 1
  make_tmp
  dgit ls-tree -r --name-only "$c" -- context | sed -n '/\/layouts\/[^/]*\/manifest\.yml$/p' > "$REPLY/list"
  while IFS= read -r f; do
    dgit show "$c:$f" > "$REPLY/m" && recs=$(parse_yaml "$REPLY/m") || { warn "cannot parse $f"; continue; }
    scope=${f#context/}; scope=${scope%layouts/*}; scope=${scope%/}
    printf '%s\t%s\t%s\n' "$(yaml_get "$recs" name)" "${scope:-.}" "$(yaml_get "$recs" harness)"
  done < "$REPLY/list"
}

# _layout_pick <commit> <scope> <name> <tmpdir>: interactive manifest on stdout (prompts on stderr).
_layout_pick() {
  local c=$1 scope=$2 s=$2 items="" sel="" it key a h hs line k list IFS='
'
  is_tty || die "non-interactive session: pass a drafted manifest with --from <file>"
  while :; do   # recommendations, closest scope first
    dgit show "$c:context/${s:+$s/}scope.yml" > "$4/scope.yml" 2>/dev/null &&
      items="$items
$(parse_yaml "$4/scope.yml" | awk -F'\t' '$1 == "recommend" && NF == 2 { print $2 }')"
    [ -n "$s" ] || break
    case $s in */*) s=${s%/*} ;; *) s="" ;; esac
  done
  items="$items
$(dgit ls-tree -r --name-only "$c" -- "context/$scope/blocks" | sed 's#^context/##')"
  for it in $(printf '%s\n' "$items" | awk 'NF && !seen[$0]++'); do
    case "/$it" in
      */harness/instructions/*) key=instructions ;; */harness/skills/*) key=skills ;;
      */harness/mcp/*) key=mcp ;; */harness/settings/*) key=settings ;; */blocks/*) key=blocks ;; */docs/*) key=docs ;;
      *) warn "skipping '$it': not a block or harness path"; continue ;;
    esac
    a=$(ask "Include $it? [y/N]") || exit 1
    case $a in y|Y|yes) ;; *) continue ;; esac
    if [ "$key" = settings ] && in_list settings "$(printf '%s\n' "$sel" | cut -f1)"; then
      warn "only one settings file; keeping the first"; continue
    fi
    sel="$sel
$key	$it"
  done
  hs=$(cd "$DELPHI_ROOT/lib/harness" && ls *.sh | sed 's/\.sh$//')
  h=$hs
  case $hs in *"$IFS"*) h=$(ask "Harness ($(printf '%s' "$hs" | tr '\n' ' '))?" claude-code) || exit 1 ;; esac
  printf 'name: %s\nharness: %s\n' "$3" "$h"
  for k in instructions blocks docs skills mcp; do
    list=$(printf '%s\n' "$sel" | awk -F'\t' -v k="$k" '$1 == k { print "  - " $2 }')
    if [ -n "$list" ]; then printf '%s:\n%s\n' "$k" "$list"; fi
  done
  list=$(printf '%s\n' "$sel" | awk -F'\t' '$1 == "settings" { print $2 }')
  if [ -n "$list" ]; then printf 'settings: %s\n' "$list"; fi
  list=""
  while line=$(ask "Repo as 'name url' (blank to finish):") && [ -n "$line" ]; do
    case $line in *" "?*) list="$list
  ${line%% *}: ${line#* }" ;; *) warn "expected 'name url'" ;; esac
  done
  if [ -n "$list" ]; then printf 'repos:%s\n' "$list"; fi
}

layout_new() {
  local scope=$1 name=$2 c mf recs h
  case $name in *[!a-z0-9-]*|"") die "invalid layout name: '$name' (use a-z, 0-9, -)" ;; esac
  path_ok "$scope" || die "invalid scope: '$scope'"
  [ -z "$OPT_FROM" ] || [ -f "$OPT_FROM" ] || die "no such file: $OPT_FROM"
  delphi_fetch
  c=$(delphi_commit main) || exit 1
  dgit cat-file -e "$c:context/$scope/scope.yml" 2>/dev/null || die "not a scope on origin/main: $scope"
  [ -z "$(dgit ls-tree -r --name-only "$c" -- context | sed -n "/\/layouts\/$name\/manifest\.yml\$/p")" ] ||
    die "layout name already used: $name"
  make_tmp; mf="$REPLY/manifest.yml"
  if [ -n "$OPT_FROM" ]; then cp "$OPT_FROM" "$mf" || die "cannot read $OPT_FROM"
  else _layout_pick "$c" "$scope" "$name" "$REPLY" > "$mf" || exit 1; fi
  recs=$(parse_yaml "$mf") || exit 1
  [ "$(yaml_get "$recs" name)" = "$name" ] || die "manifest name must be '$name'"
  h=$(yaml_get "$recs" harness)
  [ -n "$h" ] || die "manifest has no harness"
  provenance_resolve "$OPT_MODEL" "$OPT_EFFORT" "$h"
  pr_begin "delphi/layout/$name" "$c"
  mkdir -p "$PR_WT/context/$scope/layouts/$name" && cp "$mf" "$PR_WT/context/$scope/layouts/$name/manifest.yml" ||
    die "cannot write manifest"
  check_tree "$PR_WT" || die "layout fails check; nothing pushed"
  pr_commit "delphi: add layout $name" || die "nothing to commit"
  pr_finish "delphi: add layout $name" "Adds layout \`$name\` in scope \`$scope\`:

\`\`\`yaml
$(cat "$mf")
\`\`\`"
  printf '%s\n' "$PR_BRANCH"
}
