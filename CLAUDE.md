# Hub: application-software overview

You're in Delphi workspace `software/application-software/hub` (branch `ws/software/application-software/hub`):
the head of application software's overview of the workspaces they run. It has no code repos by default; add
one under `repos:` in `workspace.yml` to make worktrees here (`new-worktree` skill).

Each workspace listed under `workspaces:` in `workspace.yml` is also cloned separately on this machine, on its
own `ws/<name>` branch, with its own Claude Code session. The user works in those in parallel. Here you
only see their read-only copies under `linked/<branch>/` (refresh with `bash .delphi/setup.sh`; change which are
listed with the `setup-workspace` skill). Park rough notes with the `journal` skill.

## What you do here

- Status across workspaces: open PRs (propose PRs to main, PRs into each `ws/*`), CI, issues, and what each
  workspace has changed since main, from `gh` and `linked/`.
- Compare workspaces: CLAUDE.md, workspace.yml, skills. Point out drift and gaps between them.
- Hand off: when a task belongs in a workspace, name it and write a prompt the user can paste into that
  workspace's session. Don't do the work here.
- Cross-workspace Delphi changes (templates, `workspace-inherit/`, CI) go as PRs to main, made from a
  temporary worktree of `origin/main`.
- Tickets across projects: `create-ticket`, `consolidate-spikes`.

## Don't

- Switch this clone to another workspace unless the user explicitly asks (`switch-workspace`). By default,
  hand off: the user relaunches Claude in that workspace's own clone.
- Edit anything under `linked/`.
