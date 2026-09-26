//! End-to-end tests of the CLI in a sandbox (see tests/common).

mod common;

use common::{Sb, A, LAYOUT, S};
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

#[test]
fn usage_and_argument_errors() {
    let sb = Sb::new("args");
    let r = sb.d(&sb.dir, &[]);
    assert_eq!(r.code, 0);
    assert!(r.stdout.starts_with("usage: delphi <command> [args]"));
    for (args, err) in [
        (&["bogus"][..], "delphi: unknown command 'bogus' (see: delphi help)\n"),
        (&["ws", "frob"], "delphi: usage: delphi workspace new|open|refresh|diff|propose|status (see: delphi help)\n"),
        (&["ws", "new"], "delphi: usage: delphi workspace new <layout> [--as <ws>] [--ref <branch>]\n"),
        (&["ws", "new", "a", "b"], "delphi: too many arguments (see: delphi help)\n"),
        (&["ws", "status", "--bogus"], "delphi: unknown flag for this command: --bogus (allowed: --offline)\n"),
        (
            &["ws", "diff", "--dry-run"],
            "delphi: unknown flag for this command: --dry-run (allowed: --upstream --offline)\n",
        ),
        (&["ws", "new", "argos-dev", "--as"], "delphi: --as needs a value\n"),
        (&["ws", "new", "Bad_Name!"], "delphi: invalid workspace name: 'Bad_Name!'\n"),
        (&["ws", "new", "nope"], "delphi: layout not found: nope\n"),
        (&["layout"], "delphi: usage: delphi layout new <scope> <layout> --from <manifest> | delphi layout list\n"),
        (&["layout", "new", "software", "Bad"], "delphi: invalid layout name: 'Bad' (use a-z, 0-9, -)\n"),
        (&["block", "mv", "a"], "delphi: usage: delphi block mv <old> <new>\n"),
        (&["block", "mv", "../x", "b", "--yes"], "delphi: unsafe path: '../x'\n"),
        (&["check", "extra"], "delphi: usage: delphi check\n"),
    ] {
        let r = sb.d(&sb.dir, args);
        assert_eq!((r.code, r.stderr.as_str()), (1, err), "{args:?}");
    }
    let r = sb.d(&sb.dir, &["ws", "refresh", "missing"]);
    assert_eq!(r.code, 1);
    assert!(r.stderr.starts_with("delphi: not a Delphi workspace: "), "{}", r.stderr);
    sb.assert_cleaned_up();
}

