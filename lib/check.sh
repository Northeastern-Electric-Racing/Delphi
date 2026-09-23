# check.sh — repo-wide validation. `check_tree <root>` prints every violation, returns 1 if any.
# Layouts are validated by compiling them; the rules here cover what compile doesn't enforce.
. "$DELPHI_ROOT/lib/parse.sh"
. "$DELPHI_ROOT/lib/compile.sh"

check_main() {
  [ $# -eq 0 ] || die "usage: delphi check"
  if check_tree "$DELPHI_ROOT"; then info "check: ok"; else exit 1; fi
}

_ce() { printf '%s\n' "$*" >> "$_CHECK_ERRS"; }

# _ck_entry <file> <key> <path> <kind>: placement rule for the kind (instructions|skills|mcp|
# settings|body); `body` (skill specs) and `any` (recommendations) must also exist.
_ck_entry() {
  local f=$1 key=$2 p=$3 want='*'
  path_ok "${p%/\*}" || { _ce "$f: $key: unsafe path '$p'"; return 0; }
  case $4 in
    instructions) want='*/harness/instructions/*' ;; skills) want='*/harness/skills/*' ;;
    mcp) want='*/harness/mcp/*.json' ;; settings) want='*/harness/settings/*' ;; body) want='*/blocks/*' ;;
  esac
  case "/$p" in $want) ;; *) _ce "$f: $key: '$p' is not under ${want#\*/}" ;; esac
  case $4 in body|any) [ -e "$_CK_ROOT/context/$p" ] || _ce "$f: $key: missing '$p'" ;; esac
  return 0
}

check_tree() {
  _CK_ROOT=$1
  local ctx="$1/context" f rel recs k p n names dup name hfile h i=0
  make_tmp; _CHECK_ERRS="$REPLY/errs"; : > "$_CHECK_ERRS"
  [ -d "$ctx" ] || { _ce "missing context/ directory"; cat "$_CHECK_ERRS" >&2; return 1; }

  # scopes: every non-reserved directory needs scope.yml
  while IFS= read -r d; do
    [ -f "$d/scope.yml" ] || _ce "${d#$1/}: scope directory has no scope.yml"
    for f in "$d"/*; do
      [ -f "$f" ] && [ "${f##*/}" != scope.yml ] && _ce "${f#$1/}: stray file (scopes hold only scope.yml, blocks/, docs/, harness/, layouts/, child scopes)"
    done
  done <<EOF
$(find "$ctx" -type d \( -name blocks -o -name docs -o -name harness -o -name layouts \) -prune -o -type d -print)
EOF

  # files: no symlinks, no empty files, trailing newline, no harness instruction file names
  [ -z "$(find "$ctx" -type l)" ] || _ce "context/ must not contain symlinks: $(find "$ctx" -type l | sed "s#^$1/##" | tr '\n' ' ')"
  hfile=""
  for h in "$DELPHI_ROOT"/lib/harness/*.sh; do
    hfile="$hfile
$( (. "$h"; printf '%s' "$HARNESS_INSTRUCTIONS") )"
  done
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    rel=${f#$1/}
    [ -s "$f" ] || { _ce "$rel: empty file"; continue; }
    [ -z "$(tail -c 1 "$f")" ] || _ce "$rel: missing trailing newline"
    in_list "${f##*/}" "$hfile" && _ce "$rel: harness instruction file names are not allowed under context/"
  done <<EOF
$(find "$ctx" -type f)
EOF

  # every yml/skill parses
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    parse_yaml "$f" > /dev/null 2>> "$_CHECK_ERRS" || true
  done <<EOF
$(find "$ctx" -type f \( -name '*.yml' -o -name '*.skill' \))
EOF

  # scope recommendations exist
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    recs=$(parse_yaml "$f" 2>/dev/null) || continue
    while IFS= read -r p; do [ -n "$p" ] && _ck_entry "${f#$1/}" recommend "$p" any; done <<EOF2
$(yaml_list "$recs" recommend)
EOF2
  done <<EOF
$(find "$ctx" -type f -name scope.yml)
EOF

  # skill specs
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    rel=${f#$1/}
    recs=$(parse_yaml "$f" 2>/dev/null) || continue
    [ -n "$(yaml_get "$recs" name)" ] || _ce "$rel: missing name"
    [ -n "$(yaml_get "$recs" description)" ] || _ce "$rel: missing description"
    for k in $(yaml_keys "$recs"); do
      case $k in name|description|body|references) ;; *) _ce "$rel: unknown key '$k'" ;; esac
    done
    while IFS= read -r p; do [ -n "$p" ] && _ck_entry "$rel" body "$p" body; done <<EOF2
$(yaml_list "$recs" body; yaml_list "$recs" references)
EOF2
  done <<EOF
$(find "$ctx" -type f -name '*.skill')
EOF

  # layouts
  names=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    rel=${f#$1/}
    recs=$(parse_yaml "$f" 2>/dev/null) || continue
    name=$(yaml_get "$recs" name)
    dup=${f%/manifest.yml}; dup=${dup##*/}
    [ -n "$name" ] || _ce "$rel: missing name"
    [ "$name" = "$dup" ] || _ce "$rel: name '$name' must equal its directory '$dup'"
    in_list "$name" "$names" && _ce "$rel: layout name '$name' is not unique"
    names="$names
$name"
    h=$(yaml_get "$recs" harness)
    if [ -z "$h" ]; then _ce "$rel: missing harness"
    elif [ ! -f "$DELPHI_ROOT/lib/harness/$h.sh" ]; then _ce "$rel: unknown harness '$h'"
    else   # compile it: catches missing paths, empty globs, duplicate outputs, bad skill specs
      i=$((i + 1)); mkdir "$_CHECK_ERRS.$i"
      ( compile "$1" "$(dirname "${rel#context/}")" "$_CHECK_ERRS.$i" ) 2>&1 > /dev/null | sed "s#^delphi: #$rel: #" >> "$_CHECK_ERRS" || true
    fi
    for k in $(yaml_keys "$recs"); do
      case $k in name|harness|instructions|blocks|docs|skills|mcp|settings|repos) ;; *) _ce "$rel: unknown key '$k'" ;; esac
    done
    n=$(yaml_list "$recs" settings | awk 'NF' | awk 'END { print NR }')
    [ "$n" -le 1 ] || _ce "$rel: at most one settings file"
    for k in instructions skills mcp settings; do
      while IFS= read -r p; do [ -n "$p" ] && _ck_entry "$rel" "$k" "$p" "$k"; done <<EOF2
$(yaml_list "$recs" "$k")
EOF2
    done
  done <<EOF
$(find "$ctx" -type f -path '*/layouts/*/manifest.yml')
EOF

  # moves.tsv: three fields
  [ ! -f "$1/moves.tsv" ] ||
    awk -F'\t' '!/^#/ && NF && NF != 3 { printf "moves.tsv:%d: expected old<TAB>new<TAB>date\n", NR }' "$1/moves.tsv" >> "$_CHECK_ERRS"

  # MCP fragments are valid JSON (only if jq is installed)
  if command -v jq > /dev/null 2>&1; then
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      { printf '{'; cat "$f"; printf '}'; } | jq empty > /dev/null 2>&1 || _ce "${f#$1/}: not a valid mcpServers member"
    done <<EOF
$(find "$ctx" -type f -path '*/harness/mcp/*.json')
EOF
  else
    info "check: jq not installed; skipping MCP JSON validation"
  fi

  if [ -s "$_CHECK_ERRS" ]; then sed 's/^/check: /' "$_CHECK_ERRS" >&2; return 1; fi
  return 0
}
