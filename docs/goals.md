# Delphi — Goals

What Delphi must achieve, not how. Any change must keep these. Details: `docs/design.md`.

## Purpose

Store NER's AI context (instructions, skills, docs, settings) once, organized by the org chart. Let
anyone, person or agent, work on a workspace with plain git and send improvements back.

## Goals

- **G1. Workspaces live in Delphi.** Each workspace is a folder on `main` with every file at its
  normal harness location.
- **G2. The workspace is the repo root.** Checking out `ws/<name>` gives exactly that workspace at
  the root. `.delphi/setup.sh` clones the code repos it lists.
- **G3. Both directions, automatically.** Merged workspace changes reach `main` as a PR; changes on
  `main` reach the workspace branch. Refreshing is `git merge origin/ws/<name>`.
- **G4. Conflicts are reported, never guessed.** A conflicting workspace is skipped with its files
  listed and resolved by a person in a normal PR; other workspaces keep syncing.
- **G5. Keep Delphi valid.** `ci/check.sh` catches bad manifests and structure before merge. New
  workspaces arrive through PRs too.
- **G6. Simple.** No CLI to install: git, `gh`, and a few short shell scripts.

## Invariants

- **I1.** Changes reach `main` and `ws/*` only through PRs (CI's own merges excepted).
- **I2.** `ws/<name>` history is joined to `main`; no unrelated histories, no force-pushes to `ws/*`.
- **I3.** Code repos in `repos/` never show up as workspace changes.
- **I4.** `setup.sh` works on macOS bash 3.2 and Git Bash.
- **I5.** Everything is testable end to end without GitHub (`tests/e2e.sh`).