#[test]
fn workspace_new_places_files_writes_lock_adds_copies_clones_repos() {
    let sb = Sb::new("new");
    let r = sb.d(&sb.dir, &["workspace", "new", "argos-dev"]);
    let ws = sb.ws("argos-dev");
    assert_eq!(r.code, 0, "{r:#?}");
    assert_eq!(
        r.stderr,
        format!(
            "  copied .claude/settings.json\ncloning argos…\nworkspace ready: {}\nnext: delphi workspace open argos-dev\n",
            ws.display()
        )
    );

    // files at harness paths: assembled instructions, skills, docs, context/, layout files
    assert_eq!(
        sb.read(&ws.join("CLAUDE.md")),
        "# Software conventions\n\n- Use conventional commits.\n- Open PRs against develop.\n\n# Argos\n\nArgos is the telemetry dashboard.\n"
    );
    assert!(sb.read(&ws.join(".claude/skills/run-tests/SKILL.md")).contains("name: run-tests"));
    assert_eq!(
        fs::metadata(ws.join(".claude/skills/run-tests/scripts/run.sh")).unwrap().permissions().mode() & 0o111,
        0o111
    );
    assert_eq!(sb.read(&ws.join("docs/guide.md")), "# Guide\n\nLine one.\nLine two.\n");
    assert_eq!(fs::read(ws.join("docs/logo.png")).unwrap(), b"\x89PNG\r\n\0\x01\x02");
    assert_eq!(sb.read(&ws.join(format!("context/{A}/blocks/style.md"))), "# Style\n\nTabs.\n");
    assert_eq!(sb.read(&ws.join(".claude/skills/open-pr/pr-body.md")), "**PR body:** fill the template.\n");
    assert_eq!(sb.read(&ws.join(".claude/skills/update-pr/pr-body.md")), "**PR body:** fill the template.\n");
    assert!(sb.read(&ws.join(".claude/skills/argos-notes/SKILL.md")).contains("Argos notes."));
    assert_eq!(
        sb.read(&ws.join(".delphi/manifest.yml")),
        sb.read(&sb.root().join(format!("context/{LAYOUT}/manifest.yml")))
    );

    let lock = sb.read(&ws.join(".delphi/lock.tsv"));
    assert_eq!(
        lock,
        format!(
            "# dest\tsource\tkind
CLAUDE.md\tsoftware/harness/instructions/base.md\tassembled
CLAUDE.md\t{A}/harness/instructions/argos.md\tassembled
.claude/skills/run-tests/SKILL.md\t{A}/harness/skills/run-tests/SKILL.md\tsync
.claude/skills/run-tests/scripts/run.sh\t{A}/harness/skills/run-tests/scripts/run.sh\tsync
docs/guide.md\t{A}/docs/guide.md\tsync
docs/logo.png\t{A}/docs/logo.png\tsync
context/{A}/blocks/style.md\t{A}/blocks/style.md\tsync
.claude/skills/open-pr/pr-body.md\t{A}/blocks/pr-body.md\tsync
.claude/skills/update-pr/pr-body.md\t{A}/blocks/pr-body.md\tsync
.claude/settings.json\tsoftware/harness/settings/settings.json\tcopy
.claude/skills/argos-notes/SKILL.md\t{LAYOUT}/files/.claude/skills/argos-notes/SKILL.md\tlayout
.delphi/manifest.yml\t{LAYOUT}/manifest.yml\tlayout
"
        )
    );

    // copies: committed on working (not in the compile), recorded in .git/delphi/copied
    let c = sb.git(&sb.root(), &["rev-parse", "origin/main"]);
    assert_eq!(sb.read(&ws.join(".claude/settings.json")), "{\n  \"model\": \"sonnet\"\n}\n");
    assert_eq!(
        sb.read(&ws.join(".git/delphi/copied")),
        format!(".claude/settings.json\tsoftware/harness/settings/settings.json\t{c}\n")
    );
    assert_eq!(sb.git(&ws, &["log", "-1", "--format=%s"]), "delphi: copy .claude/settings.json");
    assert_eq!(sb.git(&ws, &["ls-tree", "-r", "--name-only", "generated", ".claude/settings.json"]), "");
    let tree = sb.git(&ws, &["ls-tree", "-r", "generated", ".claude/skills/run-tests/scripts/run.sh"]);
    assert!(tree.starts_with("100755 "), "{tree}");

    // refs, meta, hook, exclude, repos
    assert_eq!(sb.git(&ws, &["rev-parse", "--abbrev-ref", "HEAD"]), "working");
    assert_eq!(sb.git(&ws, &["rev-parse", "generated"]), sb.git(&ws, &["rev-parse", "generated-merged^{commit}"]));
    let msg = sb.git(&ws, &["log", "-1", "--format=%B", "generated"]);
    assert_eq!(msg, format!("delphi: compile argos-dev@{}\n\nDelphi-Compile: {c}", &c[..7]));
    let meta = sb.read(&ws.join(".git/delphi/meta"));
    assert!(
        meta.contains(&format!("layout=argos-dev\nlayout_path={LAYOUT}\nref=main\nharness=claude-code\n")),
        "{meta}"
    );
    assert!(meta.ends_with(&format!("compile_commit={c}\n")), "{meta}");
    assert!(sb.read(&ws.join(".git/info/exclude")).ends_with("repos/\nworktrees/\n.claude/settings.local.json\n"));
    assert_eq!(fs::metadata(ws.join(".git/hooks/commit-msg")).unwrap().permissions().mode() & 0o111, 0o111);
    assert!(ws.join("repos/argos/README.md").is_file());

    // a fresh workspace has nothing to propose; status says clean
    let r = sb.ok(&ws, &["ws", "diff"]);
    assert_eq!((r.stdout.as_str(), r.stderr.as_str()), ("", "argos-dev: no changes since the last refresh\n"));
    let r = sb.ok(&sb.dir, &["ws", "status"]);
    assert!(
        r.stdout.contains(
            "argos-dev              argos-dev        main     no    clean      -     no     delphi ws open argos-dev\n"
        ),
        "{}",
        r.stdout
    );

    // same Delphi commit + same layout = identical compile
    let two = sb.new_ws("two");
    assert_eq!(sb.git(&ws, &["rev-parse", "generated^{tree}"]), sb.git(&two, &["rev-parse", "generated^{tree}"]));

    let again = sb.d(&sb.dir, &["workspace", "new", "argos-dev"]);
    assert_eq!((again.code, again.stderr), (1, format!("delphi: workspace already exists: {}\n", ws.display())));
    sb.assert_cleaned_up();
}

