---
name: switch-workspace
description: Switch this clone to another Delphi workspace, or to Delphi's main, to work in it. Use when the user wants to check out, switch to, open, or work in another workspace or project, or to change another workspace's or main's files.
---

Run from the workspace root:

```
bash .delphi/switch.sh <workspace>   # ws/<workspace>
bash .delphi/switch.sh main          # Delphi's main: project folders, templates, CI
```

- List workspaces: `git branch -r --list 'origin/ws/*'`.
- It refuses while tracked files have changes: commit them on a branch (and PR them) first. Then it fetches, switches, fast-forwards, and runs the new workspace's `.delphi/setup.sh`.
- The post-checkout hook parks this workspace's `repos/`, `worktrees/`, `references/` and `linked/` in `.git/delphi/<name>/` and brings the other's back at the same paths, so worktrees and the work in them return as they were. Switch back the same way.
- Before switching, stop anything running from `worktrees/` (dev servers, Docker builds): its folder moves.
- This session keeps the old workspace's `CLAUDE.md` and skills. After switching, tell the user to restart Claude Code in the same folder, and don't start work in the new workspace until they have.
- To change the workspace you switched to: `git switch -c <branch>`, commit, push, and open a PR into `ws/<name>` (or `main`).
- To only read another workspace or main without leaving this one, link it instead (`setup-workspace` skill).
