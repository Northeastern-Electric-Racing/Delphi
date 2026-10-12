# Delphi — Design

Goals: `docs/goals.md`. No CLI: plain git plus a few shell scripts run by GitHub Actions.

## 1. Model

`main` holds every workspace as a folder, `software/**/workspaces/<leaf>/`, with its files at their
normal harness paths (`CLAUDE.md`, `.claude/…`, `docs/…`). A workspace's `<name>` is its place in
the tree: the folder's path without `workspaces/` (`software/application-software/argos/argos-dev`
for `software/application-software/argos/workspaces/argos-dev`). For each workspace, branch
**`ws/<name>`** has **that folder as its repo root**. Two directions keep them in sync, both subtree
merges (`git merge -Xsubtree=<folder>`), so the histories stay joined and edits on either side meet
in normal three-way merges. The one thing shared is main's root `.delphi/` (the scripts): sync
puts it at the root of every `ws/*` branch, so it is on every branch, main included, and is edited
only on main. Likewise each `workspace-inherit/` folder: sync writes its files onto the `ws/*`
root of every workspace below its folder and never proposes them back. Otherwise nothing is shared
or generated between workspaces: a project's `workspace-defaults/` is copied once at creation, `workspaces:` only checks out other branches to read, and
harness plugins (section 2) carry what workspaces opt into. The one generated workspace file is
`.claude/settings.json`.

```
   ┌───────────────────────────────┐
   │ main                          │
   │ software/…/workspaces/<name>/ │
   └───────────────────────────────┘
        │                  ▲
        │ refresh          │ merge PR
        │ (CI)             │ (after check.sh)
        ▼                  │
   ┌──────────────────┐  ┌──────────────────┐
   │ ws/<name>        │  │ propose/<name>   │
   │ root = workspace │─►│ PR to main       │
   └──────────────────┘  └──────────────────┘
        │         ▲    propose (CI)
        │ branch  │ merge PR
        ▼         │
   ┌──────────────────┐
   │ your branch      │
   │ edit · commit    │
   └──────────────────┘

   refresh: main → ws/<name>        (folder becomes root)
   propose: ws/<name> → main PR     (root goes back under folder)
   CI runs both on every push to main or ws/**
```

## 2. Repository (main)

```
software/<org>/…/<project>/           README.md  AUTHORING.md  workspace-defaults/   (optional, main only)
software/[<org>/…/]workspace-inherit/  files every workspace below gets on its ws/* root (optional, main only)
software/<org>/…/plugins/<harness>/<set>/   a plugin set for the workspaces under that folder (optional, main only)
software/<org>/…/plugins/scope        the folder's short name in plugin names (optional; default: its name)
.claude-plugin/marketplace.json       every Claude Code plugin set under software/ (generated)
software/<org>/…/workspaces/<name>/   workspace.yml  CLAUDE.md  .claude/…  docs/…
                                      .github/workflows/delphi.yml  .gitattributes
.delphi/                              {setup,new-worktree,switch,park,plugins,version}.sh  manifest.yml  versions
                                      migrations/  .gitattributes  .gitignore: on every ws/* root
ci/sync.sh  ci/check.sh               CI scripts
ci/plugins.sh                         writes the marketplace and each workspace's .claude/settings.json
tools/new-workspace.sh                new workspace as a PR
templates/workspace/                  what new-workspace copies
.github/workflows/delphi.yml          CI
tests/e2e.sh                          sandbox test of all of the above
```

Org folders under `software/` are plain directories. `workspace.yml` is tiny YAML: `name:` (the
workspace's name, so a checkout of `ws/<name>` knows which workspace it is), `harness: <adapter>`, an
optional `repos:` map of `<name>: <git-url>`, and an optional `references-git:` map of
`<name>: <git-url> [<ref>]` (names unique across both maps), and an optional `workspaces:` list of
`- ws/<name>` (a workspace on main) or `- main` (no duplicates, not itself). Names are lowercase
letters, digits, `-` and `/`. Workspaces in different places may end in the same leaf, but no name
may be a folder of another's (git can't hold both `ws/a` and `ws/a/b`). Workspaces never nest; no symlinks under
`software/`. The root `.delphi/` holds the scripts and the version files (section 5b), and no
workspace folder (nor the template) has a `.delphi/` of its own. Each manifest file outside
`.delphi/` (the workflow) is the same at main's root, in the template, and in every workspace. `ci/check.sh` enforces all of this and lists every problem.
`.gitattributes` (`eol=lf`, in `.delphi/` and each workspace) keeps the scripts runnable in Git Bash
clones.
`.github/CODEOWNERS` assigns reviewers per org folder.