#[test]
fn refresh_merges_lists_authors_conflicts_and_copies() {
    let sb = Sb::new("refresh");
    let ws = sb.new_ws("w");
    let r = sb.ok(&sb.dir, &["ws", "refresh", "w"]);
    assert_eq!(r.stderr, "w: up to date with origin/main\n");

    // an upstream change to a synced file merges and is listed with its author and subject
    sb.upstream(
        "Speed up tests",
        &format!("printf 'Run them in parallel.\\n' >> context/{A}/harness/skills/run-tests/SKILL.md"),
    );
    let r = sb.ok(&sb.dir, &["ws", "refresh", "w"]);
    let c = sb.git(&sb.root(), &["rev-parse", "--short=7", "origin/main"]);
    assert_eq!(
        r.stderr,
        format!("w: merged compile of origin/main ({c})\n  updated .claude/skills/run-tests/SKILL.md  (Alice: Speed up tests)\n")
    );
    assert!(sb.read(&ws.join(".claude/skills/run-tests/SKILL.md")).ends_with("Run them in parallel.\n"));

    // a shared source is tagged
    sb.upstream("Reword", &format!("printf '**PR body:** fill it.\\n' > context/{A}/blocks/pr-body.md"));
    let r = sb.ok(&sb.dir, &["ws", "refresh", "w"]);
    assert!(
        r.stderr.contains("  updated .claude/skills/open-pr/pr-body.md  (Alice: Reword)  (shared: nero-dev)\n"),
        "{}",
        r.stderr
    );
    assert!(r.stderr.contains("  updated .claude/skills/update-pr/pr-body.md  (Alice: Reword)  (shared: nero-dev)\n"));

    // conflicting edits: exit 2, then "merge in progress", then resolve and re-run finalizes
    sb.edit(&ws, "sed -i 's/^Line one.$/Line one (mine)./' docs/guide.md");
    sb.upstream("Theirs", &format!("sed -i 's/^Line one.$/Line one (theirs)./' context/{A}/docs/guide.md"));
    let r = sb.d(&sb.dir, &["ws", "refresh", "w"]);
    assert_eq!(r.code, 2, "{r:#?}");
    assert_eq!(
        r.stderr,
        "conflicts in w:\n  docs/guide.md\nresolve them, commit, then re-run: delphi workspace refresh w\n"
    );
    let r = sb.d(&sb.dir, &["ws", "refresh", "w"]);
    assert_eq!(r.code, 1);
    assert!(r.stderr.contains("merge in progress in"), "{}", r.stderr);
    sb.sh(&ws, "git checkout --ours docs/guide.md && git add docs/guide.md && git commit -q --no-edit");
    let r = sb.ok(&sb.dir, &["ws", "refresh", "w"]);
    let c = sb.git(&sb.root(), &["rev-parse", "--short=7", "origin/main"]);
    assert_eq!(
        r.stderr,
        format!("w: merged compile of origin/main ({c})\n  updated docs/guide.md  (Alice: Theirs)\nw: up to date with origin/main\n")
    );
    assert_eq!(sb.git(&ws, &["rev-parse", "generated"]), sb.git(&ws, &["rev-parse", "generated-merged^{commit}"]));

    // a newly listed copy is added; a copy is never overwritten
    sb.upstream("Add a copy", &format!(
        "printf '  - {A}/blocks/style.md -> notes/style.md\\n' >> context/{LAYOUT}/manifest.yml.new\n\
         awk '/^copy:/ {{ print; while ((getline l < \"context/{LAYOUT}/manifest.yml.new\") > 0) print l; next }} {{ print }}' context/{LAYOUT}/manifest.yml > m && mv m context/{LAYOUT}/manifest.yml && rm context/{LAYOUT}/manifest.yml.new\n\
         printf '{{\"model\": \"opus\"}}\\n' > context/software/harness/settings/settings.json"
    ));
    sb.edit(&ws, "printf '{\"model\": \"mine\"}\\n' > .claude/settings.json");
    let r = sb.ok(&sb.dir, &["ws", "refresh", "w"]);
    assert!(
        r.stderr.contains("  updated .delphi/manifest.yml  (Alice: Add a copy)\n  copied notes/style.md\n"),
        "{}",
        r.stderr
    );
    assert_eq!(sb.read(&ws.join("notes/style.md")), "# Style\n\nTabs.\n");
    assert_eq!(sb.read(&ws.join(".claude/settings.json")), "{\"model\": \"mine\"}\n");
    assert_eq!(sb.read(&ws.join(".git/delphi/copied")).lines().count(), 2);
    let r = sb.ok(&sb.dir, &["ws", "refresh", "w"]);
    assert_eq!(r.stderr, "w: up to date with origin/main\n");

    // copies and local files are not proposable: status is clean except for the kept conflict edit
    let r = sb.ok(&ws, &["ws", "diff"]);
    assert_eq!(
        r.stdout,
        format!("  update    docs/guide.md -> {A}/docs/guide.md\n  local     .claude/settings.json  (copy (yours))\n")
    );
    sb.assert_cleaned_up();
}

#[test]
fn diff_upstream_lists_delphi_changes_copies_and_shared_sources() {
    let sb = Sb::new("diff");
    let ws = sb.new_ws("w");
    let r = sb.ok(&ws, &["ws", "diff", "--upstream"]);
    assert_eq!((r.stdout.as_str(), r.stderr.as_str()), ("", "w: up to date with origin/main\n"));

    sb.upstream("Reword body", &format!("printf '**PR body:** fill it.\\n' > context/{A}/blocks/pr-body.md"));
    sb.upstream("New doc", &format!("printf '# FAQ\\n' > context/{A}/docs/faq.md"));
    sb.upstream("Base", "printf -- '- Squash.\\n' >> context/software/harness/instructions/base.md");
    sb.upstream("Opus", "printf '{\"model\": \"opus\"}\\n' > context/software/harness/settings/settings.json");
    sb.upstream("Unrelated", "printf 'x\\n' > context/software/other.md");
    let r = sb.ok(&ws, &["ws", "diff", "--upstream"]);
    assert_eq!(
        r.stdout,
        format!(
            "  sync      .claude/skills/open-pr/pr-body.md <- {A}/blocks/pr-body.md  (Alice: Reword body)  (shared: nero-dev)
  sync      .claude/skills/update-pr/pr-body.md <- {A}/blocks/pr-body.md  (Alice: Reword body)  (shared: nero-dev)
  sync      docs/faq.md <- {A}/docs/faq.md  (Alice: New doc)
  assembled CLAUDE.md <- software/harness/instructions/base.md  (Alice: Base)
  copy      .claude/settings.json <- software/harness/settings/settings.json  (Alice: Opus)  (your copy is not updated)
"
        )
    );
    let r = sb.ok(&sb.dir, &["ws", "status"]);
    assert!(r.stdout.contains(" clean      -     yes    delphi ws refresh w\n"), "{}", r.stdout);

    // after refresh, only the copy is still behind
    sb.ok(&sb.dir, &["ws", "refresh", "w"]);
    let r = sb.ok(&ws, &["ws", "diff", "--upstream"]);
    assert_eq!(r.stdout, "  copy      .claude/settings.json <- software/harness/settings/settings.json  (Alice: Opus)  (your copy is not updated)\n");

    // plain diff tags shared sources too
    sb.edit(&ws, "printf 'more\\n' >> .claude/skills/open-pr/pr-body.md");
    let r = sb.ok(&ws, &["ws", "diff"]);
    assert_eq!(
        r.stdout,
        format!("  update    .claude/skills/open-pr/pr-body.md -> {A}/blocks/pr-body.md  (shared: nero-dev)\n")
    );
    sb.assert_cleaned_up();
}

