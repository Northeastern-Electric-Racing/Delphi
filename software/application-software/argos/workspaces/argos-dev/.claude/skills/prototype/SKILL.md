---
name: prototype
description: Build a throwaway prototype to answer one design question. Use when the user wants to check whether a state model or logic feels right, or explore what a UI should look like.
---

A prototype is throwaway code that answers one question. State the question in one line at the top of the prototype first.

## Pick the shape

- **Logic / state** ("does this model handle X then Y?"): one self-contained HTML file, no framework or server, opens by double-click. Put the logic in one `<script>` block as a pure module with no DOM access, so it lifts into real code. Pick its shape by the question: a reducer for discrete events on one state value, a state machine when which actions are legal is part of the question, pure functions when there's no ongoing state, a class when the logic owns internal state. The page shows the question, the current state as a readable panel re-rendered after every action, a button per action, and tabbed walkthroughs (happy path, an edge case, something that should be illegal). Label everything in `docs/CONTEXT.md` terms, not code names.
- **UI** ("what should this look like?"): 3 structurally different variants (max 5) on an existing angular-client route, chosen by `?variant=`, with a small floating switcher (arrows and ←/→ keys, hidden in production). Keep the route's real data; only the rendered subtree swaps. Use a new route with `prototype` in its path only if nothing can host it. Variants differ in layout and hierarchy, not colour.

Unsure which? A backend module means logic, a page means UI; state the assumption.

## Rules

- Work in a ticket worktree, never `repos/argos/`. Name files so they're obviously prototypes.
- Trivial to run, in-memory state, no tests, no polish.
- When done: record the verdict on the issue, fold the validated decision into real code (rewritten properly), and commit the prototype to a throwaway `prototype/<name>` branch linked from the issue. Never merge it to `develop`.
