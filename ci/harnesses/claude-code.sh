#!/usr/bin/env bash
# shellcheck disable=SC2034
# Claude-native paths and CI capabilities; read by the shared registry.
set -euo pipefail
instruction=CLAUDE.md
instruction_base=''
instruction_template=templates/workspace/CLAUDE.md
skills=.claude/skills
native='.claude'
protected='.claude/settings.json'
plugins=claude
settings_file=.claude/settings.json
settings_generator=ci/plugins.sh
bootstrap=hook
skill_format=claude-code
