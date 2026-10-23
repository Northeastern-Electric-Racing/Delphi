#!/usr/bin/env bash
# ci/render.sh [--check] [<main checkout>]: materialize native managed files before a PR reaches main.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=ci/inherit.sh
source "$here/inherit.sh"
# shellcheck source=ci/managed.sh
source "$here/managed.sh"
check=0
[ "${1:-}" != --check ] || { check=1; shift; }
cd "${1:-.}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
problems=0
bad() { echo "render: $*" >&2; problems=$((problems + 1)); }
if [ "$check" = 1 ]; then
  bash "$here/plugins.sh" --check . || problems=$((problems + 1))
else
  bash "$here/plugins.sh" . || exit 1
fi

render_workspace() { # <workspace folder>
  local folder=$1 adapter out records old meta path src seen="" used="" o start=$problems previous actual
  adapter=$(awk '/^harness:/ { print $2; exit }' "$folder/workspace.yml")
  harness "$adapter" || { bad "$folder/workspace.yml: unknown harness '$adapter'"; return; }
  if [ "$plugins" = none ] && awk '/^plugins:/ { s = 1; next } /^[^[:space:]#]/ { s = 0 }
    s && /^[[:space:]]+-/ { found = 1 } END { exit !found }' "$folder/workspace.yml"; then
    bad "$folder/workspace.yml: $adapter does not support Delphi plugin sets"; return
  fi
  out=$(optouts <"$folder/workspace.yml")
  records=$(inherited_files "$folder" "$adapter") || { bad "$folder: cannot resolve inherited sources"; return; }
  old=""
  [ ! -f "$folder/$generated" ] || old=$(generated_records <"$folder/$generated") || { bad "$folder/$generated: invalid ownership record"; return; }
  rm -rf "$tmp/native"
  : >"$tmp/records"
  while IFS=$'\t' read -r meta path src; do
    [ -n "$path" ] || continue
    if ! safe_path "$path" || ! safe_path "$src"; then
      bad "$src: unsafe inherited destination '$path'"; continue
    fi
    case "$path" in CLAUDE.md | AGENTS.md | workspace.yml | workspace.generated | .delphi | .delphi/* | .claude/settings.json | .codex/config.toml | .github/workflows/delphi.yml)
      bad "$src: each workspace has its own $path; it can't be inherited"; continue ;;
    esac
    case " $seen " in *" $path "*) bad "$src: $folder also inherits it from a folder above; keep one" ;; esac
    seen="$seen $path"
    for o in $out; do
      if opted_out "$path" "$o"; then used="$used $o"; fi
    done
    opted_out "$path" "$out" && continue
    mkdir -p "$(dirname "$tmp/native/$path")"
    harness_file "$adapter" "$src" >"$tmp/native/$path"
    meta="${meta%% *} $(git hash-object -- "$tmp/native/$path")"
    printf '%s\t%s\t%s\n' "$meta" "$path" "$src" >>"$tmp/records"
  done <<<"$records"
  for o in $out; do
    case " $used " in *" $o "*) ;; *) bad "$folder/workspace.yml: opt-out: $o is nothing it inherits" ;; esac
  done
  if [ "$plugins" = claude ] && [ -f "$folder/.claude/settings.json" ]; then
    printf '100644 %s\t.claude/settings.json\tci/plugins.sh\n' "$(git hash-object -- "$folder/.claude/settings.json")" >>"$tmp/records"
  fi
  LC_ALL=C sort -t $'\t' -k2,2 "$tmp/records" >"$tmp/sorted"
  { ledger_header; cat "$tmp/sorted"; } >"$tmp/ledger"
  # Explicit opt-outs transfer ownership. Only a previous managed record permits retirement.
  while IFS=$'\t' read -r meta path src; do
    [ -n "$path" ] || continue
    opted_out "$path" "$out" && continue
    awk -F'\t' -v p="$path" '$2 == p { found = 1 } END { exit !found }' "$tmp/sorted" && continue
    [ -f "$folder/$path" ] || continue
    if [ "$(git hash-object -- "$folder/$path")" != "${meta#* }" ]; then
      bad "$folder/$path: retired managed file has local edits; preserve it explicitly before rendering"
    elif [ "$check" = 1 ]; then
      bad "$folder/$path: stale managed output; run ci/render.sh"
    fi
  done <<<"$old"
  while IFS=$'\t' read -r meta path src; do
    [ -n "$path" ] || continue
    previous=$(printf '%s\n' "$old" | awk -F'\t' -v p="$path" '$2 == p { print $1; exit }')
    if [ -e "$folder/$path" ] && [ -z "$previous" ] && [ "$src" != ci/plugins.sh ]; then
      bad "$folder/$path: workspace-owned file collides with $src; opt out or remove it explicitly"
      continue
    fi
    actual=""
    [ ! -f "$folder/$path" ] || actual=$(git hash-object -- "$folder/$path")
    if [ "$check" = 1 ]; then
      [ "$actual" = "${meta#* }" ] || bad "$folder/$path: inherited from $src and out of date; run ci/render.sh"
      if [ -f "$folder/$path" ]; then
        if [ "${meta%% *}" = 100755 ]; then [ -x "$folder/$path" ] || bad "$folder/$path: executable mode is out of date; run ci/render.sh"
        else [ ! -x "$folder/$path" ] || bad "$folder/$path: executable mode is out of date; run ci/render.sh"; fi
      fi
    elif [ -n "$previous" ] && [ -n "$actual" ] && [ "$actual" != "${previous#* }" ] && [ "$actual" != "${meta#* }" ]; then
      bad "$folder/$path: managed file has local edits; edit $src or opt out before rendering"
    fi
  done <"$tmp/sorted"
  if [ "$check" = 1 ]; then
    cmp -s "$tmp/ledger" "$folder/$generated" || bad "$folder/$generated: ownership record is out of date; run ci/render.sh"
    return
  fi
  [ "$problems" = "$start" ] || return 0
  while IFS=$'\t' read -r meta path src; do
    [ -n "$path" ] || continue
    opted_out "$path" "$out" && continue
    if ! awk -F'\t' -v p="$path" '$2 == p { found = 1 } END { exit !found }' "$tmp/sorted"; then
      rm -f "$folder/$path"
      previous=$(dirname "$folder/$path")
      while [ "$previous" != "$folder" ] && rmdir "$previous" 2>/dev/null; do previous=$(dirname "$previous"); done
    fi
  done <<<"$old"
  while IFS=$'\t' read -r meta path src; do
    [ -n "$path" ] || continue
    [ "$src" != ci/plugins.sh ] || continue
    mkdir -p "$(dirname "$folder/$path")"
    cp "$tmp/native/$path" "$folder/$path"
    if [ "${meta%% *}" = 100755 ]; then chmod +x "$folder/$path"; else chmod -x "$folder/$path"; fi
  done <"$tmp/sorted"
  cp "$tmp/ledger" "$folder/$generated"
}

while read -r _ folder; do render_workspace "$folder"; done < <(bash "$here/../.delphi/names.sh")
[ "$problems" = 0 ] || exit 1
