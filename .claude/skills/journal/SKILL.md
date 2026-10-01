---
name: journal
description: Park rough notes locally mid-task ("note to self", "remember to", "journal this"), and later export them to their permanent home (issue, spec, ADR, glossary, docs) through the skill that owns it. Use when the user wants to jot a thought without derailing, or to file parked notes.
---

Notes live in `.journal/` at the workspace root (git-excluded, outside worktrees so they survive removal). An **entry** is one file, a **category** a subfolder. The journal never pushes, files, or contacts GitHub itself.

**Capture** (from anywhere; no git, no other skills):

```
bash <workspace>/.claude/skills/journal/scripts/capture.sh [-c <category>] ["note text"]
```

Omit `-c` for a loose entry, omit the text for an empty one to edit. Report the path it prints.

**Export** (only when asked):

1. Read the entries and propose a grouping: one entry → one output, a category → one merged output, or one entry split across several. Let the user adjust.
2. For each output, pick the workspace skill whose description fits its permanent home, preferring an existing docs area. A new section always needs approval.
3. Show the destination and reshaped text and wait for approval. Nothing lands silently.
4. Delegate to that skill; it owns formatting, conventions, and any GitHub contact.
5. Ask whether to delete the exported entry (default: keep).
