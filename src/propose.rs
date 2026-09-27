//! `delphi propose [<checkout> | [<workspace>] --branch <b>] [--dry-run]` (spec §5). The branch's
//! changes since its merge-base with `origin/ws/<name>` (a binary patch) are 3-way applied under
//! the workspace folder in a temp worktree off `origin/main` (conflicts exit 1), checked, committed
//! once with provenance, pushed to `propose/<user>/<name>-<branch>` with a lease, and opened as
//! (or update) one PR to main. A checkout's commits are fetched into the Delphi repo first;
//! `--branch` takes a branch on origin (the CI mirror of PRs into `ws/*`).

use crate::check::check_tree;
use crate::checkout::resolve;
use crate::core::{
    commit, fetch_main, git, need_yes_or_tty, ok_q, out, out_q, parse_args, root, run, under, worktree, Fail,
};
use crate::pr::{self, user};
use crate::{die, info, provenance, workspace};
use anyhow::Result;
use std::io::Write;
use std::path::Path;
use std::process::Stdio;

pub fn main(args: &[String]) -> Result<()> {
    let (o, pos) = parse_args("--branch --model --effort --yes --dry-run --offline", args)?;
    if pos.len() > 1 {
        die!("too many arguments (see: delphi help)");
    }
    let arg = pos.first().map(String::as_str).unwrap_or("");
    if !o.dry {
        need_yes_or_tty()?;
    }
    let main = fetch_main()?;
    let r = root();
    let (co, name, src, label) = if o.branch.is_empty() {
        let co = resolve(arg)?;
        co.warn_uncommitted();
        let Some(label) = out_q(co.git().args(["symbolic-ref", "--short", "HEAD"])) else {
            die!("{} is not on a branch", co.dir.display())
        };
        if !ok_q(git(r).args(["fetch", "--quiet", "--no-tags"]).arg(&co.dir).arg("HEAD")) {
            die!("cannot fetch {} into the Delphi repo", co.dir.display());
        }
        let name = co.meta("workspace");
        (Some(co), name, commit(r, "FETCH_HEAD").unwrap_or_default(), label)
    } else {
        let b = &o.branch;
        let Some(src) = commit(r, &format!("origin/{b}")).or_else(|| commit(r, b)) else {
            die!("no such branch: {b} (push it to origin)")
        };
        let name = if arg.is_empty() { infer(r, &src)? } else { arg.to_string() };
        (None, name, src, b.clone())
    };
    let w = workspace::named(r, &main, &name)?;
    let ws = format!("origin/ws/{name}");
    let Some(base) = out_q(git(r).args(["merge-base", &src, &ws])) else {
        die!("{label} shares no history with {ws}; work on a branch cut from ws/{name}")
    };
    let patch = run(git(r).args(["diff", "--binary", "--full-index", "--no-renames", &base, &src]), false);
    let patch = patch.unwrap_or_default();
    if patch.is_empty() {
        info!("nothing to propose: {label} has no changes vs {ws}");
        return Ok(());
    }
    let safe: String =
        label.chars().map(|c| if c.is_ascii_alphanumeric() || "._".contains(c) { c } else { '-' }).collect();
    let pb = format!("propose/{}/{name}-{safe}", user());
    let prov = if o.dry { None } else { Some(provenance::resolve(&o.model, &o.effort, w.h.name)?) };
    let pr = prov.map(|p| pr::begin(&pb, &main, p)).transpose()?;
    let wt = match &pr {
        Some(pr) => pr.wt.clone(),
        None => worktree(r, &["--detach"], &main, "cannot make a worktree of origin/main")?,
    };
    apply(&wt, &w.folder, &patch, &name)?;
    let d = out(git(&wt).args(["diff", "--cached", "--name-status", "--no-renames", "HEAD"])).unwrap_or_default();
    if d.is_empty() {
        info!("nothing to propose: origin/main already has the changes from {label}");
        return Ok(());
    }
    let passed = check_tree(&wt)?;
    let title = format!("delphi: {name}: changes from {label}");
    let short = |s: &str| s[..7.min(s.len())].to_string();
    let mut body = format!(
        "Changes to `{}` from branch `{label}` ({}, based on `ws/{name}` {}):\n\n",
        w.folder,
        short(&src),
        short(&base)
    );
    for (st, p) in d.lines().filter_map(|l| l.split_once('\t')) {
        body += &format!("- {st} `{}`\n", under(p, &w.folder).unwrap_or(p));
    }
    let Some(mut pr) = pr else {
        println!("---- {title} (to {pb})\n{body}----");
        return if passed { Ok(()) } else { Err(Fail(1, "check would fail; fix the errors above".into()).into()) };
    };
    if !passed {
        die!("check failed on the proposed tree; nothing pushed");
    }
    pr.prov.workspace = w.folder.clone();
    let me = format!("{}|{}|{}", pr.prov.harness, pr.prov.model, pr.prov.effort);
    pr.prov.rows = prov_rows(r, &format!("{base}..{src}"), &me);
    pr.commit(&format!("{title}\n\nSource branch: {label} ({src})\nBase: ws/{name} ({base})"))?;
    // lease: what this checkout last pushed there (so others' pushes are not overwritten), else
    // what origin has now ("" = absent, e.g. deleted after merging)
    let remote = commit(r, &format!("origin/{pb}")).unwrap_or_default();
    let pushed = co.as_ref().map(|c| c.meta("pushed")).filter(|p| !p.is_empty() && !remote.is_empty());
    if pr.finish(&title, body.trim_end(), Some(&pushed.unwrap_or(remote)))? {
        if let Some(co) = co {
            co.meta_set("proposed", &src)?;
            co.meta_set("pushed", &commit(&pr.wt, "HEAD").unwrap_or_default())?;
        }
        println!("{pb}");
    }
    Ok(())
}

