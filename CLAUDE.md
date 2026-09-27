# Delphi — developing the CLI

Delphi stores NER's AI-harness context under `context/`. Every workspace is a self-contained folder
(`context/<scope>/workspaces/<name>/`) on `main`; CI projects each one into a branch `ws/<name>`
whose repo root is that folder (`delphi split`, a deterministic `git subtree split`). Anyone works on
a branch cut from `ws/<name>`; a small Rust CLI checks it out, refreshes it, and proposes the
branch's changes back as a PR to `main`, re-rooted under the folder. The design spec (`docs/design.md`) is the source of truth; `docs/goals.md` lists
what any change must keep.

## Layout

- `src/main.rs`: dispatcher. Resolves the Delphi repo, then runs the command.
- `src/core.rs`: messages (`die!`, `warn!`, `info!`), deferred cleanup, prompts, config, `safe_path`, running git, fetch/commit/worktree helpers, `parse_args`, path helpers.
- `src/parse.rs`: strict YAML-subset parser.
- `src/workspace.rs`: `workspace.yml` (`name`, `harness`, `repos`) and listing workspaces at a revision.
- `src/split.rs`: `delphi split`: `ws/<name>` for every workspace with git plumbing (same commits as `git subtree split`).
- `src/check.rs`: `delphi check`: repo validation.
- `src/checkout.rs`: local checkouts (clone at `ws/<name>`, branch `edit/<user>/<c>`) and `checkout`, `open`, `refresh`, `diff`, `status`.
- `src/propose.rs`: `delphi propose`: a branch's diff vs `ws/<name>`, 3-way applied under the folder on `main`, as one PR.
- `src/manage.rs`: `create`, `list`.
- `src/pr.rs`: the only write path to Delphi (temp worktree, commit with trailers, push, `gh`).
- `src/provenance.rs`: harness/model/effort resolution.
- `src/harness.rs`: harness adapters (file names + provenance + launch).
- `src/setup.rs`: `delphi setup`.
- `tests/`: end-to-end tests. `tests/common` builds a throwaway sandbox (temp dir, bare origin, two
  sample workspaces split into `ws/*`, stub `gh` on PATH); `tests/cli.rs` drives the binary against it.
- `.github/workflows/delphi.yml`: CI: `check` on PRs to main, `split --push` on pushes to main,
  `propose --branch` mirror of PRs into `ws/*` (tested by `tests/cli.rs`).
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
