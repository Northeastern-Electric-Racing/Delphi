---
name: code-review
description: Review the changes since a fixed point (commit, branch, tag, or merge-base) on two axes, Standards and Spec, in parallel sub-agents. Use when the user wants to review a branch, a PR, work-in-progress changes, or asks to "review since X".
---

1. **Fixed point.** Use the one the user gives, or ask. Confirm `git rev-parse <ref>` resolves and `git diff <ref>...HEAD` is non-empty.
2. **Spec.** Use a path the user passes, else the issue referenced in the commits, else `docs/spec/`, else ask. If there is none, skip the Spec axis.
3. **Standards.** Read `CLAUDE.md`, plus `angular-client/CLAUDE.md` and `scylla-server/CLAUDE.md` for the parts the diff touches.
4. **Two parallel `general-purpose` sub-agents**, each given the diff command and commit list, and each asked to stay under 400 words:
   - **Standards** (also give it the standards files): cite each violated rule by file. Also flag Fowler code smells (duplication, feature envy, speculative generality, unclear names, …) as judgement calls. Documented rules override smells. Skip anything prettier, eslint or clippy enforces.
   - **Spec** (also give it the spec): missing or partial requirements, scope creep, and wrong implementations, quoting the spec line for each.
5. **Report** under `## Standards` and `## Spec`, unmerged, and end with the finding count and worst issue per axis.
