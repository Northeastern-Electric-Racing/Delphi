---
name: consolidate-spikes
description: Turn finished spikes into implementation tickets: an idea's spikes, once all are done, into an epic of dev work slices; a standalone spike into its dev work, usually one ticket. Use when the user wants to wrap up, settle, or consolidate an idea or spike on an application-software repo (Argos, Nero).
---

Drafts and files by the `create-ticket` rules; load it and the project's `ticket-conventions` first. Takes an idea or a standalone spike.

1. **Gather** each spike's findings comment, draft PR, and the PR's reviews; from an idea, its sub-issues too.
2. **Check it's done.** From an idea, every spike under it has findings and a lead review, and every approach is covered by a spike area. Otherwise list what's missing, offer spikes for uncovered approaches, and stop.
3. **Choose:** per area (title prefix), propose the direction to build (one spike's, or a mix) with a one-line why, from the findings and the lead's review. The user confirms or changes each.
4. **Slice** the chosen directions into dev work by `create-ticket`'s Dev work rules: vertical slices, cut for the most parallel work, which may cross areas. Each ticket: What, the slice; Notes, links to the spikes and draft PRs it draws on, any "Blocked by", and the dropped directions with why; context transfer, the findings' facts. A standalone spike usually makes one.
5. **Draft** them, and from an idea one epic (From idea; Approach: each area's direction) with the dev work as its sub-issues. Show all, with which slices run in parallel; file what the user OKs.
6. **Close**, each with a one-line comment: the spikes as completed ("Consolidated into #<epic or dev work>"), their draft PRs unless a dev work ticket builds on that branch, and the idea as completed ("Settled in #<epic>").
