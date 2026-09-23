# claude-code.sh — harness adapter for Claude Code. Names + two functions; no file logic.

HARNESS_INSTRUCTIONS=CLAUDE.md
HARNESS_SKILLS_DIR=.claude/skills
HARNESS_MCP_FILE=.mcp.json
HARNESS_SETTINGS_FILE=.claude/settings.json
HARNESS_IGNORE=".claude/settings.local.json"

# harness_provenance: prints harness+version, model, effort (one per line; blank if unknown).
harness_provenance() {
  local v
  v=$(claude --version 2>/dev/null | awk 'NR == 1 { print $1 }')
  printf 'claude-code%s\n' "${v:+ $v}"
  printf '%s\n' "${ANTHROPIC_MODEL:-}"
  printf '%s\n' "${CLAUDE_CODE_EFFORT_LEVEL:-}"
}

# harness_launch <model> <effort>: replaces the current process with the harness.
harness_launch() {
  [ -n "$2" ] && export CLAUDE_CODE_EFFORT_LEVEL="$2"
  if [ -n "$1" ]; then exec claude --model "$1"; else exec claude; fi
}
