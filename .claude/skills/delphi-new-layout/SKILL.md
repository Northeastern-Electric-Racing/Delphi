---
name: delphi-new-layout
description: Build a new Delphi layout with the user. Interview them about the work, pick blocks from scope recommendations, draft manifest.yml, and open the layout PR with `delphi layout new --from`. Use when someone wants a new layout or workspace setup in Delphi.
---

# Create a Delphi layout

Drive the CLI. Don't write to `context/` yourself.

1. **Interview.** Ask what the work is (team, repo, typical tasks) and pick the closest scope
   under `context/` (for example `software/application-software/argos`).
2. **Gather candidates.** Read `recommend:` in the scope's `scope.yml` and in each ancestor's,
   closest scope first. Browse the scopes' `blocks/`, `docs/`, and `harness/` directories. Run
   `delphi layout list` to reuse ideas from existing layouts and avoid name clashes.
3. **Draft** a manifest in a temp file (format: `docs/design.md` §2). Paths are relative to
   `context/`; a directory source maps every file under it.
   - `name`: the layout name (`[a-z0-9-]+`). `harness: claude-code`.
   - `instructions:` (optional): parts assembled into `CLAUDE.md`, usually
     `harness/instructions/workspace.md` first. The assembled file is generated: users edit a part
     by syncing it.
   - `sync:` files the team keeps in step with Delphi (refresh updates them, propose sends edits
     back). `copy:` starting points the user then owns (never updated or proposed).
   - Entry = `<source> [-> <dest>]`. Default dests: `…/harness/skills/<n>` → `.claude/skills/<n>`,
     `…/docs/<rest>` → `docs/<rest>`, anything else → `context/<source>`. Use `->` for anything
     else, e.g. `…/blocks/pr-body.md -> .claude/skills/open-pr/pr-body.md`.
   - Dests must not overlap: no dest inside another entry's dest (sync a skill's `SKILL.md` as a
     file if a block also goes into that skill folder).
   - `repos:` as `name: git-url`.
   Tell the user which sources other layouts also sync (`delphi layout list`, then read their
   manifests): edits to those reach other teams.
4. **Show the draft** and get explicit approval.
5. **Create it:**
   `delphi layout new <scope> <name> --from <draft> --model <your model> --effort <effort> --yes`
   The command runs `check` and prints the branch (`delphi/layout/<name>`). On a check failure,
   fix the draft and retry.
6. **Optionally try it** before the PR merges: `delphi workspace new <name> --ref delphi/layout/<name>`.
   Once the PR merges, run `delphi workspace refresh <name> --ref main`.
