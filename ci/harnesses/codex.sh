#!/usr/bin/env bash
# shellcheck disable=SC2034
# Codex-native paths and CI capabilities; host credentials and integrations stay external.
set -euo pipefail
instruction=AGENTS.md
instruction_base=templates/workspace/CLAUDE.md
instruction_template=templates/harnesses/codex/AGENTS.md
skills=.agents/skills
native='.agents .codex'
protected='.codex/config.toml'
plugins=none
settings_file=''
settings_generator=''
bootstrap='exec'
skill_ref='$%s'
github_tool='PR reader'
github_integration='available authenticated GitHub integration'
browser_tool='browser automation available in this harness'
pane_guidance=drop
reload_guidance="Start a fresh Codex session after switching so the new workspace's instructions and skills load before further work."

translate_skill() { # Claude metadata becomes Codex metadata; identifiers follow this descriptor's contract.
  {
    awk '
      { sub(/\r$/, "") }
      NR == 1 { if ($0 !~ /^---$/) exit; front = 1; print; next }
      front && /^---$/ { print; exit }
      front {
        line = $0; sub(/^ */, "", line); indent = length($0) - length(line)
        if (!root && line !~ /^(#|$)/) { root = 1; level = indent }
        if (indent == level && line ~ /^["\047]?(allowed-tools|user-invocable|disable-model-invocation)["\047]?[[:space:]]*:/) { skip = 1; next }
        if (skip && (indent > level || line ~ /^(#|$|-([[:space:]]|$))/)) next
        skip = 0
        if (indent == level && line ~ /^description: / && substr(line, 14) ~ /: / && substr(line, 14) !~ /^["\047>|]/) {
          print substr($0, 1, level) "description: >-"; print substr($0, 1, level) "  " substr(line, 14)
        } else print
      }' "$1"
    skill_bootstrap
    awk '
      NR == 1 && /^---\r?$/ { front = 1; next }
      front && /^---\r?$/ { front = 0; next }
      !front { print }
    ' "$1"
  } | claude_identifiers | skill_commands
}
