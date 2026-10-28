---
name: verify-telemetry
description: Verification checklist for changes to MQTT-displayed telemetry values in the Angular frontend. Use whenever modifying, adding, or debugging a value that flows from the car through MQTT to the UI — including display formatting, new subscriptions, missing data, or incorrect readings.
---

Run every skill helper through the workspace bootstrap, including in fresh shells and sub-agents:

```sh
bash "<absolute-workspace-root>/.delphi/exec.sh" bash "<absolute-installed-skill-folder>/scripts/<script>.sh" <arguments...>
```

Replace the placeholders with the known workspace root, this skill's installed native folder, the script name, and its arguments. Obtain the workspace's absolute path once with `bash .delphi/paths.sh` from the checked-out workspace root. The wrapper sets `DELPHI_ROOT` for every invocation and preserves the caller's working directory; do not assume shell exports persist.


Work from the workspace root against the ticket's worktree, `worktrees/argos/<branch>/` (via `new-worktree`). Stop and fix at the first failing step.

1. **Trace the subscription** in that worktree, from the component: its property is updated by a `this.storage.get(topics.someTopicFn())` subscription, the function in `angular-client/src/utils/topic.utils.ts` returns the right topic, and the value is parsed right for its type (`parseInt` vs `parseFloat`). A missing subscription is the bug.
2. **Check the topic end to end:**

   ```bash
   bash "<absolute-workspace-root>/.delphi/exec.sh" bash "<absolute-installed-skill-folder>/scripts/check-topic.sh" <TOPIC>
   ```

   It prints the CAN definition (unit, value points; exit 1 if the topic isn't defined), refreshes the Calypso image (if it changed, restart with `(cd worktrees/argos/<branch> && ./argos.sh client-dev down)` then `run-local <branch>`), and shows the topic's last scylla-server log lines. Confirm the unit and value index match the UI; no log lines means it isn't being published.
3. **See it live:** bring the app up with `run-local <branch>`, open the page with Playwright, wait for data, and screenshot to `pictures/<branch>/<name>.png`. Check value, formatting, and layout.
