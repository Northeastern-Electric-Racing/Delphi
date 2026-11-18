---
name: teardown-storage
description: Free the disk the local Argos stack leaves behind — the dev compose stacks with their database volume, unused Argos images, Docker's build cache and run-local's state. Run it only when the user asks; when a session that ran run-local, verify-graph or verify-telemetry is done, suggest it instead.
---

Never run this unasked: the dev backend is shared by every workspace and session on this machine, so wiping it stops their stacks and drops their data, verify-graph's seeded run included. At the end of a session that ran the stack, suggest it in one line.

1. Stop what uses the stack first: this session's clients (`kill <pid>` from run-local's lines), its Playwright CLI sessions (`playwright-cli list`, then `playwright-cli -s=<name> close`) and a `cargo run` backend it started. Clients from other checkouts are the user's; ask before stopping them.
2. List what would go, with sizes:

   ```
   bash scripts/teardown.sh
   ```

   It names the dev stacks' containers, volumes and networks, unused Argos images, the build cache (every project's, since Docker can't tell them apart) and run-local's state, then what it leaves alone and what is still in use. Show the user the list and ask before going on. If it refuses because a dev-named stack came from a production compose file, report that; never remove it another way.
3. On a yes: `bash scripts/teardown.sh remove`. It refuses while a run-local client still serves. Report the space freed; Docker Desktop's disk image can take a while to shrink.

With Docker stopped it clears only run-local's state; start Docker and run it again for the rest. Base images, worktrees' `node_modules` and `target` folders, and Playwright's browsers stay.
