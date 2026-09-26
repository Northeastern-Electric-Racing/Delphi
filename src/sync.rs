//! `delphi sync [--check] [--base <rev>]` (spec §3). For every linked source file, its source and
//! all linked copies (across every workspace) are compared with the base revision(s): one distinct
//! new state is written everywhere, several are a conflict. Then generated files (instruction
//! file, MCP file) are regenerated from `instructions:` and `mcp:`. Works on any full Delphi working tree; deterministic and idempotent.

use crate::core::{
    commit, exit, find, git, join, out, out_q, out_stdin, parse_args, rel_to, root, safe_path, under, write_file,
};
use crate::workspace::{self, folder_of, Ws, YML};
use crate::{die, info};
use anyhow::Result;
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

pub fn main(args: &[String]) -> Result<()> {
    let (o, pos) = parse_args("--check --base", args)?;
    if !pos.is_empty() {
        die!("usage: delphi sync [--check] [--base <rev>]");
    }
    let base = match o.base.as_str() {
        "" => merge_base(root())?,
        rev => commit(root(), rev).ok_or_else(|| anyhow::anyhow!("not a revision: {rev}"))?,
    };
    let r = sync(root(), &[base], o.check)?;
    r.print(o.check);
    if !r.conflicts.is_empty() {
        info!("sync: {} conflict(s); fix them by hand, then re-run: delphi sync", r.conflicts.len());
        return Err(exit(1));
    }
    match (r.writes.len(), o.check) {
        (0, _) => info!("sync: ok"),
        (_, true) => {
            info!("sync: out of sync (run: delphi sync)");
            return Err(exit(1));
        }
        (n, false) => info!("sync: {n} file(s) written"),
    }
    Ok(())
}

/// The default base: merge-base of HEAD and origin/main.
pub fn merge_base(dir: &Path) -> Result<String> {
    match out_q(git(dir).args(["merge-base", "HEAD", "origin/main"])) {
        Some(b) => Ok(b),
        None => die!("no merge-base of HEAD and origin/main in {}; pass --base <rev>", dir.display()),
    }
}

/// A file's state: absent, or (executable, blob id).
type State = Option<(bool, String)>;

