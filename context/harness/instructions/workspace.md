# Delphi workspace

You are in a Delphi workspace: a folder that pairs team context with the code repos it's about. It has two kinds of git repo, and every change belongs to exactly one:

| Path | What it is | Changes go |
|---|---|---|
| `CLAUDE.md`, `.claude/`, `context/`, `docs/` | Team context and docs pulled from Delphi | Workspace git (`working` branch); `delphi workspace propose` opens the Delphi PR |
| `repos/<name>/` | A normal clone of a code repo, with its own remote | That repo's git, branches, and PRs, per its conventions |
| `worktrees/` | Empty; for extra checkouts of a repo (`git -C repos/<name> worktree add ../../worktrees/<branch> <branch>`) | Same as the repo it came from |

- Run a repo's git, `gh`, build, and test commands from inside that repo (`cd repos/<name>`), never from the workspace root: at the root, `git` is the workspace repo.
- Code changes never go in the workspace git (`repos/` and `worktrees/` are git-ignored there). Context changes (instructions, skills, blocks) never go in a code repo.
- `.delphi/` is Delphi bookkeeping. Don't edit it by hand.
