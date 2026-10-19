# Delphi workspace

You're in Delphi workspace `s.firmware.calypso.calypso-dev` (branch `ws/s.firmware.calypso.calypso-dev`); code repos are cloned at `repos/<repo>/`, and separately checked out as worktrees under `worktrees/<repo>/` (`.delphi/setup.sh` makes the default branch's). Work in worktrees: make each new branch one under `worktrees/<repo>/<branch>` (`new-worktree` skill) unless the user says not to. Read-only dependency sources from `references-git:` are checked out under `references/<name>/` at the version the workspace pins: read them to learn how a dependency behaves (prefer them over web docs), and never edit, branch, or push them. Delphi workspaces (or `main`) under `workspaces:` in `workspace.yml` (`- <name>`, a workspace's dotted name like `s.app.argos.argos-dev`, or `- main`) are clones at `workspaces/<name>/`, each on its branch, for reading their context (don't edit them from here; setup switches each back to its branch and pulls it); change what's checked out with the `setup-workspace` skill. To work in another workspace, switch this clone to it (`switch-workspace` skill). Park rough notes with the `journal` skill. Work here unless the task clearly belongs to another project.

# Calypso

CAN ↔ telemetry bridge for NER's Odyssey car (Rust). Decodes CAN into protobuf `ServerData` published per topic to Siren (MQTT, or Zenoh with `-z`); encodes `CommandData` on `Calypso/Bidir/Command/#` back to CAN. The CAN spec is JSON in the `Odyssey-Definitions` submodule. `calypso-sim` publishes simulated `ServerData`; its `README.md` is the source of truth for its flags.

- `worktrees/calypso/develop/` mirrors `develop`: run things there, never edit or commit. Make branches with `new-worktree` from `origin/develop`, then `git -C worktrees/calypso/<branch> submodule update --init --recursive`.
- Branches `{issue}-{kebab-title}`; commits `#{issue} - {description}`; draft PRs into `develop`.
- Check with `ci-local` (bare `cargo test` skips workspace members; on macOS the main crate doesn't compile).
