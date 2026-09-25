//! End-to-end tests of the Rust CLI in a sandbox, asserting parity with the bash CLI where it is
//! available (same sandbox, same commands, identical output).

mod common;

use common::{same, Out, Sb, BLOCKS, LAYOUT};
use std::fs;
use std::os::unix::fs::PermissionsExt;

/// Create a workspace with the Rust CLI (and, when possible, a sibling one with bash).
fn new_pair(sb: &Sb) -> (Out, Option<Out>) {
    let r = sb.rust(&sb.dir, &["workspace", "new", "argos-dev", "--as", "ws-rust"]);
    assert_eq!(r.code, 0, "{r:#?}");
    let b = sb.bash(&sb.dir, &["workspace", "new", "argos-dev", "--as", "ws-bash"]);
    (r, b)
}

fn norm(o: &Option<Out>) -> Option<Out> {
    o.as_ref().map(|o| o.norm("ws-bash", "ws-rust"))
}

/// The same edits in a workspace, committed.
fn edit(sb: &Sb, ws: &str, script: &str) {
    sb.sh(&sb.ws(ws), &format!("{script}\ngit add -A\ngit commit -qm edits"));
}

const EDITS: &str = r#"
A=context/software/application-software/argos/blocks
sed -i.bak 's/Line two./Line two, edited./' $A/overview.md && rm $A/overview.md.bak
printf '# New block\n\nFresh.\n' > $A/new.md
mkdir -p docs && printf '# Guide\n' > docs/guide.md
printf 'notes\n' > .claude/skills/run-tests/notes.md
mkdir -p .claude/skills/lint && printf -- '---\nname: lint\ndescription: Lint.\n---\n' > .claude/skills/lint/SKILL.md
printf 'Appended line.\n\n## Deploying\n\nUse the pipeline.\n' >> CLAUDE.md
"#;

#[test]
fn usage_and_argument_errors_match_bash() {
    let sb = Sb::new("args");
    // parity checks only skip when the bash CLI has been removed from the repo
    let bash_present = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("lib/core.sh").exists();
    assert_eq!(sb.has_bash(), bash_present && std::path::Path::new("/bin/bash").exists());
    let r = sb.rust(&sb.dir, &[]);
    assert_eq!(r.code, 0);
    assert!(r.stdout.starts_with("usage: delphi <command> [args]"));
    for args in [
        &["bogus"][..],
        &["ws", "frob"],
        &["ws", "new"],
        &["ws", "new", "a", "b"],
        &["ws", "status", "--bogus"],
        &["ws", "status", "extra"],
        &["ws", "new", "argos-dev", "--as"],
        &["ws", "new", "Bad_Name!"],
        &["ws", "new", "nope"],
        &["ws", "refresh", "missing"],
        &["layout"],
        &["layout", "list", "--yes"],
        &["layout", "new", "software", "Bad"],
        &["block", "mv", "a"],
        &["block", "mv", "a/x", "b/y", "--yes"],
        &["check", "extra"],
    ] {
        let r = sb.rust(&sb.dir, args);
        assert_ne!(r.code, 0, "{args:?}");
        same(&r, &sb.bash(&sb.dir, args));
    }
    sb.assert_cleaned_up();
}

