Run from the checked-out workspace root:

```
bash .delphi/switch.sh <name>        # ws/<name>: its dotted name, e.g. s.app.argos.argos-dev
bash .delphi/switch.sh main          # Delphi's main: project folders, templates, CI
```

- List workspaces and their project folders: `bash .delphi/switch.sh --list`.
- Switching refuses tracked changes. Commit them on a branch and open its PR first. The switch fetches, fast-forwards, and runs the destination workspace's setup.
- The post-checkout hook parks this workspace's ignored working folders under `.delphi/parked/<name>/` and restores the destination workspace's folders at their original paths. Never run `git clean -X` or `git stash --all` at the workspace root: they take parked work too.
- Before switching, stop processes that run from the workspace's working folders, since their paths move.
- Start a fresh Codex session after switching. The new workspace's instructions and skills must load before starting its work.
- To change the destination workspace, create a branch, commit, push, and open a PR into its `ws/<name>` branch (or `main`).
- To read another workspace without switching, list it under `workspaces:` instead (`setup-workspace` skill).
