//! End-to-end tests of the CLI in a sandbox (see tests/common).

mod common;

use common::{Sb, AD, ND, PB, RT};
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

fn exec(p: &Path) -> bool {
    fs::metadata(p).unwrap().permissions().mode() & 0o111 != 0
}

#[test]
fn usage_and_argument_errors() {
    let sb = Sb::new("args");
    let r = sb.d(&sb.dir, &[]);
    assert_eq!(r.code, 0);
    assert!(r.stdout.starts_with("usage: delphi <command> [args]"));
    for (args, err) in [
        (&["bogus"][..], "delphi: unknown command 'bogus' (see: delphi help)\n"),
        (&["checkout"], "delphi: usage: delphi checkout <workspace> [--as <checkout>]\n"),
        (&["checkout", "a", "b"], "delphi: too many arguments (see: delphi help)\n"),
        (&["status", "--bogus"], "delphi: unknown flag for this command: --bogus (allowed: --offline)\n"),
        (&["diff", "--dry-run"], "delphi: unknown flag for this command: --dry-run (allowed: --upstream --offline)\n"),
        (&["checkout", "argos-dev", "--as"], "delphi: --as needs a value\n"),
        (&["checkout", "argos-dev", "--as", "Bad/Name"], "delphi: invalid checkout name: 'Bad/Name'\n"),
        (&["checkout", "nope"], "delphi: no workspace named 'nope' on origin/main (see: delphi list)\n"),
        (&["create", "software"], "delphi: usage: delphi create <scope> <name> --from <workspace.yml>\n"),
        (&["create", "software", "Bad"], "delphi: invalid workspace name: 'Bad' (use a-z, 0-9, -)\n"),
        (&["mv", "a"], "delphi: usage: delphi mv <old> <new>\n"),
        (&["mv", "../x", "b", "--yes"], "delphi: unsafe path: '../x'\n"),
        (&["sync", "x"], "delphi: usage: delphi sync [--check] [--base <rev>]\n"),
        (&["sync", "--base", "nope"], "delphi: not a revision: nope\n"),
        (&["check", "extra"], "delphi: usage: delphi check\n"),
        (&["list", "x"], "delphi: usage: delphi list\n"),
    ] {
        let r = sb.d(&sb.dir, args);
        assert_eq!((r.code, r.stderr.as_str()), (1, err), "{args:?}");
    }
    let r = sb.d(&sb.dir, &["refresh", "missing"]);
    assert_eq!(r.code, 1);
    assert!(r.stderr.starts_with("delphi: not a Delphi checkout: "), "{}", r.stderr);
    sb.assert_cleaned_up();
}

#[test]
fn sandbox_is_materialized_and_in_sync() {
    let sb = Sb::new("init");
    let root = sb.root();
    assert_eq!(
        sb.read(&root.join(AD).join("CLAUDE.md")),
        "# Workspace\n\nYou are in a Delphi workspace.\n\n# Software conventions\n\n- Use conventional commits.\n"
    );
    for w in [AD, ND] {
        assert_eq!(
            sb.read(&root.join(w).join(".claude/skills/run-tests/SKILL.md")),
            sb.read(&root.join(RT).join("SKILL.md"))
        );
        assert!(exec(&root.join(w).join(".claude/skills/run-tests/scripts/run.sh")));
    }
    assert_eq!(sb.read(&root.join(AD).join("docs/guide.md")), "# Guide\n\nLine one.\nLine two.\n");
    for d in [".claude/skills/open-pr/pr-body.md", ".claude/skills/update-pr/pr-body.md"] {
        assert_eq!(sb.read(&root.join(AD).join(d)), "**PR body:** fill the template.\n");
    }
    assert_eq!(sb.read(&root.join(ND).join("CLAUDE.md")), "# NERO\n\nNERO is the dashboard firmware.\n");
    let r = sb.ok(&root, &["sync", "--check"]);
    assert_eq!((r.stdout.as_str(), r.stderr.as_str()), ("", "sync: ok\n"));
    let r = sb.ok(&root, &["check"]);
    assert_eq!(r.stderr, "check: ok\n");
}

#[test]
fn sync_source_edit_fans_out_check_and_idempotent() {
    let sb = Sb::new("fan");
    let root = sb.root();
    sb.sh(&root, &format!("printf 'Run them in parallel.\\n' >> {RT}/SKILL.md && chmod -x {RT}/scripts/run.sh"));
    let r = sb.d(&root, &["sync", "--check"]);
    assert_eq!(r.code, 1);
    assert_eq!(
        r.stdout,
        format!(
            "  would be updated {AD}/.claude/skills/run-tests/SKILL.md\n  would be updated {ND}/.claude/skills/run-tests/SKILL.md\n  would be updated {AD}/.claude/skills/run-tests/scripts/run.sh\n  would be updated {ND}/.claude/skills/run-tests/scripts/run.sh\n"
        )
    );
    assert_eq!(r.stderr, "sync: out of sync (run: delphi sync)\n");
    assert!(!sb.read(&root.join(AD).join(".claude/skills/run-tests/SKILL.md")).contains("parallel"));

    let r = sb.ok(&root, &["sync"]);
    assert_eq!(r.stdout.lines().count(), 4, "{}", r.stdout);
    assert_eq!(r.stderr, "sync: 4 file(s) written\n");
    for w in [AD, ND] {
        assert!(sb.read(&root.join(w).join(".claude/skills/run-tests/SKILL.md")).ends_with("Run them in parallel.\n"));
        assert!(!exec(&root.join(w).join(".claude/skills/run-tests/scripts/run.sh")));
    }
    // idempotent
    let r = sb.ok(&root, &["sync"]);
    assert_eq!((r.stdout.as_str(), r.stderr.as_str()), ("", "sync: ok\n"));
    sb.ok(&root, &["sync", "--check"]);

    // executable means the owner's x bit, as in git: a group-only x bit is no change
    sb.sh(&root, "git add -A && git commit -qm fan");
    let p = root.join(AD).join(".claude/skills/run-tests/SKILL.md");
    fs::set_permissions(&p, fs::Permissions::from_mode(0o654)).unwrap();
    assert_eq!(sb.git(&root, &["status", "--porcelain"]), "");
    let r = sb.ok(&root, &["sync", "--check", "--base", "HEAD"]);
    assert_eq!((r.stdout.as_str(), r.stderr.as_str()), ("", "sync: ok\n"));
}

#[test]
fn sync_copy_edit_reaches_source_and_other_copies() {
    let sb = Sb::new("copy");
    let root = sb.root();
    sb.write(&root.join(AD).join(".claude/skills/open-pr/pr-body.md"), "**PR body:** be brief.\n");
    let r = sb.ok(&root, &["sync"]);
    assert_eq!(
        r.stdout,
        format!(
            "  updated {PB}\n  updated {AD}/.claude/skills/update-pr/pr-body.md\n  updated {ND}/.claude/skills/pr/pr-body.md\n"
        )
    );
    for p in [
        PB.to_string(),
        format!("{AD}/.claude/skills/update-pr/pr-body.md"),
        format!("{ND}/.claude/skills/pr/pr-body.md"),
    ] {
        assert_eq!(sb.read(&root.join(p)), "**PR body:** be brief.\n");
    }
}