#[test]
fn workspace_new_compiles_like_bash() {
    let sb = Sb::new("new");
    let (r, b) = new_pair(&sb);
    let ws = sb.ws("ws-rust");
    assert_eq!(
        r.stderr,
        format!("cloning argos…\nworkspace ready: {}\nnext: delphi workspace open ws-rust\n", ws.display())
    );
    same(&r, &norm(&b));

    // compile output
    let claude = fs::read_to_string(ws.join("CLAUDE.md")).unwrap();
    assert_eq!(
        claude,
        "<!-- Compiled by Delphi from layout 'argos-dev'. Edit freely: every line is traced to its source block. -->\n\
         <!-- When your work is done, commit it; 'delphi workspace propose' sends block changes upstream. -->\n\n\
         # Software conventions\n\n- Use conventional commits.\n- Open PRs against develop.\n\n\
         # Argos\n\nArgos is the telemetry dashboard.\nIt has an Angular client and a Rust server.\n"
    );
    let mf_sha = sb.git(&sb.root(), &["hash-object", &format!("context/{LAYOUT}/manifest.yml")]);
    let lock = fs::read_to_string(ws.join(".delphi/lock.tsv")).unwrap();
    let expect = format!(
        "# output\tstart\tend\tsource\tsha
CLAUDE.md\t1\t2\t@gen:delphi\t-
CLAUDE.md\t3\t3\t@glue\t-
CLAUDE.md\t4\t7\tsoftware/harness/instructions/base.md\te15e9d20225a14a4537a670898ae51ad85f164c2
CLAUDE.md\t8\t8\t@glue\t-
CLAUDE.md\t9\t12\tsoftware/application-software/argos/harness/instructions/argos.md\t1e293bae4c5fc02f774bacc6dccf4196f5f62e5f
context/software/application-software/argos/blocks/overview.md\t1\t5\tsoftware/application-software/argos/blocks/overview.md\te9c980c2f329f7398d66b9895521c1f2abcbb0f1
context/software/application-software/argos/blocks/testing.md\t1\t4\tsoftware/application-software/argos/blocks/testing.md\tc95bcf63822f0a48402ba742eff5a7603edeb698
.claude/skills/run-tests/SKILL.md\t1\t6\tsoftware/application-software/argos/harness/skills/run-tests/SKILL.md\ta5bd6b06d122106ef62bda5994102db63ef017b0
.claude/skills/run-tests/scripts/run.sh\t1\t2\tsoftware/application-software/argos/harness/skills/run-tests/scripts/run.sh\t329015816566c2f78499d85ca721636166cc0c2a
.claude/skills/triage/SKILL.md\t1\t4\t@gen:software/application-software/argos/harness/skills/triage.skill\t-
.claude/skills/triage/SKILL.md\t5\t5\t@glue\t-
.claude/skills/triage/SKILL.md\t6\t9\tsoftware/application-software/argos/blocks/testing.md\tc95bcf63822f0a48402ba742eff5a7603edeb698
.mcp.json\t1\t1\t@gen:delphi\t-
.mcp.json\t2\t5\tsoftware/harness/mcp/github.json\t2457b9f5b11fc333819bd215d2031dc9391f6219
.mcp.json\t6\t6\t@gen:delphi\t-
.delphi/manifest.yml\t1\t14\t{LAYOUT}/manifest.yml\t{mf_sha}
"
    );
    assert_eq!(lock, expect);
    let tree = sb.git(&ws, &["ls-tree", "-r", "generated", ".claude/skills/run-tests/scripts/run.sh"]);
    assert!(tree.starts_with("100755 "), "{tree}");

    // refs, meta, git plumbing
    let head = sb.git(&ws, &["rev-parse", "--abbrev-ref", "HEAD"]);
    assert_eq!(head, "working");
    assert_eq!(sb.git(&ws, &["rev-parse", "generated"]), sb.git(&ws, &["rev-parse", "generated-merged^{commit}"]));
    let msg = sb.git(&ws, &["log", "-1", "--format=%B", "generated"]);
    let c = sb.git(&sb.root(), &["rev-parse", "origin/main"]);
    assert_eq!(msg, format!("delphi: compile argos-dev@{}\n\nDelphi-Compile: {c}", &c[..7]));
    let meta = fs::read_to_string(ws.join(".git/delphi/meta")).unwrap();
    let meta: Vec<&str> = meta.lines().filter(|l| !l.starts_with("created=")).collect();
    assert_eq!(
        meta,
        [
            "layout=argos-dev".to_string(),
            format!("layout_path={LAYOUT}"),
            "ref=main".into(),
            "harness=claude-code".into(),
            "last_proposed=".into(),
            "last_proposed_hash=".into(),
            "pending_since=".into(),
            format!("compile_commit={c}"),
        ]
    );
    let exclude = fs::read_to_string(ws.join(".git/info/exclude")).unwrap();
    assert!(exclude.ends_with("repos/\nworktrees/\n.claude/settings.local.json\n"));
    let hook = fs::metadata(ws.join(".git/hooks/commit-msg")).unwrap();
    assert_eq!(hook.permissions().mode() & 0o111, 0o111);
    assert!(ws.join("repos/argos/README.md").is_file());

    // byte-for-byte parity with the bash compile (same Delphi commit -> same tree hash)
    if b.is_some() {
        let wb = sb.ws("ws-bash");
        assert_eq!(sb.git(&ws, &["rev-parse", "generated^{tree}"]), sb.git(&wb, &["rev-parse", "generated^{tree}"]));
        assert_eq!(
            fs::read(ws.join(".git/hooks/commit-msg")).unwrap(),
            fs::read(wb.join(".git/hooks/commit-msg")).unwrap()
        );
        assert_eq!(exclude, fs::read_to_string(wb.join(".git/info/exclude")).unwrap());
    }

    let again = sb.rust(&sb.dir, &["workspace", "new", "argos-dev", "--as", "ws-rust"]);
    assert_eq!(again.code, 1);
    assert_eq!(again.stderr, format!("delphi: workspace already exists: {}\n", ws.display()));
    sb.assert_cleaned_up();
}

