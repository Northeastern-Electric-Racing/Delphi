# Delphi CLI — Goals

What the CLI must achieve, not how. Any rewrite or simplification must keep these.
Details live in the spec (`docs/design.md`).

## Purpose

Store NER's AI context (instructions, blocks, docs, skills, MCP, settings) once, organized by the
org chart. Let anyone turn a chosen set of it into a working directory, keep that directory current,
and send improvements back — with or without an AI harness.

## Goals

**G1. Compressed sources, compiled workspaces on `main`.** Context is stored once as blocks and
selected by layouts. Every layout's compiled workspace (files at normal harness locations) is
committed on `main` and always matches its sources. Every compiled line is traceable to its block.

**G2. Work locally on just your workspace.** A checkout contains only that layout's folder, on your
own branch. Code repos listed in the layout are cloned into it.

**G3. Refresh.** Pull the latest `main` into a checkout without losing the user's edits.
Conflicts are shown with git's normal tools.

**G4. Know what changed.** At any time, show what the user changed versus `main`, what changed on
`main` since, and whether the changes have been proposed yet.

**G5. Propose.** Send a checkout's changes back as one pull request per checkout.

**G5a. Edit line by line.** Any line of a compiled file can be edited; each edit lands in the
block it came from, new sections become new fragments, and every layout using that block is
recompiled. Edits Delphi can't place are reported and block the PR, never guessed or dropped.

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
- Resolved: strict YAML subset kept; `.skill` specs kept (v4).
