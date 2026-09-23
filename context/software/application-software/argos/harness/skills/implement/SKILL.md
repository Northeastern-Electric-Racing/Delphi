---
name: implement
description: Implement a piece of work based on a spec or set of tickets.
disable-model-invocation: true
---

Implement the ticket(s) the user names, one ticket per fresh context, on its own branch.

1. Work test-first at the spec's agreed seams, one behavior at a time: write a failing test, then the minimum code to pass it, and refactor only while green. Test behavior through public interfaces, and mock only at system boundaries.
2. Check as you go:
   - **Frontend:** single specs with `ng test --include='src/**/thing.spec.ts' --watch=false` while iterating. At the end, run `ng test --watch=false` (bare `ng test` watches and blocks the shell), then the lint and format checks.
   - **Backend:** `cargo build` and single tests while iterating, `cargo test` at the end.
3. Review with `/code-review` against `develop`, and fix what it finds.
4. Commit with `/commit`. Don't push or open a PR unless asked; that's `/open-pr`.
