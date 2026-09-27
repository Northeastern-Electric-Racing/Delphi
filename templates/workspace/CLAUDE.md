# Delphi workspace

You are in a Delphi workspace: this repo root is branch `ws/{{name}}` of Delphi (or a branch cut from it), which mirrors the folder `{{folder}}/` on Delphi's `main`. It holds two kinds of git repo, and every change belongs to exactly one:

| Path | What it is | Changes go |
|---|---|---|
| `CLAUDE.md`, `.claude/`, `docs/`, other files here | The workspace | Commit on a branch cut from `ws/{{name}}`; open a PR into `ws/{{name}}` |
| `repos/<name>/` | A clone of a code repo listed in `workspace.yml` (git-ignored here) | That repo's git, branches, and PRs, per its conventions |

- First time in a clone: run `.delphi/setup.sh` to clone the repos into `repos/`.
- Run a repo's git, `gh`, build, and test commands from inside that repo (`cd repos/<name>`), never from the root: here, `git` is the workspace branch.
- Code changes never go in the workspace's git. Context changes (instructions, skills, docs) never go in a code repo.
- Never push to `ws/{{name}}` or Delphi's `main` directly. After your PR merges into `ws/{{name}}`, CI opens a PR to `main`; once that merges, CI merges `main` back into `ws/{{name}}`.
- Refresh your branch with `git fetch origin && git merge origin/ws/{{name}}`.
