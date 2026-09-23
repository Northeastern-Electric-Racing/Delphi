# route.sh — a workspace's pending diff -> edits against the Delphi tree (spec §8).
#
#   route_plan    route `generated-merged..HEAD` of workspace $WS; results in $RT:
#                   plan           manifest <out> <layout manifest>
#                                  patch    <out> <block> <patchfile>
#                                  key      <out> <spec> <key> <value>
#                                  new      <out> <target> [<manifest key> <entry>]
#                                  noop     <out> <reason>
#                                  unresolved <out> <reason>
#                   unresolved.md  one markdown section per unresolved item (for the PR body)
#   route_apply   apply the plan inside $PR_WT, one commit per step (manifest, edits, new files)
# Requires workspace.sh helpers (wgit, meta) and pr.sh.

_rt_row() { local IFS='	'; printf '%s\n' "$*" >> "$RT/plan"; }

# _rt_unres <out> <reason>: file-level unresolved item, with the file's diff.
_rt_unres() {
  local d
  _rt_row unresolved "$1" "$2"
  d=$(wgit diff --no-renames generated-merged HEAD -- "$1" | awk '/^@@|^Binary/ { p = 1 } p')
  printf '#### `%s`: %s\n\n```diff\n%s\n```\n\n' "$1" "$2" "$d" >> "$RT/unresolved.md"
}

# _rt_covered <path> <entries-file>: an entry names the path, a parent dir, or a */ glob over it.
_rt_covered() {
  awk -v p="$1" '
    $0 == p || index(p, $0 "/") == 1 { f = 1; exit }
    /\/\*$/ && index(p, substr($0, 1, length($0) - 1)) == 1 && index(substr(p, length($0)), "/") == 0 { f = 1; exit }
    END { exit !f }' "$2"
}

# _rt_skill_src <out>: source of the rendered skill dir holding <out>: a .skill spec (built),
# a native skill dir, or empty when that skill dir is not rendered.
_rt_skill_src() {
  local p=${1#"$HARNESS_SKILLS_DIR"/}
  p="$HARNESS_SKILLS_DIR/${p%%/*}/"
  awk -F'\t' -v p="$p" 'index($1, p) != 1 { next }
    $4 ~ /^@gen:/ { g = substr($4, 6) }
    $4 !~ /^@/ && d == "" { d = substr($4, 1, length($4) - length($1) + length(p) - 1) }
    END { print (g != "" ? g : d) }' "$RT/lock"
}

# _rt_dropped <out>: the deleted output's sources are gone from the workspace manifest. Anything
# in a built skill's dir counts as dropped only when its .skill spec is.
_rt_dropped() {
  local s
  case $1 in "$HARNESS_SKILLS_DIR"/*/*)
    s=$(_rt_skill_src "$1")
    case $s in *.skill) ! _rt_covered "$s" "$RT/entries"; return ;; esac ;;
  esac
  for s in $(awk -F'\t' -v o="$1" '$1 == o && $4 !~ /^@/ { print $4 }' "$RT/lock"); do
    _rt_covered "$s" "$RT/entries" && return 1
  done
  return 0
}

route_plan() {
  local rc lp st out p scope sk name rest src n=0
  make_tmp; RT=$REPLY; mkdir -p "$RT/p"; : > "$RT/plan"; : > "$RT/unresolved.md"
  rc=$(meta render_commit); lp=$(meta layout_path)
  load_harness "$(meta harness)"
  wgit show generated-merged:.delphi/lock.tsv | sed '/^#/d' > "$RT/lock" || die "cannot read lock"
  wgit show HEAD:.delphi/manifest.yml > "$RT/manifest.yml" || die "cannot read .delphi/manifest.yml"
  parse_yaml "$RT/manifest.yml" | awk -F'\t' 'NF == 2 { print $2 }' > "$RT/entries" || exit 1
  _ws_pending --numstat > "$RT/numstat"
  _ws_pending --name-status > "$RT/files"
  sk=$HARNESS_SKILLS_DIR
  while IFS='	' read -r st out; do
    case "$st:$out" in
      M:.delphi/manifest.yml) _rt_row manifest "$out" "$lp/manifest.yml"; continue ;;
      *:.delphi/*) _rt_unres "$out" "Delphi bookkeeping file; only .delphi/manifest.yml edits are proposed"; continue ;;
    esac
    if awk -F'\t' -v o="$out" '$3 == o && $1 == "-" { f = 1 } END { exit !f }' "$RT/numstat"; then
      _rt_unres "$out" "binary file"; continue
    fi
    case $st in
      D)
        if _rt_dropped "$out"; then _rt_row noop "$out" "deleted; its source was dropped from .delphi/manifest.yml"
        else _rt_unres "$out" "deleted, but still rendered by .delphi/manifest.yml (drop blocks by editing the manifest)"; fi ;;
      M)
        awk -F'\t' -v o="$out" '$1 == o' "$RT/lock" > "$RT/seg"
        if [ ! -s "$RT/seg" ]; then _rt_unres "$out" "not a rendered file"; continue; fi
        n=$((n + 1))
        wgit diff -U0 --no-renames generated-merged HEAD -- "$out" > "$RT/diff"
        awk -F'\t' -v OUT="$out" -v PDIR="$RT/p" -v PID="$n" -v UMD="$RT/unresolved.md" \
          -f "$DELPHI_ROOT/lib/route.awk" "$RT/seg" "$RT/diff" >> "$RT/plan" || die "route.awk failed on $out" ;;
      A)
        case $out in
          context/*)
            p=${out#context/}; scope="/$p"
            case $scope in */blocks/*) scope=${scope%%/blocks/*}; scope=${scope#/} ;; *) scope=-; esac
            if [ "$scope" != - ] && path_ok "$p" && dgit cat-file -e "$rc:context/${scope:+$scope/}scope.yml" 2>/dev/null; then
              _rt_row new "$out" "$p" blocks "$p"
            else
              _rt_unres "$out" "new file: must be under context/<existing scope>/blocks/"
            fi ;;
          "$sk"/*/*)
            name=${out#"$sk"/}; name=${name%%/*}; rest=${out#"$sk/$name/"}
            src=$(_rt_skill_src "$out")
            case $src in
              "") src="${lp%layouts/*}harness/skills/$name"; _rt_row new "$out" "$src/$rest" skills "$src" ;;
              *.skill) _rt_unres "$out" "new file in a built (.skill) skill: add it as a block and list it in the spec" ;;
              *) _rt_row new "$out" "$src/$rest" ;;
            esac ;;
          *) _rt_unres "$out" "new file: must be under context/<scope>/blocks/ or $sk/<name>/" ;;
        esac ;;
      *) _rt_unres "$out" "unsupported change type '$st'" ;;
    esac
  done < "$RT/files"
}

