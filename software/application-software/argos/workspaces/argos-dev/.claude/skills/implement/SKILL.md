---
name: implement
description: Implement an Argos ticket or task in its own worktree, test-first, ending in a commit. Use when the user asks to build, fix, or implement something in Argos.
---

1. **Worktree.** Get the ticket's branch (`{issue-number}-{kebab-case-title}`) with the `new-worktree` skill: `bash .delphi/new-worktree.sh argos <branch> origin/develop`. It reuses an existing one. `cd` to the path it prints and do everything there; never work in the `develop` checkout. Run `npm ci` in `angular-client/` before touching the client.
2. **Understand.** Read the issue (`gh issue view <n> --comments`), the code involved, and `docs/CONTEXT.md` terms.
3. **Build test-first**, one behavior at a time: a failing test, the least code to pass it, refactor while green. Test through public interfaces; mock only at system boundaries.
4. **Check.**
   - Frontend: `ng test --include='src/**/thing.spec.ts' --watch=false` while iterating; at the end `ng test --watch=false` (bare `ng test` blocks), then the lint and format checks.
   - Backend: `cargo build` and single tests while iterating; `cargo test` at the end.
   - UI changes: verify in the running app with `run-local`.
5. **Commit** with `/commit`. Don't push or open a PR unless asked; that's `/open-pr`.