const EDITS: &str = r#"
printf 'Also lint.\n' >> .claude/skills/run-tests/SKILL.md && chmod +x .claude/skills/run-tests/SKILL.md
printf '\211PNG\r\n\0\3' > docs/logo.png
printf '# New\n' > docs/new.md
sed -i 's#^sync:$#sync:\n  - software/application-software/argos/harness/skills/deploy#' .delphi/manifest.yml
mkdir -p .claude/skills/deploy && printf -- '---\nname: deploy\ndescription: Deploy.\n---\n' > .claude/skills/deploy/SKILL.md
sed -i '/blocks\/style.md$/d' .delphi/manifest.yml && git rm -q context/software/application-software/argos/blocks/style.md
git rm -q docs/guide.md
printf 'My note.\n' >> CLAUDE.md
printf 'stray\n' > notes.txt
printf 'Keep it short.\n' | tee -a .claude/skills/open-pr/pr-body.md >> .claude/skills/update-pr/pr-body.md
printf 'More notes.\n' >> .claude/skills/argos-notes/SKILL.md
"#;

#[test]
fn propose_routes_each_kind_of_change_then_merge_and_refresh_is_clean() {
    let sb = Sb::new("propose");
    let ws = sb.new_ws("w");
    sb.edit(&ws, EDITS);
    let listing = format!(
        "  update    .claude/skills/argos-notes/SKILL.md -> {LAYOUT}/files/.claude/skills/argos-notes/SKILL.md
  new       .claude/skills/deploy/SKILL.md -> {A}/harness/skills/deploy/SKILL.md
  update    .claude/skills/open-pr/pr-body.md -> {A}/blocks/pr-body.md  (shared: nero-dev)
  update    .claude/skills/run-tests/SKILL.md -> {A}/harness/skills/run-tests/SKILL.md
  noop      .claude/skills/update-pr/pr-body.md  (same edit as .claude/skills/open-pr/pr-body.md)
  manifest  .delphi/manifest.yml -> {LAYOUT}/manifest.yml
  noop      context/{A}/blocks/style.md  (deleted; its entry was removed from .delphi/manifest.yml)
  update    docs/logo.png -> {A}/docs/logo.png
  new       docs/new.md -> {A}/docs/new.md
  local     notes.txt  (new file, not in a synced directory)
Unresolved:
  CLAUDE.md: generated; sync a part to edit it
  docs/guide.md: deleted, but still listed in .delphi/manifest.yml (remove its entry to drop it)
"
    );
    let r = sb.ok(&ws, &["ws", "diff"]);
    assert_eq!((r.stdout.as_str(), r.stderr.as_str()), (listing.as_str(), ""));
    let r = sb.ok(&ws, &["ws", "propose", "--dry-run"]);
    assert_eq!((r.stdout.as_str(), r.stderr.as_str()), (listing.as_str(), ""));
    let r = sb.ok(&sb.dir, &["ws", "status"]);
    assert!(r.stdout.contains(" unproposed 0d    no     delphi ws propose w\n"), "{}", r.stdout);

    let r = sb.ok(&sb.dir, &["ws", "propose", "w", "--yes"]);
    assert_eq!(r.stdout, "https://github.invalid/pr/1\n");
    assert!(
        r.stderr.starts_with(&format!(
            "w: up to date with origin/main\n---- delphi: changes from workspace w (argos-dev)\n## Routed changes\n\n\
         - update: `{LAYOUT}/files/.claude/skills/argos-notes/SKILL.md` (from `.claude/skills/argos-notes/SKILL.md`)\n\
         - new: `{A}/harness/skills/deploy/SKILL.md` (from `.claude/skills/deploy/SKILL.md`)\n\
         - update: `{A}/blocks/pr-body.md` (from `.claude/skills/open-pr/pr-body.md`)  (shared: nero-dev)\n"
        )),
        "{}",
        r.stderr
    );
    assert!(
        r.stderr.contains(
            "## Unresolved\n\n#### `CLAUDE.md`: generated; sync a part to edit it\n\n```diff\n@@ -6,3 +6,4 @@"
        ),
        "{}",
        r.stderr
    );
    assert!(r.stderr.contains("| sandbox | sandbox-model | low |\n----\n"), "{}", r.stderr);

    // the branch: each file landed on its source, the manifest replaced, trailers recorded
    let root = sb.root();
    let br = "origin/delphi/propose/tester/w";
    let show = |p: &str| sb.git(&root, &["show", &format!("{br}:context/{p}")]);
    assert!(show(&format!("{A}/harness/skills/run-tests/SKILL.md")).ends_with("Also lint."));
    let mode = sb.git(&root, &["ls-tree", br, &format!("context/{A}/harness/skills/run-tests/SKILL.md")]);
    assert!(mode.starts_with("100755 "), "{mode}");
    assert_eq!(show(&format!("{A}/blocks/pr-body.md")), "**PR body:** fill the template.\nKeep it short.");
    assert_eq!(show(&format!("{A}/docs/new.md")), "# New");
    assert!(show(&format!("{A}/harness/skills/deploy/SKILL.md")).contains("name: deploy"));
    assert!(show(&format!("{LAYOUT}/files/.claude/skills/argos-notes/SKILL.md")).ends_with("More notes."));
    assert_eq!(show(&format!("{LAYOUT}/manifest.yml")), sb.read(&ws.join(".delphi/manifest.yml")).trim_end());
    let logo = sb.git(&root, &["cat-file", "-p", &format!("{br}:context/{A}/docs/logo.png")]);
    assert!(logo.ends_with('\u{3}'), "{logo:?}");
    let files = sb.git(&root, &["diff", "--name-only", "origin/main", br]);
    assert_eq!(files.lines().count(), 7, "{files}");
    assert!(!files.contains("guide.md") && !files.contains("style.md") && !files.contains("notes.txt"));
    let c = sb.git(&root, &["rev-parse", "--short=7", "origin/main"]);
    assert_eq!(
        sb.git(&root, &["log", "--format=%B", &format!("origin/main..{br}")]),
        format!(
            "delphi: changes from workspace w\n\nDelphi-Harness: sandbox\nDelphi-Model: sandbox-model\nDelphi-Effort: low\n\
             Delphi-Layout: {LAYOUT}\nDelphi-Workspace: w\nDelphi-Base: {c}"
        )
    );
    assert!(sb.gh_log().contains("gh pr create --head delphi/propose/tester/w --base main --title delphi: changes from workspace w (argos-dev) --body ## Routed changes"));
    let r = sb.ok(&sb.dir, &["ws", "status"]);
    assert!(r.stdout.contains(" proposed   -     no     delphi ws open w\n"), "{}", r.stdout);

    // proposing again (not merged yet) force-updates the same branch and PR
    let r = sb.ok(&sb.dir, &["ws", "propose", "w", "--yes"]);
    assert!(r.stderr.ends_with("----\nUpdated PR #1\n"), "{}", r.stderr);

    // merge the PR; undo the unresolved edits; refresh: status clean, nothing to propose
    sb.upstream("merge", "git merge -q --no-edit origin/delphi/propose/tester/w");
    sb.edit(&ws, "git checkout generated-merged -- CLAUDE.md docs/guide.md");
    let r = sb.ok(&sb.dir, &["ws", "refresh", "w"]);
    assert!(
        r.stderr.contains("  updated .claude/skills/deploy/SKILL.md  (Sandbox: delphi: changes from workspace w)\n"),
        "{}",
        r.stderr
    );
    assert!(r.stderr.contains("  removed context/"), "{}", r.stderr);
    let r = sb.ok(&sb.dir, &["ws", "status"]);
    assert!(r.stdout.contains(" clean      -     no     delphi ws open w\n"), "{}", r.stdout);
    assert_eq!(sb.ok(&ws, &["ws", "diff"]).stdout, "  local     notes.txt  (new file, not in a synced directory)\n");
    let r = sb.ok(&sb.dir, &["ws", "propose", "w", "--yes"]);
    assert_eq!(
        r.stderr,
        "w: up to date with origin/main\nnothing to propose\ndelphi: warning: PR #1 still contains earlier changes; close it with: gh pr close 1\n"
    );
    sb.assert_cleaned_up();
}

