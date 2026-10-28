---
name: address-pr-comments
description: Fetch review comments on a PR (Argos, Nero), judge whether each (including outdated ones) still applies, and walk through fixes in the PR's worktree
---

Run every skill helper through the workspace bootstrap, including in fresh shells and sub-agents:

```sh
bash "<absolute-workspace-root>/.delphi/exec.sh" bash "<absolute-installed-skill-folder>/scripts/<script>.sh" <arguments...>
```

Replace the placeholders with the known workspace root, this skill's installed native folder, the script name, and its arguments. Obtain the workspace's absolute path once with `bash .delphi/paths.sh` from the checked-out workspace root. The wrapper sets `DELPHI_ROOT` for every invocation and preserves the caller's working directory; do not assume shell exports persist.


Propose and apply fixes for a PR's unresolved review feedback. **Never reply to threads**; the user does.

1. **Fetch** from the workspace root: `bash "<absolute-workspace-root>/.delphi/exec.sh" bash "<absolute-installed-skill-folder>/scripts/fetch-feedback.sh" <repo> <pr>|<branch>` (`<repo>` as under `repos/`, e.g. `argos`; `--all` first for unfiltered history). It checks out the PR head's worktree and prints JSON: `worktree` (target it by path from the root from now on), unresolved `threads`, `comments`, `reviews`. Any non-zero exit: use the available authenticated GitHub integration's `PR reader` instead.
2. **Judge.** Skip bot noise and anything already fixed at HEAD. For an `outdated` thread, find its `diffHunk` code by content, then label it **addressed**, **applies**, **moved**, **obsolete**, or **unclear**.
3. **Present** before editing, grouped by file, and ask to confirm, skip, or change each (offer to batch clear ones past 8):

   ```
   <file>:<line> — <reviewer> · <active|outdated> · <label>
   "<excerpt>" → <proposed fix>
   <optional ≤5-line snippet, for the user only>
   ```
4. **Apply** in that worktree, by path, with grouped `$commit`s. For a follow-up-ticket request, reuse a match from `gh issue list --search` before filing.
5. **Report** what was fixed (file:line, commit SHA), what was already addressed or obsolete (why), and what is unclear.
