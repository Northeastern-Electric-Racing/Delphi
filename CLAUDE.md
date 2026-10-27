# Delphi — developing it

Delphi stores NER's AI-harness context. Each workspace is a folder `software/**/workspaces/<leaf>/`
on `main`, named by the short names of its folders and its leaf, joined by dots (`.delphi/names.sh`;
a folder's short name is its `short-name` file, else its name: `s.app.argos.argos-dev`); branch `ws/<name>` has that folder as its repo root. `ci/sync.sh` keeps them in sync with
subtree merges: **refresh** (main → `ws/<name>`) and **propose** (`ws/<name>` → PR to main via
`propose/<name>`). There is no CLI, just a few shell scripts run by CI. `docs/design.md` is the
source of truth; `docs/goals.md` lists what any change must keep.

## Layout

- `ci/sync.sh [refresh|propose] [<name>]`: refresh and/or propose each workspace (both by default).
  Runs on pushes to main and `ws/**`.
- `ci/check.sh [<dir>]`: validates the repo. Runs on PRs to main and on each proposal.
- `tools/new-workspace.sh`: new workspace folder from `templates/workspace/` as a PR. Its PR and
  sync's propose PRs fill `.github/pull_request_template.md`'s sections (keep them in step) and are
  labelled `by: ai` (new-workspace: `--by ai-assisted|human` when the user says so).
- `ci/plugins.sh`: writes `.claude-plugin/marketplace.json` from the plugin sets
  (`software/**/plugins/<harness>/<set>/`, named `<scope>[.<set>]`; a folder's scope is its
  `plugins/scope`, else its `short-name`, else its name), each Claude Code workspace's `workspace.yml` `plugins:` defaults (the
  `default` set of every folder above), and its `.claude/settings.json` (enabled sets, and the SessionStart hook that sets `$DELPHI_ROOT`; never edit
  it by hand). `ci/render.sh` calls it for main-side plugin output; sync keeps branch-selected
  plugin sets active while their proposal to main is pending.
- `.delphi/{setup,new-worktree,switch,park,plugins}.sh`: the scripts every workspace runs (setup.sh
  runs `plugins.sh`, which makes this clone's local `@delphi` installs what the workspace enables and
  uninstalls ones the marketplace dropped, so plugin changes need no migration); `.delphi/paths.sh`
  is the layout (`DELPHI_ROOT`, `DELPHI_WORKTREES`, …) that they and skill scripts source; `.delphi/names.sh` names every
  workspace (dotted short names; setup, switch, sync, check and the migration all use it); park.sh also moves
  the root folders under a workspace's `park:` in `workspace.yml` on a switch, and setup.sh excludes them. Only here: sync
  puts `.delphi/` at the root of every `ws/*` branch and strips it from proposals.
- `.delphi/manifest.yml` (Delphi's files and their `version:`), `.delphi/versions` (one line per
  version, with its hash from `.delphi/version.sh`), `.delphi/migrations/<version>-<slug>.sh` (clone
  cleanup, run by `setup.sh`).
- `templates/workspace/`: `workspace.yml`, `CLAUDE.md` (`{{name}}`, `{{folder}}`), the managed
  `.github/workflows/delphi.yml` every workspace carries unchanged. The general skills are in
  `software/workspace-inherit/.claude/skills/`; Codex adds its bootstrap from `templates/harnesses/`
  to the common instruction base once at creation.
- `software/plugins/claude/default/`: the `delphi` plugin set, a mod whose `/ws-delphi` pane switches
  workspaces (`hooks/register.tsx`, tests in `tests/ws.test.ts`, run by `claude plugin test`);
  `/ws-delphi --web` serves the same cards in a browser tab (`web/server.py`, `web/index.html`).
- `software/…/workspaces/<leaf>/`: the workspaces. Org structure is plain directories. A project
  folder (the one holding `workspaces/`) may add `README.md`, `AUTHORING.md`, and `workspace-defaults/`
  (translated once into a new workspace there). Existing source layouts stay intact; optional
  `source.yml` declares a different authoring format. Any org/project folder may add `workspace-inherit/`;
  CI prepares inheritance in temporary staging and refresh copies it only to ws branches.
  Their `workspace.generated` records ownership; `opt-out:` transfers a native path to the workspace.
  Main keeps owned native files and canonical sources, never inherited copies or ledgers.
