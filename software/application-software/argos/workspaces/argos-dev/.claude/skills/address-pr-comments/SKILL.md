---
name: address-pr-comments
description: Fetch review comments on an Argos PR, judge whether each (including outdated ones) still applies, and walk through fixes in the PR's worktree
allowed-tools: Bash(git:*), Bash(gh pr:*), Bash(gh issue list:*), Bash(bash */.claude/skills/address-pr-comments/scripts/fetch-feedback.sh:*)
user-invocable: true
---

Walk through unresolved review feedback on a PR, propose fixes, and apply the approved ones. **Never reply to threads**; the user does that.

1. **Fetch.** From the workspace root:

   ```bash
   bash .claude/skills/address-pr-comments/scripts/fetch-feedback.sh argos [<pr-number>|<branch>]
   ```

   It checks out the PR head at `worktrees/argos/<head>/` (reused if present) and prints JSON: `pr`, `worktree`, unresolved `threads` (first + latest message, `bot` flag, `diffHunk` when outdated), conversation `comments`, and `reviews` with text. Work in `worktree` from here on. Add `--all` for everything unfiltered (resolved threads, every reply, empty reviews) when you need history. It uses `gh` when logged in, else (in a Claude Code remote session) the session's GitHub REST proxy. Exit 3 means neither is available: use the GitHub MCP server's `pull_request_read` (`get_review_comments`, `get_comments`, `get_reviews`) instead.
2. **Judge.** Skip bot noise unless it needs action, and anything already fixed at HEAD. For an **outdated** thread, find the code from its `diffHunk` by searching for its content, not line numbers, then label it **addressed**, **applies**, **moved** (fix at the new spot), **obsolete**, or **unclear** (ask).
3. **Present** before editing, grouped by file then reviewer:

   ```
   <file>:<line> — <reviewer>
   Comment: "<short excerpt>"
   Status: <active | outdated> · <label>
   Proposed fix: <plain words>
   Snippet: <optional, ≤5 lines, for the user only; never posted>
   ```

   Ask to confirm, skip, or change each. With more than 8, offer to batch the clear ones.
4. **Apply** in the worktree, grouping related fixes into `/commit`s. If a comment asks for a follow-up ticket, search first (`gh issue list --search "<keywords>"`) and reuse a match.
5. **Report** fixed (file:line, one line each, commit SHAs), addressed or obsolete (why), and unclear.
