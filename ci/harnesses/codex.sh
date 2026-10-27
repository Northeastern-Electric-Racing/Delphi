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
skill_format=codex
