//! End-to-end tests of the CLI in a sandbox (see tests/common).

mod common;

use common::{Sb, AD, ND};
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

fn exec(p: &Path) -> bool {
    fs::metadata(p).unwrap().permissions().mode() & 0o111 != 0
}

fn lines(s: &str) -> Vec<&str> {
    s.lines().collect()
}

#[test]
fn usage_and_argument_errors() {
    let sb = Sb::new("args");
    let r = sb.d(&sb.dir, &[]);
    assert_eq!(r.code, 0);
    assert!(r.stdout.starts_with("usage: delphi <command> [args]"));
    for (args, err) in [
        (&["bogus"][..], "delphi: unknown command 'bogus' (see: delphi help)\n"),
        (&["sync"], "delphi: unknown command 'sync' (see: delphi help)\n"),
        (&["mv", "a", "b"], "delphi: unknown command 'mv' (see: delphi help)\n"),
        (&["checkout"], "delphi: usage: delphi checkout <workspace> [--as <checkout>]\n"),
        (&["checkout", "a", "b"], "delphi: too many arguments (see: delphi help)\n"),
        (&["status", "--bogus"], "delphi: unknown flag for this command: --bogus (allowed: --offline)\n"),
        (&["diff", "--dry-run"], "delphi: unknown flag for this command: --dry-run (allowed: --upstream --offline)\n"),
        (&["checkout", "argos-dev", "--as"], "delphi: --as needs a value\n"),
        (&["checkout", "argos-dev", "--as", "Bad/Name"], "delphi: invalid checkout name: 'Bad/Name'\n"),
        (&["checkout", "nope"], "delphi: no workspace named 'nope' on origin/main (see: delphi list)\n"),
        (&["create", "software"], "delphi: usage: delphi create <scope> <name> [--from <dir>]\n"),
        (&["create", "software", "Bad"], "delphi: invalid workspace name: 'Bad' (use a-z, 0-9, -)\n"),
        (&["split", "x"], "delphi: usage: delphi split [--check] [--push]\n"),
        (&["propose", "--branch", "nope", "--dry-run"], "delphi: no such branch: nope (push it to origin)\n"),
        (&["propose", "a", "b"], "delphi: too many arguments (see: delphi help)\n"),
        (&["check", "extra"], "delphi: usage: delphi check\n"),
        (&["list", "x"], "delphi: usage: delphi list\n"),
    ] {
        let r = sb.d(&sb.dir, args);
        assert_eq!((r.code, r.stderr.as_str()), (1, err), "{args:?}");
    }
    let r = sb.d(&sb.dir, &["refresh", "missing"]);
    assert_eq!(r.code, 1);
    assert!(r.stderr.starts_with("delphi: not a Delphi checkout: "), "{}", r.stderr);
    let r = sb.d(&sb.dir, &["propose", "--dry-run"]);
    assert!(r.stderr.starts_with("delphi: no checkouts in "), "{}", r.stderr);
    sb.assert_cleaned_up();
}

