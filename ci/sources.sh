#!/usr/bin/env bash
# Source readers: a bundle declares its authoring format independently of the consuming workspace.
set -euo pipefail
# shellcheck source=ci/harnesses.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/harnesses.sh"
# shellcheck source=ci/managed.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/managed.sh"

source_format() { # <bundle>: legacy bundles are Claude-authored
  local config format
  if [ ! -e "$1/source.yml" ]; then echo claude-code; return; fi
  config=$(cat "$1/source.yml")
  format=$(printf '%s\n' "$config" | awk '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    /^format:[[:space:]]+[a-z0-9-]+[[:space:]]*(#.*)?$/ { if (!n++) value = $2; next }
    { invalid = 1 }
    END { if (n == 1 && !invalid) print value }')
  { [ -n "$format" ] && harness_exists "$format"; } || { echo "source: $1/source.yml: declare one supported source format" >&2; return 1; }
  printf '%s\n' "$format"
}

source_path() { # <format> <target> <path>: explicit native mapping without global registry mutation
  local from_instruction from_skills incompatible native to_skills
  from_instruction=$(harness_field "$1" instruction) || return 1
  from_skills=$(harness_field "$1" skills) || return 1
  safe_path "$3" || { echo "source: unsafe path '$3'" >&2; return 1; }
  for incompatible in $(harness_foreign "$1"); do
    case "$3" in "$incompatible" | "$incompatible"/*)
      echo "source: $3 does not belong to the declared $1 format" >&2; return 1 ;;
    esac
  done
  case "$3" in
    "$from_instruction") harness_field "$2" instruction ;;
    "$from_skills"/*)
      to_skills=$(harness_field "$2" skills) || return 1
      [ -n "$to_skills" ] || { echo "source: $1:$3 has no skill mapping to $2" >&2; return 1; }
      printf '%s/%s\n' "$to_skills" "${3#"$from_skills"/}" ;;
    *)
      for native in $(harness_field "$1" native); do
        case "$3" in "$native" | "$native"/*)
          [ "$1" = "$2" ] || { echo "source: $1:$3 has no mapping to $2; opt out of its source path or provide an adapter mapping" >&2; return 1; } ;;
        esac
      done
      printf '%s\n' "$3" ;;
  esac
}

bundle_files() { # <bundle> <target> [<source exclusions>]: mode blob<TAB>destination<TAB>source
  local format records record meta path dest
  format=$(source_format "$1") || return 1
  records=$(source_files "$1") || return 1
  while IFS= read -r record; do
    [ -n "$record" ] || continue
    meta=${record%%$'\t'*}; path=${record#*$'\t'}
    [ "$path" != source.yml ] || continue
    meta="${meta%% *} ${meta##* }"
    if opted_out "$path" "${3:-}"; then
      # A source-path exclusion can skip unavailable mappings. Mapped files still use native opt-outs.
      if dest=$(source_path "$format" "$2" "$path" 2>/dev/null); then
        if [ "$dest" != "$path" ] && ! opted_out "$dest" "${3:-}"; then
          echo "source: opt-out for $path must use its native destination $dest" >&2; return 1
        fi
      else dest=$path; fi
    else
      dest=$(source_path "$format" "$2" "$path") || return 1
    fi
    printf '%s\t%s\t%s\n' "$meta" "$dest" "$1/$path"
  done <<<"$records"
}

source_files() { # <folder>: validate NUL-delimited names before emitting sorted newline/tab records
  local file mode path
  [ -d "$1" ] || return 0
  while IFS= read -r -d '' file; do
    path=${file#"$1"/}
    safe_path "$path" || { echo "source: unsafe path '$path'" >&2; return 1; }
    mode=100644; [ ! -x "$file" ] || mode=100755
    printf '%s %s\t%s\n' "$mode" "$(git hash-object -- "$file")" "$path"
  done < <(find "$1" -type f -print0) | LC_ALL=C sort -t $'\t' -k2,2
}