pub struct Report {
    /// (created|updated|deleted, repo-relative path)
    pub writes: Vec<(&'static str, String)>,
    pub conflicts: Vec<String>,
}

impl Report {
    pub fn print(&self, check: bool) {
        for (verb, p) in &self.writes {
            println!("  {}{verb} {p}", if check { "would be " } else { "" });
        }
        for c in &self.conflicts {
            info!("conflict: {c}");
        }
    }
}

/// A base revision: its files and each workspace's links.
struct Base {
    tree: HashMap<String, (bool, String)>,
    links: HashMap<String, Vec<(&'static str, String, String)>>,
}

fn load_base(dir: &Path, rev: &str) -> Base {
    let t = out(git(dir).args(["ls-tree", "-r", "--full-tree", rev, "--", "context"])).unwrap_or_default();
    let tree = t
        .lines()
        .filter_map(|l| {
            let (meta, path) = l.split_once('\t')?;
            let f: Vec<&str> = meta.split(' ').collect();
            let id = f.get(2).filter(|_| f.get(1) == Some(&"blob"))?;
            Some((path.to_string(), (f[0] == "100755", id.to_string())))
        })
        .collect();
    let links = workspace::all_at(dir, rev, false).into_iter().map(|w| (w.folder, w.links)).collect();
    Base { tree, links }
}

/// Files (relative) below `p` on disk and in the bases.
fn files_below(dir: &Path, bases: &[Base], p: &str) -> BTreeSet<String> {
    let abs = dir.join(p);
    let mut v: BTreeSet<String> = if abs.is_dir() {
        find(&abs, &|_| false).into_iter().filter(|(_, ft)| ft.is_file()).map(|(f, _)| rel_to(&f, &abs)).collect()
    } else {
        BTreeSet::new()
    };
    for b in bases {
        v.extend(b.tree.keys().filter_map(|k| under(k, p)).filter(|r| !r.is_empty()).map(String::from));
    }
    v
}

/// Current states of `paths` (blob ids via one `git hash-object`).
fn states<'a>(dir: &Path, paths: impl IntoIterator<Item = &'a String>) -> Result<HashMap<String, State>> {
    let (mut m, mut files) = (HashMap::new(), vec![]);
    for p in paths {
        match fs::symlink_metadata(safe_path(dir, p)?) {
            // executable = the owner's x bit, as git records it
            Ok(md) if md.is_file() => files.push((p.clone(), md.permissions().mode() & 0o100 != 0)),
            _ => drop(m.insert(p.clone(), None)),
        }
    }
    if !files.is_empty() {
        let input: String = files.iter().map(|(p, _)| format!("{p}\n")).collect();
        let Some(ids) = out_stdin(git(dir).args(["hash-object", "--stdin-paths"]), input.as_bytes()) else {
            die!("git hash-object failed")
        };
        for ((p, x), id) in files.into_iter().zip(ids.lines()) {
            m.insert(p, Some((x, id.to_string())));
        }
    }
    Ok(m)
}

/// The workspaces in the working tree at `dir`, sorted by folder.
pub fn workspaces(dir: &Path) -> Result<Vec<Ws>> {
    let ctx = dir.join("context");
    let mut v = vec![];
    for (p, ft) in find(&ctx, &|_| false) {
        let rel = format!("context/{}", rel_to(&p, &ctx));
        if let (true, Some(f)) = (ft.is_file(), folder_of(&rel)) {
            v.push(workspace::load(f, &String::from_utf8_lossy(&fs::read(&p)?), &rel)?);
        }
    }
    v.sort_by(|a, b| a.folder.cmp(&b.folder));
    Ok(v)
}

/// One group's writes `(path, target, a path holding the target)`, or a conflict.
type Writes = Vec<(String, State, Option<String>)>;

fn plan(src: &str, members: &[(String, bool)], cur: &HashMap<String, State>, bases: &[Base]) -> Result<Writes, String> {
    let sp = format!("context/{src}");
    let all: Vec<(&String, bool)> = std::iter::once((&sp, true)).chain(members.iter().map(|(p, o)| (p, *o))).collect();
    let st = |p: &String| cur.get(p).cloned().flatten();
    let changed: Vec<&String> = all
        .iter()
        .filter(|(p, old)| *old && !bases.iter().any(|b| b.tree.get(*p).cloned() == st(p)))
        .map(|x| x.0)
        .collect();
    let mut new: Vec<State> = changed.iter().map(|p| st(p)).collect();
    new.sort();
    new.dedup();
    let list = |v: &[&String]| v.iter().map(|p| p.as_str()).collect::<Vec<_>>().join(", ");
    let target = match new.len() {
        1 => new.remove(0),
        0 if st(&sp).is_some() => st(&sp),
        0 => {
            let present: Vec<&String> = all.iter().map(|x| x.0).filter(|p| st(p).is_some()).collect();
            let mut v: Vec<State> = present.iter().map(|p| st(p)).collect();
            v.sort();
            v.dedup();
            match v.len() {
                0 => return Ok(vec![]),
                1 => v.remove(0),
                _ => return Err(format!("{sp} is missing and its copies differ: {}", list(&present))),
            }
        }
        _ => return Err(format!("{sp}: different edits in {}", list(&changed))),
    };
    if let Some((p, _)) = all.iter().find(|(p, old)| !old && st(p).is_some() && st(p) != target) {
        return Err(format!("{p} is newly linked to {sp} but differs from it (delete it to take the source)"));
    }
    let from = all.iter().map(|x| x.0).find(|p| st(p) == target).cloned();
    Ok(all.iter().filter(|(p, _)| st(p) != target).map(|(p, _)| ((*p).clone(), target.clone(), from.clone())).collect())
}

/// Delete a file and the empty directories above it (up to `dir`).
fn remove(dir: &Path, f: &Path) {
    let _ = fs::remove_file(f);
    let mut d = f.parent();
    while let Some(p) = d.filter(|p| p.starts_with(dir) && *p != dir && fs::remove_dir(p).is_ok()) {
        d = p.parent();
    }
}

/// A generated file assembled from parts (instructions: joined by a blank line; mcp: wrapped in
/// `mcpServers`, joined by `,` lines), or the missing part.
fn assemble(dir: &Path, key: &str, parts: &[String]) -> Result<Result<Vec<u8>, String>> {
    let (head, sep, tail): (&[u8], &[u8], &[u8]) =
        if key == "mcp" { (b"{\"mcpServers\": {\n", b",\n", b"}}\n") } else { (b"", b"\n", b"") };
    let mut text = head.to_vec();
    for (i, p) in parts.iter().enumerate() {
        let Ok(t) = fs::read(safe_path(dir, &format!("context/{p}"))?) else { return Ok(Err(p.clone())) };
        if i > 0 {
            text.extend(sep);
        }
        text.extend(t);
        if text.last() != Some(&b'\n') {
            text.push(b'\n');
        }
    }
    text.extend(tail);
    Ok(Ok(text))
}

/// Every linked file grouped by its source (relative to context/): (copy path, whether its link
/// existed at a base). A directory link covers the files under its source and under every copy.
type Groups = BTreeMap<String, Vec<(String, bool)>>;

fn groups(dir: &Path, wss: &[Ws], bases: &[Base]) -> Groups {
    let mut groups = Groups::new();
    let mut dir_links = vec![];
    let in_base = |p: &str| bases.iter().any(|b| b.tree.contains_key(p));
    let under_base = |p: &str| bases.iter().any(|b| b.tree.keys().any(|k| under(k, p).is_some()));
    let add = |groups: &mut Groups, w: &Ws, s: String, d: String| {
        let mut old = bases.iter().filter_map(|b| b.links.get(&w.folder)).flatten();
        let old = old.any(|(_, bs, bd)| under(&s, bs).is_some_and(|r| join(bd, r) == d));
        let m = groups.entry(s).or_default();
        if !m.iter().any(|x| x.0 == w.path(&d)) {
            m.push((w.path(&d), old));
        }
    };
    for w in wss {
        for (_, src, dest) in &w.links {
            let (sp, dp) = (format!("context/{src}"), w.path(dest));
            let is_dir = match (dir.join(&sp).is_file(), dir.join(&sp).is_dir()) {
                (true, _) => false,
                (_, true) => true,
                _ => !in_base(&sp) && (under_base(&sp) || dir.join(&dp).is_dir() || under_base(&dp)),
            };
            if !is_dir {
                add(&mut groups, w, src.clone(), dest.clone());
                continue;
            }
            for rel in files_below(dir, bases, &sp).into_iter().chain(files_below(dir, bases, &dp)) {
                add(&mut groups, w, join(src, &rel), join(dest, &rel));
            }
            dir_links.push((w, src, dest));
        }
    }
    // a file new in one copy of a directory belongs in every copy
    for (w, src, dest) in dir_links {
        let keys: Vec<String> =
            groups.keys().filter(|k| under(k, src).is_some_and(|r| !r.is_empty())).cloned().collect();
        for k in keys {
            let d = join(dest, under(&k, src).unwrap_or(""));
            add(&mut groups, w, k, d);
        }
    }
    groups
}

/// Regenerate each workspace's generated files (`instructions:`, `mcp:`); a hand edit is a conflict.
fn generate(dir: &Path, wss: &[Ws], bases: &[Base], check: bool, r: &mut Report) -> Result<()> {
    for (w, (key, parts, file, what)) in wss.iter().flat_map(|w| w.generated().into_iter().map(move |g| (w, g))) {
        let text = match assemble(dir, key, parts)? {
            Ok(t) => t,
            Err(p) => {
                r.conflicts.push(format!("{}: {key}: missing context/{p}", w.path(YML)));
                continue;
            }
        };
        let ip = w.path(file);
        let f = safe_path(dir, &ip)?;
        let now = fs::read(&f).ok();
        if now.as_deref() == Some(&text[..]) {
            continue;
        }
        let st = states(dir, [&ip])?.remove(&ip).flatten();
        if now.is_some() && !bases.iter().any(|b| b.tree.get(&ip).cloned() == st) {
            r.conflicts.push(format!("{ip}: generated from {key}: in {YML} (don't hand-edit it; edit a {what})"));
            continue;
        }
        if !check {
            write_file(&f, &text, false, &ip)?;
        }
        r.writes.push((if now.is_none() { "created" } else { "updated" }, ip));
    }
    Ok(())
}

/// Reconcile the working tree at `dir` against base commits; with `check`, change nothing.
pub fn sync(dir: &Path, base_revs: &[String], check: bool) -> Result<Report> {
    let wss = workspaces(dir)?;
    let bases: Vec<Base> = base_revs.iter().map(|r| load_base(dir, r)).collect();
    let groups = groups(dir, &wss, &bases);
    let paths: BTreeSet<String> = groups
        .iter()
        .flat_map(|(s, m)| std::iter::once(format!("context/{s}")).chain(m.iter().map(|x| x.0.clone())))
        .collect();
    let cur = states(dir, &paths)?;
    let mut r = Report { writes: vec![], conflicts: vec![] };
    for (src, members) in &groups {
        let writes = match plan(src, members, &cur, &bases) {
            Ok(w) => w,
            Err(c) => {
                r.conflicts.push(c);
                continue;
            }
        };
        for (p, target, from) in writes {
            let verb = match (&target, cur.get(&p).cloned().flatten()) {
                (None, _) => "deleted",
                (_, None) => "created",
                _ => "updated",
            };
            if !check {
                let f = safe_path(dir, &p)?;
                match (target, from) {
                    (Some((x, _)), Some(from)) => write_file(&f, &fs::read(safe_path(dir, &from)?)?, x, &p)?,
                    _ => remove(dir, &f),
                }
            }
            r.writes.push((verb, p));
        }
    }
    generate(dir, &wss, &bases, check, &mut r)?;
    Ok(r)
}