#[test]
fn sync_new_file_and_delete_in_linked_dir() {
    let sb = Sb::new("newdel");
    let root = sb.root();
    sb.write(&root.join(AD).join(".claude/skills/run-tests/notes.md"), "Notes.\n");
    let r = sb.ok(&root, &["sync"]);
    assert_eq!(r.stdout, format!("  created {RT}/notes.md\n  created {ND}/.claude/skills/run-tests/notes.md\n"));
    assert_eq!(sb.read(&root.join(ND).join(".claude/skills/run-tests/notes.md")), "Notes.\n");
    sb.sh(&root, "git add -A && git commit -qm notes && git push -q origin HEAD:main");

    // deleting a copy deletes the source and the other copies (and their empty directories)
    fs::remove_file(root.join(ND).join(".claude/skills/run-tests/scripts/run.sh")).unwrap();
    let r = sb.ok(&root, &["sync"]);
    assert_eq!(
        r.stdout,
        format!("  deleted {RT}/scripts/run.sh\n  deleted {AD}/.claude/skills/run-tests/scripts/run.sh\n")
    );
    assert!(!root.join(RT).join("scripts").exists());
    assert!(!root.join(AD).join(".claude/skills/run-tests/scripts").exists());
    sb.ok(&root, &["sync", "--check"]);
}

#[test]
fn sync_conflicting_edits_exit_1_and_list_files() {
    let sb = Sb::new("conflict");
    let root = sb.root();
    sb.write(&root.join(AD).join(".claude/skills/run-tests/SKILL.md"), "mine\n");
    sb.write(&root.join(ND).join(".claude/skills/run-tests/SKILL.md"), "theirs\n");
    sb.write(&root.join(PB), "**PR body:** new.\n");
    let r = sb.d(&root, &["sync"]);
    assert_eq!(r.code, 1, "{r:#?}");
    assert_eq!(
        r.stderr,
        format!(
            "conflict: {RT}/SKILL.md: different edits in {AD}/.claude/skills/run-tests/SKILL.md, {ND}/.claude/skills/run-tests/SKILL.md\nsync: 1 conflict(s); fix them by hand, then re-run: delphi sync\n"
        )
    );
    // the conflicting files are left alone; other links still sync
    assert_eq!(sb.read(&root.join(RT).join("SKILL.md")).lines().nth(1), Some("name: run-tests"));
    assert_eq!(sb.read(&root.join(ND).join(".claude/skills/pr/pr-body.md")), "**PR body:** new.\n");
    // resolve by making them agree
    sb.write(&root.join(ND).join(".claude/skills/run-tests/SKILL.md"), "mine\n");
    sb.ok(&root, &["sync"]);
    assert_eq!(sb.read(&root.join(RT).join("SKILL.md")), "mine\n");
}

#[test]
fn sync_new_links_dest_missing_source_missing_and_differing() {
    let sb = Sb::new("links");
    let root = sb.root();
    let yml = root.join(ND).join("workspace.yml");
    let base = sb.read(&yml);
    sb.write(&yml, &format!("{base}docs:\n  - software/docs/guide.md\n  - software/docs/new.md\n"));
    sb.write(&root.join(ND).join("docs/new.md"), "# New\n");
    let r = sb.ok(&root, &["sync"]);
    assert_eq!(r.stdout, format!("  created {ND}/docs/guide.md\n  created context/software/docs/new.md\n"));
    assert_eq!(sb.read(&root.join("context/software/docs/new.md")), "# New\n");
    assert_eq!(sb.read(&root.join(ND).join("docs/guide.md")), "# Guide\n\nLine one.\nLine two.\n");

    // a new link whose dest already exists with different content is a conflict
    sb.sh(&root, "git add -A && git commit -qm links && git push -q origin HEAD:main");
    let base = sb
        .read(&yml)
        .replace("blocks:\n", "blocks:\n  - software/application-software/argos/blocks/pr-body.md -> CLAUDE.md\n");
    sb.write(&yml, &base);
    let r = sb.d(&root, &["sync"]);
    assert_eq!(r.code, 1);
    assert!(
        r.stderr.starts_with(&format!("conflict: {ND}/CLAUDE.md is newly linked to {PB} but differs from it")),
        "{}",
        r.stderr
    );
}

#[test]
fn sync_regenerates_instructions_and_flags_hand_edits() {
    let sb = Sb::new("instr");
    let root = sb.root();
    sb.sh(&root, "printf -- '- Open PRs against develop.\\n' >> context/software/harness/instructions/base.md");
    let r = sb.ok(&root, &["sync"]);
    assert_eq!(r.stdout, format!("  updated {AD}/CLAUDE.md\n"));
    assert!(sb
        .read(&root.join(AD).join("CLAUDE.md"))
        .ends_with("- Use conventional commits.\n- Open PRs against develop.\n"));
    sb.sh(&root, "git add -A && git commit -qm base && git push -q origin HEAD:main");

    // hand edits: conflict for a generated file; fine for a workspace's own CLAUDE.md
    sb.sh(&root, &format!("echo hand >> {AD}/CLAUDE.md && echo more >> {ND}/CLAUDE.md"));
    let r = sb.d(&root, &["sync"]);
    assert_eq!(r.code, 1);
    assert_eq!(
        r.stderr,
        format!(
            "conflict: {AD}/CLAUDE.md: generated from instructions: in workspace.yml (don't hand-edit it; edit a part)\nsync: 1 conflict(s); fix them by hand, then re-run: delphi sync\n"
        )
    );
    // deleting it regenerates it
    fs::remove_file(root.join(AD).join("CLAUDE.md")).unwrap();
    let r = sb.ok(&root, &["sync"]);
    assert_eq!(r.stdout, format!("  created {AD}/CLAUDE.md\n"));
}

