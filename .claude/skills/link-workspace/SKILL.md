---
name: link-workspace
description: Check out another Delphi workspace, or Delphi's main (project-level context and guides), next to this one under linked/ so you can read or reuse its instructions, skills, and docs. Use when the user refers to another workspace or project, or asks how workspaces are organized.
---

Run from the workspace root:

```
bash .delphi/link.sh <workspace>   # ws/<workspace> at linked/<workspace>/
bash .delphi/link.sh main          # Delphi's main at linked/main/
```

- List workspaces: `git branch -r --list 'origin/ws/*'`.
- This workspace's project folder (shared context, `AUTHORING.md`, `defaults/`) is the folder above `workspaces/<this-name>/` in `linked/main/`: `git -C linked/main ls-files '*/workspaces/<this-name>/workspace.yml'`.
- Linked checkouts are for reference; re-running updates them. To change one, `git -C linked/<name> switch -c <branch>`, commit, push, and open a PR into `ws/<name>` (or `main` for `linked/main`).
- Remove with `git worktree remove linked/<name>`.