- `.github/workflows/delphi.yml` (identical to the template's copy), `.github/CODEOWNERS`; issue templates (idea, spike, epic, dev work) and the PR template in `.github/`, filed with the `create-ticket` skill (`.claude/skills/`).
- `tests/e2e.sh`: end-to-end test in a throwaway sandbox (bare origin, stub `gh` logging to `gh.log`).
- `ci/render.sh [--check] [--workspace <folder>] [<main-checkout> [<staging-output>]]`: update plugin
  output, or prepare inherited native files and ledgers in optional temporary staging. Main-side
  checks reject managed copies, ledgers and ownership collisions; inherited output is never committed there.
  `ci/harnesses.sh` reads `ci/harnesses/<name>.sh` through pure `harness_field` queries;
  `ci/sources.sh` reads independently selected formats; `ci/inherit.sh` resolves sources.
  `ci/managed.sh` shares ownership logic with sync, whose refresh
  copies staged output. Every workspace must explicitly declare its harness. Codex uses
  `.delphi/exec.sh` to initialize helper commands in independent shells.

## Rules

- Keep it small: fewest lines that implement the design; a short header comment per script.
  Prefer deleting to adapting.
- Don't list out groups of things in docs or comments (`docs/design.md`, README, CLAUDE.md, script
  headers): name the file or key that holds them ("the folders in `.delphi/park.list`", "each repo
  under `repos:`"), never its entries. A copied list goes stale. Runtime tools: bash, git, and `gh` (only to open or update PRs).
- Every script: `#!/usr/bin/env bash`, `set -euo pipefail`, `shellcheck`-clean.
- Keep Claude skill sources under workspace-inherit/.claude/skills with their metadata intact.
  Each descriptor owns `translate_skill`; native metadata conversion, identifier mappings and
  helper bootstrap affect only generated output. Write skills once in Claude format; translate
  identifiers and feature bullets, never exact source sentences or per-skill copies. Validation
  rejects unmapped Claude identifiers in other harnesses; qualified code-repository paths stay literal.
  Shared-source paths and opt-out keys follow `docs/design.md`'s portable-path rule; existing owned
  workspace filenames are unaffected.
  Skill scripts stay harness-independent (SKILL.md uses the Agent Skills format): call scripts by
  their path in the skill's folder, `bash scripts/<script>.sh <names>…`, and reference files the same
  way. Skill scripts (inherited, plugin or workspace) take only names (repo, branch) and read the workspace
  from `$DELPHI_ROOT`, sourcing `$DELPHI_ROOT/.delphi/paths.sh` for every folder; each harness's
  bootstrap sets it (Claude Code: a SessionStart hook in `.claude/settings.json`, from
  `ci/plugins.sh`). Never search for the root or default to the cwd's branch.
- `.delphi/*.sh` run on people's machines: bash 3.2 (macOS) and Git Bash safe. No bash-4
  features (associative arrays, `mapfile`, `${x,,}`, `|&`), POSIX awk only.
- Changing the workflow: update the template, `.github/`, and every workspace copy in the same PR,
  or `ci/check.sh` fails. `.delphi/*.sh` has one copy, at the root.
- Changing any file `.delphi/manifest.yml` lists makes a new version: bump `version:` (PATCH for a
  fix, MINOR for something new, MAJOR when clones need cleanup, MINOR while 0.x), then append
  `<what bash .delphi/version.sh prints> <what changed>` to `.delphi/versions`. Only add lines there.
- When people's clones need cleanup, ship a migration rather than instructions: safe to re-run, a no-op
  on a fresh clone, run from the workspace root, deletes only what nothing is lost from and otherwise
  exits 1 saying what to do. Never edit a released one.
- `bash tests/e2e.sh` and `ci/check.sh` must pass. Add a test there for every behavior change.
- Never test against real GitHub repos or this checkout's origin; use the sandbox in `tests/e2e.sh`.