The folder holding a `workspaces/` directory is a project folder. It may hold shared context
(`README.md`), a guide to its workspaces (`AUTHORING.md`), and `workspace-defaults/`: files a new
workspace directly in its `workspaces/` starts with, copied once and then its own. These live only on
`main`; workspaces read them by listing `main` under `workspaces:`. A `workspace-defaults/workspace.yml`
is checked as a manifest (without `name:`) but is not a workspace.

Any folder from `software/` down to a project folder may hold `workspace-inherit/`: files laid out as
in a workspace root (`.claude/skills/<skill>/…`) that every workspace below it gets, at any depth.
They are never copied into the workspace folder on main; refresh writes them onto `ws/<name>` and
propose drops them, so they stay one copy, edited on main, and a workspace's own edit to one is
undone on refresh. A workspace that wants its own copy lists the path (or a folder above it) under
`opt-out:` in its `workspace.yml`; refresh then leaves that path alone and propose carries it like
any workspace file. `ci/check.sh` fails on a path inherited from two folders, a workspace file at an
inherited path it hasn't opted out of, an `opt-out:` that matches nothing, and a workspace's own
files in `workspace-inherit/` (`CLAUDE.md`, `workspace.yml`, `.delphi/`, `.claude/settings.json`,
the workflow). The general skills (`new-worktree`, `switch-workspace`,
`setup-workspace`, `journal`) live in `software/workspace-inherit/`, and the skills a folder's
workspaces share live in its own: `application-software/` (`commit`, `open-pr`, `update-pr`,
`address-pr-comments`, `create-ticket`), `argos/` (`implement`, `run-local`, `verify-graph`,
`verify-telemetry`, `pr-conventions`, `ticket-conventions`) and `nero/` (`pr-conventions`,
`ticket-conventions`). Shared skills go there rather than in a plugin: they're plain files on the
workspace branch, with nothing to install.

A plugin set is for what `workspace-inherit/` can't do: context only some workspaces opt into, or
harness features beyond files (hooks, MCP servers). It lives in `plugins/<harness>/<set>/` of a
folder (`plugins/claude/` for Claude Code; a sister folder per other harness), one copy for the
workspaces below. The one so far is `delphi`, `software/`'s `default` set (scope `delphi`): a mod
(section 5) whose `/ws` pane switches workspaces. Every workspace gets the
`default` set of each folder above it, which `ci/plugins.sh` lists first under `plugins:` in its
`workspace.yml` (`- argos   # default, from software/application-software/argos/`; a removed line
comes back); other sets are listed there by hand (`- <scope>.<set>`). `ci/plugins.sh` generates the
rest, and `ci/check.sh` fails if the list or either file is out of date:

- `.claude-plugin/marketplace.json` at main's root: marketplace `delphi`, one plugin per set, named
  `<scope>` for a folder's `default` set and `<scope>.<set>` for the others (`argos`,
  `argos.testing`), so names stay short in Claude Code's `/` menu. A folder's scope is its own name,
  or the one line in its `plugins/scope` (`application-software` has `app`). Scopes are lowercase
  letters, digits and `-`, unique across the tree, and each `plugin.json` uses its name. (Claude
  Code refuses `/` in plugin names; `.` works, though Claude.ai's marketplace sync wants kebab-case.)
- Each `harness: claude-code` workspace's `.claude/settings.json`: the shared settings in
  `ci/plugins.sh`, plus the `delphi` marketplace (with `autoUpdate`) and the sets under `plugins:`
  in `enabledPlugins`. Never edit it by hand: personal settings go in `.claude/settings.local.json`
  (git-ignored by Claude Code), shared ones in `workspace.yml` or the generator. Sync regenerates it
  on every `ws/*` branch (section 3); a PR to `main` that changes a set or a `workspace.yml` runs
  `ci/plugins.sh` itself.
- Enabled isn't installed: someone's Claude Code may never have installed a set, and then its skills
  are silently missing. `setup.sh` warns, through `.delphi/plugins.sh`, about enabled sets not
  installed for this workspace (`claude plugin list --json`: user scope, or project or local scope
  for this root); install with `claude plugin install <plugin> --scope local`, which leaves the
  generated file alone (`delphi` at `--scope user` also has `/ws` on `main` and in every clone).

Claude Code installs a plugin from `main` by copying only its folder, so it can't use files outside
it; at run time its skills read the workspace as usual. With no `version`, each commit to `main`
that touches a set is an update.

## 3. Sync (`ci/sync.sh [refresh|propose] [<name>]`; no direction = both)

For every workspace on `origin/main` (or just `<name>`):

1. **Refresh** (main → `ws/<name>`). If `ws/<name>` is missing and `ws/<leaf>` (its name before
   workspaces were named by path) exists, start from that, so its history and unproposed edits
   carry over, and refresh as below ("created from ws/<leaf>, its old name"; the old branch is kept,
   with a notice). Otherwise, if `ws/<name>` is missing, create it as one commit
   (`git commit-tree <main>:<folder> -p <main>`, "delphi: create ws/<name> from <folder>"): root =
   folder plus main's `.delphi/`, parent = main, so no unrelated histories. Otherwise merge
   `origin/main` into `ws/<name>` with `--no-ff -Xsubtree=<folder>`, then, if its `.delphi/` differs
   from main's, commit main's over it ("delphi: sync .delphi/ from main", built in a temporary
   index). Then write over it the files it inherits from main (every `workspace-inherit/` from
   `software/` down to its project folder, less its `opt-out:` paths) and remove those it
   inherited from the main it last merged (the merge base) but no longer does ("delphi: sync
   inherited files from main"; a new branch gets them in its one commit), and push if the tree changed. (`--no-ff` matters: once ws commits are in main, a
   fast-forward would put main's whole tree on the ws branch.) A `.delphi/` edit made on `ws/<name>`
   is undone here. Then, for a `claude-code` workspace, list main's default sets above it under the
   branch's `workspace.yml` `plugins:` and regenerate `.claude/settings.json` from that
   (`ci/plugins.sh yml`, `settings`), and commit them if they changed ("delphi: generate plugins:
   defaults and .claude/settings.json"), so a new default set or one added under `plugins:` is
   enabled and a hand edit is undone. A set that main doesn't have is reported and that
   workspace is skipped.
2. **Propose** (`ws/<name>` → PR to main). Build `propose/<name>` = `origin/main` +
   `git merge --no-ff -Xsubtree=<folder> ws/<name>`, with `<folder>/.delphi/` dropped from the result
   (it is main's, never a workspace's) and its inherited paths put back to main's. Stop if its tree equals main's or the current
   `propose/<name>`'s (nothing new). Otherwise run `ci/check.sh` on it, force-push it, and create or
   update the PR `ws/<name> → main` with `gh` (body: changed files, ws commit subjects and authors).

A conflict or failed check is reported (conflicts with their files); that workspace is skipped, the
others continue, and the script exits 1. A `ws/*` branch without a folder on main gets a notice and
is never deleted. Merges happen in a temporary worktree, so the caller's checkout is untouched.

## 4. Working on a workspace

1. Clone or check out `ws/<name>` (it is the workspace root); run `.delphi/setup.sh` once.
2. Branch, commit, push, open a PR into `ws/<name>`. Update with `git merge origin/ws/<name>`.
3. After it merges, CI proposes it; merge that PR with a merge commit or squash, never rebase
   (rebasing replays folder-rooted commits onto main). CI then refreshes `ws/<name>`.
4. On a sync conflict: on a branch cut from `ws/<name>`, `git merge -Xsubtree=<folder>
   origin/main`, resolve, and PR it into `ws/<name>`.

Nobody pushes to `ws/*` or `main` directly (branch protection; CI's token is the exception).

## 5. `.delphi/setup.sh` (on every branch; does nothing on main, which has no `workspace.yml`)

First runs the workspace's pending migrations (section 5b). Then reads `repos:` from `workspace.yml` and, for each not yet present, fetches it into a bare store at
`repos/<name>`, then checks out its default branch as the first worktree,
`worktrees/<name>/<default-branch>/` (re-created if missing). Adds `/repos/` and `/worktrees/` to
the clone's `.git/info/exclude` once. For each repo under `references-git:` (read-only dependency
sources), it fetches `<ref>` (default: origin's `HEAD`) with `--depth 1` into `references/<name>/`,
checks it out detached, disables pushes, and does this again on every run, so the copy tracks its pin;
a failed fetch is reported and the old copy kept. Adds `/references/` to the exclude too; references get
no store and no worktrees (`new-worktree.sh` refuses them). Each entry under `workspaces:` (`- ws/<name>`
or `- main`; the workspace itself is skipped) gets the same kind of copy of that branch of the clone's
own origin, at `linked/<branch>/`, also refreshed every run; `/linked/` is excluded too.
Links are separate clones, not worktrees of the Delphi clone, so two workspaces can both link `main`
and each copy parks with its workspace. Writes the clone's `post-checkout` hook, a 3-line script that
runs `.delphi/park.sh` from the worktree that checked out (replacing an older link to or copy of a
`park.sh`), unless another hook is there (it says so and leaves it). `.delphi/` is on every branch, so
the hook always runs the `park.sh` just checked out, never a stale copy, and each worktree of the clone
its own: the worktrees share one hook, so a link would run one checkout's `park.sh` for all of them. Nothing else: code is edited only in worktrees. Must run on macOS `/bin/bash` 3.2
and Git Bash: no bash-4 features, POSIX awk only.

`.delphi/park.sh` (the hook) lets one clone switch freely between workspaces and `main`. When a
branch checkout changes the `name:` in `workspace.yml` (none on `main`), it moves the old
workspace's `repos/`, `worktrees/`, `references/` and `linked/` to `.delphi/parked/<name>/` and
moves the new one's back. A name from before workspaces were named by path (`argos-dev`) is the same
workspace as the path ending in it, so moving a clone onto its renamed branch moves nothing.
`.delphi/.gitignore` ignores `parked/`; since `.delphi/` is on every branch, so is that rule. Parked
work is ignored, not hidden: `git clean -X` or `git stash --all` at the root would take it. A move is a rename, so it is instant and every
absolute path (worktree links, build caches) is the same again whenever its workspace is checked
out; nothing is repaired or rebuilt. Branches of the same workspace move nothing. It never
overwrites: a folder in the way is reported and the other copy stays parked.

`.delphi/new-worktree.sh <repo> <branch> [<base>]` creates or reuses `worktrees/<repo>/<branch>`
from that store: checks out an existing branch, else starts one from `<base>` (default `origin/HEAD`). Same shell rules.
The inherited `new-worktree` skill makes worktrees the default way to start a branch.

`.delphi/paths.sh` is the layout in one place: sourced, it sets and exports `DELPHI_ROOT` (from the
file's own place) and `DELPHI_REPOS`, `DELPHI_WORKTREES`, `DELPHI_REFERENCES`, `DELPHI_LINKED`; run,
it prints them as an export line. Each harness's generated settings put that line into every shell
at session start: for Claude Code, a SessionStart hook in `.claude/settings.json` (from
`ci/plugins.sh`) appends it to `$CLAUDE_ENV_FILE`, which reaches the model's commands, subagents' and
skill scripts'. In a terminal, `. .delphi/paths.sh` from the root. `new-worktree.sh` sources it from
its own folder; every skill script, plugin or workspace, sources `$DELPHI_ROOT/.delphi/paths.sh` and
takes only names (repo, branch), never a searched-for path, so the model types only the names.
Skills themselves stay harness-neutral (SKILL.md is the shared Agent Skills format): they call
scripts by their path in the skill's folder (`bash scripts/<script>.sh …`) and name no harness
variable, so another harness needs only its own settings to set `DELPHI_ROOT`.

`.delphi/switch.sh <workspace>|main` moves the clone to `ws/<workspace>` (or `main`): it refuses while
tracked files have changes, fetches the branch, switches (the hook parks and restores), fast-forwards
to origin, and runs the new workspace's `setup.sh`. `switch.sh --list` prints `main` and the workspaces, `*` before this clone's. The `delphi` mod
(`software/plugins/claude/default/`) puts that in a pane to keep open: `/ws` shows them as cards grouped by project, this clone's
marked current, with a warning when tracked files have changed; pressing a card selects it, and
**Switch workspace** runs `switch.sh` (`/ws <name>` skips the pane); since a session keeps the `CLAUDE.md` and skills it loaded, it then asks for a restart. All
the git work stays in `switch.sh`, which `tests/e2e.sh` covers; the mod's own tests
(`tests/ws.test.ts`, `claude plugin test`) stub its processes, and `tests/e2e.sh` runs them when a
real `claude` is installed. The inherited `switch-workspace` skill makes it
the way to work in another workspace; its `setup-workspace` skill covers `workspace.yml` (repos,
references, links) and re-running setup.

The inherited `journal` skill parks rough notes in `.journal/` at the workspace root (its
`capture.sh` adds `/.journal/` to `.git/info/exclude`) and exports them through other skills.

## 5b. Versions and migrations

Delphi's own files, the ones identical on main and every `ws/*` branch, are listed in
`.delphi/manifest.yml` (`files:`, itself included), under a `version:` that is MAJOR.MINOR.PATCH:
PATCH for fixes and wording, MINOR for something new that existing clones need nothing for, MAJOR
(MINOR while 0.x) when clones need cleanup. `.delphi/version.sh` prints `<version> <hash>`, the hash
covering the listed files' paths and contents as git stores them (line endings don't change it).
`.delphi/versions` has one line per version, `<version> <hash> <what changed>`, oldest first, and is
the one file in `.delphi/` outside the hash. `ci/check.sh` requires: the manifest lists itself and
every file in `.delphi/` but `versions`; the last line of `versions` is the current
`<version> <hash>` (so any change to a listed file, the manifest included, needs a new version);
versions rise; and, against main in CI, `versions` only gains lines and released migrations stay as
they are.

A version whose clones need cleanup ships `.delphi/migrations/<version>-<slug>.sh` and bumps MAJOR
(MINOR while 0.x; `check.sh` enforces it). `setup.sh` runs, oldest first, each migration above the
workspace's recorded version, `git config delphi.<name>.version` in the clone (`0.0.0` if unset),
from the workspace root, recording each as it succeeds and then the current version; it stops at
one that fails, so the next run retries it. Records are per workspace because the state migrations
fix sits in each workspace's own checkouts, parked ones included: a parked workspace migrates when
it's switched back to (`switch.sh` runs setup). Migrations must be safe to re-run, do nothing on a
fresh clone, and delete only what nothing is lost from, stopping with what to do otherwise. `setup.sh`
also warns when `.delphi/` isn't exactly the version it says (edited in the clone).

## 6. New workspaces (`tools/new-workspace.sh <org-path> <name>`)

Validates the name (format, not on main, no leftover `ws/<name>` or `ws/<leaf>`), copies `templates/workspace/`
and then `software/<org-path>/workspace-defaults/` if present (its `CLAUDE.md` appended to the template's)
into `software/<org-path>/workspaces/<name>/` (filling `{{name}}`/`{{folder}}` in `CLAUDE.md`) in a
temporary worktree, sets `name: software/<org-path>/<leaf>`, generates its `.claude/settings.json`, runs `ci/check.sh`, pushes branch
`new-workspace/<org-path>/<leaf>`, and opens a PR. Sync creates `ws/<name>` once it merges.

## 7. CI (`.github/workflows/delphi.yml`)

- `check`: PRs to main, read-only token, full history, runs `ci/check.sh . origin/main`.
- `sync`: pushes to main or `ws/**`; checks out main (scripts never come from a ws branch) with full
  history, sets the bot identity, runs `ci/sync.sh` (contents + pull-requests write; one run at a
  time).

GitHub runs a push's workflow from the pushed commit, so the same file sits at the root of every
`ws/<name>` (via the workspace folder). Pushes and PRs made with `GITHUB_TOKEN` trigger no
workflows: no loops, and CI-opened PRs don't run `check`, which is why sync runs `ci/check.sh`
itself (so `check` can't be a required status check).

## 8. Testing

`tests/e2e.sh` builds a sandbox (temp dir, bare origin, stub `gh` logging to `gh.log`, two
workspaces in different org folders) and drives the scripts as CI and people would. Never test
against GitHub.