#[test]
fn split_roots_each_workspace_deterministically() {
    let sb = Sb::new("split");
    let root = sb.root();
    // the sandbox build pushed ws/* for both workspaces
    let files = sb.git(&root, &["ls-tree", "-r", "--name-only", "origin/ws/argos-dev"]);
    assert_eq!(
        lines(&files),
        [
            ".claude/skills/open-pr/SKILL.md",
            ".claude/skills/run-tests/scripts/run.sh",
            "CLAUDE.md",
            "docs/guide.md",
            "workspace.yml"
        ]
    );
    let tree = |r: &str| sb.git(&root, &["rev-parse", r]);
    assert_eq!(tree("origin/ws/argos-dev^{tree}"), tree(&format!("origin/main:{AD}")));
    assert_eq!(tree("origin/ws/nero-dev^{tree}"), tree(&format!("origin/main:{ND}")));
    // the commit outside the workspaces is skipped; author and message are kept
    assert_eq!(sb.git(&root, &["log", "--format=%an|%s", "origin/ws/argos-dev"]), "Sandbox|sandbox: workspaces");

    // deterministic: another run (another clone) gives the same commits; --check agrees
    let before = sb.git(&root, &["ls-remote", "--heads", "origin", "ws/*"]);
    let r = sb.ci_split();
    let ws = |r: &str| sb.git(&root, &["rev-parse", r]);
    let a = ws("origin/ws/argos-dev");
    assert!(r.stdout.contains(&format!("{a} ws/argos-dev\n")), "{}", r.stdout);
    assert_eq!(sb.git(&root, &["ls-remote", "--heads", "origin", "ws/*"]), before);
    let r = sb.ok(&root, &["split", "--check"]);
    assert_eq!(r.stderr, "split: ok\n");
    if sb.sh(&root, "git subtree --help >/dev/null 2>&1 && echo yes || true").contains("yes") {
        assert_eq!(sb.git(&root, &["subtree", "split", "-q", &format!("--prefix={AD}"), "HEAD"]), a);
    }

    // incremental: a new main commit in one folder adds one commit on top of its branch only
    let n = ws("origin/ws/nero-dev");
    sb.upstream("Argos: more docs", &format!("echo more >> {AD}/docs/guide.md"));
    sb.git(&root, &["fetch", "-q", "origin"]);
    assert_eq!(ws("origin/ws/argos-dev^"), a);
    assert_eq!(sb.git(&root, &["log", "-1", "--format=%an|%s", "origin/ws/argos-dev"]), "Alice|Argos: more docs");
    assert_eq!(ws("origin/ws/nero-dev"), n);

    // the local refs are now stale
    sb.git(&root, &["pull", "-q", "--no-rebase", "origin", "main"]);
    let r = sb.d(&root, &["split", "--check"]);
    assert_eq!((r.code, r.stderr.as_str()), (1, "split: ws/argos-dev is out of date (run: delphi split)\n"));
    let r = sb.ok(&root, &["split"]);
    assert_eq!(r.stdout, format!("{} ws/argos-dev\n{n} ws/nero-dev\n", ws("origin/ws/argos-dev")));
    sb.ok(&root, &["split", "--check"]);

    // a removed workspace loses its branch (with --push)
    sb.upstream("Remove nero-dev", &format!("git rm -rq {ND}"));
    assert!(!sb.git(&root, &["ls-remote", "--heads", "origin"]).contains("ws/nero-dev"));
    sb.git(&root, &["pull", "-q", "--no-rebase", "origin", "main"]);
    let r = sb.ok(&root, &["split"]);
    assert!(r.stdout.ends_with("deleted ws/nero-dev\n"), "{}", r.stdout);
    sb.ok(&root, &["split", "--check"]);
}

#[test]
fn checkout_roots_the_workspace_on_an_edit_branch() {
    let sb = Sb::new("co");
    let r = sb.d(&sb.dir, &["checkout", "argos-dev"]);
    assert_eq!(r.code, 0, "{r:#?}");
    let co = sb.co("argos-dev");
    assert_eq!(
        r.stderr,
        format!(
            "cloning argos…\ncheckout ready: {} (branch edit/tester/argos-dev)\nnext: delphi open argos-dev\n",
            co.display()
        )
    );
    let files = sb.sh(&co, "find . -path ./.git -prune -o -path ./repos -prune -o -type f -print | sort");
    assert_eq!(
        lines(&files),
        [
            "./.claude/skills/open-pr/SKILL.md",
            "./.claude/skills/run-tests/scripts/run.sh",
            "./CLAUDE.md",
            "./docs/guide.md",
            "./workspace.yml"
        ]
    );
    assert!(exec(&co.join(".claude/skills/run-tests/scripts/run.sh")));
    assert_eq!(sb.git(&co, &["rev-parse", "--abbrev-ref", "HEAD"]), "edit/tester/argos-dev");
    assert_eq!(sb.git(&co, &["rev-parse", "--abbrev-ref", "@{upstream}"]), "origin/ws/argos-dev");
    assert_eq!(
        sb.git(&co, &["branch", "-a", "--format=%(refname:short)"]),
        "edit/tester/argos-dev\norigin/ws/argos-dev"
    );
    assert!(co.join("repos/argos/README.md").is_file());
    assert_eq!(sb.git(&co, &["status", "--porcelain"]), "");
    assert!(sb.read(&co.join(".git/info/exclude")).ends_with("/repos/\n/.claude/settings.local.json\n"));
    assert!(exec(&co.join(".git/hooks/commit-msg")));
    assert_eq!(sb.read(&co.join(".git/delphi/meta")), "workspace=argos-dev\nproposed=\n");

    // the hook adds provenance trailers from the environment
    sb.edit(&co, "echo more >> docs/guide.md");
    assert_eq!(
        sb.git(&co, &["log", "-1", "--format=%(trailers)"]),
        "Delphi-Harness: sandbox\nDelphi-Model: sandbox-model\nDelphi-Effort: low"
    );

    let r = sb.d(&sb.dir, &["checkout", "argos-dev"]);
    assert_eq!((r.code, r.stderr), (1, format!("delphi: checkout already exists: {}\n", co.display())));
    let two = sb.checkout("argos-dev", "two");
    assert_eq!(sb.git(&two, &["rev-parse", "--abbrev-ref", "HEAD"]), "edit/tester/two");
    sb.assert_cleaned_up();
}

