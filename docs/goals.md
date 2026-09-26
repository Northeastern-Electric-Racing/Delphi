# Delphi CLI — Goals

What the CLI must achieve, not how. Any rewrite or simplification must keep these.
Details live in the spec (`docs/design.md`).

## Purpose

Store NER's AI context (instructions, blocks, docs, skills, MCP, settings) once, organized by the
org chart. Let anyone turn a chosen set of it into a working directory, keep that directory current,
and send improvements back — with or without an AI harness.

## Goals

**G1. Workspaces live in Delphi.** Each workspace is a folder in Delphi with every file at its
normal harness location, fully materialized on `main`. Shared files are linked to one source.

**G2. Work locally on just your workspace.** A checkout contains only that folder, on your own
branch. Code repos listed in the workspace are cloned into it.

**G3. Refresh.** Pull the latest `main` into a checkout without losing the user's edits.
Conflicts are shown with git's normal tools.

**G4. Know what changed.** At any time, show what the user changed versus `main`, what changed on
`main` since, and whether the changes have been proposed yet.

**G5. Propose.** Send a checkout's changes back as one pull request per checkout.

**G5a. Shared stays consistent.** A change to a shared file, made in its source or in any
workspace that links it, reaches the source and every linked copy before it lands on `main`.
Editing a shared file is flagged with the workspaces it affects. Conflicting edits are reported,
never guessed.

**G6. Provenance.** Every change written to Delphi records which harness, model, and effort made
it.

**G7. Keep Delphi valid.** `check` catches broken manifests, missing paths, and bad structure
before anything is pushed. New workspaces and moves are created through PRs too.

**G8. Harness-agnostic.** Supporting a new harness (beyond Claude Code) means adding one small
adapter: file names plus how to launch it.

## Invariants

- **I1.** Changes reach `main` only through PRs; Delphi never rewrites a user's uncommitted work.
- **I2.** Reject unsafe paths (absolute, `..`, symlinks escaping) before any read or write.
- **I3.** Workspace bookkeeping never shows up as a user change.
- **I4.** Clear errors that say what to run next; never hang waiting for input in scripts.
- **I5.** Works offline where possible; GitHub (`gh`) is only needed to open PRs.
- **I6.** Easy to install (`cargo install`) and to test end to end without real GitHub.

## Open questions

- Should "proposed" come from GitHub's PR state instead of a local hash?
- Should a rejected change stop reappearing without reverting it?
- Resolved: built `.skill` specs dropped (native skill folders only); strict YAML subset kept.
