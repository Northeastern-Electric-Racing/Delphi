---
name: switch-workspace
description: Switch this clone to another Delphi workspace, or to Delphi's main, to work in it. Use when the user wants to check out, switch to, open, or work in another workspace or project, or to change another workspace's or main's files.
---

Run from the workspace root:

```
bash .delphi/switch.sh <name>        # ws/<name>: its dotted name, e.g. s.app.argos.argos-dev
bash .delphi/switch.sh main          # Delphi's main: project folders, templates, CI
```

- List workspaces and their project folders: `bash .delphi/switch.sh --list`.
- It refuses while tracked files have changes: commit them on a branch (and PR them) first. Then it fetches, switches, fast-forwards, and runs the new workspace's `.delphi/setup.sh`.
- The post-checkout hook parks this workspace's `repos/`, `worktrees/`, `references/` and `workspaces/` in `.delphi/parked/<name>/` (git-ignored; `<name>` as in its `workspace.yml`) and brings the other's back at the same paths, so worktrees and the work in them return as they were. Switch back the same way. Never run `git clean -X` or `git stash --all` at the workspace root: they take ignored files, parked work included.
- Before switching, stop anything running from `worktrees/` (dev servers, Docker builds): its folder moves.
- Start a fresh harness session after switching so its instructions and skills match the new workspace. A harness integration may explicitly support reloading in place; follow its documented behavior.
- To change the workspace you switched to: `git switch -c <branch>`, commit, push, and open a PR into `ws/<name>` (or `main`).
- To only read another workspace or main without leaving this one, list it under `workspaces:` instead (`setup-workspace` skill).