#[test]
fn checkout_is_sparse_on_its_branch_with_repos_excluded() {
    let sb = Sb::new("co");
    let r = sb.d(&sb.dir, &["checkout", "argos-dev"]);
    assert_eq!(r.code, 0, "{r:#?}");
    let co = sb.co("argos-dev");
    let folder = co.join(AD);
    assert_eq!(
        r.stderr,
        format!("cloning argos…\ncheckout ready: {}\nnext: delphi open argos-dev\n", folder.display())
    );

    // only the folder is on disk (no root CLAUDE.md, no sources, no other workspace)
    let files = sb.sh(&co, "find . -path ./.git -prune -o -path '*/repos' -prune -o -type f -print | sort");
    let want: Vec<String> = [
        ".claude/skills/argos-notes/SKILL.md",
        ".claude/skills/open-pr/SKILL.md",
        ".claude/skills/open-pr/pr-body.md",
        ".claude/skills/run-tests/SKILL.md",
        ".claude/skills/run-tests/scripts/run.sh",
        ".claude/skills/update-pr/pr-body.md",
        "CLAUDE.md",
        "docs/guide.md",
        "workspace.yml",
    ]
    .iter()
    .map(|f| format!("./{AD}/{f}"))
    .collect();
    assert_eq!(files.lines().collect::<Vec<_>>(), want);
    assert!(!co.join("CLAUDE.md").exists());
    assert!(exec(&folder.join(".claude/skills/run-tests/scripts/run.sh")));

    assert_eq!(sb.git(&co, &["rev-parse", "--abbrev-ref", "HEAD"]), "ws/tester/argos-dev");
    assert_eq!(sb.git(&co, &["config", "remote.origin.partialclonefilter"]), "blob:none");
    assert_eq!(sb.git(&co, &["config", "core.sparseCheckoutCone"]), "false");
    assert!(folder.join("repos/argos/README.md").is_file());
    assert_eq!(sb.git(&co, &["status", "--porcelain"]), "");
    assert!(sb
        .read(&co.join(".git/info/exclude"))
        .ends_with(&format!("/{AD}/repos/\n/{AD}/.claude/settings.local.json\n")));
    assert!(exec(&co.join(".git/hooks/commit-msg")));
    assert_eq!(
        sb.read(&co.join(".git/delphi/meta")),
        format!("workspace=argos-dev\nfolder={AD}\nharness=claude-code\nbranch=ws/tester/argos-dev\nlast_pushed=\n")
    );

    // the hook adds provenance trailers from the environment
    sb.edit(&folder, "echo more >> docs/guide.md");
    assert_eq!(
        sb.git(&co, &["log", "-1", "--format=%(trailers)"]),
        "Delphi-Harness: sandbox\nDelphi-Model: sandbox-model\nDelphi-Effort: low"
    );

    let r = sb.d(&sb.dir, &["checkout", "argos-dev"]);
    assert_eq!((r.code, r.stderr), (1, format!("delphi: checkout already exists: {}\n", co.display())));
    let two = sb.checkout("argos-dev", "two");
    assert_eq!(sb.git(&two, &["rev-parse", "--abbrev-ref", "HEAD"]), "ws/tester/two");
    sb.assert_cleaned_up();
}

#[test]
fn refresh_merges_main_and_exits_2_on_conflicts() {
    let sb = Sb::new("refresh");
    let co = sb.checkout("nero-dev", "n");
    let folder = co.join(ND);
    let r = sb.ok(&sb.dir, &["refresh", "n"]);
    assert_eq!(r.stderr, "n: up to date with origin/main\n");

    sb.upstream("Describe NERO", &format!("printf 'More.\\n' >> {ND}/CLAUDE.md"));
    let r = sb.ok(&folder, &["refresh"]);
    let c = sb.git(&co, &["rev-parse", "--short=7", "origin/main"]);
    assert_eq!(r.stderr, format!("n: merged origin/main ({c})\n  updated CLAUDE.md\n"));
    assert!(sb.read(&folder.join("CLAUDE.md")).ends_with("More.\n"));
    assert!(!co.join("CLAUDE.md").exists());

    // uncommitted changes block it
    sb.sh(&folder, "echo dirty >> CLAUDE.md");
    let r = sb.d(&folder, &["refresh"]);
    assert_eq!(r.code, 1);
    assert!(r.stderr.ends_with("has uncommitted changes; commit or stash them first\n"), "{}", r.stderr);

    // conflicting edits: exit 2, listed; then "merge in progress"; resolve with git
    sb.sh(&folder, "git checkout -q CLAUDE.md");
    sb.edit(&folder, "sed -i 's/^More.$/Mine./' CLAUDE.md");
    sb.upstream("Theirs", &format!("sed -i 's/^More.$/Theirs./' {ND}/CLAUDE.md"));
    let r = sb.d(&folder, &["refresh"]);
    assert_eq!(r.code, 2, "{r:#?}");
    assert_eq!(
        r.stderr,
        format!(
            "conflicts in n:\n  {ND}/CLAUDE.md\nresolve them with git in {}, commit, then re-run: delphi refresh n\n",
            co.display()
        )
    );
    let r = sb.d(&folder, &["refresh"]);
    assert_eq!(r.code, 1);
    assert!(r.stderr.contains("merge in progress in"), "{}", r.stderr);
    sb.sh(&folder, "git checkout --ours CLAUDE.md && git add CLAUDE.md && git commit -q --no-edit");
    let r = sb.ok(&folder, &["refresh"]);
    assert_eq!(r.stderr, "n: up to date with origin/main\n");
    sb.assert_cleaned_up();
}

#[test]
fn diff_tags_own_and_linked_files_and_upstream_authors() {
    let sb = Sb::new("diff");
    let co = sb.checkout("argos-dev", "a");
    let folder = co.join(AD);
    let r = sb.ok(&folder, &["diff"]);
    assert_eq!((r.stdout.as_str(), r.stderr.as_str()), ("", "a: no changes vs main\n"));

    sb.edit(
        &folder,
        "echo more >> .claude/skills/argos-notes/SKILL.md && echo more >> .claude/skills/run-tests/SKILL.md \
         && echo more >> docs/guide.md && echo x >> CLAUDE.md && echo new > notes.md",
    );
    sb.sh(&folder, "echo uncommitted >> notes.md");
    let r = sb.ok(&folder, &["diff"]);
    assert_eq!(
        r.stdout,
        "  M own       .claude/skills/argos-notes/SKILL.md
  M linked    .claude/skills/run-tests/SKILL.md <- software/harness/skills/run-tests/SKILL.md (shared: nero-dev)
  M generated CLAUDE.md
  M linked    docs/guide.md <- software/docs/guide.md
  A own       notes.md
"
    );
    assert!(r.stderr.contains("uncommitted changes in"), "{}", r.stderr);

    // --upstream: changes on main since the last refresh, with author and subject
    let r = sb.ok(&folder, &["diff", "--upstream"]);
    assert_eq!(r.stderr, "a: up to date with origin/main\n");
    sb.upstream("Better PRs", &format!("echo better >> {AD}/.claude/skills/open-pr/SKILL.md"));
    let r = sb.ok(&folder, &["diff", "--upstream"]);
    assert_eq!(r.stdout, "  M .claude/skills/open-pr/SKILL.md  (Alice: Better PRs)\n");
    sb.assert_cleaned_up();
}

