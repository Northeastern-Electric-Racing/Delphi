---
name: delphi-propose
description: Propose a Delphi workspace's changes back to the monorepo. Dry-run the routing, help the user resolve each unresolved item inside the workspace, then run `delphi workspace propose`. Use when someone wants to send workspace edits upstream or asks why an edit is unresolved.
---

# Propose workspace changes

Run these inside the workspace. Drive the CLI. Don't edit the Delphi repo directly.

1. Make sure the work is committed (`git status` is clean).
2. Run `delphi workspace propose --dry-run`. It prints the plan (where each edit routes) and the
   **Unresolved** items, each with its path, reason, and diff.
3. For each unresolved item, suggest a fix *in the workspace* and apply it only after the user approves:
   - **Edit touches generated/separator lines or spans two blocks:** move the text wholly inside
     one block's lines, or split it into two edits.
   - **New file outside a recognised place:** move it under `context/<scope>/blocks/` (an
     existing scope), `docs/` for a doc, or `.claude/skills/<name>/` for a skill. Otherwise leave it out of the PR
     by deleting it or keeping it uncommitted.
   - **Deleted file that is still compiled:** drop its entry from `.delphi/manifest.yml` instead.
     To replace a block, swap the manifest entry, delete the old file, and add the new one under
     `context/<scope>/blocks/`.
   - **Patch did not apply (same block edited in two places):** keep the edit in one place only.
   - **Binary file:** Delphi doesn't route it. Remove it from the workspace commit.
   Commit the fixes, then run `--dry-run` again until only acceptable items remain. Unresolved
   items never block the PR. They are listed in its body.
4. Run `delphi workspace propose --model <your model> --effort <effort> --yes`.
   It refreshes first. On exit code 2 (merge conflicts), help resolve them, commit, and run it again.
5. Report the branch and PR URL. Proposing again later replaces the same PR with the
   workspace's full pending diff.
