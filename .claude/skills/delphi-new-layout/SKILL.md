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
3. **Draft** a manifest in a temp file. Use the format in spec §4.3. All paths are relative to
   `context/`, and each entry goes under the key that matches its location:
   `harness/instructions/*` → `instructions`, `harness/skills/*` → `skills`,
   `harness/mcp/*.json` → `mcp`, `harness/settings/*` → `settings` (at most one),
   `blocks/*` → `blocks`, `docs/*` → `docs` (a trailing `/*` glob is allowed for both). `name` must equal the layout name
   (`[a-z0-9-]+`). `harness: claude-code`. Add `repos:` as `name: git-url`.
4. **Show the draft** and get explicit approval.
5. **Create it:**
   `delphi layout new <scope> <name> --from <draft> --model <your model> --effort <effort> --yes`
   The command runs `check` and prints the branch (`delphi/layout/<name>`). On a check failure,
   fix the draft and retry.
6. **Optionally try it** before the PR merges: `delphi workspace new <name> --ref delphi/layout/<name>`.
   Once the PR merges, run `delphi workspace refresh <name> --ref main`.