#[test]
fn propose_syncs_pushes_and_the_other_workspace_gets_it() {
    let sb = Sb::new("propose");
    let co = sb.checkout("argos-dev", "argos-dev");
    let nero = sb.checkout("nero-dev", "nero");
    let folder = co.join(AD);
    let r = sb.ok(&folder, &["propose", "--dry-run"]);
    assert_eq!(r.stderr, "nothing to propose\n");

    sb.edit(&folder, "echo 'Run them in parallel.' >> .claude/skills/run-tests/SKILL.md && echo more >> .claude/skills/argos-notes/SKILL.md");
    let r = sb.ok(&folder, &["propose", "--dry-run"]);
    let body = format!(
        "- M own `.claude/skills/argos-notes/SKILL.md`
- M linked `.claude/skills/run-tests/SKILL.md` ← `software/harness/skills/run-tests/SKILL.md` (shared: nero-dev)
- M sync `{ND}/.claude/skills/run-tests/SKILL.md`
- M sync `{RT}/SKILL.md`
"
    );
    assert!(
        r.stdout.starts_with(&format!("  updated {RT}/SKILL.md\n  updated {ND}/.claude/skills/run-tests/SKILL.md\n")),
        "{}",
        r.stdout
    );
    assert!(
        r.stdout.contains("---- delphi: changes from workspace argos-dev (to ws/tester/argos-dev)\n"),
        "{}",
        r.stdout
    );
    assert!(r.stdout.contains(&body), "{}", r.stdout);
    assert_eq!(sb.gh_log(), "");
    assert_eq!(sb.git(&co, &["ls-remote", "--heads", "origin", "ws/tester/argos-dev"]), "");

    // non-interactive without --yes fails fast
    let r = sb.d(&folder, &["propose"]);
    assert_eq!(
        (r.code, r.stderr.as_str()),
        (1, "delphi: non-interactive session: re-run with --yes (or DELPHI_YES=1)\n")
    );

    let r = sb.ok(&folder, &["propose", "--yes"]);
    assert!(r.stderr.contains(&body), "{}", r.stderr);
    assert!(r.stderr.contains("| sandbox | sandbox-model | low |"), "{}", r.stderr);
    let head = sb.git(&co, &["rev-parse", "origin/ws/tester/argos-dev"]);
    assert_eq!(sb.git(&co, &["rev-parse", "HEAD"]), head, "local branch fast-forwarded");
    assert_eq!(
        sb.git(&co, &["log", "-1", "--format=%s%n%(trailers)", &head]),
        format!("delphi: sync shared files\nDelphi-Harness: sandbox\nDelphi-Model: sandbox-model\nDelphi-Effort: low\nDelphi-Workspace: {AD}")
    );
    assert_eq!(
        sb.git(&co, &["show", "--name-only", "--format=", &head]),
        format!("{ND}/.claude/skills/run-tests/SKILL.md\n{RT}/SKILL.md")
    );
    assert!(!co.join(RT).exists(), "sparse checkout stays sparse");
    let log = sb.gh_log();
    assert!(log.contains("gh pr create --head ws/tester/argos-dev --base main --title delphi: changes from workspace argos-dev --body "), "{log}");
    assert!(sb.read(&co.join(".git/delphi/meta")).ends_with(&format!("last_pushed={head}\n")));
    let r = sb.ok(&sb.dir, &["status"]);
    assert!(
        r.stdout.contains("argos-dev        argos-dev        no    0     0      delphi open argos-dev\n"),
        "{}",
        r.stdout
    );

    // a second edit to the same linked file is proposed without conflicting with the first sync
    sb.edit(&folder, "echo 'And fast.' >> .claude/skills/run-tests/SKILL.md");
    sb.ok(&folder, &["propose", "--yes"]);
    assert!(sb.gh_log().contains("gh pr edit 1 --title"), "{}", sb.gh_log());
    let head = sb.git(&co, &["rev-parse", "origin/ws/tester/argos-dev"]);
    let skill = sb.git(&co, &["show", &format!("{head}:{RT}/SKILL.md")]);
    assert!(skill.ends_with("Run them in parallel.\nAnd fast."), "{skill}");

    // merge the PR on origin; the other workspace's checkout gets the change on refresh
    sb.upstream("Merge", "git fetch -q origin ws/tester/argos-dev && git merge -q --no-edit FETCH_HEAD");
    let r = sb.ok(&nero.join(ND), &["refresh"]);
    assert!(r.stderr.contains("  updated .claude/skills/run-tests/SKILL.md\n"), "{}", r.stderr);
    assert!(sb.read(&nero.join(ND).join(".claude/skills/run-tests/SKILL.md")).ends_with("And fast.\n"));

    // after refreshing, nothing is left to propose
    sb.ok(&folder, &["refresh"]);
    let r = sb.ok(&folder, &["propose", "--yes"]);
    assert!(r.stderr.contains("nothing to propose"), "{}", r.stderr);
    sb.assert_cleaned_up();
}

#[test]
fn propose_reports_sync_conflicts_and_pushes_nothing() {
    let sb = Sb::new("pconf");
    let co = sb.checkout("argos-dev", "a");
    let folder = co.join(AD);
    sb.edit(&folder, "echo a >> .claude/skills/open-pr/pr-body.md && echo b >> .claude/skills/update-pr/pr-body.md");
    let r = sb.d(&folder, &["propose", "--yes"]);
    assert_eq!(r.code, 1, "{r:#?}");
    assert!(r.stderr.contains(&format!("conflict: {PB}: different edits in {AD}/.claude/skills/open-pr/pr-body.md, {AD}/.claude/skills/update-pr/pr-body.md\n")), "{}", r.stderr);
    assert!(r.stderr.contains("sync: 1 conflict(s); nothing proposed"), "{}", r.stderr);
    assert_eq!(sb.gh_log(), "");
    sb.assert_cleaned_up();
}

#[test]
fn status_lists_every_checkout() {
    let sb = Sb::new("status");
    let a = sb.checkout("argos-dev", "a");
    let n = sb.checkout("nero-dev", "n");
    sb.edit(&a.join(AD), "echo x >> docs/guide.md");
    sb.sh(&n.join(ND), "echo x >> CLAUDE.md");
    sb.upstream("Up", &format!("echo up >> {AD}/.claude/skills/open-pr/SKILL.md"));
    let r = sb.ok(&sb.dir, &["status"]);
    assert_eq!(
        r.stdout,
        format!(
            "CHECKOUT         WORKSPACE        DIRTY AHEAD BEHIND NEXT
a                argos-dev        no    1     1      delphi refresh a
n                nero-dev         yes   0     0      commit your changes in {}
",
            n.display()
        )
    );
}

#[test]
fn open_shell_runs_in_the_folder_with_provenance_env() {
    let sb = Sb::new("open");
    let co = sb.checkout("argos-dev", "a");
    let shell = sb.dir.join("bin/fake-shell");
    fs::write(&shell, "#!/bin/sh\necho \"$(pwd) h=$DELPHI_HARNESS m=$DELPHI_MODEL e=$DELPHI_EFFORT\"\n").unwrap();
    fs::set_permissions(&shell, fs::Permissions::from_mode(0o755)).unwrap();
    let r = sb.d_env(&sb.dir, &["open", "a", "--shell", "--model", "m1"], &[("SHELL", shell.to_str().unwrap())]);
    assert_eq!((r.code, r.stderr.as_str()), (0, ""));
    let out = r.stdout;
    assert!(out.starts_with(&format!("{} h=claude-code", co.join(AD).display())), "{out}");
    assert!(out.ends_with(" m=m1 e=low\n"), "{out}");
}

