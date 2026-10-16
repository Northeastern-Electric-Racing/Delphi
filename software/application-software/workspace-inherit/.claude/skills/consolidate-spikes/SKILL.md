---
name: consolidate-spikes
description: Turn an idea whose spikes are done into an epic with one dev work ticket per area. Use when the user wants to wrap up, settle, or consolidate an idea or its spikes on an application-software repo (Argos, Nero).
---

Drafts and files tickets by the `create-ticket` rules; load it and the project's `ticket-conventions` first.

1. **Gather:** the idea (`gh issue view <idea> --comments`), its sub-issues, and for each spike its findings comment, draft PR, and the PR's reviews.
2. **Group** the spikes by area (the title prefix) and map the areas onto the idea's approaches. The idea is settled when every approach is covered by an area and every area has at least one reviewed spike with findings. If not, list what is missing (approaches with no area, spikes without findings or review) and stop; offer to file spikes for the gaps with `create-ticket`.
3. **Choose:** for each area, propose the direction to build from its findings and the lead's review (one spike's, or a mix), with a one-line why. The user confirms or changes each pick.
4. **Draft** one epic (From idea; Approach: each area's chosen direction, linking its spikes) and one dev work ticket per area (What: the chosen direction; Notes: links to the area's spikes and draft PRs, and the dropped directions with why; context transfer: the facts from the findings). Show them all, then file what the user OKs, each dev work ticket a sub-issue of the epic.
5. **Close**, each with a one-line comment: the spikes as completed ("Consolidated into #<dev work>"), their draft PRs unless a dev work ticket builds on that branch, and the idea as completed ("Settled in #<epic>").
