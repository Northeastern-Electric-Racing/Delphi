---
name: report-spike
description: Post a spike's findings on its ticket, judged against its hypothesis, and ask the lead to review its draft PR. Use when a spike's approach has been tried on an application-software repo (Argos, Nero).
---

A spike runs like any ticket (branch, commits, a draft PR from `open-pr`); this reports it. Load the project's `pr-conventions` first.

1. **Read** the spike (`gh issue view <n> --comments`), its draft PR, and the branch's diff against the base.
2. **Draft** one findings comment, short and factual:

   ```
   ### Findings
   **Hypothesis:** holds | partly holds | doesn't hold. One sentence why.
   **Learned:** measurements, limits hit, surprises, with links to the draft PR's code.
   **Recommendation:** adopt, adopt with changes, or drop, and why.
   **Open questions:** what the spike didn't settle.
   Draft PR: #<pr>
   ```
3. **Show** it and ask who the lead is; on OK, post it (`gh issue comment <n> --body-file /tmp/<branch>-findings.md`).
4. **Request review:** `(cd worktrees/<repo>/<branch> && gh pr edit <branch> --add-reviewer <lead>)`, keeping the PR a draft, and remind the user to ping the lead on Slack.

Address review feedback on the branch as on any PR (`address-pr-comments`), and edit the findings comment if it changes them. The spike is done when the lead approves the draft PR (`create-ticket`'s Spikes rules); it stays open until `consolidate-spikes` closes it.
