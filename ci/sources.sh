#!/usr/bin/env bash
# Source readers: a bundle declares its authoring format independently of the consuming workspace.
set -euo pipefail
# shellcheck source=ci/harnesses.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/harnesses.sh"

source_format() { # <revision or '' for disk> <bundle>: legacy bundles are Claude-authored
  local config format
  if [ -n "$1" ]; then
    if ! git cat-file -e "$1:$2/source.yml" 2>/dev/null; then echo claude-code; return; fi
    config=$(git show "$1:$2/source.yml")
  else
    if [ ! -e "$2/source.yml" ]; then echo claude-code; return; fi
    config=$(cat "$2/source.yml")
  fi
  format=$(printf '%s\n' "$config" | awk '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    /^format:[[:space:]]+(claude-code|codex)[[:space:]]*(#.*)?$/ { if (!n++) value = $2; next }
    { invalid = 1 }
    END { if (n == 1 && !invalid) print value }')
  [ -n "$format" ] || { echo "source: $2/source.yml: declare one supported format (claude-code or codex)" >&2; return 1; }
  printf '%s\n' "$format"
}

source_path() { # <format> <target harness> <source path>: native destination; no semantic guesses
  local from_instruction from_skills
  case "$1" in
    claude-code) from_instruction=CLAUDE.md; from_skills=.claude/skills ;;
    codex) from_instruction=AGENTS.md; from_skills=.agents/skills ;;
    *) echo "source: unknown format '$1'" >&2; return 1 ;;
  esac
  case "$3" in '' | /* | *[!A-Za-z0-9._/-]* | */ | *//* )
    echo "source: unsafe path '$3'" >&2; return 1 ;;
  esac
  case "/$3/" in */../* | */./* | */.git/*)
    echo "source: unsafe path '$3'" >&2; return 1 ;;
  esac
  case "$1:$3" in
    claude-code:AGENTS.md | claude-code:.agents/* | claude-code:.codex/* | codex:CLAUDE.md | codex:.claude/*)
      echo "source: $3 does not belong to the declared $1 format" >&2; return 1 ;;
  esac
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

bundle_files() { # <revision or '' for disk> <bundle> <target harness>: mode blob<TAB>destination<TAB>source
  local format records record meta path dest
  format=$(source_format "$1" "$2") || return 1
  records=$(source_files "$1" "$2") || return 1
  while IFS= read -r record; do
    [ -n "$record" ] || continue
    meta=${record%%$'\t'*}; path=${record#*$'\t'}
    [ "$path" != source.yml ] || continue
    meta="${meta%% *} ${meta##* }"
    dest=$(source_path "$format" "$3" "$path") || return 1
    printf '%s\t%s\t%s\n' "$meta" "$dest" "$2/$path"
  done <<<"$records"
}

source_files() { # <revision or '' for disk> <folder>: mode blob<TAB>relative path
  local file mode
  if [ -n "$1" ]; then git ls-tree -r "$1:$2" 2>/dev/null || true
  elif [ -d "$2" ]; then
    while IFS= read -r file; do
      mode=100644; [ ! -x "$file" ] || mode=100755
      printf '%s %s\t%s\n' "$mode" "$(git hash-object -- "$file")" "${file#"$2"/}"
    done < <(find "$2" -type f | LC_ALL=C sort)
  fi
}
