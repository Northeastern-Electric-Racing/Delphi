# Delphi CLI — Goals

What the CLI must achieve, not how. Any rewrite or simplification must keep these.
Details live in the spec (`context/docs/delphi-design.md`).

## Purpose

Store NER's AI context (instructions, blocks, docs, skills, MCP, settings) once, organized by the
org chart. Let anyone turn a chosen set of it into a working directory, keep that directory current,
and send improvements back — with or without an AI harness.

## Goals

**G1. Compile.** A layout (a manifest picking context + a harness) compiles into a workspace's
files at normal harness locations. Same Delphi commit + same layout = identical output. Every
compiled file is traceable to its source file (the lock).

**G2. Workspaces are independent.** Each workspace is its own git repo outside Delphi, where the
user works freely. Many workspaces can come from one layout. Code repos listed in the layout are
cloned into it.

**G3. Refresh.** Pull the latest Delphi `main` into a workspace without losing the user's edits.
Conflicts are shown with git's normal tools. Re-running always picks up where it left off.
Renamed/moved blocks are followed.

**G4. Know what changed.** At any time, show what the user changed versus what came from Delphi,
and whether those changes have been proposed yet.

**G5. Propose.** Send the workspace's changes back as one pull request per workspace. Each edit
to a synced file lands in the source file it came from; new shared files are declared in the
manifest. Copied and other local files stay local. Anything Delphi can't place is listed in the
PR, never guessed.

**G5a. Sync is opt-in.** A layout chooses per file: synced (linked to its source) or copied
(yours after the first copy). Editing a file other layouts also sync is flagged as shared.

**G6. Provenance.** Every change written to Delphi records which harness, model, and effort made
it.

**G7. Keep Delphi valid.** `check` catches broken manifests, missing paths, and bad structure
before anything is pushed. Layouts and block moves are created through PRs too.

**G8. Harness-agnostic.** Supporting a new harness (beyond Claude Code) means adding one small
adapter: file names plus how to launch it.

## Invariants

- **I1.** Never modify the user's own Delphi checkout; all writes go through PRs.
- **I2.** Reject unsafe paths (absolute, `..`, symlinks escaping) before any read or write.
- **I3.** Workspace bookkeeping never shows up as a user change.
- **I4.** Clear errors that say what to run next; never hang waiting for input in scripts.
- **I5.** Works offline where possible; GitHub (`gh`) is only needed to open PRs.
- **I6.** Easy to install (`cargo install`) and to test end to end without real GitHub.

## Open questions

- Should "proposed" come from GitHub's PR state instead of a local hash?
- Should a rejected change stop reappearing without reverting it?
- Resolved: built `.skill` specs dropped (native skill folders only); strict YAML subset kept.