#[test]
fn refresh_merges_conflicts_and_finalizes() {
    let sb = Sb::new("refresh");
    let (_, b) = new_pair(&sb);
    let names: &[&str] = if b.is_some() { &["ws-rust", "ws-bash"] } else { &["ws-rust"] };
    let step = |args: &[&str]| -> (Out, Option<Out>) {
        let r = sb.rust(&sb.dir, &[args, &["ws-rust"]].concat());
        let b = sb.bash(&sb.dir, &[args, &["ws-bash"]].concat());
        (r, norm(&b))
    };

    // up to date
    let (r, b) = step(&["workspace", "refresh"]);
    assert_eq!((r.code, r.stderr.as_str()), (0, "ws-rust: up to date with origin/main\n"));
    same(&r, &b);

    // upstream change merges cleanly
    sb.upstream("printf -- '- Squash on merge.\\n' >> context/software/harness/instructions/base.md");
    let (r, b) = step(&["workspace", "refresh"]);
    let c = sb.git(&sb.root(), &["rev-parse", "--short=7", "origin/main"]);
    assert_eq!((r.code, r.stderr.clone()), (0, format!("ws-rust: merged compile of origin/main ({c})\n")));
    same(&r, &b);
    assert!(fs::read_to_string(sb.ws("ws-rust").join("CLAUDE.md")).unwrap().contains("- Squash on merge.\n"));

    // conflicting edits: exit 2, then "merge in progress", then resolve and re-run
    for n in names {
        edit(&sb, n, "sed -i.bak 's/^- Use conventional commits.$/- Use conventional commits (ws)./' CLAUDE.md && rm CLAUDE.md.bak");
    }
    sb.upstream("sed -i.bak 's/^- Use conventional commits.$/- Use gitmoji./' context/software/harness/instructions/base.md && rm context/software/harness/instructions/base.md.bak");
    let (r, b) = step(&["workspace", "refresh"]);
    assert_eq!(r.code, 2, "{r:#?}");
    assert_eq!(
        r.stderr,
        "conflicts in ws-rust:\n  CLAUDE.md\nresolve them, commit, then re-run: delphi workspace refresh ws-rust\n"
    );
    same(&r, &b);
    let (r, b) = step(&["workspace", "refresh"]);
    assert_eq!(r.code, 1);
    assert!(r.stderr.contains("merge in progress in"), "{}", r.stderr);
    same(&r, &b);
    for n in names {
        sb.sh(&sb.ws(n), "git checkout --ours CLAUDE.md && git add CLAUDE.md && git commit -q --no-edit");
    }
    // the re-run finalizes the merge, then finds the compile current
    let (r, b) = step(&["workspace", "refresh"]);
    let c = sb.git(&sb.root(), &["rev-parse", "--short=7", "origin/main"]);
    let want = format!("ws-rust: merged compile of origin/main ({c})\nws-rust: up to date with origin/main\n");
    assert_eq!((r.code, r.stderr.clone()), (0, want));
    same(&r, &b);
    let ws = sb.ws("ws-rust");
    assert_eq!(sb.git(&ws, &["rev-parse", "generated"]), sb.git(&ws, &["rev-parse", "generated-merged^{commit}"]));
    let (r, b) = step(&["workspace", "refresh"]);
    assert_eq!((r.code, r.stderr.as_str()), (0, "ws-rust: up to date with origin/main\n"));
    same(&r, &b);

    // status agrees with bash (both workspaces listed)
    let r = sb.rust(&sb.dir, &["ws", "status"]);
    assert!(r.stdout.contains("ws-rust                argos-dev        main     no    unproposed 0d    no     delphi ws propose ws-rust\n"), "{}", r.stdout);
    same(&r, &sb.bash(&sb.dir, &["ws", "status"]));
    sb.assert_cleaned_up();
}

