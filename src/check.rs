//! Repo-wide validation (spec §6). `check_tree(root)` prints every violation and returns false if
//! any: scopes have scope.yml; workspace.yml files parse, use known keys, a known harness, and
//! `name` = folder (unique); instruction parts and link sources exist outside workspace folders;
//! dests are unique, don't nest in a directory link's dest, and aren't the generated instruction
//! file; instruction file names only inside workspace folders; no symlinks.

use crate::core::{basename, exit, find, path_ok, rel_to, root, under};
use crate::harness::HARNESSES;
use crate::parse::parse_yaml;
use crate::workspace::{folder_of, load, KEYS, YML};
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

    let all = find(&ctx, &|_| false);
    let mut folders: Vec<String> = vec![];
    for (p, ft) in &all {
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
        }
    }

    // workspaces
    let mut names: Vec<String> = vec![];
    folders.sort();
    for f in &folders {
        let label = format!("context/{f}/{YML}");
        let (y, name) = (ctx.join(f).join(YML), basename(f).to_string());
        if !y.is_file() || folder_of(&label).is_none() {
            errs.push(format!("context/{f}: workspace folder has no {YML}"));
            continue;
        }
        let w = match load(f, &String::from_utf8_lossy(&std::fs::read(&y)?), &label) {
            Ok(w) => w,
            Err(e) => {
                errs.push(format!("{e:#}"));
                continue;
            }
        };
        let e = |m: String| format!("{label}: {m}");
        if w.y.get("name") != name {
            errs.push(e(format!("name '{}' must equal its folder '{name}'", w.y.get("name"))));
        }
        if names.contains(&name) {
            errs.push(e(format!("workspace name '{name}' is not unique")));
        }
        names.push(name);
        for k in w.y.keys().into_iter().filter(|k| !KEYS.contains(&k.as_str())) {
            errs.push(e(format!("unknown key '{k}'")));
        }
        for p in w.parts.iter().filter(|p| !ctx.join(p).is_file()) {
            errs.push(e(format!("instructions: missing context/{p}")));
        }
        let mut dests: Vec<(&str, bool)> = vec![];
        for (s, d) in &w.links {
            let sp = ctx.join(s);
            if !sp.is_file() && !sp.is_dir() {
                errs.push(e(format!("links: missing source context/{s}")));
            } else if in_workspace(s).is_some() {
                errs.push(e(format!("links: source context/{s} is inside a workspace folder")));
            }
            if !w.parts.is_empty() && d == w.h.instructions {
                errs.push(e(format!("links: {d} is generated from instructions:")));
            }
            for (o, dir) in &dests {
                let nested = |a: &str, b: &str, is_dir: bool| is_dir && under(a, b).is_some();
                if o == d || nested(d, o, *dir) || nested(o, d, sp.is_dir()) {
                    errs.push(e(format!("links: dests overlap: '{o}' and '{d}'")));
                }
            }
            dests.push((d, sp.is_dir()));
        }
        for (n, _) in w.y.map("repos").iter().filter(|(n, _)| n.starts_with('.') || n.contains('/')) {
            errs.push(e(format!("repos: invalid name '{n}'")));
        }
    }

    for e in &errs {
        eprintln!("check: {e}");
    }
    Ok(errs.is_empty())
}
