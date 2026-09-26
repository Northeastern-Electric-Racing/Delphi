//! Layout -> workspace files + `.delphi/lock.tsv`. Deterministic: same tree + layout = same output.
//!
//! Every compiled file is a 1:1 copy of one source file under `context/`, except the optional
//! instruction file assembled from `instructions:` parts. Lock rows are `dest<TAB>source<TAB>kind`
//! with kind `assembled` (one row per part), `sync`, `layout` (the layout's `files/` and its
//! manifest), or `copy` (listed only: copies are added to `working` once, never compiled).

use crate::core::{find, path_ok, rel_to, safe_path, under};
use crate::die;
use crate::harness::{self, Harness};
use crate::parse::{parse_yaml, Yaml};
use anyhow::Result;
use std::fs;
use std::path::Path;

pub const LOCK_HEADER: &str = "# dest\tsource\tkind\n";

/// A lock row.
pub struct Row {
    pub dest: String,
    pub source: String,
    pub kind: String,
}

pub fn parse_lock(text: &str) -> Vec<Row> {
    text.lines()
        .filter(|l| !l.starts_with('#') && !l.is_empty())
        .map(|l| {
            let f: Vec<&str> = l.split('\t').collect();
            let g = |i: usize| f.get(i).unwrap_or(&"").to_string();
            Row { dest: g(0), source: g(1), kind: g(2) }
        })
        .collect()
}

/// A `sync:` or `copy:` entry: `<source> [-> <dest>]`.
pub struct Entry {
    pub key: &'static str,
    pub source: String,
    pub dest: String,
}

/// Where a source goes when the entry has no `-> dest`.
pub fn default_dest(src: &str, h: &Harness) -> String {
    let c: Vec<&str> = src.split('/').collect();
    if let Some(i) = c.windows(2).position(|w| w == ["harness", "skills"]).filter(|i| i + 2 < c.len()) {
        return format!("{}/{}", h.skills_dir, c[i + 2..].join("/"));
    }
    match c.iter().position(|&x| x == "docs") {
        Some(i) => [&["docs"][..], &c[i + 1..]].concat().join("/"),
        None => format!("context/{src}"),
    }
}

/// Dests the workspace keeps for itself.
fn dest_ok(d: &str) -> bool {
    path_ok(d) && ![".git", ".delphi", "repos", "worktrees"].contains(&d.split('/').next().unwrap_or(""))
}

/// The `sync:` and `copy:` entries of a manifest (`name` labels errors).
pub fn entries(y: &Yaml, h: &Harness, name: &str) -> Result<Vec<Entry>> {
    let mut v = vec![];
    for key in ["sync", "copy"] {
        for raw in y.list(key) {
            let (s, d) = raw.split_once(" -> ").map_or((raw.as_str(), None), |(a, b)| (a, Some(b)));
            let t = |x: &str| x.trim_matches(' ').trim_end_matches('/').to_string();
            let source = t(s);
            let dest = d.map_or_else(|| default_dest(&source, h), t);
            if !path_ok(&source) || source.contains(" -> ") {
                die!("{name}: {key}: bad source in '{raw}'");
            }
            if !dest_ok(&dest) {
                die!("{name}: {key}: unsafe dest in '{raw}'");
            }
            v.push(Entry { key, source, dest });
        }
    }
    Ok(v)
}

/// The source files a source path names, with their path below it ("" for a file).
pub fn expand(ctx: &Path, src: &str) -> Result<Vec<(String, String)>> {
    let abs = safe_path(ctx, src)?;
    if abs.is_file() {
        return Ok(vec![(src.to_string(), String::new())]);
    }
    if !abs.is_dir() {
        die!("missing context/{src}");
    }
    let mut v = vec![];
    for (p, ft) in find(&abs) {
        let rel = rel_to(&p, &abs);
        if ft.is_symlink() {
            die!("symlink: context/{src}/{rel}");
        }
        if ft.is_file() {
            v.push((format!("{src}/{rel}"), rel));
        }
    }
    if v.is_empty() {
        die!("no files in context/{src}");
    }
    v.sort();
    Ok(v)
}

fn join(d: &str, rel: &str) -> String {
    if rel.is_empty() {
        d.to_string()
    } else {
        format!("{d}/{rel}")
    }
}