#[test]
fn propose_dry_run_plans_every_kind_of_edit() {
    let sb = Sb::new("dry");
    sb.rust(&sb.dir, &["workspace", "new", "argos-dev", "--as", "ws-rust"]);
    edit(&sb, "ws-rust", &format!(
        "{EDITS}\ngit rm -q {BLOCKS}/testing.md\n\
         sed -i.bak 's/^description: Triage a failing Argos test./description: Triage failing tests./' .claude/skills/triage/SKILL.md && rm .claude/skills/triage/SKILL.md.bak"
    ));
    let ws = sb.ws("ws-rust");
    let r = sb.rust(&ws, &["ws", "propose", "--dry-run"]);
    let a = "software/application-software/argos";
    let expect = format!(
        "  new       .claude/skills/lint/SKILL.md -> {a}/harness/skills/lint/SKILL.md
  new       .claude/skills/run-tests/notes.md -> {a}/harness/skills/run-tests/notes.md
  key       .claude/skills/triage/SKILL.md -> {a}/harness/skills/triage.skill
  patch     CLAUDE.md -> {a}/harness/instructions/argos.md
  fragment  CLAUDE.md -> {a}/harness/instructions/deploying.md
  new       context/{a}/blocks/new.md -> {a}/blocks/new.md
  patch     context/{a}/blocks/overview.md -> {a}/blocks/overview.md
  new       docs/guide.md -> {a}/docs/guide.md
Unresolved:
#### `context/{a}/blocks/testing.md`: deleted, but still compiled by .delphi/manifest.yml (drop blocks by editing the manifest)

```diff
@@ -1,4 +0,0 @@
-# Testing
-
-Run `npm test` in angular-client.
-Run `cargo test` in the server.
```

"
    );
    assert_eq!((r.code, r.stdout.as_str(), r.stderr.as_str()), (0, "", expect.as_str()));
    same(&r, &sb.bash(&ws, &["ws", "propose", "--dry-run"]));

    // manifest edit + deletions whose source was dropped -> manifest + noop rows; unresolved edits
    sb.rust(&sb.dir, &["workspace", "new", "argos-dev", "--as", "ws-two"]);
    edit(
        &sb,
        "ws-two",
        &format!(
            "sed -i.bak '/run-tests$/d' .delphi/manifest.yml && rm .delphi/manifest.yml.bak\n\
         git rm -q -r .claude/skills/run-tests\n\
         printf 'x\\n' >> .delphi/lock.tsv\n\
         printf 'stray\\n' > notes.txt\n\
         printf '\\0\\1' > {BLOCKS}/blob.bin\n\
         sed -i.bak '1s/.*/<!-- changed -->/' CLAUDE.md && rm CLAUDE.md.bak\n\
         printf 'Line zero.\\n' | cat - {BLOCKS}/overview.md > o && mv o {BLOCKS}/overview.md"
        ),
    );
    let ws2 = sb.ws("ws-two");
    let r = sb.rust(&ws2, &["ws", "propose", "--dry-run"]);
    assert_eq!(r.code, 0);
    for want in [
        format!("  manifest  .delphi/manifest.yml -> {LAYOUT}/manifest.yml\n"),
        "  noop      .claude/skills/run-tests/SKILL.md -> deleted; its source was dropped from .delphi/manifest.yml\n"
            .into(),
        "  noop      .claude/skills/run-tests/scripts/run.sh -> deleted; its source was dropped".into(),
        format!("  patch     context/{a}/blocks/overview.md -> {a}/blocks/overview.md\n"),
        "#### `CLAUDE.md` (line 1): change spans segments or touches generated/separator lines".into(),
        format!("#### `context/{a}/blocks/blob.bin`: binary file"),
        "#### `notes.txt`: new file: must be under context/<scope>/blocks/, docs/, or .claude/skills/<name>/".into(),
    ] {
        assert!(r.stderr.contains(&want), "missing {want:?} in:\n{}", r.stderr);
    }
    same(&r, &sb.bash(&ws2, &["ws", "propose", "--dry-run"]));
    sb.assert_cleaned_up();
}

