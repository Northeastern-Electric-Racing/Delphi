#!/usr/bin/env bash
# Target harness registry for main-side authoring and validation. Branch refresh never loads it.
set -euo pipefail
# shellcheck disable=SC2034 # native paths are consumed by callers sourcing the registry
harness() { # <name>: native paths, template, plugin capability and foreign-file exclusions
  case "$1" in
    claude-code) instruction=CLAUDE.md; instruction_template=templates/workspace/CLAUDE.md; skills=.claude/skills; plugins=claude; foreign="AGENTS.md .agents .codex" ;;
    codex) instruction=AGENTS.md; instruction_template=templates/harnesses/codex/AGENTS.md; skills=.agents/skills; plugins=none; foreign="CLAUDE.md .claude" ;;
    *) echo "harness: unknown harness '$1'" >&2; return 1 ;;
  esac
}

harness_file() { # <target harness> <source file>: Claude passes through; Codex adapts its own output only
  case "$1:$2" in
    codex:*/SKILL.md)
      awk '
        { sub(/\r$/, "") }
        NR == 1 && /^---$/ { front = 1; print; next }
        front && /^---$/ { front = 0; print; next }
        front {
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
          next
        }
        /^- The user can also switch from the `\/ws-delphi` pane/ { next }
        /^- No restart needed: skills under/ {
          print "- Start a fresh Codex session after switching so its instructions and skills match the new workspace."
          next
        }
        {
          gsub(/CLAUDE[.]md/, "AGENTS.md")
          gsub(/GitHub MCP server.s `pull_request_read`/, "available GitHub integration\047s PR-reading tool")
          print
        }' "$2" ;;
    *) cat "$2" ;;
  esac
}