/// Copy a source file to `out/dest` (mode kept).
fn put(out: &Path, dest: &str, src: &Path) -> Result<()> {
    let o = safe_path(out, dest)?;
    let made = o.parent().is_some_and(|p| fs::create_dir_all(p).is_ok()) && fs::copy(src, &o).is_ok();
    if !made {
        die!("cannot write {dest}");
    }
    Ok(())
}

/// Compile layout `layout` (dir relative to `src/context`) into the empty dir `out`.
pub fn compile(src: &Path, layout: &str, out: &Path) -> Result<&'static Harness> {
    let ctx = src.join("context");
    let mfp = format!("{layout}/manifest.yml");
    let y = parse_yaml(&safe_path(&ctx, &mfp)?)?;
    let h = harness::load(&y.get("harness"))?;
    let label = format!("context/{mfp}");
    let ents = entries(&y, h, &label)?;
    let mut lock = String::from(LOCK_HEADER);
    // (dest, files below it for a directory entry; None for a single file)
    let mut dests: Vec<(String, Option<Vec<String>>)> = vec![];
    let mut puts: Vec<(String, String)> = vec![]; // (dest, source), written once dests are checked
    let mut row = |d: &str, s: &str, k: &str| lock.push_str(&format!("{d}\t{s}\t{k}\n"));

    let files_dir = format!("{layout}/files");
    let files = if safe_path(&ctx, &files_dir)?.is_dir() { expand(&ctx, &files_dir)? } else { vec![] };
    let parts = y.list("instructions");
    if !parts.is_empty() {
        if files.iter().any(|(_, rel)| rel == h.instructions) {
            die!("{label}: uses both instructions: and files/{}", h.instructions);
        }
        let mut text = Vec::new();
        for p in &parts {
            let f = safe_path(&ctx, p)?;
            if !f.is_file() {
                die!("{label}: instructions: missing file context/{p}");
            }
            if !text.is_empty() {
                text.push(b'\n');
            }
            text.extend(fs::read(&f)?);
            if text.last() != Some(&b'\n') {
                text.push(b'\n');
            }
            row(h.instructions, p, "assembled");
        }
        fs::write(safe_path(out, h.instructions)?, text)?;
        dests.push((h.instructions.into(), None));
    }
    for e in &ents {
        let src = expand(&ctx, &e.source).map_err(|x| anyhow::anyhow!("{label}: {}: {x}", e.key))?;
        let is_dir = src.iter().any(|(_, rel)| !rel.is_empty());
        for (s, rel) in &src {
            let d = join(&e.dest, rel);
            row(&d, s, e.key);
            if e.key == "sync" {
                puts.push((d, s.clone()));
            }
        }
        dests.push((e.dest.clone(), is_dir.then(|| src.into_iter().map(|x| x.1).collect())));
    }
    for (s, rel) in &files {
        if !dest_ok(rel) {
            die!("{label}: files/{rel}: reserved workspace path");
        }
        row(rel, s, "layout");
        puts.push((rel.clone(), s.clone()));
        dests.push((rel.clone(), None));
    }
    row(".delphi/manifest.yml", &mfp, "layout");
    puts.push((".delphi/manifest.yml".into(), mfp.clone()));
    // a file may sit inside a directory entry's dest when that directory has nothing at its path
    let fits =
        |f: &(String, Option<Vec<String>>), d: &(String, Option<Vec<String>>)| match (&f.1, &d.1, under(&f.0, &d.0)) {
            (None, Some(files), Some(rel)) if !rel.is_empty() => {
                !files.iter().any(|x| under(rel, x).is_some() || under(x, rel).is_some())
            }
            _ => false,
        };
    for (i, a) in dests.iter().enumerate() {
        for b in &dests[i + 1..] {
            let nested = under(&a.0, &b.0).is_some() || under(&b.0, &a.0).is_some();
            if nested && !fits(a, b) && !fits(b, a) {
                die!("{label}: dests overlap: '{}' and '{}'", a.0, b.0);
            }
        }
    }
    for (d, s) in &puts {
        put(out, d, &ctx.join(s))?;
    }
    fs::write(out.join(".delphi/lock.tsv"), lock)?;
    Ok(h)
}