#[test]
fn propose_differing_edits_to_one_source_and_only_unresolved() {
    let sb = Sb::new("differ");
    let ws = sb.new_ws("w");
    sb.edit(&ws, "printf 'a\\n' >> .claude/skills/open-pr/pr-body.md\nprintf 'b\\n' >> .claude/skills/update-pr/pr-body.md\nprintf 'x\\n' >> CLAUDE.md\nprintf 'y\\n' >> .claude/settings.json");
    let why = format!("differing edits to one source {A}/blocks/pr-body.md (.claude/skills/open-pr/pr-body.md, .claude/skills/update-pr/pr-body.md)");
    let r = sb.ok(&ws, &["ws", "propose", "--dry-run"]);
    assert_eq!(
        r.stdout,
        format!(
            "  local     .claude/settings.json  (copy (yours))\nUnresolved:\n  .claude/skills/open-pr/pr-body.md: {why}\n  .claude/skills/update-pr/pr-body.md: {why}\n  CLAUDE.md: generated; sync a part to edit it\n"
        )
    );
    let r = sb.ok(&ws, &["ws", "propose", "--yes"]);
    assert!(r.stderr.starts_with("w: up to date with origin/main\n  local"), "{}", r.stderr);
    assert!(r.stderr.ends_with("nothing to propose\n"), "{}", r.stderr);
    assert_eq!(sb.gh_log(), "");
    sb.assert_cleaned_up();
}

