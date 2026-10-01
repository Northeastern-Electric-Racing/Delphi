---
name: to-tickets
description: Break a spec, plan, or the current conversation into tracer-bullet tickets with blocking edges, then publish them to the issue tracker once the user approves. Use when the user wants to turn a spec or plan into issues or break down work.
disable-model-invocation: true
---

1. Source: use a spec or issue given, else `.workflow/spec.md`, else the conversation. Cover only the done criteria, and nothing from Non-goals.
2. Slice into tracer bullets. Each ticket is a narrow but complete path through every layer, is demoable on its own, and lists the tickets that block it. Prefactors go first.
   A wide mechanical refactor can't land as one slice. Sequence it as expand, migrate in batches, then contract.
3. Show a numbered list: title, blocked by, and what it delivers. Iterate until the user approves.
4. Create the issues in dependency order only when the user explicitly says to. Follow the repo's issue-tracker docs for labels, if any. Link blockers, and set Parent to the spec issue if one exists.

```md
## Parent
Spec issue, or omit.

## What to build
End-to-end behavior, from the user's perspective.

## Acceptance criteria
- [ ] …

## Blocked by
Tickets, or "None".
```
