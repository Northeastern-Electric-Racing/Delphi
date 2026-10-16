---
name: implement
description: Implement an Argos ticket or task in its own worktree, test-first, ending in a commit. Use when the user asks to build, fix, or implement something in Argos.
---

1. **Worktree.** Get the ticket's branch (`{issue-number}-{kebab-case-title}`) with the `new-worktree` skill, based on `origin/develop`. Make every change in `worktrees/argos/<branch>/`, never in `worktrees/argos/develop/`, while staying at the workspace root: edit files by path, `git -C worktrees/argos/<branch> …` for git, and one-off subshells for the rest. Run `(cd worktrees/argos/<branch>/angular-client && npm ci)` before touching the client.
2. **Understand.** Read the issue (`gh issue view <n> --comments`), the code involved, and `docs/CONTEXT.md` terms. A spike runs the same way, building just enough of its direction to test its hypothesis.
3. **Build test-first**, one behavior at a time: a failing test, the least code to pass it, refactor while green. Test through public interfaces; mock only at system boundaries.
4. **Check.**
   - Frontend, in `(cd worktrees/argos/<branch>/angular-client && …)`: `npx ng test --include='src/**/thing.spec.ts' --watch=false` while iterating; at the end `npx ng test --watch=false` (bare `ng test` blocks), then `npx prettier --check "src/**/*.{ts,html,scss}" && npx ng lint`.
   - Backend, in `(cd worktrees/argos/<branch>/scylla-server && …)`: `cargo build` and single tests while iterating; `cargo test` at the end.
   - UI changes: verify in the running app with `run-local <branch>`.
5. **Commit** with `/commit`. Don't push or open a PR unless asked; that's `/open-pr`.
