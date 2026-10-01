---
name: verify-telemetry
description: Verification checklist for changes to MQTT-displayed telemetry values in the Angular frontend. Use whenever modifying, adding, or debugging a value that flows from the car through MQTT to the UI — including display formatting, new subscriptions, missing data, or incorrect readings.
---

Run from the ticket's worktree (`worktrees/argos/<branch>/`, via `new-worktree`). Stop and fix at the first failing step.

1. **Trace the subscription** from the component: its property is updated by a `this.storage.get(topics.someTopicFn())` subscription, the function in `angular-client/src/utils/topic.utils.ts` returns the right topic, and the value is parsed right for its type (`parseInt` vs `parseFloat`). A missing subscription is the bug.
2. **Check the topic end to end** from the workspace root:

   ```bash
   bash .claude/skills/verify-telemetry/scripts/check-topic.sh <TOPIC>
   ```

   It prints the CAN definition (unit, value points; exit 1 if the topic isn't defined), refreshes the Calypso image (restart with `./argos.sh client-dev down && ./argos.sh client-dev up` if it changed), and shows the topic's last scylla-server log lines. Confirm the unit and value index match the UI; no log lines means it isn't being published.
3. **See it live:** bring the app up with `run-local`, open the page with Playwright, wait for data, and screenshot to `pictures/<branch>/<name>.png`. Check value, formatting, and layout.
