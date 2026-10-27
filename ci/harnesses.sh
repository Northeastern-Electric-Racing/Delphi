#!/usr/bin/env bash
# Harness registry and shared skill rendering. Per-target facts live in harnesses/<name>.sh.
set -euo pipefail
harness_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/harnesses" && pwd)

harnesses() { # registered target/source formats
  local file
  for file in "$harness_dir"/*.sh; do
    [ -f "$file" ] || continue
    file=${file##*/}; printf '%s\n' "${file%.sh}"
  done
}

harness_exists() {
  case "$1" in '' | *[!a-z0-9-]*) return 1 ;; esac
  [ -f "$harness_dir/$1.sh" ]
}

harness_field() { # <target> <property>: local descriptor fields never mutate a caller's target
  harness_exists "$1" || { echo "harness: unknown harness '$1'" >&2; return 1; }
  case "$2" in instruction | instruction_base | instruction_template | skills | native | protected | plugins | settings_file | settings_generator | bootstrap | skill_format) ;;
    *) echo "harness: unknown property '$2'" >&2; return 1 ;;
  esac
  # shellcheck disable=SC2034 # descriptors are read through indirect property expansion
  local instruction='' instruction_base='' instruction_template='' skills='' native='' protected='' plugins=none
  # shellcheck disable=SC2034 # optional descriptor properties
  local settings_file='' settings_generator='' bootstrap='' skill_format=claude-code
  # shellcheck disable=SC1090 # a registered, trusted main-side descriptor
  source "$harness_dir/$1.sh"
  printf '%s\n' "${!2}"
}

harness_foreign() { # paths owned by other targets, excluding shared native conventions
  local own other path
  own="$(harness_field "$1" instruction) $(harness_field "$1" native)"
  for other in $(harnesses); do
    [ "$other" != "$1" ] || continue
    for path in $(harness_field "$other" instruction) $(harness_field "$other" native); do
      case " $own " in *" $path "*) ;; *) printf '%s\n' "$path" ;; esac
    done
  done
}

harness_protected() { # native root instructions and target-owned configuration are never inherited
  local target
  for target in $(harnesses); do
    harness_field "$target" instruction
    harness_field "$target" settings_file
    harness_field "$target" protected
  done
}

harness_settings() { # <target> <folder> <manifest>: the target's registered settings generator
  local generator
  generator=$(harness_field "$1" settings_generator) || return 1
  [ -n "$generator" ] || return 0
  bash "$harness_dir/../../$generator" settings "$2" "$3"
}

harness_file() { # <target harness> <source file>: metadata format, explicit body variant and bootstrap
  local target=$1 file=$2 format bootstrap variant
  case "$file" in */SKILL.md) ;; *) cat "$file"; return ;; esac
  format=$(harness_field "$target" skill_format) || return 1
  bootstrap=$(harness_field "$target" bootstrap) || return 1
  variant=${file%/*}/BODY.$target.md
  # Preserve canonical native output byte for byte unless this target asks for adaptation.
  if [ "$format" = claude-code ] && [ "$bootstrap" != exec ] && [ ! -f "$variant" ]; then
    cat "$file"; return
  fi
  # Read metadata only; prose and code-repository instruction references stay source-owned.
  awk -v format="$format" '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 !~ /^---$/) exit; front = 1; print; next }
    front && /^---$/ { print; exit }
    front {
      if (format != "codex") { print; next }
      line = $0; sub(/^ */, "", line); indent = length($0) - length(line)
      if (!root && line !~ /^(#|$)/) { root = 1; level = indent }
      # Claude-only fields are omitted from Codex output, including block values.
      if (indent == level && line ~ /^["\047]?(allowed-tools|user-invocable|disable-model-invocation)["\047]?[[:space:]]*:/) { skip = 1; next }
      if (skip && (indent > level || line ~ /^(#|$|-([[:space:]]|$))/)) next
      skip = 0
      # Quote descriptions that need a native YAML block scalar.
      if (indent == level && line ~ /^description: / && substr(line, 14) ~ /: / && substr(line, 14) !~ /^["\047>|]/) {
        print substr($0, 1, level) "description: >-"; print substr($0, 1, level) "  " substr(line, 14)
      } else print
    }' "$file"
  if [ "$bootstrap" = exec ]; then
    cat <<'BOOTSTRAP'

Run every skill helper through the workspace bootstrap, including in fresh shells and sub-agents:

```sh
bash "<absolute-workspace-root>/.delphi/exec.sh" bash "<absolute-installed-skill-folder>/scripts/<script>.sh" <arguments...>
```

Replace the placeholders with the known workspace root, this skill's installed native folder, the script name, and its arguments. Obtain the workspace's absolute path once with `bash .delphi/paths.sh` from the checked-out workspace root. The wrapper sets `DELPHI_ROOT` for every invocation and preserves the caller's working directory; do not assume shell exports persist.

BOOTSTRAP
  fi
  {
    if [ -f "$variant" ]; then cat "$variant"
    else
      awk '
        NR == 1 && /^---\r?$/ { front = 1; next }
        front && /^---\r?$/ { front = 0; next }
        !front { print }
      ' "$file"
    fi
  } | awk -v bootstrap="$bootstrap" '
    bootstrap == "exec" {
      rest = $0; adapted = ""
      # Translate the command syntax, including nested command substitutions, without editing prose.
      while (match(rest, /(^|[[:space:]`(;])bash scripts\/[A-Za-z0-9._\/-]+/)) {
        before = substr(rest, 1, RSTART - 1); command = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        at = index(command, "bash scripts/")
        adapted = adapted before substr(command, 1, at - 1) "bash \"<absolute-workspace-root>/.delphi/exec.sh\" bash \"<absolute-installed-skill-folder>/" substr(command, at + 5) "\""
      }
      print adapted rest; next
    }
    { print }
  '
}
