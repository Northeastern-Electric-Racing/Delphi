# Spec

The spec captures intent: the smallest MVP that solves the user's problem.

1. Restate the request in one or two sentences.
2. If the area is unfamiliar, spawn read-only Explore subagents in parallel to find code, components, and utils to reuse.
3. Break assumptions: ask pointed questions in one batch, each with a recommended answer.
4. Move anything the goal doesn't need to Non-goals.
5. Write the MVP card to `spec.md`, at most one screen:

```md
# <task>
Goal: one sentence.
Done criteria: checkable list.
Non-goals: out-of-scope list.
Assumptions broken: assumption, then what we learned.
Reuse: path, then what it gives us.
```
