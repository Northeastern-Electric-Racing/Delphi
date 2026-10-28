---
name: implement
description: Implement an Argos ticket or task in its own worktree, test-first, ending in a commit, here or in a subagent (one per ticket, in parallel, for several). Use when the user asks to build, fix, or implement something in Argos.
---

Run every skill helper through the workspace bootstrap, including in fresh shells and sub-agents:

```sh
bash "<absolute-workspace-root>/.delphi/exec.sh" bash "<absolute-installed-skill-folder>/scripts/<script>.sh" <arguments...>
```

Replace the placeholders with the known workspace root, this skill's installed native folder, the script name, and its arguments. Obtain the workspace's absolute path once with `bash .delphi/paths.sh` from the checked-out workspace root. The wrapper sets `DELPHI_ROOT` for every invocation and preserves the caller's working directory; do not assume shell exports persist.


1. **Worktree.** Get the ticket's branch (`{issue-number}-{kebab-case-title}`) with the `new-worktree` skill, based on `origin/develop`. Make every change in `worktrees/argos/<branch>/`, never in `worktrees/argos/develop/`, while staying at the workspace root: edit files by path, `git -C worktrees/argos/<branch> …` for git, and one-off subshells for the rest. Run `(cd worktrees/argos/<branch>/angular-client && npm ci)` before touching the client.
2. **Hand off?** Unless the user already chose, ask whether a subagent should do the rest, and recommend one: one per ticket, in parallel, when there are several (step 1 for each first), or one for work long enough to fill this conversation. Tell it the ticket, its worktree's absolute path, and to follow this skill from step 3, change files only under that path (`git -C` for git), name temp files after the branch, stop the clients it starts, and report its commits, checks, and the port and browser it used. Never turn on the harness's own worktree isolation (`new-worktree` says why). Then confirm its commits with `git -C <path> log origin/develop..` and pass its report on.
3. **Understand.** Read the issue (`gh issue view <n> --comments`), the code involved, and `docs/CONTEXT.md` terms.
4. **Build test-first**, one behavior at a time: a failing test, the least code to pass it, refactor while green. Test through public interfaces; mock only at system boundaries.
5. **Check.**
   - Frontend, in `(cd worktrees/argos/<branch>/angular-client && …)`: `npx ng test --include='src/**/thing.spec.ts' --watch=false` while iterating; at the end `npx ng test --watch=false` (bare `ng test` blocks), then `npx prettier --check "src/**/*.{ts,html,scss}" && npx ng lint`.
   - Backend, in `(cd worktrees/argos/<branch>/scylla-server && …)`: `cargo build` and single tests while iterating; `cargo test` at the end.
   - UI changes: verify in the running app with `run-local <branch>`.
6. **Commit** with `$commit`. Don't push or open a PR unless asked; that's `$open-pr`.