#[test]
fn refresh_merges_the_workspace_branch_and_exits_2_on_conflicts() {
    let sb = Sb::new("refresh");
    let co = sb.checkout("nero-dev", "n");
    let r = sb.ok(&sb.dir, &["refresh", "n"]);
    assert_eq!(r.stderr, "n: up to date with origin/ws/nero-dev\n");

    sb.upstream("Nero: skill", &format!("echo 'Then report.' >> {ND}/.claude/skills/run-tests/SKILL.md"));
    sb.edit(&co, "echo mine >> CLAUDE.md");
    let r = sb.ok(&co, &["refresh"]);
    assert!(r.stderr.starts_with("n: merged origin/ws/nero-dev ("), "{}", r.stderr);
    assert!(r.stderr.ends_with(")\n  updated .claude/skills/run-tests/SKILL.md\n"), "{}", r.stderr);
    assert!(sb.read(&co.join(".claude/skills/run-tests/SKILL.md")).ends_with("Then report.\n"));

    sb.upstream("Nero: firmware", &format!("sed -i 's/dashboard/display/' {ND}/CLAUDE.md"));
    sb.edit(&co, "sed -i 's/dashboard/steering/' CLAUDE.md");
    let r = sb.d(&co, &["refresh"]);
    assert_eq!(r.code, 2, "{r:#?}");
    assert_eq!(
        r.stderr,
        format!(
            "conflicts in n:\n  CLAUDE.md\nresolve them with git in {}, commit, then re-run: delphi refresh n\n",
            co.display()
        )
    );
    let r = sb.d(&co, &["refresh"]);
    assert_eq!(r.code, 1);
    assert!(r.stderr.starts_with("delphi: merge in progress in "), "{}", r.stderr);
}

#[test]
fn diff_shows_own_changes_and_upstream_authors() {
    let sb = Sb::new("diff");
    let co = sb.checkout("argos-dev", "a");
    let r = sb.ok(&co, &["diff"]);
    assert_eq!((r.stdout.as_str(), r.stderr.as_str()), ("", "a: no changes vs origin/ws/argos-dev\n"));
    sb.edit(&co, "echo x >> docs/guide.md && echo n > notes.md");
    sb.upstream("Up: open-pr", &format!("echo up >> {AD}/.claude/skills/open-pr/SKILL.md"));
    sb.write(&co.join("CLAUDE.md"), "uncommitted\n");
    let r = sb.ok(&co, &["diff"]);
    assert_eq!(r.stdout, "  M docs/guide.md\n  A notes.md\n");
    assert!(r.stderr.contains("uncommitted changes in"), "{}", r.stderr);
    let r = sb.ok(&co, &["diff", "--upstream"]);
    assert_eq!(r.stdout, "  M .claude/skills/open-pr/SKILL.md  (Alice: Up: open-pr)\n");
}

