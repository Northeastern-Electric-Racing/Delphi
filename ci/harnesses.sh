#!/usr/bin/env bash
# Target harness registry for main-side authoring and validation. Branch refresh never loads it.
set -euo pipefail
# shellcheck disable=SC2034 # native paths are consumed by callers sourcing the registry
harness() { # <name>: sets instruction, skills and plugins capability; rejects unknown adapters
  case "$1" in
    claude-code) instruction=CLAUDE.md; instruction_template=templates/workspace/CLAUDE.md; skills=.claude/skills; plugins=claude ;;
    codex) instruction=AGENTS.md; instruction_template=templates/harnesses/codex/AGENTS.md; skills=.agents/skills; plugins=none ;;
    *) echo "harness: unknown harness '$1'" >&2; return 1 ;;
  esac
}
