---
name: switch-workspace
description: Switch this clone to another Delphi workspace, or to Delphi's main, to work in it. Use when the user wants to check out, switch to, open, or work in another workspace or project, or to change another workspace's or main's files.
---

Run from the workspace root:

```
bash .delphi/switch.sh <name>        # ws/<name>: its place in the tree, e.g. software/application-software/argos/argos-dev
bash .delphi/switch.sh argos-dev     # its last part alone, if only one workspace ends in it
bash .delphi/switch.sh main          # Delphi's main: project folders, templates, CI
```

- The user can also switch from the `/ws` pane (the `delphi` plugin's mod), which lists them (`bash .delphi/switch.sh --list`) and switches to the one picked; `/ws <name>` switches straight away.
- List workspaces: `git branch -r --list 'origin/ws/*'`. A workspace's name is its folder path on main without `workspaces/`.
- It refuses while tracked files have changes: commit them on a branch (and PR them) first. Then it fetches, switches, fast-forwards, and runs the new workspace's `.delphi/setup.sh`.
- The post-checkout hook parks this workspace's `repos/`, `worktrees/`, `references/` and `linked/` in `.delphi/parked/<name>/` (git-ignored; `<name>` as in its `workspace.yml`) and brings the other's back at the same paths, so worktrees and the work in them return as they were. Switch back the same way. Never run `git clean -X` or `git stash --all` at the workspace root: they take ignored files, parked work included.
- Before switching, stop anything running from `worktrees/` (dev servers, Docker builds): its folder moves.
- This session keeps the old workspace's `CLAUDE.md` and skills. After switching, tell the user to restart Claude Code in the same folder, and don't start work in the new workspace until they have.
- To change the workspace you switched to: `git switch -c <branch>`, commit, push, and open a PR into `ws/<name>` (or `main`).
- To only read another workspace or main without leaving this one, list it under `workspaces:` instead (`setup-workspace` skill).
