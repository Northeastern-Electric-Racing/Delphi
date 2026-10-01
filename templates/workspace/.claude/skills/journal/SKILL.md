---
name: journal
description: Capture rough notes locally with zero ceremony, then export them to their right permanent home. Use when the user wants to jot/park/stash a thought mid-task without derailing ("note to self", "remember to", "journal this"), or when they later want to export/file/route parked notes into an issue, spec, ADR, CONTEXT term, or docs. Capture is local and gitignored; export delegates to whichever existing skill owns the note's permanent home.
---

Notes live in `.journal/` at the workspace root (git-excluded, outside worktrees so they survive removal): an **entry** is one file, a **category** a subfolder. The journal only captures and routes; it never pushes, files, or contacts GitHub itself.

**Capture** (from anywhere; no git, no other skills):

```
bash <workspace>/.claude/skills/journal/scripts/capture.sh [-c <category>] ["note text"]
```

Omit `-c` for a loose entry, omit the text for an empty one to edit. Report the path it prints.

**Export** (only when asked):

1. Read the entries and propose a grouping: one entry → one output, a category → one merged output, or one entry split across several. Let the user adjust.
2. For each output, pick the workspace skill whose description fits its permanent home (see CLAUDE.md and each skill's description), preferring an existing docs area; a new section always needs approval.
3. Show the destination and reshaped text and wait for approval. Nothing lands silently.
4. Delegate to that skill; it owns formatting, conventions, and any GitHub contact.
5. Ask whether to delete the exported entry (default: keep).
