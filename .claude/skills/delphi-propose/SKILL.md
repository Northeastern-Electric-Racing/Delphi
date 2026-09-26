---
name: delphi-propose
description: Propose a Delphi workspace checkout's changes back to the monorepo. Review `delphi diff`, point out shared impact, dry-run the sync, help resolve sync conflicts, then run `delphi propose`. Use when someone wants to send workspace edits upstream or asks about a sync conflict.
---

# Propose workspace changes

Run these inside the checkout (the workspace folder). Drive the CLI. Don't edit the Delphi repo
directly.

1. Make sure the work is committed (`git status` is clean). Only committed changes are proposed,
   and propose refuses to run with uncommitted changes.
2. Run `delphi diff`. Each changed file gets one line:
   - `own`: the workspace's own file; the change lands only in this folder.
   - `linked … <- <source>`: a shared file. Propose writes the edit to the source and to every
     other workspace that links it. `(shared: a, b)` names those workspaces: tell the user their
     edit reaches those teams, and ask them to confirm.
   - `generated`: `CLAUDE.md` built from `instructions:`, `.mcp.json` built from `mcp:`, or a
     skill's `SKILL.md` built from the blocks in its `skill.yml`. Hand edits are rejected: revert it
     and edit the part, fragment, or block (or `skill.yml`) in Delphi instead.
   - `sync`: a file outside the folder written by an earlier propose (a source or another
     workspace's copy).
   `delphi diff --upstream` shows what changed on `main` since the last refresh.
3. Run `delphi propose --dry-run`. It syncs in a throwaway worktree and prints which sources and
   other workspaces' copies would be written, then the PR body. Nothing is pushed.
4. **Sync conflicts** (exit 1, `conflict: …`) mean one shared file has different new versions:
   - `different edits in A, B`: the same shared file was changed differently in two places (two
     copies in this folder, or this folder and a change already on `main`). Make them identical,
     or keep the edit in only one of them, commit, and re-run.
   - `… is newly linked to <source> but differs from it`: a new `blocks`/`docs`/`skills`/`settings`
     entry points at a file that already exists here with other content. Delete the file to take
     the source (or make it identical), commit, re-run.
   - `generated from instructions:` / `generated from mcp:` / `generated from skill.yml (don't
     hand-edit it; edit a block)`: see `generated` above. Restore the file (`git checkout
     origin/main -- <file>`), make the change in the block or `skill.yml`, commit, re-run.
   - `…/skill.yml: body: missing context/<block>`: a `body:` entry names a block that doesn't
     exist; fix the path.
   Suggest a fix and apply it only after the user approves.
5. Run `delphi propose --model <your model> --effort <effort> --yes`. It merges `main` first: on
   exit code 2 (merge conflicts), help resolve them with git, commit, and run it again. Then it
   syncs, commits `delphi: sync shared files`, runs `delphi check`, pushes the branch, and opens
   or updates the PR.
6. Report the branch and PR URL. Proposing again later updates the same PR.