#[test]
fn propose_pushes_then_merge_and_refresh_is_clean() {
    let sb = Sb::new("propose");
    let (_, b) = new_pair(&sb);
    edit(&sb, "ws-rust", EDITS);
    if b.is_some() {
        edit(&sb, "ws-bash", EDITS);
    }
    let r = sb.rust(&sb.dir, &["ws", "propose", "ws-rust", "--yes"]);
    assert_eq!(r.code, 0, "{r:#?}");
    assert!(r.stderr.starts_with("ws-rust: up to date with origin/main\n---- delphi: changes from workspace ws-rust (argos-dev)\n## Routed changes\n"));
    assert!(r.stderr.contains("\n## Unresolved\n\nNone.\n\n| Harness | Model | Effort |\n|---|---|---|\n| sandbox | sandbox-model | low |\n----\n"), "{}", r.stderr);
    assert_eq!(r.stdout, "https://github.invalid/pr/1\n");
    let root = sb.root();
    let br = "origin/delphi/propose/tester/ws-rust";
    let c = sb.git(&root, &["rev-parse", "--short=7", "origin/main"]);
    let msg = sb.git(&root, &["log", "-1", "--format=%B", br]);
    assert_eq!(
        msg,
        format!(
            "delphi: add new files from workspace ws-rust\n\nDelphi-Harness: sandbox\nDelphi-Model: sandbox-model\nDelphi-Effort: low\n\
             Delphi-Layout: {LAYOUT}\nDelphi-Workspace: ws-rust\nDelphi-Base: {c}"
        )
    );
    let subjects = sb.git(&root, &["log", "--format=%s", &format!("origin/main..{br}")]);
    assert_eq!(
        subjects,
        "delphi: add new files from workspace ws-rust\ndelphi: route block edits from workspace ws-rust"
    );
    let a = "context/software/application-software/argos";
    let frag = sb.git(&root, &["show", &format!("{br}:{a}/harness/instructions/deploying.md")]);
    assert_eq!(frag, "## Deploying\n\nUse the pipeline.");
    let manifest = sb.git(&root, &["show", &format!("{br}:{a}/layouts/argos-dev/manifest.yml")]);
    assert!(manifest.contains("  - software/application-software/argos/harness/instructions/argos.md\n  - software/application-software/argos/harness/instructions/deploying.md\n"));
    assert!(manifest.contains("  - software/application-software/argos/harness/skills/lint\n"));
    assert!(manifest.contains("docs:\n  - software/application-software/argos/docs/guide.md"));
    let gh = sb.gh_log();
    assert!(gh.contains("gh pr create --head delphi/propose/tester/ws-rust --base main --title delphi: changes from workspace ws-rust (argos-dev) --body ## Routed changes"));

    if b.is_some() {
        let bo = sb.bash(&sb.dir, &["ws", "propose", "ws-bash", "--yes"]).unwrap();
        assert_eq!(bo.code, 0, "{bo:#?}");
        let bo = bo.norm("ws-bash", "ws-rust");
        assert_eq!(r.stderr, bo.stderr);
        assert_eq!(bo.stdout, "https://github.invalid/pr/2\n");
        let bb = "origin/delphi/propose/tester/ws-bash";
        assert_eq!(
            sb.git(&root, &["rev-parse", &format!("{br}^{{tree}}")]),
            sb.git(&root, &["rev-parse", &format!("{bb}^{{tree}}")])
        );
        let bmsgs = sb.git(&root, &["log", "--format=%B", &format!("origin/main..{bb}")]).replace("ws-bash", "ws-rust");
        assert_eq!(sb.git(&root, &["log", "--format=%B", &format!("origin/main..{br}")]), bmsgs);
        let log = sb.gh_log().replace("ws-bash", "ws-rust");
        let (x, y) = log.split_at(log.len() / 2);
        assert_eq!(x, y, "gh calls differ");
        let meta = |w: &str| {
            let m = fs::read_to_string(sb.ws(w).join(".git/delphi/meta")).unwrap();
            m.lines().find(|l| l.starts_with("last_proposed_hash=")).unwrap().to_string()
        };
        assert_eq!(meta("ws-rust"), meta("ws-bash"));
    }

    let r = sb.rust(&sb.dir, &["ws", "status"]);
    assert!(
        r.stdout.contains(
            "ws-rust                argos-dev        main     no    proposed   -     no     delphi ws open ws-rust\n"
        ),
        "{}",
        r.stdout
    );
    same(&r, &sb.bash(&sb.dir, &["ws", "status"]));

    // proposing again (not merged yet) force-pushes the same branch and updates the PR
    let r = sb.rust(&sb.dir, &["ws", "propose", "ws-rust", "--yes"]);
    assert_eq!(r.code, 0, "{r:#?}");
    assert!(r.stderr.ends_with("----\nUpdated PR #1\n"), "{}", r.stderr);

    // merge the PR, refresh: clean
    sb.upstream("git merge -q --no-edit origin/delphi/propose/tester/ws-rust");
    let r = sb.rust(&sb.dir, &["ws", "refresh", "ws-rust"]);
    assert_eq!(r.code, 0, "{r:#?}");
    let r = sb.rust(&sb.dir, &["ws", "status"]);
    assert!(
        r.stdout.contains(
            "ws-rust                argos-dev        main     no    clean      -     no     delphi ws open ws-rust\n"
        ),
        "{}",
        r.stdout
    );
    same(&r, &sb.bash(&sb.dir, &["ws", "status"]));
    let r = sb.rust(&sb.dir, &["ws", "status", "--offline"]);
    assert_eq!(r.code, 0);

    // nothing left to propose: says so and warns about the still-open PR
    let r = sb.rust(&sb.dir, &["ws", "propose", "ws-rust", "--yes"]);
    assert_eq!(r.code, 0);
    assert_eq!(
        r.stderr,
        "ws-rust: up to date with origin/main\nnothing to propose\ndelphi: warning: PR #1 still contains earlier changes; close it with: gh pr close 1\n"
    );
    sb.assert_cleaned_up();
}