#[test]
fn create_from_file_and_list() {
    let sb = Sb::new("create");
    let r = sb.ok(&sb.dir, &["list"]);
    assert_eq!(
        r.stdout,
        "argos-dev\tsoftware/application-software/argos\tclaude-code\nnero-dev\tsoftware/application-software/nero\tclaude-code\n"
    );
    let f = sb.dir.join("tools.yml");
    sb.write(
        &f,
        "name: tools-dev\nharness: claude-code\ninstructions:\n  - software/harness/instructions/base.md\nskills:\n  - software/harness/skills/run-tests\n",
    );
    let fs_ = f.to_str().unwrap();
    for (args, err) in [
        (
            &["create", "software", "other", "--from", fs_, "--yes"][..],
            format!("delphi: {fs_}: name must be 'other'\n"),
        ),
        (&["create", "nope", "tools-dev", "--from", fs_, "--yes"], "delphi: not a scope on origin/main: nope\n".into()),
    ] {
        let r = sb.d(&sb.dir, args);
        assert_eq!((r.code, r.stderr), (1, err));
    }
    let r = sb.ok(&sb.dir, &["create", "software", "tools-dev", "--from", fs_, "--yes"]);
    assert_eq!(r.stdout.lines().last(), Some("delphi/create/tools-dev"));
    let br = "origin/delphi/create/tools-dev";
    sb.git(&sb.root(), &["fetch", "-q", "origin"]);
    let files = sb.git(&sb.root(), &["diff", "--name-only", "origin/main", br]);
    let w = "context/software/workspaces/tools-dev";
    assert_eq!(
        files,
        format!("{w}/.claude/skills/run-tests/SKILL.md\n{w}/.claude/skills/run-tests/scripts/run.sh\n{w}/CLAUDE.md\n{w}/workspace.yml")
    );
    assert_eq!(
        sb.git(&sb.root(), &["log", "-1", "--format=%s%n%(trailers)", br]),
        "delphi: create workspace tools-dev\nDelphi-Harness: sandbox\nDelphi-Model: sandbox-model\nDelphi-Effort: low"
    );
    assert!(sb.gh_log().contains(
        "gh pr create --head delphi/create/tools-dev --base main --title delphi: create workspace tools-dev"
    ));
    let r = sb.d(&sb.dir, &["create", "software", "argos-dev", "--from", fs_, "--yes"]);
    assert_eq!(r.code, 1);
    sb.assert_cleaned_up();
}

#[test]
fn mv_rewrites_links_and_keeps_dests() {
    let sb = Sb::new("mv");
    let r = sb.ok(&sb.dir, &["mv", "software/docs/guide.md", "software/docs/guides/guide.md", "--yes"]);
    let br = r.stdout.lines().last().unwrap().to_string();
    assert!(br.starts_with("delphi/mv/guide.md-"), "{br}");
    sb.git(&sb.root(), &["fetch", "-q", "origin"]);
    let yml = sb.git(&sb.root(), &["show", &format!("origin/{br}:{AD}/workspace.yml")]);
    assert!(yml.contains("docs:\n  - software/docs/guides/guide.md -> docs/guide.md\n"), "{yml}");
    assert!(!yml.contains("software/docs/guide.md"));

    let r = sb.ok(
        &sb.dir,
        &["mv", "software/harness/skills/run-tests", "software/application-software/harness/skills/run-tests", "--yes"],
    );
    let br = r.stdout.lines().last().unwrap().to_string();
    sb.git(&sb.root(), &["fetch", "-q", "origin"]);
    for w in [AD, ND] {
        let yml = sb.git(&sb.root(), &["show", &format!("origin/{br}:{w}/workspace.yml")]);
        assert!(yml.contains("  - software/application-software/harness/skills/run-tests\n"), "{yml}");
    }
    let r = sb.d(&sb.dir, &["mv", "software/nope", "software/x", "--yes"]);
    assert_eq!((r.code, r.stderr.as_str()), (1, "delphi: no such path on origin/main: context/software/nope\n"));
    sb.assert_cleaned_up();
}

#[test]
fn check_passes_then_reports_every_failure() {
    let sb = Sb::new("check");
    let root = sb.root();
    sb.ok(&root, &["check"]);
    let n = root.join(ND);
    sb.write(
        &n.join("workspace.yml"),
        "name: nero\nharness: claude-code\nbogus: 1\nlinks:\n  - software/docs/guide.md\ninstructions:\n  - software/nope.md\n\
         docs:\n  - software/missing\n  - software/docs/guide.md -> CLAUDE.md\n  - software/docs/guide.md -> CLAUDE.md\n  - software/application-software/argos/workspaces/argos-dev/docs/guide.md -> x.md\n\
         blocks:\n  - software/application-software/argos -> stuff\n  - software/docs/guide.md -> y.md\n\
         skills:\n  - software/harness/skills/run-tests/scripts\n  - software/application-software/argos/blocks/pr-body.md\n\
         settings:\n  - software/docs/guide.md\n  - software/harness/skills/run-tests/SKILL.md -> z.json\n\
         mcp:\n  - software/harness/mcp/nope.json\n  - software/docs/guide.md\n",
    );
    sb.write(&root.join("context/software/tools/README.md"), "x\n");
    sb.write(&root.join("context/software/docs/CLAUDE.md"), "x\n");
    sb.write(&root.join("context/software/application-software/argos/workspaces/stray/x.md"), "x\n");
    std::os::unix::fs::symlink("guide.md", root.join("context/software/docs/link.md")).unwrap();
    let r = sb.d(&root, &["check"]);
    assert_eq!(r.code, 1);
    let y = format!("{ND}/workspace.yml");
    let want = format!(
        "check: context/software/tools: scope directory has no scope.yml
check: context/software/docs/CLAUDE.md: instruction files belong in a workspace folder
check: context/software/docs/link.md: symlinks are not allowed
check: context/software/application-software/argos/workspaces/stray: workspace folder has no workspace.yml
check: {y}: name 'nero' must equal its folder 'nero-dev'
check: {y}: unknown key 'bogus'
check: {y}: unknown key 'links'
check: {y}: instructions: missing context/software/nope.md
check: {y}: mcp: missing context/software/harness/mcp/nope.json
check: {y}: mcp: context/software/docs/guide.md must be a file under a scope's harness/mcp/
check: {y}: settings: at most one entry
check: {y}: blocks: source context/software/application-software/argos contains workspace folder context/software/application-software/argos/workspaces/argos-dev
check: {y}: blocks: context/software/docs/guide.md must be under a scope's blocks/
check: {y}: docs: missing source context/software/missing
check: {y}: docs: CLAUDE.md is generated from instructions:
check: {y}: docs: CLAUDE.md is generated from instructions:
check: {y}: docs: dests overlap: 'CLAUDE.md' and 'CLAUDE.md'
check: {y}: docs: source context/software/application-software/argos/workspaces/argos-dev/docs/guide.md is inside a workspace folder
check: {y}: skills: context/software/harness/skills/run-tests/scripts must be a skill directory directly under a scope's harness/skills/
check: {y}: skills: context/software/application-software/argos/blocks/pr-body.md must be a skill directory directly under a scope's harness/skills/
check: {y}: settings: context/software/docs/guide.md must be a file under a scope's harness/settings/
check: {y}: settings: context/software/harness/skills/run-tests/SKILL.md must be a file under a scope's harness/settings/
"
    );
    let mut got: Vec<&str> = r.stderr.lines().collect();
    let mut exp: Vec<&str> = want.lines().collect();
    got.sort();
    exp.sort();
    assert_eq!(got, exp, "{}", r.stderr);

    sb.write(
        &n.join("workspace.yml"),
        "name: nero-dev\nharness: claude-code\ndocs:\n  - software/docs -> repos/docs\n",
    );
    let r = sb.d(&root, &["check"]);
    assert!(
        r.stderr.contains(&format!("check: {y}: docs: unsafe or reserved path in 'software/docs -> repos/docs'")),
        "{}",
        r.stderr
    );
    // a link must not overwrite the workspace's own workspace.yml
    sb.write(
        &n.join("workspace.yml"),
        "name: nero-dev\nharness: claude-code\ndocs:\n  - software/docs/guide.md -> workspace.yml\n",
    );
    let r = sb.d(&root, &["check"]);
    let want = format!("check: {y}: docs: unsafe or reserved path in 'software/docs/guide.md -> workspace.yml'\n");
    assert_eq!(r.code, 1);
    assert!(r.stderr.contains(&want), "{}", r.stderr);
}

