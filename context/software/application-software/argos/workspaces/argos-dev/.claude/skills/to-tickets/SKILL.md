---
name: to-tickets
description: Break a plan, spec, or the current conversation into tracer-bullet tickets with blocking edges, published to the issue tracker. Use when the user wants to turn a plan into issues or break down work.
disable-model-invocation: true
---

1. **Context.** Work from the conversation. If given a spec or issue, read its body and comments. Explore the code if needed, looking for prefactors that make the change easy.
2. **Slice** into tracer bullets. Each ticket:
   - is a narrow but complete path through every layer (schema, API, UI, tests), demoable on its own, and fits one fresh context;
   - is AFK (no human needed) where possible, HITL otherwise;
   - lists the tickets that block it. Prefactors go first.

   A wide mechanical refactor (rename a column, retype a shared symbol) can't land as a vertical slice. Sequence it expand → migrate in batches → contract, one ticket per step.
3. **Quiz.** Show a numbered list of title, AFK/HITL, blocked by, and what it delivers. Ask about granularity, blocking edges, merges or splits, and AFK/HITL. Iterate until approved.
4. **Create** the issues in dependency order with `ready-for-agent`. Link blockers, and set `Parent` to the spec issue only if one exists. Don't modify the parent.

<issue-template>
## Parent
The spec issue (omit if none).

## What to build
The end-to-end behavior, from the user's perspective.

## Acceptance criteria
- [ ] …

## Blocked by
Blocking tickets, or "None — can start immediately".
</issue-template>
