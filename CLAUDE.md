# Delphi — developing the CLI

Delphi stores NER's AI-harness context under `context/` and ships a small bash CLI that renders
layouts into workspaces, refreshes them, and proposes edits back as PRs. The design spec
(`docs/superpowers/specs/2026-09-23-delphi-context-repo-design.md`) is the source of truth.

## Layout

- `bin/delphi`: dispatcher. It resolves its own path and sources `lib/core.sh`, then the group's module.
- `lib/core.sh`: messages, `defer` cleanup, prompts, config, `safe_path`, Delphi git access, moves, `parse_args`.
- `lib/parse.sh`: YAML-subset parser (POSIX awk).
- `lib/render.sh`: layout → files + `.delphi/lock.tsv`.
- `lib/route.sh` + `lib/route.awk`: pending diff + lock → plan → edits in a PR worktree.
- `lib/pr.sh`: the only write path to Delphi (temp worktree, commit with trailers, push, `gh`).
- `lib/provenance.sh`: harness/model/effort resolution.
- `lib/workspace.sh`, `lib/layout.sh`, `lib/block.sh`, `lib/check.sh`: the command groups.
- `lib/harness/<name>.sh`: harness adapters (names + `harness_provenance` + `harness_launch`).
- `dev/sandbox.sh`: throwaway end-to-end playground. It is the only test harness (no automated tests, no CI).
- `.claude/skills/`: LLM workflows that drive the CLI (`delphi-new-layout`, `delphi-propose`).

## Rules

- Must run under macOS `/bin/bash` 3.2. Test with `/bin/bash`, never zsh or a newer bash.
- Tools: POSIX awk (no gawk extensions), git, gh. jq is optional.
- Keep it small: fewest lines that implement the spec, terse functions, a short header per file.
- Bash 3.2 pitfalls:
  - Functions that `defer` cleanup (`make_tmp`, `delphi_worktree_at`, `pr_begin`) must not run
    inside `$(...)`. They return results in `REPLY`.
  - errexit is suspended in conditional contexts (`if f`, `f || x`), so critical commands need an explicit `|| die`.
  - A dying function inside `$(...)` needs `|| exit 1` at the call site.
  - Empty arrays error under `set -u`. Use newline-separated strings.
  - A failing command substitution inside a heredoc does not propagate. Assign it to a variable first.
  - Use `sed` rather than `grep -v`, which exits 1 on empty input and breaks under pipefail.
  - `"$var…"` (a variable followed by a non-ASCII byte) is parsed as a longer name. Write `${var}…`.
    An unbound-variable error under the EXIT trap exits with status **0**.
- Every path from config, flags, lock, or `moves.tsv` goes through `safe_path` before use.
- Never test against real GitHub repos. Use the sandbox:
  `eval "$(/bin/bash dev/sandbox.sh /tmp/sb1)"`, then `d <command>`.
  Put a stub `gh` first on `PATH` to exercise the push path against the sandbox's bare origin.