#[test]
fn repo_root_discovery_and_setup() {
    let sb = Sb::new("root");
    let co = sb.checkout("argos-dev", "a");
    let folder = co.join(AD);

    // walk up from inside the Delphi checkout
    let r = sb.d_noroot(&sb.root().join("context/software"), &["check"]);
    assert_eq!(r.code, 0, "{r:#?}");

    // inside a workspace checkout (no delphi.conf), nothing recorded
    let r = sb.d_noroot(&folder, &["diff"]);
    assert_eq!(r.code, 1);
    assert!(r.stderr.starts_with("delphi: cannot find the Delphi repo"), "{}", r.stderr);

    // setup records the checkout; then it works from the workspace
    let r = sb.d_noroot(&sb.root(), &["setup"]);
    assert_eq!(r.code, 0, "{r:#?}");
    assert_eq!(sb.read(&sb.dir.join("home/.config/delphi/root")), format!("{}\n", sb.root().display()));
    let r = sb.d_noroot(&folder, &["diff"]);
    assert_eq!((r.code, r.stderr.as_str()), (0, "a: no changes vs main\n"));
    let r = sb.d_noroot(&folder.join("repos/argos"), &["status"]);
    assert_eq!(r.code, 0);

    let r = sb.d_noroot(&sb.dir, &["setup", "/nonexistent"]);
    assert_eq!(r.code, 1);
    sb.assert_cleaned_up();
}

#[test]
fn offline_tolerance() {
    let sb = Sb::new("offline");
    let co = sb.checkout("argos-dev", "a");
    let folder = co.join(AD);
    sb.edit(&folder, "echo x >> docs/guide.md");
    fs::rename(sb.dir.join("origin.git"), sb.dir.join("gone.git")).unwrap();

    let r = sb.ok(&folder, &["diff"]);
    assert_eq!(r.stdout, "  M linked    docs/guide.md <- software/docs/guide.md\n");
    assert!(r.stderr.contains("warning: git fetch failed in a; using local refs"), "{}", r.stderr);
    let r = sb.ok(&sb.dir, &["status"]);
    assert!(r.stdout.contains("\na "), "{}", r.stdout);
    let r = sb.d_env(&folder, &["diff"], &[("DELPHI_OFFLINE", "1")]);
    assert_eq!((r.code, r.stderr.as_str()), (0, ""));
    let r = sb.ok(&sb.dir, &["list"]);
    assert!(r.stderr.contains("git fetch failed; using local refs"), "{}", r.stderr);
    assert!(r.stdout.starts_with("argos-dev\t"));
    sb.ok(&sb.root(), &["sync", "--check"]);
    sb.ok(&sb.root(), &["check"]);
}

#[test]
fn propose_after_reverting_a_shared_edit_reverts_it_everywhere() {
    let sb = Sb::new("revert");
    let co = sb.checkout("argos-dev", "a");
    let folder = co.join(AD);
    let skill = folder.join(".claude/skills/run-tests/SKILL.md");
    let orig = sb.read(&skill);
    sb.edit(&folder, "echo 'Run them in parallel.' >> .claude/skills/run-tests/SKILL.md");
    sb.ok(&folder, &["propose", "--yes"]);

    // the revert is the one new state since the last push: it reaches the source and the copies
    sb.write(&skill, &orig);
    sb.sh(&folder, "git commit -qam revert");
    let r = sb.ok(&folder, &["propose", "--yes"]);
    assert!(r.stdout.contains(&format!("  updated {RT}/SKILL.md\n")), "{r:#?}");
    assert!(r.stderr.contains("nothing to propose"), "{}", r.stderr);
    assert_eq!(sb.read(&skill), orig);
    let lp = sb.read(&co.join(".git/delphi/meta"));
    assert!(lp.ends_with(&format!("last_pushed={}\n", sb.git(&co, &["rev-parse", "origin/ws/tester/a"]))));
    sb.assert_cleaned_up();
}

#[test]
fn status_ahead_counts_only_unpushed_own_commits() {
    let sb = Sb::new("ahead");
    let co = sb.checkout("argos-dev", "a");
    let folder = co.join(AD);
    sb.edit(&folder, "echo x >> docs/guide.md");
    sb.ok(&folder, &["propose", "--yes"]);
    sb.upstream("Up1", &format!("echo 1 >> {ND}/CLAUDE.md"));
    sb.upstream("Up2", &format!("echo 2 >> {AD}/.claude/skills/open-pr/SKILL.md"));
    sb.ok(&folder, &["refresh"]);
    let r = sb.ok(&sb.dir, &["status"]);
    assert!(r.stdout.ends_with("a                argos-dev        no    0     0      delphi open a\n"), "{}", r.stdout);
    sb.edit(&folder, "echo y >> docs/guide.md");
    let r = sb.ok(&sb.dir, &["status"]);
    assert!(
        r.stdout.ends_with("a                argos-dev        no    1     0      delphi propose a\n"),
        "{}",
        r.stdout
    );
}

/// The `sync-main` script from the CI workflow, run in a clone of the sandbox's origin.
fn ci_sync_main(sb: &Sb, clone: &Path) -> String {
    let yml = fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join(".github/workflows/delphi.yml")).unwrap();
    let block = yml.rsplit("- run: |\n").next().unwrap();
    let script: String = block.lines().map(|l| format!("{}\n", l.strip_prefix("          ").unwrap_or(l))).collect();
    let bin = Path::new(env!("CARGO_BIN_EXE_delphi")).parent().unwrap().display().to_string();
    let sha = sb.git(clone, &["rev-parse", "HEAD"]);
    sb.sh(clone, &format!("export PATH={bin}:$PATH GITHUB_SHA={sha}\n{script}"))
}

