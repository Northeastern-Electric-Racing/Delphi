//! `delphi check`: repo-wide validation (spec §6). `check_tree(root)` prints every violation and
//! returns false if any.

use crate::core::{basename, exit, find, path_ok, rel_to, root, under};
use crate::harness::HARNESSES;
use crate::parse::parse_yaml;
use crate::workspace::{below, folder_of, load, KEYS, SKILL_YML, YML};
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

/// The workspace folder (relative to context/) containing `rel`, if any.
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
    let rel = |p: &Path| rel_to(p, &ctx);

    // scopes: every directory outside blocks/, docs/, harness/, workspaces/ needs scope.yml
    let reserved = |p: &Path| matches!(basename(&p.to_string_lossy()), "blocks" | "docs" | "harness" | "workspaces");
    let dirs = find(&ctx, &reserved).into_iter().filter(|(_, ft)| ft.is_dir()).map(|(p, _)| p);
    for d in std::iter::once(ctx.clone()).chain(dirs) {
        if !d.join("scope.yml").is_file() {
            errs.push(
                format!("context/{}: scope directory has no scope.yml", rel(&d)).replace("context/:", "context:"),
            );
        }
    }

    let mut folders: Vec<String> = vec![];
    for (p, ft) in &find(&ctx, &|_| false) {
        let r = rel(p);
        let parent = r.rsplit_once('/').map_or("", |x| x.0);
        if ft.is_symlink() {
            errs.push(format!("context/{r}: symlinks are not allowed"));
        } else if ft.is_dir() && basename(parent) == "workspaces" && in_workspace(parent).is_none() {
            folders.push(r.clone());
        } else if ft.is_file() && HARNESSES.iter().any(|h| h.instructions == basename(&r)) && in_workspace(&r).is_none()
        {
            errs.push(format!("context/{r}: instruction files belong in a workspace folder"));
        } else if ft.is_file() && basename(&r) == "scope.yml" {
            match parse_yaml(p) {
                Err(e) => errs.push(format!("{e:#}")),
                Ok(y) => {
                    for s in y.list("recommend").iter().filter(|s| !path_ok(s) || !ctx.join(s).exists()) {
                        errs.push(format!("context/{r}: recommend: missing '{s}'"));
                    }
                }
            }
        } else if ft.is_file() && basename(&r) == SKILL_YML {
            check_skill(&ctx, p, &r, &mut errs);
        }
    }

    // workspaces
    folders.sort();
    let mut names: Vec<String> = vec![];
    for f in &folders {
        check_ws(&ctx, f, &folders, &mut names, &mut errs)?;
    }

    for e in &errs {
        eprintln!("check: {e}");
    }
    Ok(errs.is_empty())
}

/// Violations in a `skill.yml` (`r` relative to context/).
fn check_skill(ctx: &Path, p: &Path, r: &str, errs: &mut Vec<String>) {
    let y = match parse_yaml(p) {
        Ok(y) => y,
        Err(e) => return errs.push(format!("{e:#}")),
    };
    let mut err = |m: String| errs.push(format!("context/{r}: {m}"));
    for k in ["name", "description"].into_iter().filter(|k| y.get(k).is_empty()) {
        err(format!("missing {k}"));
    }
    for k in y.keys().into_iter().filter(|k| !["name", "description", "body"].contains(&k.as_str())) {
        err(format!("unknown key '{k}'"));
    }
    for b in y.list("body") {
        if !path_ok(&b) || !ctx.join(&b).is_file() {
            err(format!("body: missing context/{b}"));
        } else if below(&b, "blocks").is_none_or(|x| x.is_empty()) {
            err(format!("body: context/{b} must be a file under a scope's blocks/"));
        }
    }
}

/// Violations in workspace folder `f` (relative to context/); `names` collects names seen so far.
fn check_ws(ctx: &Path, f: &str, folders: &[String], names: &mut Vec<String>, errs: &mut Vec<String>) -> Result<()> {
    let label = format!("context/{f}/{YML}");
    let (y, name) = (ctx.join(f).join(YML), basename(f).to_string());
    if !y.is_file() || folder_of(&label).is_none() {
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
    for p in w.parts.iter().filter(|p| !ctx.join(p).is_file()) {
        err(format!("instructions: missing context/{p}"));
    }
    for p in &w.mcp {
        if !ctx.join(p).is_file() {
            err(format!("mcp: missing context/{p}"));
        } else if below(p, "harness/mcp").is_none_or(|r| r.is_empty()) {
            err(format!("mcp: context/{p} must be a file under a scope's harness/mcp/"));
        }
    }
    if w.y.list("settings").len() > 1 {
        err("settings: at most one entry".into());
    }
    let mut dests: Vec<(&str, bool)> = vec![];
    for (k, s, d) in &w.links {
        let sp = ctx.join(s);
        let fits = match *k {
            "skills" => below(s, "harness/skills").is_some_and(|r| !r.is_empty() && !r.contains('/') && sp.is_dir()),
            "settings" => below(s, "harness/settings").is_some_and(|r| !r.is_empty() && sp.is_file()),
            _ => below(s, k).is_some(),
        };
        if !sp.is_file() && !sp.is_dir() {
            err(format!("{k}: missing source context/{s}"));
        } else if in_workspace(s).is_some() {
            err(format!("{k}: source context/{s} is inside a workspace folder"));
        } else if let Some(f) = folders.iter().find(|f| under(f, s).is_some()) {
            err(format!("{k}: source context/{s} contains workspace folder context/{f}"));
        } else if !fits {
            let want = match *k {
                "skills" => "a skill directory directly under a scope's harness/skills/",
                "settings" => "a file under a scope's harness/settings/",
                "docs" => "under a scope's docs/",
                _ => "under a scope's blocks/",
            };
            err(format!("{k}: context/{s} must be {want}"));
        }
        for (g, _, file, _) in w.generated().into_iter().filter(|g| g.2 == d) {
            err(format!("{k}: {file} is generated from {g}:"));
        }
        for (o, dir) in &dests {
            let nested = |a: &str, b: &str, is_dir: bool| is_dir && under(a, b).is_some();
            if o == d || nested(d, o, *dir) || nested(o, d, sp.is_dir()) {
                err(format!("{k}: dests overlap: '{o}' and '{d}'"));
            }
        }
        dests.push((d, sp.is_dir()));
    }
    for (n, _) in w.y.map("repos").iter().filter(|(n, _)| n.starts_with('.') || n.contains('/')) {
        err(format!("repos: invalid name '{n}'"));
    }
    Ok(())
}
