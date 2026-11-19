---
name: demo
description: Rerun, fix or start a saved web UI demo (a Playwright script per page, kept in the code repo) to get stills with a walkthrough, or an MP4 with chapters, for a PR. Use when a PR or ticket should show a UI change, a demo step breaks, or a page needs its first demo.
---

Run every skill helper through the workspace bootstrap, including in fresh shells and sub-agents:

```sh
bash "<absolute-workspace-root>/.delphi/exec.sh" bash "<absolute-installed-skill-folder>/scripts/<script>.sh" <arguments...>
```

Replace the placeholders with the known workspace root, this skill's installed native folder, the script name, and its arguments. Obtain the workspace's absolute path once with `bash .delphi/paths.sh` from the checked-out workspace root. The wrapper sets `DELPHI_ROOT` for every invocation and preserves the caller's working directory; do not assume shell exports persist.


It needs an app that runs in a browser (a web app, or a browser build of one). A demo is `<name>.demo.js` in the code repo, next to the app it shows, so a UI change updates its demo in the same diff. It is a list of named steps, and its first line, `// covers: <path fragment>…`, names the source it shows. `scripts/template.demo.js` documents the format and the helpers a step gets.

A demo lives on the branch with the UI change it shows. To demo the default branch as it is, make a branch off it (the project's new-worktree skill, named by its convention for work without a ticket) and commit the demo there.

Start the branch's app in local development first, then load the data its demos show: a seed script from one of the project's skills where it has one, else whatever the user names. Then use the app's URL:

1. **Which demos:** `bash "<absolute-workspace-root>/.delphi/exec.sh" bash "<absolute-installed-skill-folder>/scripts/affected.sh" <repo> <branch> [<base>]` lists the demos whose covered source, or whose own file, the branch changed since `<base>` (default `origin/HEAD`).
2. **Stills, the quick check:** `bash "<absolute-workspace-root>/.delphi/exec.sh" bash "<absolute-installed-skill-folder>/scripts/run.sh" <repo> <branch> <url> [<demo>…]` (every demo if none is named) writes a 2× PNG per step and `walkthrough.md`, each step's caption over its still, to `pictures/<branch>/demo/<demo>/`. Dwells are skipped; waits for data are kept. Open the stills and judge them. Stills and video each replace only their own files, so both can sit in the folder for the PR.
3. **Video:** add `--video` for `<demo>.mp4` at real pacing, with a cursor and no burned-in captions, and `chapters.md`, a timestamp per step for the PR body. GitHub attachments must be under 10 MB: the run says when it's over, and `DEMO_CRF=28` (default 20) makes it smaller.

A failed step stops its demo with the step's name and `failed-<step>.png`: look at it, fix that step in the demo file, and rerun from it with `--from "<step>"` (earlier steps run unpaced and unrecorded; their stills from the last run stay in the walkthrough). Console errors are listed after each demo; report them.

**New demo:** `bash "<absolute-workspace-root>/.delphi/exec.sh" bash "<absolute-installed-skill-folder>/scripts/new.sh" <repo> <branch> <name> <route> [<app-folder>]` copies the template next to the repo's other demos and prints its path; the repo's first demo needs `<app-folder>`, the folder of the app it shows, and goes in its `demos/`. Fill in its steps by hand with `npx playwright codegen <url><route>` (no model needed), or from the page's accessibility snapshot. Group the actions into named steps with captions, add dwells where a viewer should look, and check it with a stills run. Set `covers:` (it starts as `TODO`) to fragments only this page's source has, its page and component folders, not a word other pages share. Find data by what the page shows, never by an id that changes with each seed. Helpers only one app needs (a tree item, say) go in a `lib.js` next to its demos.

Commit demo changes on the branch with the UI change. Attach the MP4 or the stills to the PR, with `chapters.md` or the walkthrough's captions in its body.