#[test]
fn layout_new_from_file_and_list() {
    let sb = Sb::new("layout");
    let r = sb.rust(&sb.dir, &["layout", "list"]);
    assert_eq!((r.code, r.stdout.as_str()), (0, "argos-dev\tsoftware/application-software/argos\tclaude-code\n"));
    same(&r, &sb.bash(&sb.dir, &["layout", "list"]));

    let manifest = |name: &str| {
        format!(
            "name: {name}\nharness: claude-code\ninstructions:\n  - software/harness/instructions/base.md\nblocks:\n  - software/application-software/argos/blocks/overview.md\n"
        )
    };
    fs::write(sb.dir.join("rust.yml"), manifest("rust-dev")).unwrap();
    fs::write(sb.dir.join("bash.yml"), manifest("bash-dev")).unwrap();
    let scope = "software/application-software/argos/";
    let r = sb.rust(&sb.dir, &["layout", "new", scope, "rust-dev", "--from", "rust.yml", "--yes"]);
    assert_eq!(r.code, 0, "{r:#?}");
    assert_eq!(r.stdout, "https://github.invalid/pr/1\ndelphi/layout/rust-dev\n");
    assert!(r.stderr.starts_with("---- delphi: add layout rust-dev\nAdds layout `rust-dev` in scope `software/application-software/argos`:\n\n```yaml\nname: rust-dev\n"), "{}", r.stderr);
    let root = sb.root();
    let f = sb.git(
        &root,
        &[
            "show",
            "origin/delphi/layout/rust-dev:context/software/application-software/argos/layouts/rust-dev/manifest.yml",
        ],
    );
    assert_eq!(format!("{f}\n"), manifest("rust-dev"));
    let msg = sb.git(&root, &["log", "-1", "--format=%B", "origin/delphi/layout/rust-dev"]);
    assert_eq!(
        msg,
        "delphi: add layout rust-dev\n\nDelphi-Harness: sandbox\nDelphi-Model: sandbox-model\nDelphi-Effort: low"
    );
    if let Some(b) = sb.bash(&sb.dir, &["layout", "new", scope, "bash-dev", "--from", "bash.yml", "--yes"]) {
        let b = b.norm("bash-dev", "rust-dev").norm("pr/2", "pr/1");
        same(&r, &Some(b));
        let t = |n: &str| {
            sb.git(&root, &["log", "-1", "--format=%s%n%b", &format!("origin/delphi/layout/{n}")]).replace(n, "X")
        };
        assert_eq!(t("rust-dev"), t("bash-dev"));
    }

    // errors
    for (args, err) in [
        (
            &["layout", "new", scope, "other", "--from", "rust.yml", "--yes"][..],
            "delphi: manifest name must be 'other'\n",
        ),
        (
            &["layout", "new", scope, "argos-dev", "--from", "rust.yml", "--yes"],
            "delphi: layout name already used: argos-dev\n",
        ),
        (
            &["layout", "new", "software/nope", "x", "--from", "rust.yml", "--yes"],
            "delphi: not a scope on origin/main: software/nope\n",
        ),
        (&["layout", "new", scope, "x", "--from", "missing.yml"], "delphi: no such file: missing.yml\n"),
        (
            &["layout", "new", scope, "x"],
            "delphi: non-interactive session: pass a drafted manifest with --from <file>\n",
        ),
    ] {
        let r = sb.rust(&sb.dir, args);
        assert_eq!((r.code, r.stderr.as_str()), (1, err), "{args:?}");
        same(&r, &sb.bash(&sb.dir, args));
    }
    fs::write(sb.dir.join("x.yml"), manifest("x")).unwrap();
    let r = sb.rust(&sb.dir, &["layout", "new", scope, "x", "--from", "x.yml"]);
    assert_eq!(r.stderr, "delphi: non-interactive session: re-run with --yes (or DELPHI_YES=1)\n");
    sb.assert_cleaned_up();
}

