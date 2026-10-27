Propose and apply fixes for a PR's unresolved review feedback. **Never reply to threads**; the user does.

1. **Fetch** from the workspace root: `bash scripts/fetch-feedback.sh <repo> <pr>|<branch>` (`<repo>` as under `repos/`, e.g. `argos`; `--all` first for unfiltered history). It checks out the PR head's worktree and prints JSON: `worktree` (target it by path from the root from now on), unresolved `threads`, `comments`, `reviews`. If the helper fails, use an available authenticated GitHub integration to read the PR's reviews and comments. If neither is available, report the missing access.
2. **Judge.** Skip bot noise and anything already fixed at HEAD. For an `outdated` thread, find its `diffHunk` code by content, then label it **addressed**, **applies**, **moved**, **obsolete**, or **unclear**.
3. **Present** before editing, grouped by file, and ask to confirm, skip, or change each (offer to batch clear ones past 8):

   ```
   <file>:<line> — <reviewer> · <active|outdated> · <label>
   "<excerpt>" → <proposed fix>
   <optional ≤5-line snippet, for the user only>
   ```
4. **Apply** in that worktree, by path, with grouped commits using the `commit` skill. For a follow-up-ticket request, reuse a matching existing GitHub issue before filing.
5. **Report** what was fixed (file:line, commit SHA), what was already addressed or obsolete (why), and what is unclear.