#[test]
fn propose_dry_run_then_push_opens_one_pr_to_main() {
    let sb = Sb::new("propose");
    let co = sb.checkout("argos-dev", "a");
    let bin: Vec<u8> = (0..=255u8).chain(0..=255u8).collect();
    fs::write(co.join("docs/logo.bin"), &bin).unwrap();
    sb.edit(
        &co,
        "echo 'Line three.' >> docs/guide.md && chmod +x CLAUDE.md && git rm -q .claude/skills/open-pr/SKILL.md",
    );
    let pb = "propose/tester/argos-dev-edit-tester-a";

    let r = sb.ok(&co, &["propose", "--dry-run"]);
    let src = sb.git(&co, &["rev-parse", "--short=7", "HEAD"]);
    let base = sb.git(&co, &["rev-parse", "--short=7", "origin/ws/argos-dev"]);
    assert_eq!(
        r.stdout,
        format!(
            "---- delphi: argos-dev: changes from edit/tester/a (to {pb})\n\
             Changes to `{AD}` from branch `edit/tester/a` ({src}, based on `ws/argos-dev` {base}):\n\n\
             - D `.claude/skills/open-pr/SKILL.md`\n- M `CLAUDE.md`\n- M `docs/guide.md`\n- A `docs/logo.bin`\n----\n"
        )
    );
    assert_eq!(sb.gh_log(), "");
    assert!(!sb.git(&sb.root(), &["ls-remote", "--heads", "origin"]).contains("propose/"));

    let r = sb.ok(&co, &["propose", "--yes"]);
    assert_eq!(r.stdout, format!("https://github.invalid/pr/1\n{pb}\n"));
    let root = sb.root();
    sb.git(&root, &["fetch", "-q", "origin"]);
    let b = format!("origin/{pb}");
    assert_eq!(sb.git(&root, &["rev-parse", &format!("{b}^")]), sb.git(&root, &["rev-parse", "origin/main"]));
    assert_eq!(
        sb.git(&root, &["diff", "--name-status", "origin/main", &b]),
        format!(
            "D\t{AD}/.claude/skills/open-pr/SKILL.md\nM\t{AD}/CLAUDE.md\nM\t{AD}/docs/guide.md\nA\t{AD}/docs/logo.bin"
        )
    );
    let blob = |rev: &str| sb.git(&root, &["rev-parse", rev]);
    assert_eq!(blob(&format!("{b}:{AD}/docs/logo.bin")), sb.git(&co, &["rev-parse", "HEAD:docs/logo.bin"]));
    assert!(sb.git(&root, &["ls-tree", &b, &format!("{AD}/CLAUDE.md")]).starts_with("100755 "));
    let full = sb.git(&co, &["rev-parse", "HEAD"]);
    let msg = sb.git(&root, &["log", "-1", "--format=%B", &b]);
    assert!(
        msg.starts_with(&format!(
            "delphi: argos-dev: changes from edit/tester/a\n\nSource branch: edit/tester/a ({full})\n"
        )),
        "{msg}"
    );
    assert!(
        msg.ends_with(&format!(
            "Delphi-Harness: sandbox\nDelphi-Model: sandbox-model\nDelphi-Effort: low\nDelphi-Workspace: {AD}"
        )),
        "{msg}"
    );
    let log = sb.gh_log();
    assert!(log.contains(&format!("gh pr create --head {pb} --base main --title delphi: argos-dev: changes from edit/tester/a --body Changes to `{AD}`")), "{log}");
    assert!(log.contains("| sandbox | sandbox-model | low |"), "{log}");
    let pushed = sb.git(&root, &["rev-parse", &b]);
    assert_eq!(
        sb.read(&co.join(".git/delphi/meta")),
        format!("workspace=argos-dev\nproposed={full}\npushed={pushed}\n")
    );
    let r = sb.ok(&sb.dir, &["status"]);
    assert!(r.stdout.ends_with("a                argos-dev        no    0     0      delphi open a\n"), "{}", r.stdout);

    // proposing again updates the same PR (the branch is rebuilt on main; the lease holds)
    sb.edit(&co, "echo 'Line four.' >> docs/guide.md");
    let r = sb.ok(&sb.dir, &["status"]);
    assert!(
        r.stdout.ends_with("a                argos-dev        no    1     0      delphi propose a\n"),
        "{}",
        r.stdout
    );
    let r = sb.ok(&co, &["propose", "--yes"]);
    assert_eq!(r.stdout, format!("{pb}\n"));
    assert!(r.stderr.contains("Updated PR #1"), "{}", r.stderr);
    assert!(sb.gh_log().contains("gh pr edit 1 --title"));
    sb.git(&root, &["fetch", "-q", "origin"]);
    assert!(sb.git(&root, &["show", &format!("{b}:{AD}/docs/guide.md")]).ends_with("Line three.\nLine four."));

    // someone else pushed to the propose branch: the lease refuses
    sb.sh(&sb.up(), &format!("git fetch -q origin && git push -q origin origin/main:refs/heads/{pb} --force"));
    sb.edit(&co, "echo 'Line five.' >> docs/guide.md");
    let r = sb.d(&co, &["propose", "--yes"]);
    assert_eq!(r.code, 1, "{r:#?}");
    assert!(r.stderr.contains(&format!("delphi: {pb} changed on origin meanwhile")), "{}", r.stderr);
    sb.assert_cleaned_up();
}

