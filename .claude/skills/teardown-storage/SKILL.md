---
name: teardown-storage
description: Tear down what run-local brought up — its clients and `cargo run`, and the dev compose stacks it started with their database volume, networks and images — now, on a timer, or automatically after every run-local. Use when the user wants the local Argos stack gone, or when run-local reports teardown=unset.
---

It touches only what run-local started (recorded in its state); other stacks, images and Docker's build cache stay. It doesn't ask: run it when the user wants the stack gone, and report the space freed. Close this session's Playwright CLI sessions first (`playwright-cli list`, then `playwright-cli -s=<name> close`).

- Now: `bash scripts/teardown.sh`
- Later: `bash scripts/teardown.sh in <minutes>` (replaces an earlier timer).
- After every run-local: `bash scripts/teardown.sh auto <minutes|off>` stores the workspace's choice, and run-local arms the timer each time it brings the stack up; `bash scripts/teardown.sh auto` prints it. When run-local reports `teardown=unset`, ask the user once whether to tear the stack down automatically and after how many minutes, store the answer with `auto`, and arm this run with `in`.

With Docker stopped it stops the processes and keeps the record; start Docker and run it again.
