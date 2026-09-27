---
name: delphi-propose
description: Propose a Delphi workspace branch's changes back to main. Review `delphi diff`, dry-run, help resolve conflicts with main, then run `delphi propose`. Use when someone wants to send workspace edits upstream or asks about a propose or refresh conflict.
---

# Propose workspace changes

A checkout is a clone of `ws/<name>` (the workspace is the repo root) on branch
`edit/<user>/<checkout>`. Propose turns the branch's changes since it last merged `ws/<name>`
into one PR to `main`, under the workspace folder. Run these inside the checkout. Drive the CLI;
don't edit the Delphi repo directly.

1. Make sure the work is committed (`git status` is clean). Only committed changes are proposed.
2. Run `delphi diff`: the files changed versus `ws/<name>`. Every change lands only in this
   workspace. `delphi diff --upstream` shows what changed on `ws/<name>` since your last refresh,
   with author and subject.
3. If `ws/<name>` moved on, run `delphi refresh` first (a plain `git merge origin/ws/<name>`). On
   exit code 2 (merge conflicts), help resolve them with git (`git status`, edit, `git add`,
   `git commit`), then re-run it.
4. Run `delphi propose --dry-run`: it applies the changes to the latest `main` in a throwaway
   worktree, runs `delphi check`, and prints the PR title and file list. Nothing is pushed.
5. **Conflicts** (exit 1, `propose: conflicts with changes on main`, then the files): `main`
   changed the same lines in this workspace. Refresh to get those changes (step 3), resolve,
   commit, re-run. If refresh says up to date, `ws/<name>` has not caught up with `main` yet (CI
   re-splits after every push to `main`): wait a minute and retry. A `check` failure names the
   file and the rule; fix it in the checkout, commit, re-run.
6. Run `delphi propose --model <your model> --effort <effort> --yes`. It commits once on top of
   `main` with provenance trailers, pushes `propose/<user>/<workspace>-<branch>`, and opens or
   updates that PR. Report the branch and PR URL. Proposing again later updates the same PR.
7. After the PR merges, `delphi refresh` is a clean merge (the same change is on both sides).

Without the CLI (any agent): push a branch cut from `ws/<name>` and open a PR into `ws/<name>`;
CI mirrors it into a PR to `main` and comments the link. Never merge PRs into `ws/*` directly.
