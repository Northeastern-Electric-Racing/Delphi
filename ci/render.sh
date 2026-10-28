#!/usr/bin/env bash
# ci/render.sh [--check] [--workspace <folder>] [<main checkout> [<staging output>]]:
# validate main-owned files and prepare inherited native files outside workspace folders on main.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=ci/inherit.sh
source "$here/inherit.sh"
# shellcheck source=ci/managed.sh
source "$here/managed.sh"
check=0 only=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) check=1; shift ;;
    --workspace) [ "$#" -ge 2 ] || exit 2; only=$2; shift 2 ;;
    *) break ;;
  esac
done
[ "$#" -le 2 ] || { echo "render: too many arguments" >&2; exit 2; }
[ -z "$only" ] || { safe_path "$only" && [ "$#" = 2 ]; } || { echo "render: --workspace needs a safe folder and staging output" >&2; exit 2; }
checkout=${1:-.} output=${2:-}
if [ -n "$output" ]; then mkdir -p "$output"; output=$(cd "$output" && pwd -P); fi
cd "$checkout"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
output=${output:-$tmp/native}
case "$output/" in "$(pwd -P)/"*) echo "render: staging output must be outside the main checkout" >&2; exit 2 ;; esac
problems=0
bad() { echo "render: $*" >&2; problems=$((problems + 1)); }
while IFS= read -r path; do bad "$path: symlinks are not allowed under software/"; done \
  < <(find software -type l 2>/dev/null)
while IFS= read -r path; do bad "$path: symlinks are not allowed in staging output"; done \
  < <(find "$output" -type l 2>/dev/null)
[ "$problems" = 0 ] || exit 1
if [ -z "$only" ]; then
  if [ "$check" = 1 ]; then bash "$here/plugins.sh" --check . || problems=$((problems + 1))
  else bash "$here/plugins.sh" . || exit 1; fi
fi

render_workspace() { # <workspace folder>: main keeps owned files; inherited output and ledger go to staging
  local folder=$1 adapter out records meta path src seen="" used="" o parent protected_path settings_file plugins skill_names target=$output/$1
  [ ! -e "$folder/$generated" ] || { bad "$folder/$generated: ownership records belong only on workspace branches"; return; }
  adapter=$(awk '/^harness:/ { print $2; exit }' "$folder/workspace.yml")
  harness_exists "$adapter" || { bad "$folder/workspace.yml: unknown harness '$adapter'"; return; }
  plugins=$(harness_field "$adapter" plugins)
  if [ "$plugins" = none ] && awk '/^plugins:/ { s = 1; next } /^[^[:space:]#]/ { s = 0 }
    s && /^[[:space:]]+-/ { found = 1 } END { exit !found }' "$folder/workspace.yml"; then
    bad "$folder/workspace.yml: $adapter does not support Delphi plugin sets"; return
  fi
  out=$(optouts <"$folder/workspace.yml")
  records=$(inherited_files "$folder" "$adapter" "$out") || { bad "$folder: cannot resolve inherited sources"; return; }
  skill_names=$(harness_skill_names "$adapter" "$folder" "$records" "$out") || return 1
  rm -rf "$target"
  mkdir -p "$target"
  : >"$tmp/records"
  while IFS=$'\t' read -r meta path src; do
    [ -n "$path" ] || continue
    if ! safe_path "$path" || ! safe_path "$src"; then bad "$src: unsafe inherited destination '$path'"; continue; fi
    case "$path" in workspace.yml | workspace.generated | .delphi | .delphi/* | .github/workflows/delphi.yml)
      bad "$src: each workspace has its own $path; it can't be inherited"; continue ;;
    esac
    protected_path=0
    for o in $(harness_protected); do
      if [ "$path" = "$o" ]; then bad "$src: each workspace has its own $path; it can't be inherited"; protected_path=1; break; fi
    done
    [ "$protected_path" = 0 ] || continue
    case " $seen " in *" $path "*) bad "$src: $folder also inherits it from a folder above; keep one" ;; esac
    seen="$seen $path"
    for o in $out; do if opted_out "$path" "$o"; then used="$used $o"; fi; done
    opted_out "$path" "$out" && continue
    if [ -e "$folder/$path" ]; then
      bad "$folder/$path: workspace-owned file collides with $src; inherited copies belong only on workspace branches"; continue
    fi
    parent=$path
    while [ "$parent" != "${parent%/*}" ]; do
      parent=${parent%/*}
      if [ -e "$folder/$parent" ] && [ ! -d "$folder/$parent" ]; then
        bad "$folder/$parent: workspace-owned file collides with $src"; break
      fi
    done
    mkdir -p "$(dirname "$target/$path")"
    harness_file "$adapter" "$src" "$skill_names" >"$target/$path"
    meta="${meta%% *} $(git hash-object -- "$target/$path")"
    if [ "${meta%% *}" = 100755 ]; then chmod +x "$target/$path"; fi
    printf '%s\t%s\t%s\n' "$meta" "$path" "$src" >>"$tmp/records"
  done <<<"$records"
  for o in $out; do
    # Refresh can carry an obsolete branch opt-out until its owner removes it in a PR.
    [ -z "$only" ] || continue
    case " $used " in *" $o "*) ;; *) bad "$folder/workspace.yml: opt-out: $o is nothing it inherits" ;; esac
  done
  settings_file=$(harness_field "$adapter" settings_file)
  if [ -n "$settings_file" ]; then
    mkdir -p "$(dirname "$target/$settings_file")"
    harness_settings "$adapter" "$folder" "$folder/workspace.yml" >"$target/$settings_file" || return 1
    printf '100644 %s\t%s\tci/harnesses/%s.sh\n' "$(git hash-object -- "$target/$settings_file")" "$settings_file" "$adapter" >>"$tmp/records"
    if [ -z "$only" ]; then
      if [ "$check" = 1 ]; then
        cmp -s "$target/$settings_file" "$folder/$settings_file" || bad "$folder/$settings_file: generated settings are out of date"
      else mkdir -p "$(dirname "$folder/$settings_file")"; cp "$target/$settings_file" "$folder/$settings_file"; fi
    fi
  fi
  { ledger_header; LC_ALL=C sort -t $'\t' -k2,2 "$tmp/records"; } >"$target/$generated"
}

if [ -n "$only" ]; then
  [ -f "$only/workspace.yml" ] || { echo "render: no workspace $only" >&2; exit 1; }
  render_workspace "$only"
else
  while read -r _ folder; do render_workspace "$folder"; done < <(bash "$here/../.delphi/names.sh")
fi
[ "$problems" = 0 ] || exit 1