/// The workspace whose `origin/ws/*` branch `src` shares history with (exactly one).
fn infer(r: &Path, src: &str) -> Result<String> {
    let refs = out(git(r).args(["for-each-ref", "--format=%(refname:strip=4)", "refs/remotes/origin/ws/"]));
    let refs = refs.unwrap_or_default();
    let v: Vec<&str> =
        refs.lines().filter(|n| ok_q(git(r).args(["merge-base", src, &format!("origin/ws/{n}")]))).collect();
    match v[..] {
        [n] => Ok(n.to_string()),
        [] => die!("the branch shares no history with any ws/* branch; cut it from ws/<workspace>"),
        _ => die!(
            "the branch shares history with several workspaces ({}); name one: delphi propose <workspace> --branch <b>",
            v.join(", ")
        ),
    }
}

/// 3-way apply `patch` under `folder` in `wt` (index and files); conflicts exit 1 listing files.
fn apply(wt: &Path, folder: &str, patch: &[u8], name: &str) -> Result<()> {
    let dir = format!("--directory={folder}");
    let mut c = git(wt);
    c.args(["apply", "--3way", "--whitespace=nowarn", &dir]).stdin(Stdio::piped()).stdout(Stdio::null());
    let mut ch = c.stderr(Stdio::piped()).spawn()?;
    ch.stdin.take().map(|mut i| i.write_all(patch));
    let o = ch.wait_with_output()?;
    if o.status.success() {
        return Ok(());
    }
    let u = out(git(wt).args(["diff", "--name-only", "--diff-filter=U"])).unwrap_or_default();
    let files: String = if u.is_empty() {
        String::from_utf8_lossy(&o.stderr).into_owned()
    } else {
        u.lines().map(|p| format!("  {}\n", under(p, folder).unwrap_or(p))).collect()
    };
    let next = format!("merge the latest ws/{name} into your branch (delphi refresh), resolve, commit, then re-run");
    Err(Fail(1, format!("propose: conflicts with changes on main (nothing proposed):\n{files}{next}")).into())
}

/// Distinct harness|model|effort trailers of the commits in `range`, except `me`.
fn prov_rows(dir: &Path, range: &str, me: &str) -> Vec<String> {
    let f = "%(trailers:key=Delphi-Harness,valueonly,separator=)|%(trailers:key=Delphi-Model,valueonly,separator=)|%(trailers:key=Delphi-Effort,valueonly,separator=)";
    let log = out(git(dir).args(["log", "--no-merges", &format!("--format={f}"), range]));
    let mut seen: Vec<String> = vec![];
    for l in log.unwrap_or_default().lines() {
        if l != "||" && l != me && !seen.iter().any(|s| s == l) {
            seen.push(l.to_string());
        }
    }
    seen
}
