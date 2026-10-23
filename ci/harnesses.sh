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
        NR == 1 && /^---$/ { front = 1; print; next }
        front && /^---$/ { front = 0; print; next }
        front {
          # Claude-only fields are omitted from Codex output, including block values.
          if (/^(allowed-tools|user-invocable|disable-model-invocation):/) { skip = 1; next }
          if (skip && /^[[:space:]]/) next
          if (/^[^[:space:]#]/) skip = 0
          if (skip) next
          # Quote descriptions that need a native YAML block scalar.
          if (/^description: / && substr($0, 14) ~ /: / && substr($0, 14) !~ /^["\047>|]/) {
            print "description: >-"; print "  " substr($0, 14)
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
