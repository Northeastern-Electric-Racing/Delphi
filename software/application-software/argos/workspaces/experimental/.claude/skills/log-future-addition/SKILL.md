---
name: log-future-addition
description: File one out-of-scope idea as a single un-triaged GitHub issue. Use when the user raises a good future addition that is out of scope for the current work ("we could also…", "would be nice to…", "let's do that later"); offer to log it.
---

For one brief idea, not a spec or plan. If the input is long, has acceptance criteria, or covers several features, suggest a full issue instead; the user can override. Follow Argos's `docs/agents/issue-tracker.md` (in any Argos worktree) for titles, labels, backticks, and assignment.

1. **Consent.** Unless the user invoked this skill, ask first ("Want me to log that as a future addition?").
2. **Idea.** Take it from the command argument, else the conversation, else ask.
3. **Duplicates.** Run `gh issue list --search "<keywords>" --state open`. Mention a strong match in step 5, but never block on it.
4. **Draft.** A concise imperative title, at most three backticks in the body, and these labels: `needs-triage` always; a type (`bug`, `new feature`, `feature enhancement`) or area (`angular-client`, `scylla-server`, `DevOps`) only when obvious; never difficulty.

   ```md
   ## What
   One or two sentences, in the user's framing.

   ## Why
   The motivation. Omit if there's nothing to add.

   > *Logged as a raw idea via log-future-addition.*
   ```
5. **Confirm, then file.** Show the title, body, and labels, and file only on consent. Write the body to a temp file and run from the workspace root:

   ```
   bash .claude/skills/log-future-addition/scripts/file-idea.sh argos "<title>" <body-file> [<label>...]
   ```

   It adds `needs-triage`, assigns you, and prints the URL. On any non-zero exit, use the GitHub MCP server's `issue_write`. Report the number and URL, and don't triage or work on it.