#[test]
fn layout_new_from_file_and_list() {
    let sb = Sb::new("layout");
    let r = sb.ok(&sb.dir, &["layout", "list"]);
    assert_eq!(r.stdout, format!("argos-dev\t{A}\tclaude-code\nnero-dev\t{S}/nero\tclaude-code\n"));

    let manifest = |name: &str| format!("name: {name}\nharness: claude-code\nsync:\n  - {A}/docs\n");
    fs::write(sb.dir.join("m.yml"), manifest("docs-dev")).unwrap();
    let scope = format!("{A}/");
    let r = sb.ok(&sb.dir, &["layout", "new", &scope, "docs-dev", "--from", "m.yml", "--yes"]);
    assert_eq!(r.stdout, "https://github.invalid/pr/1\ndelphi/layout/docs-dev\n");
    assert!(
        r.stderr.starts_with(&format!(
            "---- delphi: add layout docs-dev\nAdds layout `docs-dev` in scope `{A}`:\n\n```yaml\nname: docs-dev\n"
        )),
        "{}",
        r.stderr
    );
    let root = sb.root();
    let f =
        sb.git(&root, &["show", &format!("origin/delphi/layout/docs-dev:context/{A}/layouts/docs-dev/manifest.yml")]);
    assert_eq!(format!("{f}\n"), manifest("docs-dev"));
    let msg = sb.git(&root, &["log", "-1", "--format=%B", "origin/delphi/layout/docs-dev"]);
    assert_eq!(
        msg,
        "delphi: add layout docs-dev\n\nDelphi-Harness: sandbox\nDelphi-Model: sandbox-model\nDelphi-Effort: low"
    );

    // try it before it merges
    let r = sb.ok(&sb.dir, &["ws", "new", "docs-dev", "--ref", "delphi/layout/docs-dev"]);
    assert!(sb.ws("docs-dev").join("docs/logo.png").is_file(), "{r:#?}");
    let r = sb.d(&sb.dir, &["ws", "propose", "docs-dev", "--yes"]);
    assert!(r.stderr.starts_with("delphi: layout not on main yet"), "{}", r.stderr);

    fs::write(sb.dir.join("bad.yml"), "name: bad\nharness: claude-code\nsync:\n  - software/missing\n").unwrap();
    for (args, err) in [
        (&["layout", "new", &scope, "other", "--from", "m.yml", "--yes"][..], "delphi: manifest name must be 'other'\n"),
        (&["layout", "new", &scope, "argos-dev", "--from", "m.yml", "--yes"], "delphi: layout name already used: argos-dev\n"),
        (&["layout", "new", "software/nope", "x", "--from", "m.yml", "--yes"], "delphi: not a scope on origin/main: software/nope\n"),
        (&["layout", "new", &scope, "x", "--from", "missing.yml"], "delphi: no such file: missing.yml\n"),
        (&["layout", "new", &scope, "x"], "delphi: usage: delphi layout new <scope> <layout> --from <manifest> (draft one with the delphi-new-layout skill)\n"),
        (&["layout", "new", &scope, "docs-dev", "--from", "m.yml"], "delphi: non-interactive session: re-run with --yes (or DELPHI_YES=1)\n"),
    ] {
        let r = sb.d(&sb.dir, args);
        assert_eq!((r.code, r.stderr.as_str()), (1, err), "{args:?}");
    }
    let r = sb.d(&sb.dir, &["layout", "new", &scope, "bad", "--from", "bad.yml", "--yes"]);
    assert_eq!(r.code, 1);
    assert!(
        r.stderr.contains("sync: missing context/software/missing\n")
            && r.stderr.ends_with("delphi: layout fails check; nothing pushed\n"),
        "{}",
        r.stderr
    );
    sb.assert_cleaned_up();
}

