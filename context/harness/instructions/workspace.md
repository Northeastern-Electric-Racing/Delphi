# Delphi workspace

You are in a Delphi workspace: a folder that pairs team context with the code repos it's about. It has two kinds of git repo, and every change belongs to exactly one:

| Path | What it is | Changes go |
|---|---|---|
| `CLAUDE.md`, `.claude/`, `docs/`, `context/` | Team context and docs from Delphi | Workspace git (`working` branch); `delphi workspace propose` opens the Delphi PR |
| `repos/<name>/` | A normal clone of a code repo, with its own remote | That repo's git, branches, and PRs, per its conventions |
| `worktrees/` | Empty; for extra checkouts of a repo (`git -C repos/<name> worktree add ../../worktrees/<branch> <branch>`) | Same as the repo it came from |

- Run a repo's git, `gh`, build, and test commands from inside that repo (`cd repos/<name>`), never from the workspace root: at the root, `git` is the workspace repo.
- Code changes never go in the workspace git (`repos/` and `worktrees/` are git-ignored there). Context changes (instructions, skills, docs) never go in a code repo.
- Each context file is a copy of one file in Delphi. **Synced** files are updated by `delphi workspace refresh`, and committed edits to them are proposed back. **Copied** files are yours after the first copy and are never proposed. Files you add stay local unless they sit in a synced folder.
- If `CLAUDE.md` is assembled from parts, it is generated: edit the synced part instead (or add the part under `sync:` in `.delphi/manifest.yml`).
- `delphi workspace diff` shows what you changed and where each change would go. `--upstream` shows what changed in Delphi since the last refresh.
- `.delphi/manifest.yml` is the layout: edit it to add or drop synced files (the edit is proposed too). Don't edit `.delphi/lock.tsv`.
