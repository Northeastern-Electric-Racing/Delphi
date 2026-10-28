---
name: commit
description: Stage and commit using the project's commit message convention
---

Run every skill helper through the workspace bootstrap, including in fresh shells and sub-agents:

```sh
bash "<absolute-workspace-root>/.delphi/exec.sh" bash "<absolute-installed-skill-folder>/scripts/<script>.sh" <arguments...>
```

Replace the placeholders with the known workspace root, this skill's installed native folder, the script name, and its arguments. Obtain the workspace's absolute path once with `bash .delphi/paths.sh` from the checked-out workspace root. The wrapper sets `DELPHI_ROOT` for every invocation and preserves the caller's working directory; do not assume shell exports persist.


In the worktree you're working on, from the workspace root (`git -C worktrees/<repo>/<branch> …`), stage the relevant changes (not unrelated or generated files) and commit using the commit message format in AGENTS.md. Keep the description imperative and 2–8 words.
