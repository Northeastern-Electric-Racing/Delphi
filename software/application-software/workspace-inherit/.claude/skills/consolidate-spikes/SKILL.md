---
name: consolidate-spikes
description: Turn finished spikes into implementation tickets: an idea's spikes, once all are done, into an epic with one dev work ticket per area; a standalone spike into one dev work ticket. Use when the user wants to wrap up, settle, or consolidate an idea or spike on an application-software repo (Argos, Nero).
---

Drafts and files by the `create-ticket` rules; load it and the project's `ticket-conventions` first. Takes an idea or a standalone spike.

1. **Gather** each spike's findings comment, draft PR, and the PR's reviews; from an idea, its sub-issues too.
2. **Check it's done.** From an idea, every spike under it has findings and a lead review, and every approach is covered by a spike area. Otherwise list what's missing, offer spikes for uncovered approaches, and stop.
3. **Choose:** per area (title prefix), propose the direction to build (one spike's, or a mix) with a one-line why, from the findings and the lead's review. The user confirms or changes each.
4. **Draft** one dev work ticket per area (What: the chosen direction; Notes: links to its spikes and draft PRs, and the dropped directions with why; context transfer: the findings' facts). From an idea, also one epic (From idea; Approach: each area's direction) with the dev work as its sub-issues. Show all; file what the user OKs.
5. **Close**, each with a one-line comment: the spikes as completed ("Consolidated into #<dev work>"), their draft PRs unless a dev work ticket builds on that branch, and the idea as completed ("Settled in #<epic>").
