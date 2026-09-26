# Delphi — developing the CLI

Delphi stores NER's AI-harness context under `context/`. Every workspace is a materialized folder
(`context/<scope>/workspaces/<name>/`); shared files are linked to one source and kept identical by
`delphi sync`. A small Rust CLI checks out one workspace folder sparsely, refreshes it, and proposes
edits back as PRs. The design spec (`docs/design.md`) is the source of truth; `docs/goals.md` lists
what any change must keep.

## Layout

- `src/main.rs`: dispatcher. Resolves the Delphi repo, then runs the command.
- `src/core.rs`: messages (`die!`, `warn!`, `info!`), deferred cleanup, prompts, config, `safe_path`, running git, fetch/commit/worktree helpers, `parse_args`, path helpers.
- `src/parse.rs`: strict YAML-subset parser.
- `src/workspace.rs`: `workspace.yml` (links `<source> [-> <dest>]`, default dests) and listing workspaces at a revision.
- `src/sync.rs`: `delphi sync`: reconcile linked files across workspaces against base revisions; regenerate instruction files.
- `src/check.rs`: `delphi check`: repo validation.
- `src/checkout.rs`: local checkouts and `checkout`, `open`, `refresh`, `diff`, `propose`, `status`.
- `src/manage.rs`: `create`, `list`, `mv`.
- `src/pr.rs`: the only write path to Delphi (temp worktree, commit with trailers, push, `gh`).
- `src/provenance.rs`: harness/model/effort resolution.
- `src/harness.rs`: harness adapters (file names + provenance + launch).
- `src/setup.rs`: `delphi setup`.
- `tests/`: end-to-end tests. `tests/common` builds a throwaway sandbox (temp dir, bare origin, sample
  context, stub `gh` on PATH); `tests/cli.rs` drives the binary against it.
- `.claude/skills/`: LLM workflows that drive the CLI (`delphi-new-workspace`, `delphi-propose`).

## Rules

- `cargo build`, `cargo test`, and `cargo clippy --all-targets -- -D warnings` must be clean; run `cargo fmt`.
- Keep it small: fewest lines that implement the spec, terse functions, a short header per file.
  Prefer deleting to adapting.
- Runtime tools: git and gh only. `gh` is used only to open or update PRs.
- Every path from config, flags, `workspace.yml`, or checkout bookkeeping goes through `safe_path` (or
  `path_ok` for paths only used inside git objects) before use.
- Never test against real GitHub repos. Add a test using the sandbox in `tests/common`; its `gh`
  stub logs to `gh.log`, and `--yes` pushes only to the sandbox's bare origin.
- Try the CLI by hand the same way: point `DELPHI_ROOT` at a sandbox clone, never at this checkout's
  real origin.
