# Execute

1. Before any edit, stop if the working tree is dirty and ask the user to commit or stash. Then write `Base: <git rev-parse HEAD>` to `execute.md`.
2. Implement in one pass.
3. Build, lint, and run the tests that cover the change.

## Slices

Slice only large tasks, meaning independent parts or many files.

- Propose the slices, and slice only after the user approves.
- Run independent slices in parallel subagents with worktree isolation. Run dependent slices in order.
- To track slices as issues, the user runs `/to-tickets`.

## Review

1. Once everything is implemented, run the `review` skill against Base.
2. The user picks which fixes to apply.
3. Apply them and re-run the affected checks.
4. Append the table and its outcome to `execute.md`, then summarize what changed and what was verified.
