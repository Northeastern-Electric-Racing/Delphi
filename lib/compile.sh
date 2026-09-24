# compile.sh — layout -> workspace files + .delphi/lock.tsv (segment map). Deterministic.
#
# compile <src-root> <layout-dir> <outdir>
#   <src-root>   a checked-out Delphi tree (usually a temp worktree at a specific commit)
#   <layout-dir> layout directory relative to context/ (…/layouts/<name>)
#   <outdir>     empty directory to write into
# Requires parse.sh. Sets R_HARNESS to the layout's harness name.

_r_count() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }

# _r_seg <out-rel> <start> <end> <source> <sha>
_r_seg() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$R_LOCK"; }

# _r_file <out-rel> <src-rel>: append a source file (relative to context/) to an output file.
_r_file() {
  local out="$R_OUT/$1" src start end
  src=$(safe_path "$R_SRC/context" "$2") || exit 1
  [ -f "$src" ] || die "compile: missing file context/$2"
  [ -s "$src" ] || die "compile: empty file context/$2"
  mkdir -p "$(dirname "$out")"
  start=$(( $(_r_count "$out") + 1 ))
  cat "$src" >> "$out"
  [ -n "$(tail -c 1 "$src")" ] && printf '\n' >> "$out"
  end=$(_r_count "$out")
  _r_seg "$1" "$start" "$end" "$2" "$(git hash-object "$src")"
}

# _r_copy <out-rel> <src-rel>: 1:1 copy (keeps the executable bit); the output path must not already exist.
_r_copy() {
  [ -e "$R_OUT/$1" ] && die "compile: two sources map to the same output '$1'"
  _r_file "$1" "$2"
  if [ -x "$R_SRC/context/$2" ]; then chmod +x "$R_OUT/$1" || die "compile: cannot chmod $1"; fi
}

# _r_text <out-rel> <label> <text>: append generated (@gen:…) or separator (@glue) lines.
_r_text() {
  local out="$R_OUT/$1" start end
  mkdir -p "$(dirname "$out")"
  start=$(( $(_r_count "$out") + 1 ))
  printf '%s\n' "$3" >> "$out"
  end=$(_r_count "$out")
  _r_seg "$1" "$start" "$end" "$2" -
}

# _r_expand <entry>: prints the files an entry names (a file, or a trailing /* glob).
_r_expand() {
  local dir abs n
  case $1 in
    */\*)
      dir=${1%/\*}
      abs=$(safe_path "$R_SRC/context" "$dir") || exit 1
      [ -d "$abs" ] || die "compile: no such directory context/$dir"
      n=0
      for f in "$abs"/*; do [ -f "$f" ] && { printf '%s/%s\n' "$dir" "${f##*/}"; n=$((n + 1)); }; done
      [ "$n" -gt 0 ] || die "compile: glob matches nothing: $1"
      ;;
    *) printf '%s\n' "$1" ;;
  esac
}

_r_header() {
  printf '%s\n' \
    "<!-- Compiled by Delphi from layout '$1'. Edit freely: every line is traced to its source block. -->" \
    "<!-- When your work is done, commit it; 'delphi workspace propose' sends block changes upstream. -->"
}

compile() {
  R_SRC=$1; R_OUT=$3
  local layout=$2 mf recs name item f files first abs sub spec srecs sname sdesc skdir
  R_LOCK="$R_OUT/.delphi/lock.tmp"
  mkdir -p "$R_OUT/.delphi" && : > "$R_LOCK" || die "compile: cannot write $R_OUT"

  mf=$(safe_path "$R_SRC/context" "$layout/manifest.yml") || exit 1
  recs=$(parse_yaml "$mf") || exit 1
  name=$(yaml_get "$recs" name)
  R_HARNESS=$(yaml_get "$recs" harness)
  [ -n "$R_HARNESS" ] || die "compile: $layout/manifest.yml has no harness"
  load_harness "$R_HARNESS"

  # instructions: header, then fragments separated by one blank line
  _r_text "$HARNESS_INSTRUCTIONS" @gen:delphi "$(_r_header "$name")"
  while IFS= read -r item; do
    [ -z "$item" ] && continue
    _r_text "$HARNESS_INSTRUCTIONS" @glue ""
    _r_file "$HARNESS_INSTRUCTIONS" "$item"
  done <<EOF
$(yaml_list "$recs" instructions)
EOF

  # blocks: mirrored at context/<path>
  while IFS= read -r item; do
    [ -z "$item" ] && continue
    files=$(_r_expand "$item") || exit 1
    while IFS= read -r f; do
      case "/$f" in */blocks/*) ;; *) die "compile: '$f' is listed under blocks: but is not in a blocks/ directory" ;; esac
      _r_copy "context/$f" "$f"
    done <<EOF2
$files
EOF2
  done <<EOF
$(yaml_list "$recs" blocks)
EOF

  # docs: at docs/<path below the scope's docs/>
  while IFS= read -r item; do
    [ -z "$item" ] && continue
    files=$(_r_expand "$item") || exit 1
    while IFS= read -r f; do
      case "/$f" in */docs/?*) ;; *) die "compile: '$f' is listed under docs: but is not in a docs/ directory" ;; esac
      sub="/$f"; _r_copy "docs/${sub#*/docs/}" "$f"
    done <<EOF2
