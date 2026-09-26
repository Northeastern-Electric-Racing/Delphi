---
name: delphi-propose
description: Propose a Delphi workspace's changes back to the monorepo. Dry-run the routing, help the user resolve each unresolved item inside the workspace, then run `delphi workspace propose`. Use when someone wants to send workspace edits upstream or asks why an edit is unresolved.
---

# Propose workspace changes

Run these inside the workspace. Drive the CLI. Don't edit the Delphi repo directly.

1. Make sure the work is committed (`git status` is clean). Only committed changes are proposed.
2. Run `delphi workspace diff`. Each changed file gets one line:
   - `update` / `new` / `manifest`: goes to that Delphi path. `(shared: …)` means other layouts use
     that source too, so the edit reaches their teams. Point this out to the user.
   - `noop`: nothing to send (a deleted file whose entry was removed, or the same edit already
     routed from another copy of that source).
   - `local`: stays in the workspace, never proposed (copied files, files outside synced folders).
   - **Unresolved** items, each with a reason.
   `delphi workspace diff --upstream` shows what changed in Delphi since the last refresh.
3. For each unresolved item, suggest a fix *in the workspace* and apply it only after the user approves:
   - **generated; sync a part to edit it** (`CLAUDE.md` assembled from `instructions:`): revert the
     edit in `CLAUDE.md`, add the part under `sync:` in `.delphi/manifest.yml`, and edit it there
     after the next refresh. Or move the text into a synced file.
   - **deleted, but still listed in .delphi/manifest.yml**: remove its entry from
     `.delphi/manifest.yml` too (or restore the file).
   - **deleted, but still one of the layout's files/**: restore it; removing a layout file needs a
     Delphi PR by hand.
   - **differing edits to one source**: the same source is synced to several dests with different
     edits. Make the copies identical (or keep the edit in one of them).
   - **its source already exists in Delphi**: a new sync entry points at an existing source. Delete
     the workspace file; it arrives on refresh after the manifest change merges.
   - **Delphi bookkeeping**: revert edits to `.delphi/lock.tsv`.
   - **symlink or unsupported change type**: replace the symlink with a regular file or drop it.
   To share a new file, put it in a synced folder, or add a `sync:` entry for it in
   `.delphi/manifest.yml` (`<new source path> -> <its workspace path>`); propose creates the source.
   Commit the fixes, then run `delphi workspace diff` again until only acceptable items remain.
   Unresolved items never block the PR. They are listed in its body.
4. Run `delphi workspace propose --model <your model> --effort <effort> --yes`.
   It refreshes first. On exit code 2 (merge conflicts), help resolve them, commit, and run it again.
5. Report the branch and PR URL. Proposing again later replaces the same PR with the
   workspace's full pending diff.
