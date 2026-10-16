---
name: report-spike
description: Post a spike's findings on its ticket, judged against its hypothesis, and ask the lead to review its draft PR. Use when a spike's direction has been tried on an application-software repo (Argos, Nero).
---

A spike runs like any ticket (its branch, test-first work, commits, and a draft PR from `open-pr`); this reports it. First load the project's `pr-conventions` and `ticket-conventions` skills for the repo.

1. **Read** the spike (`gh issue view <n> --comments`), its draft PR, and the branch's diff against the base.
2. **Draft the findings** as one comment, plain and short, at most three backtick uses:

   ```
   ### Findings
   **Hypothesis:** holds | partly holds | doesn't hold. One sentence why.
   **Learned:** what the attempt showed: measurements, limits hit, surprises. Facts with links to the draft PR's code.
   **Recommendation:** adopt, adopt with changes, or drop this direction, and why. Note anything worth taking into a sibling spike's direction.
   **Open questions:** what the spike didn't settle.
   Draft PR: #<pr>
   ```
3. **Show** the comment and the lead to request (ask the user who the lead is), then post it with `gh issue comment <n> --body-file /tmp/<branch>-findings.md` only once they OK it.
4. **Ask for review:** `(cd worktrees/<repo>/<branch> && gh pr edit <branch> --add-reviewer <lead>)`, keeping the PR a draft. The review is light: the lead checks the findings and recommendation, not code polish. Remind the user to ping the lead on Slack with the spike and PR links.
