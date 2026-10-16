---
name: consolidate-spikes
description: Turn reviewed spikes into implementation tickets, from an idea (an epic with one dev work ticket per area) or from spikes the user names. Use when the user wants to wrap up, settle, or consolidate an idea or spikes on an application-software repo (Argos, Nero).
---

Drafts and files by the `create-ticket` rules; load it and the project's `ticket-conventions` first. Takes an idea, or the spikes the user names (numbers or an area prefix).

1. **Gather** each spike's findings comment, draft PR, and the PR's reviews (and the idea, if any, with its sub-issues).
2. **Group** the spikes by area (title prefix). Stop and list what's missing if a spike has no findings or review, or, from an idea, an approach has no area; offer spikes for the gaps.
3. **Choose:** per area, propose the direction to build (one spike's, or a mix) with a one-line why, from the findings and the lead's review. The user confirms or changes each.
4. **Draft** one dev work ticket per area (What: the chosen direction; Notes: links to its spikes and draft PRs, and the dropped directions with why; context transfer: the findings' facts). From an idea, also one epic (From idea; Approach: each area's direction) with the dev work as its sub-issues. Show all; file what the user OKs.
5. **Close**, each with a one-line comment: the spikes as completed ("Consolidated into #<dev work>"), their draft PRs unless a dev work ticket builds on that branch, and the idea as completed ("Settled in #<epic>").
