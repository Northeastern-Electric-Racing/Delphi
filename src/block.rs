//! `delphi block mv <old> <new>`: move a block, log it in moves.tsv, rewrite references. Port of
//! lib/block.sh.

use crate::check::check_tree;
use crate::core::{
    basename, date, delphi_commit, delphi_fetch, find, git_c, glob, ok, parse_args, parse_moves, path_ok,
    rewrite_moves, safe_path,
};
use crate::{die, provenance};
use anyhow::Result;
use std::fs::{self, OpenOptions};
use std::io::Write;

pub fn main(args: &[String]) -> Result<()> {
    let verb = args.first().map(String::as_str).unwrap_or("");
    let (o, pos) = parse_args("--model --effort --yes", args.get(1..).unwrap_or(&[]))?;
    if verb != "mv" || pos.len() != 2 {
        die!("usage: delphi block mv <old> <new>");
    }
    let t = |s: &str| s.strip_suffix('/').unwrap_or(s).to_string();
    mv(&t(&pos[0]), &t(&pos[1]), &o.model, &o.effort)
}

fn mv(old: &str, new: &str, model: &str, effort: &str) -> Result<()> {
    for p in [old, new] {
        if !path_ok(p) {
            die!("unsafe path: '{p}'");
        }
        let s = format!("/{p}");
        if !(glob("*/blocks/?*", &s) || glob("*/docs/?*", &s) || glob("*/harness/?*", &s)) {
            die!("'{p}' is not under a scope's blocks/, docs/, or harness/");
        }
    }
    delphi_fetch();
    let c = delphi_commit("main")?;
    let prov = provenance::resolve(model, effort, "claude-code")?;
    let mut pr = crate::pr::begin(&format!("delphi/mv/{}-{}", basename(old), date("%Y%m%d")), &c, prov)?;
    let ctx = pr.wt.join("context");
    let src = safe_path(&ctx, old)?;
    let dst = safe_path(&ctx, new)?;
    if !src.exists() {
        die!("no such block on origin/main: {old}");
    }
    if dst.exists() {
        die!("already exists on origin/main: {new}");
    }
    let moved = dst.parent().is_some_and(|d| fs::create_dir_all(d).is_ok())
        && ok(git_c(&pr.wt).args(["mv", &format!("context/{old}"), &format!("context/{new}")]));
    if !moved {
        die!("git mv failed");
    }
    let row = format!("{old}\t{new}\t{}\n", date("%Y-%m-%d"));
    OpenOptions::new().create(true).append(true).open(pr.wt.join("moves.tsv"))?.write_all(row.as_bytes())?;
    let rows = parse_moves(&row);
    for (f, ft) in find(&ctx) {
        let n = f.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        if ft.is_file() && (n == "manifest.yml" || n == "scope.yml" || glob("*.skill", &n)) {
            let _ = rewrite_moves(&rows, &f);
        }
    }
    if !check_tree(&pr.wt)? {
        die!("check failed after the move; nothing pushed");
    }
    let title = format!("delphi: move {old} -> {new}");
    if !pr.commit(&title, "")? {
        die!("nothing to commit");
    }
    let body = format!("Moves `{old}` to `{new}` and rewrites references. Workspaces follow on their next refresh.");
    pr.finish(&title, &body, None)?;
    println!("{}", pr.branch);
    Ok(())
}