#[test]
fn ci_main_sync_commits_as_the_bot_once_and_tolerates_a_moved_main() {
    let sb = Sb::new("ci");
    // two racing merges: a new workspace links the skill as it was; the skill changes meanwhile
    sb.upstream(
        "Add tools-dev",
        "mkdir -p context/software/workspaces/tools-dev/.claude/skills\n\
         printf 'name: tools-dev\\nharness: claude-code\\nskills:\\n  - software/harness/skills/run-tests\\n' > context/software/workspaces/tools-dev/workspace.yml\n\
         cp -r context/software/harness/skills/run-tests context/software/workspaces/tools-dev/.claude/skills/",
    );
    sb.upstream(
        "Skill edit",
        &format!("for f in {RT} {AD}/.claude/skills/run-tests {ND}/.claude/skills/run-tests; do echo fast >> $f/SKILL.md; done"),
    );
    let main = sb.dir.join("main");
    sb.git(&sb.dir, &["clone", "-q", "origin.git", "main"]);
    ci_sync_main(&sb, &main);
    let log = sb.git(&main, &["log", "-1", "--format=%an|%s|%(trailers:key=Delphi-Harness,valueonly)", "origin/main"]);
    assert_eq!(log, "github-actions[bot]|delphi: sync shared files|github-actions");
    let copy = main.join("context/software/workspaces/tools-dev/.claude/skills/run-tests/SKILL.md");
    assert!(sb.read(&copy).ends_with("fast\n"));
    // re-running changes nothing
    let head = sb.git(&main, &["rev-parse", "origin/main"]);
    ci_sync_main(&sb, &main);
    assert_eq!(sb.git(&main, &["rev-parse", "origin/main"]), head);

    // a push that loses the race to a newer commit on main is left to that commit's run
    sb.git(&main, &["reset", "-q", "--hard", "HEAD~1"]);
    sb.upstream("Newer", "echo n >> context/software/docs/guide.md");
    ci_sync_main(&sb, &main);
    assert_eq!(sb.git(&main, &["log", "-1", "--format=%s", "origin/main"]), "Newer");
}

#[test]
fn per_key_default_dests_mcp_generation_and_settings_link() {
    let sb = Sb::new("keys");
    let root = sb.root();
    let (h, t) = ("context/software/harness", "context/software/workspaces/tools-dev");
    sb.write(&root.join(h).join("mcp/github.json"), "\"github\": {\n  \"command\": \"gh-mcp\"\n}\n");
    sb.write(&root.join(h).join("mcp/local.json"), "\"local\": {\"command\": \"run\"}");
    sb.write(&root.join(h).join("settings/default.json"), "{\"model\": \"opus\"}\n");
    sb.write(&root.join("context/software/docs/sub/notes.md"), "Notes.\n");
    let yml = "name: tools-dev\nharness: claude-code\nblocks:\n  - software/application-software/argos/blocks/pr-body.md\n\
               docs:\n  - software/docs/sub/notes.md\nskills:\n  - software/harness/skills/run-tests\n\
               settings: software/harness/settings/default.json\nmcp:\n  - software/harness/mcp/github.json\n  - software/harness/mcp/local.json\n";
    sb.write(&root.join(t).join("workspace.yml"), yml);
    sb.ok(&root, &["sync"]);
    assert_eq!(
        sb.sh(&root.join(t), "find . -type f | LC_ALL=C sort"),
        "./.claude/settings.json\n./.claude/skills/run-tests/SKILL.md\n./.claude/skills/run-tests/scripts/run.sh\n./.mcp.json\n\
         ./context/software/application-software/argos/blocks/pr-body.md\n./docs/sub/notes.md\n./workspace.yml\n"
    );
    let mcp = root.join(t).join(".mcp.json");
    assert_eq!(
        sb.read(&mcp),
        "{\"mcpServers\": {\n\"github\": {\n  \"command\": \"gh-mcp\"\n}\n,\n\"local\": {\"command\": \"run\"}\n}}\n"
    );
    assert_eq!(sb.read(&root.join(t).join(".claude/settings.json")), "{\"model\": \"opus\"}\n");
    sb.ok(&root, &["check"]);
    sb.sh(&root, "git add -A && git commit -qm tools && git push -q origin HEAD:main");

    // .mcp.json is generated: a hand edit is a conflict; a fragment edit regenerates it
    sb.sh(&root, &format!("echo hand >> {t}/.mcp.json"));
    let r = sb.d(&root, &["sync"]);
    assert_eq!(r.code, 1);
    assert!(r.stderr.starts_with(&format!(
        "conflict: {t}/.mcp.json: generated from mcp: in workspace.yml (don't hand-edit it; edit a fragment)\n"
    )));
    sb.sh(&root, &format!("git checkout -q {t}/.mcp.json && printf '\"local\": {{}}\\n' > {h}/mcp/local.json"));
    let r = sb.ok(&root, &["sync"]);
    assert_eq!(r.stdout, format!("  updated {t}/.mcp.json\n"));
    assert!(sb.read(&mcp).ends_with(",\n\"local\": {}\n}}\n"));

    // the settings file is linked: an edit to the copy reaches the source; `-> dest` works too
    sb.write(&root.join(t).join(".claude/settings.json"), "{}\n");
    let r = sb.ok(&root, &["sync"]);
    assert_eq!(r.stdout, format!("  updated {h}/settings/default.json\n"));
    sb.write(
        &root.join(t).join("workspace.yml"),
        &yml.replace("default.json\n", "default.json -> .claude/team.json\n"),
    );
    sb.sh(&root, &format!("rm {t}/.claude/settings.json"));
    let r = sb.ok(&root, &["sync"]);
    assert_eq!(r.stdout, format!("  created {t}/.claude/team.json\n"));
    sb.ok(&root, &["check"]);
    sb.sh(&root, "git add -A && git commit -qm team && git push -q origin HEAD:main");

    // mv rewrites the scalar settings entry
    let r = sb
        .ok(&sb.dir, &["mv", "software/harness/settings/default.json", "software/harness/settings/base.json", "--yes"]);
    let br = r.stdout.lines().last().unwrap().to_string();
    sb.git(&root, &["fetch", "-q", "origin"]);
    let y = sb.git(&root, &["show", &format!("origin/{br}:{t}/workspace.yml")]);
    assert!(y.contains("\nsettings: software/harness/settings/base.json -> .claude/team.json\n"), "{y}");
    sb.assert_cleaned_up();
}

const SKILL_HEAD: &str = "---\nname: run-tests\ndescription: Run the test suites.\n---\n";

/// Compose the linked skill run-tests from a block (plus pr-body.md), sync, and push it to main.
fn compose_run_tests(sb: &Sb) {
    let root = sb.root();
    sb.write(&root.join("context/software/blocks/run.md"), "Run both suites.\n");
    sb.write(
        &root.join(RT).join("skill.yml"),
        "name: run-tests\ndescription: Run the test suites.\nbody:\n  - software/blocks/run.md\n  - software/application-software/argos/blocks/pr-body.md\n",
    );
    sb.ok(&root, &["sync"]);
    sb.ok(&root, &["check"]);
    sb.sh(&root, "git add -A && git commit -qm compose && git push -q origin HEAD:main");
}

