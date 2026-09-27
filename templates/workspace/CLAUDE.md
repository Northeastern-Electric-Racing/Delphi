# Delphi workspace

This repo root is branch `ws/{{name}}` of Delphi (or a branch cut from it): the folder `{{folder}}/` on Delphi's `main`, as its own root. It holds two kinds of git repo, and every change belongs to exactly one:

| Path | What it is | Changes go |
|---|---|---|
| `CLAUDE.md`, `.claude/`, `docs/`, other files here | The workspace | A branch cut from `ws/{{name}}`, then a PR into `ws/{{name}}` |
| `repos/<name>/` | A clone of a code repo listed in `workspace.yml` (git-ignored here) | That repo's git, branches, and PRs, per its conventions |

- First time in a clone: run `.delphi/setup.sh` to clone the repos into `repos/`.
- Run a repo's git, `gh`, build, and test commands inside it (`cd repos/<name>`), never from the root: here, `git` is the workspace branch.
- Code changes never go in the workspace. Context changes (instructions, skills, docs) never go in a code repo.
- Never push to `ws/{{name}}` or Delphi's `main` directly. After your PR merges into `ws/{{name}}`, CI proposes it to `main` as a PR; CI also refreshes `ws/{{name}}` with `main`'s changes.
- Don't edit `.delphi/setup.sh` or `.github/workflows/delphi.yml`; Delphi manages them.
- Update your branch with `git fetch origin && git merge origin/ws/{{name}}`.
