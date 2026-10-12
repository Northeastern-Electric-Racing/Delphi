# Plugins

The workspace's generated `.claude/settings.json` enables plugin sets from Delphi's marketplace (the `plugins:` in `workspace.yml`): that's where skills like `commit` and `open-pr` come from. Enabled isn't installed: until a set is installed on this machine, its skills are missing. Each session's start and `.delphi/setup.sh` print a warning naming the ones that aren't.

From the workspace root:

```
bash .delphi/plugins.sh             # the enabled sets not installed here; nothing when all are
bash .delphi/plugins.sh --install   # install them, for this workspace only
```

- Tell the user which are missing, and install with their go-ahead.
- `--install` adds Delphi's marketplace if this machine doesn't know it yet, then installs each set at local scope: it's recorded in the git-ignored `.claude/settings.local.json`, and the generated `settings.json` stays untouched.
- The skills load in the next session, not this one: tell the user to restart in the same folder (or reload plugins).
- If it can't run the harness's CLI, the user installs each set with the harness's own plugin installer, for this project only.
- Never enable a set by editing `.claude/settings.json`: it's generated. To add one, list it under `plugins:` in `workspace.yml` and open a PR into this workspace's branch.
