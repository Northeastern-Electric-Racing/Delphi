# Delphi — developing the CLI

Delphi stores NER's AI-harness context under `context/` and ships a small Rust CLI that compiles
layouts into workspaces, refreshes them, and proposes edits back as PRs. The design spec
(`docs/design.md`) is the source of truth; `docs/goals.md` lists what any change must keep.

## Layout

- `src/main.rs`: dispatcher. Resolves the Delphi repo, then runs the command group.
- `src/core.rs`: messages (`die!`, `warn!`, `info!`), deferred cleanup, prompts, config, `safe_path`, Delphi git access, moves, `parse_args`.
- `src/parse.rs`: strict YAML-subset parser.
- `src/compile.rs`: manifest entries (`<source> [-> <dest>]`, default dests) and layout → files + `.delphi/lock.tsv`.
- `src/route.rs`: pending diff + lock + manifest → per-file items; shared tags; applying items in a PR worktree.
- `src/pr.rs`: the only write path to Delphi (temp worktree, commit with trailers, push, `gh`).
- `src/provenance.rs`: harness/model/effort resolution.
- `src/workspace.rs`, `src/layout.rs`, `src/block.rs`, `src/check.rs`, `src/setup.rs`: the command groups.
- `src/harness.rs`: harness adapters (file names + provenance + launch).
- `tests/`: end-to-end tests. `tests/common` builds a throwaway sandbox (temp dir, bare origin, sample
  context, stub `gh` on PATH); `tests/cli.rs` drives the binary against it.
- `.claude/skills/`: LLM workflows that drive the CLI (`delphi-new-layout`, `delphi-propose`).

## Rules

- `cargo build`, `cargo test`, and `cargo clippy --all-targets -- -D warnings` must be clean; run `cargo fmt`.
- Keep it small: fewest lines that implement the spec, terse functions, a short header per file.
  Prefer deleting to adapting.
- Runtime tools: git and gh only. `gh` is used only to open or update PRs.
- Every path from config, flags, lock, manifests, or `moves.tsv` goes through `safe_path` (or
  `path_ok` for paths only used inside git objects) before use.
- Never test against real GitHub repos. Add a test using the sandbox in `tests/common`; its `gh`
  stub logs to `gh.log`, and `--yes` pushes only to the sandbox's bare origin.
- Try the CLI by hand the same way: point `DELPHI_ROOT` at a sandbox clone, never at this checkout's
  real origin.