#[test]
fn sync_generates_linked_skill_from_blocks_and_fans_out() {
    let sb = Sb::new("skill");
    let root = sb.root();
    compose_run_tests(&sb);
    let want = format!("{SKILL_HEAD}Run both suites.\n\n**PR body:** fill the template.\n");
    for d in [RT.to_string(), format!("{AD}/.claude/skills/run-tests"), format!("{ND}/.claude/skills/run-tests")] {
        assert_eq!(sb.read(&root.join(&d).join("SKILL.md")), want, "{d}");
        assert!(root.join(&d).join("skill.yml").is_file(), "{d}");
    }

    // a block edit: --check reports it stale; sync regenerates the source and both copies
    sb.sh(&root, "printf 'Run them in parallel.\\n' >> context/software/blocks/run.md");
    let r = sb.d(&root, &["sync", "--check"]);
    assert_eq!(r.code, 1);
    assert_eq!(
        r.stdout,
        format!(
            "  would be updated {AD}/.claude/skills/run-tests/SKILL.md\n  would be updated {ND}/.claude/skills/run-tests/SKILL.md\n  would be updated {RT}/SKILL.md\n"
        )
    );
    assert_eq!(r.stderr, "sync: out of sync (run: delphi sync)\n");
    assert_eq!(sb.read(&root.join(RT).join("SKILL.md")), want);
    sb.ok(&root, &["sync"]);
    let want = format!("{SKILL_HEAD}Run both suites.\nRun them in parallel.\n\n**PR body:** fill the template.\n");
    for d in [RT.to_string(), format!("{AD}/.claude/skills/run-tests"), format!("{ND}/.claude/skills/run-tests")] {
        assert_eq!(sb.read(&root.join(&d).join("SKILL.md")), want, "{d}");
    }
    let r = sb.ok(&root, &["sync"]);
    assert_eq!((r.stdout.as_str(), r.stderr.as_str()), ("", "sync: ok\n"));
    sb.sh(&root, "git add -A && git commit -qm parallel && git push -q origin HEAD:main");

    // a hand edit to a copy is a conflict, and is not spread to the source or the other copy
    sb.sh(&root, &format!("echo hand >> {ND}/.claude/skills/run-tests/SKILL.md"));
    let r = sb.d(&root, &["sync"]);
    assert_eq!(r.code, 1);
    assert_eq!(
        r.stderr,
        format!(
            "conflict: {ND}/.claude/skills/run-tests/SKILL.md: generated from skill.yml (don't hand-edit it; edit a block)\nsync: 1 conflict(s); fix them by hand, then re-run: delphi sync\n"
        )
    );
    assert_eq!(r.stdout, "");
    assert_eq!(sb.read(&root.join(RT).join("SKILL.md")), want);

    // mv of a body block rewrites every skill.yml that uses it
    sb.sh(&root, &format!("git checkout -q {ND}"));
    let r = sb.ok(&sb.dir, &["mv", "software/blocks/run.md", "software/blocks/tests/run.md", "--yes"]);
    let br = r.stdout.lines().last().unwrap().to_string();
    sb.git(&root, &["fetch", "-q", "origin"]);
    for d in [RT.to_string(), format!("{AD}/.claude/skills/run-tests"), format!("{ND}/.claude/skills/run-tests")] {
        let y = sb.git(&root, &["show", &format!("origin/{br}:{d}/skill.yml")]);
        assert!(y.contains("body:\n  - software/blocks/tests/run.md\n  - software/"), "{d}: {y}");
    }
    sb.assert_cleaned_up();
}

#[test]
fn workspace_own_skill_generated_diff_tag_and_hand_edit_conflict() {
    let sb = Sb::new("ownskill");
    let root = sb.root();
    let op = format!("{AD}/.claude/skills/open-pr");
    sb.write(
        &root.join(&op).join("skill.yml"),
        "name: open-pr\ndescription: Open a PR.\nbody:\n  - software/application-software/argos/blocks/pr-body.md\n",
    );
    let r = sb.ok(&root, &["sync"]);
    assert_eq!(r.stdout, format!("  updated {op}/SKILL.md\n"));
    assert_eq!(
        sb.read(&root.join(&op).join("SKILL.md")),
        "---\nname: open-pr\ndescription: Open a PR.\n---\n**PR body:** fill the template.\n"
    );
    sb.ok(&root, &["check"]);
    sb.sh(&root, "git add -A && git commit -qm own && git push -q origin HEAD:main");

    // a hand edit is a conflict; editing skill.yml (or a block) regenerates it
    sb.sh(&root, &format!("echo hand >> {op}/SKILL.md"));
    let r = sb.d(&root, &["sync", "--check"]);
    assert_eq!(r.code, 1);
    assert!(
        r.stderr.starts_with(&format!(
            "conflict: {op}/SKILL.md: generated from skill.yml (don't hand-edit it; edit a block)\n"
        )),
        "{}",
        r.stderr
    );
    sb.sh(&root, &format!("git checkout -q {op} && sed -i 's/Open a PR./Open a draft PR./' {op}/skill.yml"));
    let r = sb.ok(&root, &["sync"]);
    assert_eq!(r.stdout, format!("  updated {op}/SKILL.md\n"));
    assert!(sb.read(&root.join(&op).join("SKILL.md")).contains("description: Open a draft PR.\n"));

    // diff tags a generated SKILL.md
    let co = sb.checkout("argos-dev", "a");
    sb.edit(&co.join(AD), "echo x >> .claude/skills/open-pr/SKILL.md");
    let r = sb.ok(&co.join(AD), &["diff"]);
    assert_eq!(r.stdout, "  M generated .claude/skills/open-pr/SKILL.md\n");
    sb.assert_cleaned_up();
}

#[test]
fn check_reports_skill_yml_failures() {
    let sb = Sb::new("skillcheck");
    let root = sb.root();
    let op = root.join(AD).join(".claude/skills/open-pr/skill.yml");
    sb.write(
        &op,
        "description: Open a PR.\nextra: 1\nbody:\n  - software/docs/guide.md\n  - software/blocks/nope.md\n  - ../x.md\n",
    );
    let r = sb.d(&root, &["check"]);
    assert_eq!(r.code, 1);
    let y = format!("{AD}/.claude/skills/open-pr/skill.yml");
    assert_eq!(
        r.stderr,
        format!(
            "check: {y}: missing name\ncheck: {y}: unknown key 'extra'\ncheck: {y}: body: context/software/docs/guide.md must be a file under a scope's blocks/\ncheck: {y}: body: missing context/software/blocks/nope.md\ncheck: {y}: body: missing context/../x.md\n"
        )
    );
    sb.write(&op, "name: open-pr\nbody: [x]\n");
    let r = sb.d(&root, &["check"]);
    assert_eq!(r.code, 1);
    assert!(r.stderr.contains(&format!("{y}:2: unsupported YAML syntax")), "{}", r.stderr);
}