$files
EOF2
  done <<EOF
$(yaml_list "$recs" docs)
EOF

  # skills: native dirs copied 1:1; .skill specs assembled
  while IFS= read -r item; do
    [ -z "$item" ] && continue
    case $item in
      *.skill)
        spec=$(safe_path "$R_SRC/context" "$item") || exit 1
        srecs=$(parse_yaml "$spec") || exit 1
        sname=$(yaml_get "$srecs" name); sdesc=$(yaml_get "$srecs" description)
        [ -n "$sname" ] && [ -n "$sdesc" ] || die "compile: $item needs name and description"
        skdir="$HARNESS_SKILLS_DIR/$sname"
        [ -e "$R_OUT/$skdir" ] && die "compile: two skills named '$sname'"
        _r_text "$skdir/SKILL.md" "@gen:$item" "$(printf -- '---\nname: %s\ndescription: %s\n---' "$sname" "$sdesc")"
        while IFS= read -r f; do
          [ -z "$f" ] && continue
          _r_text "$skdir/SKILL.md" @glue ""
          _r_file "$skdir/SKILL.md" "$f"
        done <<EOF2
$(yaml_list "$srecs" body)
EOF2
        while IFS= read -r f; do
          [ -z "$f" ] && continue
          _r_copy "$skdir/references/${f##*/}" "$f"
        done <<EOF2
$(yaml_list "$srecs" references)
EOF2
        ;;
      *)
        abs=$(safe_path "$R_SRC/context" "$item") || exit 1
        [ -f "$abs/SKILL.md" ] || die "compile: skill '$item' has no SKILL.md"
        skdir="$HARNESS_SKILLS_DIR/${item##*/}"
        [ -e "$R_OUT/$skdir" ] && die "compile: two skills named '${item##*/}'"
        while IFS= read -r sub; do
          [ -z "$sub" ] && continue
          _r_copy "$skdir/$sub" "$item/$sub"
        done <<EOF2
$(cd "$abs" && find . -type f | sed 's#^\./##' | LC_ALL=C sort)
EOF2
        ;;
    esac
  done <<EOF
$(yaml_list "$recs" skills)
EOF

  # mcp: fragments wrapped in {"mcpServers": { … }}, omitted when empty
  first=1
  while IFS= read -r item; do
    [ -z "$item" ] && continue
    if [ "$first" = 1 ]; then _r_text "$HARNESS_MCP_FILE" @gen:delphi '{"mcpServers": {'; first=0
    else _r_text "$HARNESS_MCP_FILE" @glue ','; fi
    _r_file "$HARNESS_MCP_FILE" "$item"
  done <<EOF
$(yaml_list "$recs" mcp)
EOF
  [ "$first" = 0 ] && _r_text "$HARNESS_MCP_FILE" @gen:delphi '}}'

  # settings: single file copied 1:1
  item=$(yaml_get "$recs" settings)
  [ -n "$item" ] && _r_copy "$HARNESS_SETTINGS_FILE" "$item"

  # the layout manifest itself, editable in the workspace
  _r_copy .delphi/manifest.yml "$layout/manifest.yml"

  { printf '# output\tstart\tend\tsource\tsha\n'; cat "$R_LOCK"; } > "$R_OUT/.delphi/lock.tsv"
  rm -f "$R_LOCK"
}
