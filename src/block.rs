//! `delphi block mv <old> <new>`: move a source under context/, log it in moves.tsv, rewrite
//! manifests and scope recommendations. Workspaces follow on refresh.

use crate::check::check_tree;
use crate::core::{
    basename, date, delphi_commit, delphi_fetch, find, git, ok, parse_args, parse_moves, path_ok, rewrite_moves,
    safe_path, Opts,
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
    mv(&t(&pos[0]), &t(&pos[1]), &o)
}

fn mv(old: &str, new: &str, o: &Opts) -> Result<()> {
    for p in [old, new] {
        if !path_ok(p) {
            die!("unsafe path: '{p}'");
        }
        if p.split('/').any(|c| c == "layouts") || basename(p) == "scope.yml" {
            die!("'{p}' is a layout or scope file; only sources can be moved");
        }
    }
    delphi_fetch();
    let c = delphi_commit("main")?;
    let prov = provenance::resolve(&o.model, &o.effort, "claude-code")?;
    let pr = crate::pr::begin(&format!("delphi/mv/{}-{}", basename(old), date("%Y%m%d")), &c, prov)?;
    let ctx = pr.wt.join("context");
    let (src, dst) = (safe_path(&ctx, old)?, safe_path(&ctx, new)?);
    if !src.exists() {
        die!("no such source on origin/main: {old}");
    }
    if dst.exists() {
        die!("already exists on origin/main: {new}");
    }
    let moved = dst.parent().is_some_and(|d| fs::create_dir_all(d).is_ok())
        && ok(git(&pr.wt).args(["mv", &format!("context/{old}"), &format!("context/{new}")]));
    if !moved {
        die!("git mv failed");
    }
    let row = format!("{old}\t{new}\t{}\n", date("%Y-%m-%d"));
    OpenOptions::new().create(true).append(true).open(pr.wt.join("moves.tsv"))?.write_all(row.as_bytes())?;
    let rows = parse_moves(&row);
    for (f, ft) in find(&ctx, &|_| false) {
        if ft.is_file() && f.file_name().is_some_and(|n| n == "manifest.yml" || n == "scope.yml") {
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
