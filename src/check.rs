//! `delphi check`: repo-wide validation (spec §6). `check_tree(root)` prints every violation and
//! returns false if any.

use crate::core::{basename, exit, find, rel_to, root};
use crate::harness::HARNESSES;
use crate::parse::parse_text;
use crate::workspace::{load, KEYS, YML};
use crate::{die, info};
use anyhow::Result;
use std::path::Path;

pub fn main(args: &[String]) -> Result<()> {
    if !args.is_empty() {
        die!("usage: delphi check");
    }
    if !check_tree(root())? {
        return Err(exit(1));
    }
    info!("check: ok");
    Ok(())
}

/// The workspace folder containing `rel` (both relative to context/): the first
/// `workspaces/<name>` in the path.
fn in_workspace(rel: &str) -> Option<&str> {
    let c: Vec<&str> = rel.split('/').collect();
    let i = c.iter().position(|x| *x == "workspaces").filter(|i| i + 1 < c.len())?;
    Some(&rel[..c[..i + 2].join("/").len()])
}

pub fn check_tree(root_dir: &Path) -> Result<bool> {
    let ctx = root_dir.join("context");
    if !ctx.is_dir() {
        eprintln!("check: missing context/ directory");
        return Ok(false);
    }
    let mut errs: Vec<String> = vec![];
    if !ctx.join("scope.yml").is_file() {
        errs.push("context: scope directory has no scope.yml".into());
    }
    let mut folders: Vec<String> = vec![];
    for (p, ft) in &find(&ctx, &|_| false) {
        let r = rel_to(p, &ctx);
        let ws = in_workspace(&r);
        if ft.is_symlink() {
            errs.push(format!("context/{r}: symlinks are not allowed"));
        } else if ft.is_dir() && ws == Some(r.as_str()) {
            folders.push(r);
        } else if ft.is_dir() && ws.is_none() && basename(&r) != "workspaces" && !p.join("scope.yml").is_file() {
            errs.push(format!("context/{r}: scope directory has no scope.yml"));
        } else if ft.is_file() && ws.is_none() && HARNESSES.iter().any(|h| h.instructions == basename(&r)) {
            errs.push(format!("context/{r}: instruction files belong in a workspace folder"));
        } else if ft.is_file() && ws.is_none() && basename(&r) == "scope.yml" {
            if let Err(e) = parse_text(&String::from_utf8_lossy(&std::fs::read(p)?), &format!("context/{r}")) {
                errs.push(format!("{e:#}"));
            }
        } else if ft.is_file() && basename(&r) == YML && ws.is_some_and(|w| r != format!("{w}/{YML}")) {
            errs.push(format!("context/{r}: nested workspace (workspace folders never nest)"));
        }
    }
    folders.sort();
    let mut names: Vec<String> = vec![];
    for f in &folders {
        check_ws(&ctx, f, &mut names, &mut errs)?;
    }
    for e in &errs {
        eprintln!("check: {e}");
    }
    Ok(errs.is_empty())
}

/// Violations in workspace folder `f` (relative to context/); `names` collects names seen so far.
fn check_ws(ctx: &Path, f: &str, names: &mut Vec<String>, errs: &mut Vec<String>) -> Result<()> {
    let label = format!("context/{f}/{YML}");
    let (y, name) = (ctx.join(f).join(YML), basename(f).to_string());
    if !y.is_file() {
        errs.push(format!("context/{f}: workspace folder has no {YML}"));
        return Ok(());
    }
    let w = match load(f, &String::from_utf8_lossy(&std::fs::read(&y)?), &label) {
        Ok(w) => w,
        Err(e) => {
            errs.push(format!("{e:#}"));
            return Ok(());
        }
    };
    let mut err = |m: String| errs.push(format!("{label}: {m}"));
    if w.y.get("name") != name {
        err(format!("name '{}' must equal its folder '{name}'", w.y.get("name")));
    }
    if names.contains(&name) {
        err(format!("workspace name '{name}' is not unique"));
    }
    names.push(name);
    for k in w.y.keys().into_iter().filter(|k| !KEYS.contains(&k.as_str())) {
        err(format!("unknown key '{k}'"));
    }
    Ok(())
}