#[test]
fn block_mv_then_workspaces_follow_on_refresh() {
    let sb = Sb::new("mv");
    let ws = sb.new_ws("w");
    let root = sb.root();
    let (old, new) = (format!("{A}/harness/skills/run-tests"), format!("{A}/harness/skills/tests"));
    let day = sb.sh(&sb.dir, "date +%Y%m%d").trim().to_string();
    let br = format!("delphi/mv/run-tests-{day}");
    let r = sb.ok(&sb.dir, &["block", "mv", &old, &new, "--yes"]);
    assert_eq!(r.stdout, format!("https://github.invalid/pr/1\n{br}\n"));
    let moves = sb.git(&root, &["show", &format!("origin/{br}:moves.tsv")]);
    let date = sb.sh(&sb.dir, "date +%Y-%m-%d").trim().to_string();
    assert_eq!(moves, format!("# old\tnew\tdate\n{old}\t{new}\t{date}"));
    let scope = sb.git(&root, &["show", &format!("origin/{br}:context/{A}/scope.yml")]);
    assert!(scope.contains(&format!("  - {new}")), "{scope}");
    let mf = sb.git(&root, &["show", &format!("origin/{br}:context/{LAYOUT}/manifest.yml")]);
    assert!(mf.contains(&format!("sync:\n  - {new}\n")), "{mf}");

    let r = sb.d(&sb.dir, &["block", "mv", "software/nope/a.md", "software/nope/b.md", "--yes"]);
    assert!(r.stderr.ends_with("delphi: no such source on origin/main: software/nope/a.md\n"), "{}", r.stderr);
    let r = sb.d(&sb.dir, &["block", "mv", &format!("{LAYOUT}/manifest.yml"), "x/manifest.yml", "--yes"]);
    assert!(r.stderr.contains("is a layout or scope file"), "{}", r.stderr);

    // after the move lands, the workspace follows on refresh
    sb.upstream("merge", &format!("git merge -q --no-edit origin/{br}"));
    let r = sb.ok(&sb.dir, &["ws", "refresh", "w"]);
    assert!(r.stderr.contains("  updated .claude/skills/tests/SKILL.md"), "{}", r.stderr);
    assert!(r.stderr.contains("  removed .claude/skills/run-tests/SKILL.md"), "{}", r.stderr);
    assert!(ws.join(".claude/skills/tests/scripts/run.sh").is_file());
    assert!(!ws.join(".claude/skills/run-tests").exists());
    assert!(sb.read(&ws.join(".delphi/manifest.yml")).contains(&format!("  - {new}\n")));
    let meta = sb.read(&ws.join(".git/delphi/meta"));
    assert!(meta.contains(&format!("compile_commit={}\n", sb.git(&root, &["rev-parse", "origin/main"]))));
    let r = sb.ok(&sb.dir, &["ws", "status"]);
    assert!(r.stdout.contains(" clean      -     no     delphi ws open w\n"), "{}", r.stdout);
    sb.assert_cleaned_up();
}

#[test]
fn check_passes_then_reports_every_failure() {
    let sb = Sb::new("check");
    let r = sb.d(&sb.dir, &["check"]);
    assert_eq!((r.code, r.stderr.as_str()), (0, "check: ok\n"));

    let c = sb.root().join("context");
    let a = c.join(A);
    let lay = |n: &str, m: &str| {
        fs::create_dir_all(a.join(format!("layouts/{n}"))).unwrap();
        fs::write(a.join(format!("layouts/{n}/manifest.yml")), m).unwrap();
    };
    fs::write(a.join("blocks/empty.md"), "").unwrap();
    fs::write(a.join("blocks/CLAUDE.md"), "x\n").unwrap();
    std::os::unix::fs::symlink("style.md", a.join("blocks/link.md")).unwrap();
    fs::create_dir_all(c.join("orphan")).unwrap();
    fs::write(c.join("orphan/x.md"), "x\n").unwrap();
    fs::write(c.join("software/scope.yml"), "name: Software\nrecommend:\n  - software/nope.md\n").unwrap();
    fs::write(c.join(format!("{S}/scope.yml")), "name:\tx\n").unwrap();
    fs::write(sb.root().join("moves.tsv"), "# old\tnew\tdate\na\tb\n").unwrap();
    lay("bad", "name: other\nharness: nope\nblocks:\n  - x\n");
    lay("missing", "name: missing\nharness: claude-code\nsync:\n  - software/missing\n");
    lay(
        "overlap",
        &format!(
            "name: overlap\nharness: claude-code\nsync:\n  - {A}/docs\n  - {A}/blocks/style.md -> docs/style.md\n"
        ),
    );
    lay("dup", &format!("name: dup\nharness: claude-code\nsync:\n  - {A}/blocks/style.md -> x.md\ncopy:\n  - {A}/blocks/pr-body.md -> x.md\n"));
    lay("both", "name: both\nharness: claude-code\ninstructions:\n  - software/harness/instructions/base.md\n");
    fs::create_dir_all(a.join("layouts/both/files")).unwrap();
    fs::write(a.join("layouts/both/files/CLAUDE.md"), "# mine\n").unwrap();
    lay("unsafe", "name: unsafe\nharness: claude-code\nsync:\n  - software/harness -> .git/hooks\n");
    lay("argos-dev2", "name: argos-dev\nharness: claude-code\n");
    let r = sb.d(&sb.dir, &["check"]);
    assert_eq!(r.code, 1);
    let l = format!("context/{A}/layouts");
    for want in [
        "check: context/orphan: scope directory has no scope.yml\n".to_string(),
        format!("check: context/{A}/blocks/empty.md: empty file\n"),
        format!("check: context/{A}/blocks/CLAUDE.md: instruction file names are only allowed in a layout's files/\n"),
        format!("check: context/{A}/blocks/link.md: symlinks are not allowed\n"),
        "check: context/software/scope.yml: recommend: missing 'software/nope.md'\n".into(),
        format!("/context/{S}/scope.yml:1: tabs are not allowed\n"),
        "check: moves.tsv:2: expected old<TAB>new<TAB>date\n".into(),
        format!("check: {l}/bad/manifest.yml: name 'other' must equal its directory 'bad'\n"),
        format!("check: {l}/bad/manifest.yml: unknown key 'blocks'\n"),
        format!("check: {l}/bad/manifest.yml: unknown or missing harness 'nope'\n"),
        format!("check: {l}/missing/manifest.yml: sync: missing context/software/missing\n"),
        format!("check: {l}/overlap/manifest.yml: dests overlap: 'docs' and 'docs/style.md'\n"),
        format!("check: {l}/dup/manifest.yml: dests overlap: 'x.md' and 'x.md'\n"),
        format!("check: {l}/both/manifest.yml: uses both instructions: and files/CLAUDE.md\n"),
        format!("check: {l}/unsafe/manifest.yml: sync: unsafe dest in 'software/harness -> .git/hooks'\n"),
        format!("check: {l}/argos-dev2/manifest.yml: name 'argos-dev' must equal its directory 'argos-dev2'\n"),
        format!("check: {l}/argos-dev2/manifest.yml: layout name 'argos-dev' is not unique\n"),
    ] {
        assert!(r.stderr.contains(&want), "missing {want:?} in:\n{}", r.stderr);
    }
    let r2 = sb.d(&sb.dir, &["check"]);
    assert_eq!(r.stderr, r2.stderr);
    sb.assert_cleaned_up();
}

