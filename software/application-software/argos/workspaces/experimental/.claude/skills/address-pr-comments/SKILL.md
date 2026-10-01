---
name: address-pr-comments
description: Fetch review comments on an Argos PR, judge whether each (including outdated ones) still applies, and walk through fixes in the PR's worktree
allowed-tools: Bash(git:*), Bash(gh issue list:*), Bash(bash */.claude/skills/address-pr-comments/scripts/fetch-feedback.sh:*)
user-invocable: true
---

Propose and apply fixes for a PR's unresolved review feedback. **Never reply to threads**; the user does.

1. **Fetch** from the workspace root: `bash .claude/skills/address-pr-comments/scripts/fetch-feedback.sh argos [<pr>|<branch>]` (`--all` for unfiltered history). It checks out the PR head's worktree and prints JSON: `worktree` (work there from now on), unresolved `threads`, `comments`, `reviews`. Any non-zero exit: use the GitHub MCP server's `pull_request_read` instead.
2. **Judge.** Skip bot noise and anything already fixed at HEAD. For an `outdated` thread, find its `diffHunk` code by content, then label it **addressed**, **applies**, **moved**, **obsolete**, or **unclear**.
3. **Present** before editing, grouped by file, and ask to confirm, skip, or change each (offer to batch clear ones past 8):

   ```
   <file>:<line> — <reviewer> · <active|outdated> · <label>
   "<excerpt>" → <proposed fix>
   <optional ≤5-line snippet, for the user only>
   ```
4. **Apply** in the worktree with grouped `/commit`s. For a follow-up-ticket request, reuse a match from `gh issue list --search` before filing.
5. **Report** what was fixed (file:line, commit SHA), what was already addressed or obsolete (why), and what is unclear.