#[test]
fn block_mv_matches_bash_and_workspaces_follow() {
    let sb = Sb::new("mv");
    sb.rust(&sb.dir, &["workspace", "new", "argos-dev", "--as", "ws-rust"]);
    let root = sb.root();
    let old = "software/application-software/argos/blocks/overview.md";
    let new = "software/application-software/argos/blocks/intro.md";
    let day = sb.sh(&sb.dir, "date +%Y%m%d").trim().to_string();
    let br = format!("delphi/mv/overview.md-{day}");
    let args = ["block", "mv", old, new, "--yes"];

    let bash = sb.bash(&sb.dir, &args);
    let mut bash_tree = None;
    if let Some(b) = &bash {
        assert_eq!(b.code, 0, "{b:#?}");
        bash_tree = Some(sb.git(&root, &["rev-parse", &format!("origin/{br}^{{tree}}")]));
        sb.git(&root, &["push", "-q", "origin", "--delete", &br]);
        sb.git(&root, &["branch", "-q", "-D", &br]);
        fs::write(sb.dir.join("gh.prs"), "").unwrap();
    }
    let r = sb.rust(&sb.dir, &args);
    assert_eq!(r.code, 0, "{r:#?}");
    assert_eq!(r.stdout, format!("https://github.invalid/pr/1\n{br}\n"));
    same(&r, &bash);
    let tree = sb.git(&root, &["rev-parse", &format!("origin/{br}^{{tree}}")]);
    if let Some(t) = bash_tree {
        assert_eq!(tree, t);
    }
    let moves = sb.git(&root, &["show", &format!("origin/{br}:moves.tsv")]);
    let date = sb.sh(&sb.dir, "date +%Y-%m-%d").trim().to_string();
    assert_eq!(moves, format!("# old\tnew\tdate\n{old}\t{new}\t{date}"));
    let scope = sb.git(&root, &["show", &format!("origin/{br}:context/software/application-software/argos/scope.yml")]);
    assert!(scope.contains(&format!("  - {new}\n")), "{scope}");

    let r = sb.rust(&sb.dir, &["block", "mv", "software/nope/blocks/a.md", "software/nope/blocks/b.md", "--yes"]);
    assert_eq!(r.code, 1);
    assert!(r.stderr.ends_with("delphi: no such block on origin/main: software/nope/blocks/a.md\n"));

    // after the move lands, the workspace follows on refresh
    sb.upstream(&format!("git merge -q --no-edit origin/{br}"));
    let r = sb.rust(&sb.dir, &["ws", "refresh", "ws-rust"]);
    assert_eq!(r.code, 0, "{r:#?}");
    let ws = sb.ws("ws-rust");
    assert!(ws.join(format!("context/{new}")).is_file());
    assert!(!ws.join(format!("context/{old}")).exists());
    let meta = fs::read_to_string(ws.join(".git/delphi/meta")).unwrap();
    assert!(meta.contains(&format!("compile_commit={}\n", sb.git(&root, &["rev-parse", "origin/main"]))));
    sb.assert_cleaned_up();
}

#[test]
fn check_passes_then_reports_every_failure_like_bash() {
    let sb = Sb::new("check");
    let r = sb.rust(&sb.dir, &["check"]);
    assert_eq!((r.code, r.stderr.as_str()), (0, "check: ok\n"));
    same(&r, &sb.bash(&sb.dir, &["check"]));

    let c = sb.root().join("context");
    let a = c.join("software/application-software/argos");
    fs::write(c.join("software/notes.txt"), "stray\n").unwrap();
    fs::write(a.join("blocks/empty.md"), "").unwrap();
    fs::write(a.join("blocks/nonl.md"), "no newline").unwrap();
    fs::write(a.join("blocks/CLAUDE.md"), "x\n").unwrap();
    fs::create_dir_all(a.join("layouts/bad")).unwrap();
    fs::write(
        a.join("layouts/bad/manifest.yml"),
        "name: other\nharness: claude-code\ninstructions:\n  - software/application-software/argos/blocks/overview.md\nblocks:\n  - software/missing/blocks/*\nextra: 1\n",
    )
    .unwrap();
    fs::write(a.join("harness/skills/bad.skill"), "name: bad\nwhat: 1\nbody:\n  - software/nope.md\n").unwrap();
    fs::write(c.join("software/harness/tabbed.yml"), "a:\tb\n").unwrap();
    fs::write(c.join("software/harness/mcp/broken.json"), "\"x\": {\n").unwrap();
    fs::create_dir_all(c.join("orphan")).unwrap();
    fs::write(sb.root().join("moves.tsv"), "# old\tnew\tdate\na\tb\n").unwrap();
    let r = sb.rust(&sb.dir, &["check"]);
    assert_eq!(r.code, 1);
    for want in [
        "check: context/orphan: scope directory has no scope.yml\n",
        "check: context/software/notes.txt: stray file",
        "check: context/software/application-software/argos/blocks/empty.md: empty file\n",
        "check: context/software/application-software/argos/blocks/nonl.md: missing trailing newline\n",
        "check: context/software/application-software/argos/blocks/CLAUDE.md: harness instruction file names are not allowed under context/\n",
        "/context/software/harness/tabbed.yml:1: tabs are not allowed\n",
        "check: context/software/application-software/argos/harness/skills/bad.skill: missing description\n",
        "check: context/software/application-software/argos/harness/skills/bad.skill: unknown key 'what'\n",
        "check: context/software/application-software/argos/harness/skills/bad.skill: body: 'software/nope.md' is not under blocks/*\n",
        "check: context/software/application-software/argos/harness/skills/bad.skill: body: missing 'software/nope.md'\n",
        "check: context/software/application-software/argos/layouts/bad/manifest.yml: name 'other' must equal its directory 'bad'\n",
        "check: context/software/application-software/argos/layouts/bad/manifest.yml: compile: no such directory context/software/missing/blocks\n",
        "check: context/software/application-software/argos/layouts/bad/manifest.yml: unknown key 'extra'\n",
        "check: context/software/application-software/argos/layouts/bad/manifest.yml: instructions: 'software/application-software/argos/blocks/overview.md' is not under harness/instructions/*\n",
        "check: moves.tsv:2: expected old<TAB>new<TAB>date\n",
        "check: context/software/harness/mcp/broken.json: not a valid mcpServers member\n",
    ] {
        assert!(r.stderr.contains(want), "missing {want:?} in:\n{}", r.stderr);
    }
    same(&r, &sb.bash(&sb.dir, &["check"]));
    sb.assert_cleaned_up();
}

