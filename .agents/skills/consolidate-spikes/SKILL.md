---
name: consolidate-spikes
description: >-
  Turn finished spikes into implementation tickets: an idea's spikes, once all are done, into dev work, under an epic when it comes from an idea or splits. Use when the user wants to wrap up, settle, or consolidate an idea or spike on an application-software repo (Argos, Nero).
---

Run every skill helper through the workspace bootstrap, including in fresh shells and sub-agents:

```sh
bash "<absolute-workspace-root>/.delphi/exec.sh" bash "<absolute-installed-skill-folder>/scripts/<script>.sh" <arguments...>
```

Replace the placeholders with the known workspace root, this skill's installed native folder, the script name, and its arguments. Obtain the workspace's absolute path once with `bash .delphi/paths.sh` from the checked-out workspace root. The wrapper sets `DELPHI_ROOT` for every invocation and preserves the caller's working directory; do not assume shell exports persist.


Drafts and files by the `create-ticket` rules; load it and the project's `ticket-conventions` first. Takes an idea or a standalone spike.

1. **Gather** each spike's findings comment, draft PR, and the PR's reviews; from an idea, its sub-issues too.
2. **Check it's done.** Every spike is done by `create-ticket`'s Spikes rules (the lead's latest review on its draft PR, from repos/<owner>/<repo>/pulls/<pr>/reviews, is an approval). From an idea, that's every spike under it, and every one of its areas to explore is covered by a spike area. Otherwise list what's missing, offer spikes for uncovered areas, and stop.
3. **Choose:** per area (title prefix), propose the approach to build (one spike's, or a mix) with a one-line why, from the findings and the lead's review. The user confirms or changes each.
4. **Plan** the dev work by `create-ticket`'s Dev work rules: one ticket unless the work is large enough to split into vertical slices, which may cross areas. Each ticket: What, the slice; Notes, links to the spikes and draft PRs it draws on, and the dropped approaches with why; context transfer, the findings' facts.
5. **Draft** them, and, from an idea or when split, one epic (From: the idea or spike) with the dev work as its sub-issues. Show all, with which slices run in parallel if split; file what the user OKs.
6. **Close**, each with a one-line comment: the spikes as completed ("Consolidated into #<epic or dev work>"), their draft PRs unless a dev work ticket builds on that branch, and the idea as completed ("Settled in #<epic or dev work>").
