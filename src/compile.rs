//! Layout -> workspace files + `.delphi/lock.tsv`. Deterministic: same tree + layout = same output.
//!
//! Every compiled file is a 1:1 copy of one source file under `context/`, except the optional
//! instruction file assembled from `instructions:` parts. Lock rows are `dest<TAB>source<TAB>kind`
//! (see `Kind`); copies are listed only (added to `working` once, never compiled).

use crate::core::{find, join, path_ok, rel_to, safe_path, under};
use crate::die;
use crate::harness::{self, Harness};
use crate::parse::{parse_yaml, Yaml};
use anyhow::Result;
use std::fmt;
use std::fs;
use std::path::Path;

pub const MANIFEST: &str = ".delphi/manifest.yml";
pub const LOCK: &str = ".delphi/lock.tsv";

/// What a lock row's dest is: part of the assembled instruction file, a synced file, one of the
/// layout's own files (its `files/` and manifest), or a copy.
#[derive(Clone, Copy, PartialEq)]
pub enum Kind {
    Assembled,
    Sync,
    Layout,
    Copy,
}

impl fmt::Display for Kind {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.pad(match self {
            Kind::Assembled => "assembled",
            Kind::Sync => "sync",
            Kind::Layout => "layout",
            Kind::Copy => "copy",
        })
    }
}

/// A lock row.
pub struct Row {
    pub dest: String,
    pub source: String,
    pub kind: Kind,
}

pub fn parse_lock(text: &str) -> Vec<Row> {
    let kinds = [Kind::Assembled, Kind::Sync, Kind::Layout, Kind::Copy];
    text.lines()
        .filter_map(|l| {
            let mut f = l.split('\t');
            let (dest, source, k) = (f.next()?, f.next()?, f.next()?);
            let kind = *kinds.iter().find(|x| x.to_string() == k)?;
            Some(Row { dest: dest.into(), source: source.into(), kind })
        })
        .collect()
}

/// A `sync:` or `copy:` entry: `<source> [-> <dest>]`.
pub struct Entry {
    pub kind: Kind,
    pub source: String,
    pub dest: String,
}

/// An entry's source and explicit dest (trimmed, trailing `/` dropped).
pub fn split_entry(raw: &str) -> (String, Option<String>) {
    let t = |x: &str| x.trim_matches(' ').trim_end_matches('/').to_string();
    raw.split_once(" -> ").map_or_else(|| (t(raw), None), |(s, d)| (t(s), Some(t(d))))
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
    for (key, kind) in [("sync", Kind::Sync), ("copy", Kind::Copy)] {
        for raw in y.list(key) {
            let (source, dest) = split_entry(&raw);
            let dest = dest.unwrap_or_else(|| default_dest(&source, h));
            if !path_ok(&source) {
                die!("{name}: {key}: bad source in '{raw}'");
            }
            if !dest_ok(&dest) {
                die!("{name}: {key}: unsafe dest in '{raw}'");
            }
            v.push(Entry { kind, source, dest });
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
    for (p, ft) in find(&abs, &|_| false) {
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

/// A dest and, for a directory entry, the files below it.
type Dest = (String, Option<Vec<String>>);

/// Dests are unique and never nested, except that a file may sit inside a directory entry's dest
/// when that directory has nothing at its path.
fn check_dests(label: &str, dests: &[Dest]) -> Result<()> {
    let fits = |f: &Dest, d: &Dest| match (&f.1, &d.1, under(&f.0, &d.0)) {
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
    Ok(())
}

/// Compile layout `layout` (dir relative to `src/context`) into the new dir `out`.
pub fn compile(src: &Path, layout: &str, out: &Path) -> Result<&'static Harness> {
    let ctx = src.join("context");
    let mfp = format!("{layout}/manifest.yml");
    let y = parse_yaml(&safe_path(&ctx, &mfp)?)?;
    let h = harness::load(&y.get("harness"))?;
    let label = format!("context/{mfp}");
    let ents = entries(&y, h, &label)?;
    let files_dir = format!("{layout}/files");
    let files = if safe_path(&ctx, &files_dir)?.is_dir() { expand(&ctx, &files_dir)? } else { vec![] };
    let row = |dest: &str, source: &str, kind| Row { dest: dest.into(), source: source.into(), kind };
    let (mut rows, mut dests, mut text) = (vec![], vec![], vec![]);

    let parts = y.list("instructions");
    if !parts.is_empty() {
        if files.iter().any(|(_, rel)| rel == h.instructions) {
            die!("{label}: uses both instructions: and files/{}", h.instructions);
        }
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
            rows.push(row(h.instructions, p, Kind::Assembled));
        }
        dests.push((h.instructions.to_string(), None));
    }
    for e in ents {
        let src = expand(&ctx, &e.source).map_err(|x| anyhow::anyhow!("{label}: {}: {x}", e.kind))?;
        let is_dir = src.iter().any(|(_, rel)| !rel.is_empty());
        rows.extend(src.iter().map(|(s, rel)| row(&join(&e.dest, rel), s, e.kind)));
        dests.push((e.dest, is_dir.then(|| src.into_iter().map(|x| x.1).collect())));
    }
    for (s, rel) in &files {
        if !dest_ok(rel) {
            die!("{label}: files/{rel}: reserved workspace path");
        }
        rows.push(row(rel, s, Kind::Layout));
        dests.push((rel.clone(), None));
    }
    rows.push(row(MANIFEST, &mfp, Kind::Layout));
    check_dests(&label, &dests)?;

    fs::create_dir_all(out.join(".delphi"))?;
    if !parts.is_empty() {
        fs::write(safe_path(out, h.instructions)?, text)?;
    }
    for r in rows.iter().filter(|r| matches!(r.kind, Kind::Sync | Kind::Layout)) {
        let o = safe_path(out, &r.dest)?;
        if !(o.parent().is_some_and(|p| fs::create_dir_all(p).is_ok()) && fs::copy(ctx.join(&r.source), &o).is_ok()) {
            die!("cannot write {}", r.dest);
        }
    }
    let lock: String = rows.iter().map(|r| format!("{}\t{}\t{}\n", r.dest, r.source, r.kind)).collect();
    fs::write(out.join(LOCK), format!("# dest\tsource\tkind\n{lock}"))?;
    Ok(h)
}
