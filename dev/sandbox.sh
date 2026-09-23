#!/usr/bin/env bash
# dev/sandbox.sh — throwaway playground for trying Delphi end to end without GitHub.
#
#   eval "$(dev/sandbox.sh)"      # prints exports; then use:  d <command> …
#
# Creates, in a fresh temp dir ($SB):
#   origin.git          bare "remote" for Delphi (stands in for GitHub; PR creation will fail — answer n)
#   Delphi/             clone with this checkout's bin/ lib/ delphi.conf moves.tsv + sample content
#   argos.git           bare code repo referenced by the sample layout
#   Delphi-workspaces/  where workspaces land (the default ../Delphi-workspaces)
# `d` runs the sandbox CLI under /bin/bash (macOS bash 3.2) to catch bash-4-isms.
set -euo pipefail

here=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SB=${1:-$(mktemp -d "${TMPDIR:-/tmp}/delphi-sb.XXXXXX")}
mkdir -p "$SB"
SB=$(cd -P "$SB" && pwd)

git init -q --bare -b main "$SB/origin.git"
git clone -q "$SB/origin.git" "$SB/Delphi" 2>/dev/null
cp -R "$here/bin" "$here/lib" "$SB/Delphi/"
cp "$here/delphi.conf" "$here/moves.tsv" "$SB/Delphi/"

C="$SB/Delphi/context"
A="$C/software/application-software/argos"
mkdir -p "$C/software/harness/instructions" "$C/software/harness/mcp" \
         "$A/blocks" "$A/harness/instructions" "$A/harness/skills/run-tests" "$A/layouts/argos-dev"

printf 'name: NER\n' > "$C/scope.yml"
printf 'name: Software\nrecommend:\n  - software/harness/instructions/base.md\n' > "$C/software/scope.yml"
printf 'name: Application Software\n' > "$C/software/application-software/scope.yml"
cat > "$A/scope.yml" <<'EOF'
name: Argos
recommend:
  - software/application-software/argos/blocks/overview.md
  - software/application-software/argos/harness/skills/run-tests
EOF
printf '# Software conventions\n\n- Use conventional commits.\n- Open PRs against develop.\n' \
  > "$C/software/harness/instructions/base.md"
printf '"github": {\n  "command": "gh-mcp",\n  "args": []\n}\n' > "$C/software/harness/mcp/github.json"
printf '# Argos\n\nArgos is the telemetry dashboard.\nIt has an Angular client and a Rust server.\n' \
  > "$A/harness/instructions/argos.md"
printf '# Argos overview\n\nLine one.\nLine two.\nLine three.\n' > "$A/blocks/overview.md"
printf '# Testing\n\nRun `npm test` in angular-client.\nRun `cargo test` in the server.\n' > "$A/blocks/testing.md"
printf -- '---\nname: run-tests\ndescription: Run the Argos test suites.\n---\n\nRun both suites and summarize failures.\n' \
  > "$A/harness/skills/run-tests/SKILL.md"
cat > "$A/harness/skills/triage.skill" <<'EOF'
name: triage
description: Triage a failing Argos test.
body:
  - software/application-software/argos/blocks/testing.md
EOF

git init -q -b main "$SB/argos-src"
printf '# Argos code\n' > "$SB/argos-src/README.md"
git -C "$SB/argos-src" add -A && git -C "$SB/argos-src" commit -qm init
git clone -q --bare "$SB/argos-src" "$SB/argos.git"

cat > "$A/layouts/argos-dev/manifest.yml" <<EOF
name: argos-dev
harness: claude-code
instructions:
  - software/harness/instructions/base.md
  - software/application-software/argos/harness/instructions/argos.md
blocks:
  - software/application-software/argos/blocks/*
skills:
  - software/application-software/argos/harness/skills/run-tests
  - software/application-software/argos/harness/skills/triage.skill
mcp:
  - software/harness/mcp/github.json
repos:
  argos: file://$SB/argos.git
EOF

git -C "$SB/Delphi" add -A
git -C "$SB/Delphi" commit -qm "sandbox: code + sample content"
git -C "$SB/Delphi" push -q origin HEAD:main 2>/dev/null
git -C "$SB/Delphi" branch -q -u origin/main 2>/dev/null || true

cat <<EOF
export SB=$(printf %q "$SB")
export DELPHI_MODEL=sandbox-model DELPHI_EFFORT=low DELPHI_HARNESS=sandbox
d() { /bin/bash "\$SB/Delphi/bin/delphi" "\$@"; }
echo "sandbox ready: \$SB"
EOF