# _rt_list_add <file> <key> <entry>: append `  - entry` to a top-level list, creating the key.
_rt_list_add() {
  awk -v k="$2" -v v="$3" '
    ins && !/^  - / { print "  - " v; ins = 0; done = 1 }
    { print }
    $0 ~ "^" k ":[ ]*(#.*)?$" { ins = 1 }
    END { if (ins) print "  - " v; else if (!done) { print k ":"; print "  - " v } }' "$1" > "$1.tmp" &&
    mv "$1.tmp" "$1" || die "cannot update $1"
}

route_apply() {
  local k out tgt a b mf lay dst entries
  lay=$(meta layout); mf=$(safe_path "$PR_WT/context" "$(meta layout_path)/manifest.yml") || exit 1

  if awk -F'\t' '$1 == "manifest" { f = 1 } END { exit !f }' "$RT/plan"; then
    cp "$WS/.delphi/manifest.yml" "$mf" || die "cannot copy manifest"
    rewrite_moves "$PR_WT/moves.tsv" "$mf" || true
    pr_commit "delphi: update layout $lay from workspace $WS_NAME" || true
  fi

  while IFS='	' read -r k out tgt a b; do
    case $k in
      patch)
        git -C "$PR_WT" apply --unidiff-zero "$a" 2>/dev/null || {
          _rt_row unresolved "$out" "patch for $tgt did not apply"
          printf '#### `%s`: patch for `%s` did not apply (block edited in two places?)\n\n```diff\n%s\n```\n\n' \
            "$out" "$tgt" "$(sed '1,2d' "$a")" >> "$RT/unresolved.md"
        } ;;
      key)
        case $b in *'"'*) _rt_unres "$out" "new $a value contains a double quote (not supported)"; continue ;; esac
        case $b in *" #"*|[\[{\&\*\|\>\!#]*) b="\"$b\"" ;; esac
        dst=$(safe_path "$PR_WT/context" "$tgt") || exit 1
        V=$b awk -v k="$a" 'index($0, k ":") == 1 && !d { print k ": " ENVIRON["V"]; d = 1; next } { print }' "$dst" > "$dst.tmp" &&
          mv "$dst.tmp" "$dst" || die "cannot update $tgt" ;;
    esac
  done < "$RT/plan"
  pr_commit "delphi: route block edits from workspace $WS_NAME" || true

  make_tmp; entries="$REPLY/entries"
  while IFS='	' read -r k out tgt a b; do
    [ "$k" = new ] || continue
    dst=$(safe_path "$PR_WT/context" "$tgt") || exit 1
    mkdir -p "$(dirname "$dst")" && cp "$WS/$out" "$dst" || die "cannot add $tgt"
    [ -n "$a" ] || continue
    parse_yaml "$mf" | awk -F'\t' -v k="$a" 'NF == 2 && $1 == k { print $2 }' > "$entries" || exit 1
    _rt_covered "$b" "$entries" || _rt_list_add "$mf" "$a" "$b"
  done < "$RT/plan"
  pr_commit "delphi: add new files from workspace $WS_NAME" || true
}
