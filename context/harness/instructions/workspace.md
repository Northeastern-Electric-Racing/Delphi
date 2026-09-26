# Delphi workspace

You are in a Delphi workspace: this folder, checked out from Delphi on your own branch. It pairs team context with the code repos it's about, and holds two kinds of git repo. Every change belongs to exactly one:

| Path | What it is | Changes go |
|---|---|---|
| `CLAUDE.md`, `.claude/`, `docs/`, other files here | The workspace, a folder in Delphi (a sparse checkout that holds only this folder) | Commit on the checkout's branch; `delphi propose` opens the Delphi PR |
| `repos/<name>/` | A separate clone of a code repo, with its own remote (git-ignored by the workspace) | That repo's git, branches, and PRs, per its conventions |

- Run a repo's git, `gh`, build, and test commands from inside that repo (`cd repos/<name>`), never from this folder: here, `git` is the Delphi checkout.
- Code changes never go in the workspace's git. Context changes (instructions, skills, docs) never go in a code repo.
- Some files are **linked** to a shared source in Delphi (see `links:` in `workspace.yml`). Edit them here like any file: when you propose, `delphi sync` writes your edit to the source and to every other workspace that links it. `delphi diff` tags those files `linked` and lists the workspaces they are `shared` with. If someone else changed the same shared file differently, sync reports a conflict instead of guessing.
- Files that aren't linked are this workspace's own. To add one, just add it.
- If `workspace.yml` lists `instructions:`, `CLAUDE.md` is generated from those parts: don't edit it by hand; edit the part instead (link it into this folder under `links:` and edit the copy, or change it in Delphi).
- `delphi diff` shows what you changed versus `main`; `delphi diff --upstream` shows what changed on `main` since your last `delphi refresh`. `delphi refresh` merges `main` into your branch (conflicts are resolved with plain git). `delphi propose` sends your committed changes as one PR.