#[test]
fn repo_root_discovery_and_setup() {
    let sb = Sb::new("root");
    sb.rust(&sb.dir, &["workspace", "new", "argos-dev", "--as", "ws-rust"]);
    let ws = sb.ws("ws-rust");

    // walk up from inside the checkout
    let r = sb.rust_noroot(&sb.root().join("context/software"), &["ws", "status", "--offline"]);
    assert_eq!(r.code, 0, "{r:#?}");
    assert!(r.stdout.contains("ws-rust "));

    // outside any checkout, nothing recorded
    let r = sb.rust_noroot(&ws, &["ws", "status"]);
    assert_eq!(r.code, 1);
    assert!(r.stderr.starts_with("delphi: cannot find the Delphi repo"), "{}", r.stderr);

    // setup records the checkout; then it works from the workspace
    let r = sb.rust_noroot(&sb.root(), &["setup"]);
    assert_eq!(r.code, 0, "{r:#?}");
    let rec = fs::read_to_string(sb.dir.join("home/.config/delphi/root")).unwrap();
    assert_eq!(rec, format!("{}\n", sb.root().display()));
    let r = sb.rust_noroot(&ws, &["ws", "propose", "--dry-run"]);
    assert_eq!((r.code, r.stderr.as_str()), (0, ""));
    let r = sb.rust_noroot(&ws, &["ws", "status", "--offline"]);
    assert_eq!(r.code, 0);

    let r = sb.rust_noroot(&sb.dir, &["setup", "/nonexistent"]);
    assert_eq!(r.code, 1);
    sb.assert_cleaned_up();
}

#[test]
fn open_shell_gets_provenance_env_like_bash() {
    let sb = Sb::new("open");
    let (_, b) = new_pair(&sb);
    let shell = sb.dir.join("bin/fake-shell");
    fs::write(&shell, "#!/bin/sh\necho \"$(pwd) h=$DELPHI_HARNESS m=$DELPHI_MODEL e=$DELPHI_EFFORT\"\n").unwrap();
    fs::set_permissions(&shell, fs::Permissions::from_mode(0o755)).unwrap();
    let run = |ws: &str, bash: bool| {
        let args = ["ws", "open", ws, "--shell", "--model", "m1"];
        let mut c = std::process::Command::new(if bash { "/bin/bash" } else { env!("CARGO_BIN_EXE_delphi") });
        if bash {
            c.arg(sb.root().join("bin/delphi"));
        }
        c.args(args);
        sb.env(&mut c);
        c.env("SHELL", &shell).env("DELPHI_ROOT", sb.root()).current_dir(&sb.dir);
        let o = c.output().unwrap();
        (
            o.status.code(),
            String::from_utf8_lossy(&o.stdout).into_owned(),
            String::from_utf8_lossy(&o.stderr).into_owned(),
        )
    };
    let (code, out, err) = run("ws-rust", false);
    assert_eq!((code, err.as_str()), (Some(0), ""));
    assert!(out.starts_with(&format!("{} h=claude-code", sb.ws("ws-rust").display())), "{out}");
    assert!(out.ends_with(" m=m1 e=low\n"), "{out}");
    if b.is_some() {
        let (bc, bout, berr) = run("ws-bash", true);
        assert_eq!((code, out, err), (bc, bout.replace("ws-bash", "ws-rust"), berr));
    }
    sb.assert_cleaned_up();
}
