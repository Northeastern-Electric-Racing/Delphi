---
name: delphi
description: Keep this Delphi workspace working on this machine, and route Delphi tasks to the right place. Use when a skill this workspace's CLAUDE.md names (like commit, open-pr, create-ticket, implement) is missing or unknown, when the session starts with a warning that plugins aren't installed, or when the user asks what Delphi does here or how to fix their workspace.
---

Delphi is where this workspace comes from: `workspace.yml` says what's checked out, `.delphi/` holds the scripts every workspace runs, and plugins carry the skills workspaces share. Find the task below and follow its section; each hands off to a file in this skill's folder or to another skill.

| Task | Section |
|---|---|
| A skill the workspace should have is missing; the session warned that plugins aren't installed | `plugins.md` |
| Add or remove a repo, dependency, or linked workspace; re-run setup after cloning or pulling | the `setup-workspace` skill |
| Work in another workspace or Delphi's main | the `switch-workspace` skill |
| A branch to work on | the `new-worktree` skill |
| Park a rough note | the `journal` skill |