#[test]
fn propose_reports_conflicts_with_main_and_pushes_nothing() {
    let sb = Sb::new("conflict");
    let co = sb.checkout("argos-dev", "a");
    sb.edit(&co, "sed -i 's/Line one./Line uno./' docs/guide.md");
    sb.upstream("Up: guide", &format!("sed -i 's/Line one./Line 1./' {AD}/docs/guide.md"));
    for args in [&["propose", "--dry-run"][..], &["propose", "--yes"]] {
        let r = sb.d(&co, args);
        assert_eq!(r.code, 1, "{r:#?}");
        assert_eq!(
            r.stderr,
            "propose: conflicts with changes on main (nothing proposed):\n  docs/guide.md\n\
             merge the latest ws/argos-dev into your branch (delphi refresh), resolve, commit, then re-run\n"
        );
    }
    assert_eq!(sb.gh_log(), "");
    assert!(!sb.git(&sb.root(), &["ls-remote", "--heads", "origin"]).contains("propose/"));
    // refresh shows the same conflict with git's tools
    assert_eq!(sb.d(&co, &["refresh"]).code, 2);
    sb.assert_cleaned_up();
}

#[test]
fn after_the_main_pr_merges_refresh_is_a_clean_merge() {
    let sb = Sb::new("roundtrip");
    let co = sb.checkout("argos-dev", "a");
    sb.edit(&co, "sed -i 's/Line two./Line 2./' docs/guide.md && echo n > notes.md");
    let pb = sb.ok(&co, &["propose", "--yes"]).stdout.lines().last().unwrap().to_string();
    // meanwhile main changes the folder elsewhere, then the PR merges and CI re-splits
    sb.upstream("Up: claude", &format!("echo up >> {AD}/CLAUDE.md"));
    sb.sh(
        &sb.up(),
        &format!("git fetch -q origin && git merge -q --no-edit origin/{pb} && git push -q origin HEAD:main"),
    );
    sb.ci_split();
    let r = sb.ok(&co, &["refresh"]);
    assert!(r.stderr.starts_with("a: merged origin/ws/argos-dev"), "{}", r.stderr);
    assert_eq!(sb.git(&co, &["diff", "HEAD", "origin/ws/argos-dev"]), "");
    let r = sb.ok(&sb.dir, &["status"]);
    assert!(r.stdout.ends_with("a                argos-dev        no    0     0      delphi open a\n"), "{}", r.stdout);
    let r = sb.ok(&co, &["propose", "--yes"]);
    assert!(r.stderr.contains("nothing to propose"), "{}", r.stderr);
}

#[test]
fn propose_branch_mirrors_a_plain_git_branch() {
    let sb = Sb::new("branch");
    // an agent without the CLI: clone ws/argos-dev, branch, edit, push
    let agent = sb.dir.join("agent");
    sb.git(&sb.dir, &["clone", "-q", "-b", "ws/argos-dev", "origin.git", "agent"]);
    sb.sh(
        &agent,
        "git switch -qc fix-docs && echo 'Agent line.' >> docs/guide.md && git commit -qam 'Fix docs' \
         --trailer 'Delphi-Harness: agent-x' --trailer 'Delphi-Model: m9' --trailer 'Delphi-Effort: high' && git push -q origin fix-docs",
    );
    let env = [("DELPHI_USER", "github-actions"), ("DELPHI_HARNESS", "github-actions")];
    let args = ["propose", "--branch", "fix-docs", "--yes", "--model", "none", "--effort", "none"];
    let r = sb.d_env(&sb.dir, &args, &env);
    assert_eq!(r.code, 0, "{r:#?}");
    let pb = "propose/github-actions/argos-dev-fix-docs";
    assert_eq!(r.stdout, format!("https://github.invalid/pr/1\n{pb}\n"));
    let root = sb.root();
    sb.git(&root, &["fetch", "-q", "origin"]);
    assert_eq!(
        sb.git(&root, &["diff", "--name-only", "origin/main", &format!("origin/{pb}")]),
        format!("{AD}/docs/guide.md")
    );
    let t = sb.git(&root, &["log", "-1", "--format=%(trailers)", &format!("origin/{pb}")]);
    assert_eq!(
        t,
        format!("Delphi-Harness: github-actions\nDelphi-Model: none\nDelphi-Effort: none\nDelphi-Workspace: {AD}")
    );
    let log = sb.gh_log();
    assert!(log.contains("| github-actions | none | none |\n| agent-x | m9 | high |"), "{log}");

    // naming the workspace works too; a branch of another workspace's history does not
    let r = sb.d_env(&sb.dir, &["propose", "argos-dev", "--branch", "fix-docs", "--dry-run"], &env);
    assert_eq!(r.code, 0, "{r:#?}");
    let r = sb.d_env(&sb.dir, &["propose", "nero-dev", "--branch", "fix-docs", "--dry-run"], &env);
    assert_eq!(r.code, 1);
    assert!(r.stderr.contains("fix-docs shares no history with origin/ws/nero-dev"), "{}", r.stderr);
    sb.assert_cleaned_up();
}