#[test]
fn v1_workspaces_are_detected() {
    let sb = Sb::new("v1");
    sb.new_ws("fresh");
    let old = sb.ws("old");
    fs::create_dir_all(&old).unwrap();
    sb.sh(
        &old,
        "git init -q && mkdir -p .git/delphi .delphi && printf 'layout=argos-dev\\nref=main\\n' > .git/delphi/meta\n\
         printf '# output\\tstart\\tend\\tsource\\tsha\\n' > .delphi/lock.tsv && git add -A && git commit -qm c && git branch generated",
    );
    let want = "delphi: old is a v1 workspace, which this Delphi no longer supports; recreate it: delphi workspace new argos-dev --as <new-name> (then move your edits over)\n";
    for args in [&["ws", "refresh", "old"][..], &["ws", "diff", "old"], &["ws", "propose", "old", "--dry-run"]] {
        let r = sb.d(&sb.dir, args);
        assert_eq!((r.code, r.stderr.as_str()), (1, want), "{args:?}");
    }
    let r = sb.d(&old, &["ws", "diff"]);
    assert_eq!(r.stderr, want);
    let r = sb.ok(&sb.dir, &["ws", "status"]);
    assert!(
        r.stdout.contains(
            "old                    argos-dev        main     -     v1         -     -      old is a v1 workspace"
        ),
        "{}",
        r.stdout
    );
    assert!(r.stdout.contains("fresh "), "{}", r.stdout);
    sb.assert_cleaned_up();
}

#[test]
fn repo_root_discovery_and_setup() {
    let sb = Sb::new("root");
    let ws = sb.new_ws("w");

    // walk up from inside the checkout
    let r = sb.d_noroot(&sb.root().join("context/software"), &["ws", "status", "--offline"]);
    assert_eq!(r.code, 0, "{r:#?}");
    assert!(r.stdout.contains("w "));

    // outside any checkout, nothing recorded
    let r = sb.d_noroot(&ws, &["ws", "status"]);
    assert_eq!(r.code, 1);
    assert!(r.stderr.starts_with("delphi: cannot find the Delphi repo"), "{}", r.stderr);

    // setup records the checkout; then it works from the workspace
    let r = sb.d_noroot(&sb.root(), &["setup"]);
    assert_eq!(r.code, 0, "{r:#?}");
    assert_eq!(sb.read(&sb.dir.join("home/.config/delphi/root")), format!("{}\n", sb.root().display()));
    let r = sb.d_noroot(&ws, &["ws", "diff"]);
    assert_eq!((r.code, r.stderr.as_str()), (0, "w: no changes since the last refresh\n"));
    let r = sb.d_noroot(&ws.join("repos/argos"), &["ws", "propose", "--dry-run"]);
    assert_eq!((r.code, r.stdout.as_str()), (0, ""));

    let r = sb.d_noroot(&sb.dir, &["setup", "/nonexistent"]);
    assert_eq!(r.code, 1);
    assert!(!Path::new("/nonexistent").exists());
    sb.assert_cleaned_up();
}

#[test]
fn open_shell_gets_provenance_env() {
    let sb = Sb::new("open");
    let ws = sb.new_ws("w");
    let shell = sb.dir.join("bin/fake-shell");
    fs::write(&shell, "#!/bin/sh\necho \"$(pwd) h=$DELPHI_HARNESS m=$DELPHI_MODEL e=$DELPHI_EFFORT\"\n").unwrap();
    fs::set_permissions(&shell, fs::Permissions::from_mode(0o755)).unwrap();
    let mut c = std::process::Command::new(env!("CARGO_BIN_EXE_delphi"));
    c.args(["ws", "open", "w", "--shell", "--model", "m1"]);
    sb.env(&mut c);
    c.env("SHELL", &shell).env("DELPHI_ROOT", sb.root()).current_dir(&sb.dir);
    let o = c.output().unwrap();
    let out = String::from_utf8_lossy(&o.stdout);
    assert_eq!((o.status.code(), String::from_utf8_lossy(&o.stderr).as_ref()), (Some(0), ""));
    assert!(out.starts_with(&format!("{} h=claude-code", ws.display())), "{out}");
    assert!(out.ends_with(" m=m1 e=low\n"), "{out}");
    sb.assert_cleaned_up();
}
