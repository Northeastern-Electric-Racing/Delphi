---
name: delphi-new-workspace
description: Build a new Delphi workspace folder with the user. Interview them about the work, pick shared sources to link from scope recommendations, draft workspace.yml, and open the PR with `delphi create --from`. Use when someone wants a new workspace or harness setup in Delphi.
---

# Create a Delphi workspace

Drive the CLI. Don't write to `context/` yourself.

1. **Interview.** Ask what the work is (team, repo, typical tasks) and pick the closest scope
   under `context/` (for example `software/application-software/argos`).
2. **Gather candidates.** Read `recommend:` in the scope's `scope.yml` and in each ancestor's,
   closest scope first, and sort each into the key matching its directory. Browse the scopes'
   `blocks/`, `docs/`, and `harness/` directories. Run `delphi list` to avoid name clashes and
   read existing workspaces' `workspace.yml` for ideas.
3. **Draft** a `workspace.yml` in a temp file (format: `docs/design.md` §2). Paths are relative to
   `context/`.
   - `name`: the workspace name (`[a-z0-9-]+`, unique repo-wide). `harness: claude-code`.
   - `instructions:` (optional): parts `CLAUDE.md` is generated from, usually
     the scope's `harness/instructions/workspace.md` first (e.g. `software/application-software/argos/harness/instructions/workspace.md`). The generated file must not be hand-edited; users
     change a part instead.
   - Linked keys: shared sources kept identical in every workspace that links them. Entry =
     `<source> [-> <dest>]`; a directory links every file under it. Each source must sit in its
     key's directory in some scope:
     - `skills:` a skill directory `…/harness/skills/<n>` → default `.claude/skills/<n>`.
     - `blocks:` under `…/blocks/` → default `context/<source>`; usually give `->`, e.g.
       `…/blocks/pr-body.md -> .claude/skills/open-pr/pr-body.md`.
     - `docs:` under `…/docs/` → default `docs/<path below docs/>`.
     - `settings:` one file under `…/harness/settings/` → default `.claude/settings.json`.
     Dests must be unique and must not sit inside another directory link's dest (a file link into
     one of the workspace's own folders is fine).
   - `mcp:` (optional): MCP fragments under `…/harness/mcp/` (each one `"name": {…}` member, no
     trailing comma); `.mcp.json` is generated from them and must not be hand-edited.
   - `repos:` as `name: git-url` (cloned into `repos/` in a checkout).
   Only link what should stay shared. Anything team-specific becomes the workspace's own file:
   after the PR merges, add it in a checkout and propose it. Tell the user which sources other
   workspaces already link: edits to those reach other teams.
4. **Show the draft** and get explicit approval.
5. **Create it:**
   `delphi create <scope> <name> --from <draft> --model <your model> --effort <effort> --yes`
   It writes the folder, runs `delphi sync` (materializing linked files, `CLAUDE.md`,
   `.mcp.json`) and `delphi check`, and prints the branch (`delphi/create/<name>`). On a check
   failure, fix the draft and retry.
6. Once the PR merges: `delphi checkout <name>`, then `delphi open <name>`.