/// The mirror job's script from the CI workflow, run in a clone of main like CI's checkout.
#[test]
fn ci_mirror_script_proposes_and_links_the_main_pr() {
    let sb = Sb::new("mirror");
    let agent = sb.dir.join("agent");
    sb.git(&sb.dir, &["clone", "-q", "-b", "ws/argos-dev", "origin.git", "agent"]);
    sb.sh(&agent, "git switch -qc fix && echo x >> CLAUDE.md && git commit -qam Fix && git push -q origin fix");
    let yml = fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join(".github/workflows/delphi.yml")).unwrap();
    let block = yml.rsplit("        run: |\n").next().unwrap();
    let script: String = block.lines().map(|l| format!("{}\n", l.strip_prefix("          ").unwrap_or(l))).collect();
    let up = sb.up();
    fs::create_dir_all(up.join("target/release")).unwrap();
    std::os::unix::fs::symlink(env!("CARGO_BIN_EXE_delphi"), up.join("target/release/delphi")).unwrap();
    let env = "export HEAD_REF=fix BASE_REF=ws/argos-dev PR=7 DELPHI_USER=github-actions DELPHI_HARNESS=github-actions";
    sb.sh(&up, &format!("unset DELPHI_MODEL DELPHI_EFFORT\n{env}\n{script}"));
    let log = sb.gh_log();
    assert!(log.contains("gh pr create --head propose/github-actions/argos-dev-fix --base main"), "{log}");
    assert!(log.contains("gh pr comment 7 --edit-last --body Mirrored to https://github.invalid/pr/1\n"), "{log}");
    sb.git(&up, &["fetch", "-q", "origin"]);
    let t = sb.git(
        &up,
        &["log", "-1", "--format=%an|%(trailers:key=Delphi-Model)", "origin/propose/github-actions/argos-dev-fix"],
    );
    assert_eq!(t, "github-actions[bot]|Delphi-Model: none");
}

