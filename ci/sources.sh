#!/usr/bin/env bash
# Source readers: a bundle declares its authoring format independently of the consuming workspace.
set -euo pipefail
# shellcheck source=ci/harnesses.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/harnesses.sh"

source_format() { # <bundle>: legacy bundles are Claude-authored
  local config format
  if [ ! -e "$1/source.yml" ]; then echo claude-code; return; fi
  config=$(cat "$1/source.yml")
  format=$(printf '%s\n' "$config" | awk '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    /^format:[[:space:]]+(claude-code|codex)[[:space:]]*(#.*)?$/ { if (!n++) value = $2; next }
    { invalid = 1 }
    END { if (n == 1 && !invalid) print value }')
  [ -n "$format" ] || { echo "source: $1/source.yml: declare one supported format (claude-code or codex)" >&2; return 1; }
  printf '%s\n' "$format"
}

source_path() { # <format> <target harness> <source path>: native destination; no semantic guesses
  local from_instruction from_skills incompatible
  harness "$1" || return 1
  from_instruction=$instruction; from_skills=$skills
  case "$3" in '' | /* | *[!A-Za-z0-9._/-]* | */ | *//* )
    echo "source: unsafe path '$3'" >&2; return 1 ;;
  esac
  case "/$3/" in */../* | */./* | */.git/*)
    echo "source: unsafe path '$3'" >&2; return 1 ;;
  esac
  for incompatible in $foreign; do
    case "$3" in "$incompatible" | "$incompatible"/*)
      echo "source: $3 does not belong to the declared $1 format" >&2; return 1 ;;
    esac
  done
  harness "$2" || return 1
  case "$3" in
    "$from_instruction") printf '%s\n' "$instruction" ;;
    "$from_skills"/*) printf '%s/%s\n' "$skills" "${3#"$from_skills"/}" ;;
    CLAUDE.md | AGENTS.md | .claude/* | .agents/* | .codex/*)
      [ "$1" = "$2" ] || { echo "source: $1:$3 has no mapping to $2; provide an explicit adapter mapping" >&2; return 1; }
      printf '%s\n' "$3" ;;
    *) printf '%s\n' "$3" ;;
  esac
}

bundle_files() { # <bundle> <target harness>: mode blob<TAB>destination<TAB>source
  local format records record meta path dest
  format=$(source_format "$1") || return 1
  records=$(source_files "$1") || return 1
  while IFS= read -r record; do
    [ -n "$record" ] || continue
    meta=${record%%$'\t'*}; path=${record#*$'\t'}
    [ "$path" != source.yml ] || continue
    meta="${meta%% *} ${meta##* }"
    dest=$(source_path "$format" "$2" "$path") || return 1
    printf '%s\t%s\t%s\n' "$meta" "$dest" "$1/$path"
  done <<<"$records"
}

source_files() { # <folder>: mode blob<TAB>relative path
  local file mode
  if [ -d "$1" ]; then
    while IFS= read -r file; do
      mode=100644; [ ! -x "$file" ] || mode=100755
      printf '%s %s\t%s\n' "$mode" "$(git hash-object -- "$file")" "${file#"$1"/}"
    done < <(find "$1" -type f | LC_ALL=C sort)
  fi
}
