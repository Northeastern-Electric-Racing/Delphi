//! Repo-wide validation (spec §8). `check_tree(root)` prints every violation and returns false if
//! any. Layouts are validated by compiling them (sources exist, entries well-formed, dests safe,
//! unique, not nested except a file in a directory dest); the rules here cover the rest.

use crate::compile::compile;
use crate::core::{basename, exit, find, make_tmp, path_ok, rel_to, root};
use crate::harness::HARNESSES;
use crate::parse::parse_yaml;
use crate::{die, info};
use anyhow::Result;
use std::fs;
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

const KEYS: &[&str] = &["name", "harness", "instructions", "sync", "copy", "repos"];

/// Inside some `layouts/<name>/files/`.
fn in_layout_files(rel: &str) -> bool {
    rel.split('/').collect::<Vec<_>>().windows(3).any(|w| w[0] == "layouts" && w[2] == "files")
}

pub fn check_tree(root_dir: &Path) -> Result<bool> {
    let mut errs: Vec<String> = vec![];
    let ctx = root_dir.join("context");
    if !ctx.is_dir() {
        eprintln!("check: missing context/ directory");
        return Ok(false);
    }
    let rel = |p: &Path| format!("context/{}", rel_to(p, &ctx));

    // scopes: every directory outside blocks/, docs/, harness/, layouts/ needs scope.yml
    let reserved = |p: &Path| matches!(basename(&p.to_string_lossy()), "blocks" | "docs" | "harness" | "layouts");
    let dirs = find(&ctx, &reserved).into_iter().filter(|(_, ft)| ft.is_dir()).map(|(p, _)| p);
    for d in std::iter::once(ctx.clone()).chain(dirs) {
        if !d.join("scope.yml").is_file() {
            errs.push(format!("{}: scope directory has no scope.yml", rel(&d)));
        }
    }

    // files: no symlinks, no empty files, no instruction file names outside layouts/*/files/
    let mut files = vec![];
    for (p, ft) in find(&ctx, &|_| false) {
        let r = rel(&p);
        if ft.is_symlink() {
            errs.push(format!("{r}: symlinks are not allowed"));
        } else if ft.is_file() {
            if fs::metadata(&p).map_or(0, |m| m.len()) == 0 {
                errs.push(format!("{r}: empty file"));
            }
            if HARNESSES.iter().any(|h| h.instructions == basename(&r)) && !in_layout_files(&r) {
                errs.push(format!("{r}: instruction file names are only allowed in a layout's files/"));
            }
            files.push((p, r));
        }
    }

    // Delphi's own YAML (scope.yml, layout manifests) parses; scope recommendations exist
    let mut names: Vec<String> = vec![];
    let tmp = make_tmp()?;
    for (p, r) in files.iter().filter(|(_, r)| !in_layout_files(r)) {
        let layout = r.strip_suffix("/manifest.yml").filter(|d| basename(&d[..d.rfind('/').unwrap_or(0)]) == "layouts");
        if basename(r) != "scope.yml" && layout.is_none() {
            continue;
        }
        let y = match parse_yaml(p) {
            Ok(y) => y,
            Err(e) => {
                errs.push(format!("{e:#}"));
                continue;
            }
        };
        let Some(lay) = layout else {
            for s in y.list("recommend") {
                if !path_ok(&s) || !ctx.join(&s).exists() {
                    errs.push(format!("{r}: recommend: missing '{s}'"));
                }
            }
            continue;
        };
        let (name, dir) = (y.get("name"), basename(lay).to_string());
        if name != dir {
            errs.push(format!("{r}: name '{name}' must equal its directory '{dir}'"));
        }
        if names.contains(&name) {
            errs.push(format!("{r}: layout name '{name}' is not unique"));
        }
        names.push(name);
        for k in y.keys().into_iter().filter(|k| !KEYS.contains(&k.as_str())) {
            errs.push(format!("{r}: unknown key '{k}'"));
        }
        let h = y.get("harness");
        if !HARNESSES.iter().any(|x| x.name == h) {
            errs.push(format!("{r}: unknown or missing harness '{h}'"));
            continue;
        }
        let out = tmp.join(names.len().to_string());
        if let Err(e) = compile(root_dir, &lay["context/".len()..], &out) {
            let m = format!("{e:#}");
            errs.push(if m.starts_with("context/") { m } else { format!("{r}: {m}") });
        }
    }

    // moves.tsv: three fields, safe paths
    let moves = fs::read_to_string(root_dir.join("moves.tsv")).unwrap_or_default();
    for (n, l) in moves.lines().enumerate().filter(|(_, l)| !l.starts_with('#') && !l.is_empty()) {
        let f: Vec<&str> = l.split('\t').collect();
        if f.len() != 3 || !path_ok(f[0]) || !path_ok(f[1]) {
            errs.push(format!("moves.tsv:{}: expected old<TAB>new<TAB>date", n + 1));
        }
    }

    for e in &errs {
        eprintln!("check: {e}");
    }
    Ok(errs.is_empty())
}
