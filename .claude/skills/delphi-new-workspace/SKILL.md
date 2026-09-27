---
name: delphi-new-workspace
description: Build a new self-contained Delphi workspace folder with the user. Interview them about the work, draft the folder (workspace.yml, CLAUDE.md, skills, docs) in a temp directory, and open the PR with `delphi create --from`. Use when someone wants a new workspace or harness setup in Delphi.
---

# Create a Delphi workspace

Drive the CLI. Don't write to `context/` yourself.

1. **Interview.** Ask what the work is (team, repo, typical tasks) and pick the closest scope
   under `context/` (a directory with a `scope.yml`, e.g. `software/application-software/argos`).
2. **Look for a starting point.** Run `delphi list` to avoid name clashes. Read existing
   workspaces in the same or nearby scopes (`context/<scope>/workspaces/<name>/`) for instructions,
   skills and docs worth starting from. There is nothing to link: the new workspace gets its own
   copies, and later edits to them affect only this workspace.
3. **Draft the folder** in a temp directory, laid out exactly as the workspace root will be:
   - `workspace.yml` (format: `docs/design.md` §2): `name` (the workspace name, `[a-z0-9-]+`,
     unique repo-wide, equal to the folder name), `harness: claude-code`, and `repos:` as
     `name: git-url` (cloned into `repos/` in a checkout, git-ignored).
   - `CLAUDE.md`: the workspace's instructions.
   - `.claude/skills/<skill>/SKILL.md` (plus any scripts), `.claude/settings.json`, `docs/…`: at
     their normal harness paths.
   No symlinks, no nested `workspace.yml`, nothing under `repos/`.
4. **Show the draft** (file list and contents) and get explicit approval.
5. **Create it:**
   `delphi create <scope> <name> --from <draft-dir> --model <your model> --effort <effort> --yes`
   It copies the folder into a temp worktree of `main`, runs `delphi check`, and opens the PR
   (branch `delphi/create/<name>`, printed last). On a check failure, fix the draft and retry.
6. Once the PR merges, CI creates `ws/<name>`. Then: `delphi checkout <name>`, `delphi open <name>`.