#[test]
fn status_lists_every_checkout() {
    let sb = Sb::new("status");
    let a = sb.checkout("argos-dev", "a");
    let n = sb.checkout("nero-dev", "n");
    sb.edit(&a, "echo x >> docs/guide.md");
    sb.sh(&n, "echo x >> CLAUDE.md");
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
fn open_shell_runs_at_the_root_with_provenance_env() {
    let sb = Sb::new("open");
    let co = sb.checkout("argos-dev", "a");
    let shell = sb.dir.join("bin/fake-shell");
    fs::write(&shell, "#!/bin/sh\necho \"$(pwd) h=$DELPHI_HARNESS m=$DELPHI_MODEL e=$DELPHI_EFFORT\"\n").unwrap();
    fs::set_permissions(&shell, fs::Permissions::from_mode(0o755)).unwrap();
    let r = sb.d_env(&sb.dir, &["open", "a", "--shell", "--model", "m1"], &[("SHELL", shell.to_str().unwrap())]);
    assert_eq!((r.code, r.stderr.as_str()), (0, ""));
    assert!(r.stdout.starts_with(&format!("{} h=claude-code", co.display())), "{}", r.stdout);
    assert!(r.stdout.ends_with(" m=m1 e=low\n"), "{}", r.stdout);
}

#[test]
fn create_from_dir_and_list() {
    let sb = Sb::new("create");
    let r = sb.ok(&sb.dir, &["list"]);
    assert_eq!(
        r.stdout,
        "argos-dev\tsoftware/application-software/argos\tclaude-code\tws/argos-dev\n\
         nero-dev\tsoftware/application-software/nero\tclaude-code\tws/nero-dev\n"
    );
    let d = sb.dir.join("tools");
    sb.write(&d.join("workspace.yml"), "name: tools-dev\nharness: claude-code\n");
    sb.write(&d.join("CLAUDE.md"), "# Tools\n");
    sb.write(&d.join(".claude/skills/lint/SKILL.md"), "---\nname: lint\ndescription: Lint.\n---\n");
    sb.write(&d.join(".claude/skills/lint/run.sh"), "#!/bin/sh\n");
    fs::set_permissions(d.join(".claude/skills/lint/run.sh"), fs::Permissions::from_mode(0o755)).unwrap();
    sb.write(&d.join("repos/x/README.md"), "not copied\n");
    sb.write(&d.join(".git/HEAD"), "not copied\n");
    let ds = d.to_str().unwrap();
    for (args, err) in [
        (&["create", "software", "other", "--from", ds, "--yes"][..], "delphi: workspace.yml: name must be 'other'\n"),
        (&["create", "nope", "tools-dev", "--from", ds, "--yes"], "delphi: not a scope on origin/main: nope\n"),
        (&["create", "software", "argos-dev", "--yes"], "delphi: workspace name already used: argos-dev\n"),
    ] {
        let r = sb.d(&sb.dir, args);
        assert_eq!((r.code, r.stderr.as_str()), (1, err), "{args:?}");
    }
    let r = sb.ok(&sb.dir, &["create", "software", "tools-dev", "--from", ds, "--yes"]);
    assert_eq!(r.stdout.lines().last(), Some("delphi/create/tools-dev"));
    let br = "origin/delphi/create/tools-dev";
    sb.git(&sb.root(), &["fetch", "-q", "origin"]);
    let w = "context/software/workspaces/tools-dev";
    assert_eq!(
        sb.git(&sb.root(), &["diff", "--name-only", "origin/main", br]),
        format!("{w}/.claude/skills/lint/SKILL.md\n{w}/.claude/skills/lint/run.sh\n{w}/CLAUDE.md\n{w}/workspace.yml")
    );
    assert!(sb.git(&sb.root(), &["ls-tree", br, &format!("{w}/.claude/skills/lint/run.sh")]).starts_with("100755"));
    assert_eq!(
        sb.git(&sb.root(), &["log", "-1", "--format=%s%n%(trailers)", br]),
        "delphi: create workspace tools-dev\nDelphi-Harness: sandbox\nDelphi-Model: sandbox-model\nDelphi-Effort: low"
    );
    assert!(sb.gh_log().contains(
        "gh pr create --head delphi/create/tools-dev --base main --title delphi: create workspace tools-dev"
    ));

    // without --from: just a workspace.yml
    sb.ok(&sb.dir, &["create", ".", "bare", "--yes"]);
    sb.git(&sb.root(), &["fetch", "-q", "origin"]);
    let br = "origin/delphi/create/bare";
    assert_eq!(
        sb.git(&sb.root(), &["diff", "--name-only", "origin/main", br]),
        "context/workspaces/bare/workspace.yml"
    );
    assert_eq!(
        sb.git(&sb.root(), &["show", &format!("{br}:context/workspaces/bare/workspace.yml")]),
        "name: bare\nharness: claude-code"
    );
    sb.assert_cleaned_up();
}

#[test]
fn check_passes_then_reports_every_failure() {
    let sb = Sb::new("check");
    let root = sb.root();
    let r = sb.ok(&root, &["check"]);
    assert_eq!(r.stderr, "check: ok\n");
    let n = root.join(ND);
    sb.write(&n.join("workspace.yml"), "name: nero\nharness: claude-code\ninstructions:\n  - x.md\n");
    sb.write(&n.join("sub/workspace.yml"), "name: sub\nharness: claude-code\n");
    sb.write(&root.join("context/software/tools/README.md"), "x\n");
    sb.write(&root.join("context/software/CLAUDE.md"), "x\n");
    sb.write(&root.join("context/software/workspaces/stray/x.md"), "x\n");
    sb.write(&root.join("context/software/workspaces/argos-dev/workspace.yml"), "name: argos-dev\nharness: vim\n");
    sb.write(
        &root.join("context/software/workspaces/nero-dev/workspace.yml"),
        "name: nero-dev\nharness: claude-code\n",
    );
    sb.write(&root.join("context/software/application-software/scope.yml"), "name: [x]\n");
    std::os::unix::fs::symlink("CLAUDE.md", root.join(AD).join("link.md")).unwrap();
    let r = sb.d(&root, &["check"]);
    assert_eq!(r.code, 1);
    let y = format!("context/{}", &ND["context/".len()..]);
    let want = format!(
        "check: context/software/tools: scope directory has no scope.yml
check: context/software/CLAUDE.md: instruction files belong in a workspace folder
check: {AD}/link.md: symlinks are not allowed
check: {y}/sub/workspace.yml: nested workspace (workspace folders never nest)
check: context/software/workspaces/stray: workspace folder has no workspace.yml
check: context/software/workspaces/argos-dev/workspace.yml: unknown harness: vim
check: context/software/application-software/scope.yml:1: unsupported YAML syntax: [x]
check: {y}/workspace.yml: name 'nero' must equal its folder 'nero-dev'
check: {y}/workspace.yml: unknown key 'instructions'
check: context/software/workspaces/nero-dev/workspace.yml: workspace name 'nero-dev' is not unique
"
    );
    let mut got = lines(&r.stderr);
    let mut exp = lines(&want);
    got.sort();
    exp.sort();
    assert_eq!(got, exp, "{}", r.stderr);
}

#[test]
fn repo_root_discovery_and_setup() {
    let sb = Sb::new("root");
    let co = sb.checkout("argos-dev", "a");
    let r = sb.d_noroot(&sb.root().join("context/software"), &["check"]);
    assert_eq!(r.code, 0, "{r:#?}");
    // inside a checkout (no delphi.conf), nothing recorded
    let r = sb.d_noroot(&co, &["diff"]);
    assert_eq!(r.code, 1);
    assert!(r.stderr.starts_with("delphi: cannot find the Delphi repo"), "{}", r.stderr);
    let r = sb.d_noroot(&sb.root(), &["setup"]);
    assert_eq!(r.code, 0, "{r:#?}");
    assert_eq!(sb.read(&sb.dir.join("home/.config/delphi/root")), format!("{}\n", sb.root().display()));
    let r = sb.d_noroot(&co, &["diff"]);
    assert_eq!((r.code, r.stderr.as_str()), (0, "a: no changes vs origin/ws/argos-dev\n"));
    let r = sb.d_noroot(&co.join("repos/argos"), &["status"]);
    assert_eq!(r.code, 0);
    let r = sb.d_noroot(&sb.dir, &["setup", "/nonexistent"]);
    assert_eq!(r.code, 1);
    sb.assert_cleaned_up();
}

#[test]
fn offline_tolerance() {
    let sb = Sb::new("offline");
    let co = sb.checkout("argos-dev", "a");
    sb.edit(&co, "echo x >> docs/guide.md");
    fs::rename(sb.dir.join("origin.git"), sb.dir.join("gone.git")).unwrap();
    let r = sb.ok(&co, &["diff"]);
    assert_eq!(r.stdout, "  M docs/guide.md\n");
    assert!(r.stderr.contains("warning: git fetch failed in a; using local refs"), "{}", r.stderr);
    let r = sb.ok(&sb.dir, &["status"]);
    assert!(r.stdout.contains("\na "), "{}", r.stdout);
    let r = sb.d_env(&co, &["diff"], &[("DELPHI_OFFLINE", "1")]);
    assert_eq!((r.code, r.stderr.as_str()), (0, ""));
    let r = sb.ok(&sb.dir, &["list"]);
    assert!(r.stderr.contains("git fetch failed; using local refs"), "{}", r.stderr);
    assert!(r.stdout.starts_with("argos-dev\t"));
    let r = sb.ok(&co, &["propose", "--dry-run", "--offline"]);
    assert!(r.stdout.contains("- M `docs/guide.md`"), "{}", r.stdout);
    sb.ok(&sb.root(), &["split", "--check"]);
    sb.ok(&sb.root(), &["check"]);
    sb.assert_cleaned_up();
}
