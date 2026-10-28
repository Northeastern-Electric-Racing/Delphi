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

harness_field() ( # <target> <property>: descriptor fields and functions never escape the query
  harness_exists "$1" || { echo "harness: unknown harness '$1'" >&2; return 1; }
  case "$2" in instruction | instruction_base | instruction_template | skills | native | protected | plugins | settings_file | settings_generator | bootstrap | skill_ref) ;;
    *) echo "harness: unknown property '$2'" >&2; return 1 ;;
  esac
  # shellcheck disable=SC2034 # descriptors are read through indirect property expansion
  local instruction='' instruction_base='' instruction_template='' skills='' native='' protected='' plugins=none
  # shellcheck disable=SC2034 # optional descriptor properties
  local settings_file='' settings_generator='' bootstrap='' skill_ref='/%s'
  # shellcheck disable=SC1090 # a registered, trusted main-side descriptor
  source "$harness_dir/$1.sh"
  printf '%s\n' "${!2}"
)

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

harness_skill_names() { # <target> <workspace folder> <records> [opt-outs]: only this workspace's native skills
  local prefix path exclusion skip
  prefix=$(harness_field "$1" skills) || return 1
  [ -n "$prefix" ] || return 0
  {
    while IFS=$'\t' read -r _ path _; do
      skip=0
      for exclusion in ${4:-}; do case "$path/" in "$exclusion"/*) skip=1 ;; esac; done
      [ "$skip" = 1 ] || printf '%s\n' "$path"
    done <<<"$3"
    if [ -d "$2/$prefix" ]; then
      while IFS= read -r path; do printf '%s\n' "${path#"$2"/}"; done < <(find "$2/$prefix" -type f -name SKILL.md)
    fi
  } | awk -v prefix="$prefix/" 'index($0, prefix) == 1 {
    path = substr($0, length(prefix) + 1)
    if (path ~ /^[a-z0-9-]+\/SKILL[.]md$/) { sub(/\/SKILL[.]md$/, "", path); print path }
  }' | LC_ALL=C sort -u | tr '\n' ' '
}

harness_file() ( # <target> <source> [skill names]: each descriptor owns its translator; validate every non-Claude output
  local target=$1 file=$2 harness_skill_names=${3:-}
  case "$file" in */SKILL.md) ;; *) cat "$file"; return ;; esac
  # shellcheck source=ci/harnesses/claude-code.sh
  source "$harness_dir/claude-code.sh"
  # shellcheck disable=SC1090 # trusted target descriptor, isolated from caller state
  source "$harness_dir/$target.sh"
  if [ "$target" = claude-code ]; then translate_skill "$file"
  else translate_skill "$file" | claude_identifiers check; fi
)

skill_bootstrap() { # target translators place this after their native metadata
  cat <<'BOOTSTRAP'

Run every skill helper through the workspace bootstrap, including in fresh shells and sub-agents:

```sh
bash "<absolute-workspace-root>/.delphi/exec.sh" bash "<absolute-installed-skill-folder>/scripts/<script>.sh" <arguments...>
```

Replace the placeholders with the known workspace root, this skill's installed native folder, the script name, and its arguments. Obtain the workspace's absolute path once with `bash .delphi/paths.sh` from the checked-out workspace root. The wrapper sets `DELPHI_ROOT` for every invocation and preserves the caller's working directory; do not assume shell exports persist.

BOOTSTRAP
}

skill_commands() { # common shell syntax; targets choose whether helper commands need bootstrap
  # shellcheck disable=SC2031 # called inside the same descriptor subshell that sets bootstrap
  awk -v bootstrap="$bootstrap" '
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
