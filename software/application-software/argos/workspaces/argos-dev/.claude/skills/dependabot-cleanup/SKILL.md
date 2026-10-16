---
name: dependabot-cleanup
description: Validate, merge, and clean up open Dependabot PRs on Argos (Angular upgrades excluded). Use when asked to go through, merge, or clean up Dependabot PRs.
---

Run the scripts from the workspace root. Don't write gh, git, npm or cargo commands yourself, and read a log only when a step fails.

1. `bash scripts/list.sh` lists the PRs.
2. Run `bash scripts/validate.sh <pr>` for each PR, in the background. Show the user a table of the results.
3. After the user approves, run `bash scripts/merge.sh <pr>...`.
4. If a PR is blocked by CI, run `bash scripts/ci.sh <pr>`.
   - If develop has the same failure, draft a ticket (`create-ticket`) and fix it first.
   - Once develop has the fix, run `bash scripts/rebase.sh <pr>`, then `merge.sh` again.
5. Ask the user which PRs to clean up, then run `bash scripts/cleanup.sh <pr>...`.
