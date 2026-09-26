//! Per-file routing (spec §5): a workspace's pending diff -> items, the listings and PR body built
//! from them, and applying them to a PR worktree.

use crate::compile::{split_entry, Entry, Kind, Row, MANIFEST};
use crate::core::{delphi_commit, dgit, join, layout_manifests, out_q, path_ok, safe_path, show, under, write_file};
use crate::die;
use crate::parse::parse_text;
use crate::pr::Pr;
use crate::workspace::{Tree, Ws};
use anyhow::Result;
use std::fmt;

/// What happens to a changed file: copied over its source, a new source, the layout manifest
/// replaced, nothing, listed as unresolved, or kept local (never proposed).
#[derive(Clone, Copy, PartialEq)]
pub enum Act {
    Update,
    New,
    Manifest,
    Noop,
    Unresolved,
    Local,
}

impl fmt::Display for Act {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.pad(match self {
            Act::Update => "update",
            Act::New => "new",
            Act::Manifest => "manifest",
            Act::Noop => "noop",
            Act::Unresolved => "unresolved",
            Act::Local => "local",
        })
    }
}

pub struct Item {
    pub act: Act,
    pub dest: String,
    /// The source (relative to context/) for routed items, else the reason.
    pub target: String,
}

impl Item {
    pub fn routed(&self) -> bool {
        matches!(self.act, Act::Update | Act::New | Act::Manifest)
    }
}

/// What `git cat-file -t` says about `context/<p>` at a Delphi commit ("" if absent).
fn upstream_type(c: &str, p: &str) -> String {
    out_q(&mut dgit(["cat-file", "-t", &format!("{c}:context/{p}")])).unwrap_or_default()
}

/// What routing one file needs to know about the workspace.
struct Ctx {
    compile_commit: String,
    layout_path: String,
    lock: Vec<Row>,
    has_instructions: bool,
    syncs: Vec<Entry>,
    tree: Tree,
}

/// Route one pending change (git status letter `st`, path `o`) per the spec §5 table.
fn route(x: &Ctx, st: &str, o: &str) -> (Act, String) {
    let is = |act, why: &str| (act, why.to_string());
    let row = x.lock.iter().find(|r| r.dest == o);
    let link = x.tree.get(o).is_some_and(|(mode, _)| mode == "120000");
    if o == MANIFEST && st == "M" {
        (Act::Manifest, format!("{}/manifest.yml", x.layout_path))
    } else if o.starts_with(".delphi/") {
        is(Act::Unresolved, "Delphi bookkeeping; only .delphi/manifest.yml edits are proposed")
    } else if link || !matches!(st, "A" | "M" | "D") {
        is(Act::Unresolved, "symlink or unsupported change type")
    } else if let Some(r) = row {
        match (r.kind, st) {
            (Kind::Assembled, "D") if !x.has_instructions => {
                is(Act::Noop, "deleted; instructions were dropped from .delphi/manifest.yml")
            }
            (Kind::Assembled, _) => is(Act::Unresolved, "generated; sync a part to edit it"),
            (_, "M") => (Act::Update, r.source.clone()),
            (Kind::Sync, _) if !x.syncs.iter().any(|e| under(&r.source, &e.source).is_some()) => {
                is(Act::Noop, "deleted; its entry was removed from .delphi/manifest.yml")
            }
            (Kind::Sync, _) => {
                is(Act::Unresolved, "deleted, but still listed in .delphi/manifest.yml (remove its entry to drop it)")
            }
            _ => is(Act::Unresolved, "deleted, but still one of the layout's files/"),
        }
    } else if st != "A" {
        is(Act::Local, "not synced")
    } else if let Some(e) = x.syncs.iter().filter(|e| under(o, &e.dest).is_some()).max_by_key(|e| e.dest.len()) {
        // a new file inside a synced directory (the innermost entry wins)
        let t = join(&e.source, under(o, &e.dest).unwrap_or(""));
        if !path_ok(&t) {
            is(Act::Unresolved, "unsafe source path")
        } else if !upstream_type(&x.compile_commit, &t).is_empty() {
            is(Act::Unresolved, "its source already exists in Delphi; refresh after the manifest change merges")
        } else if upstream_type(&x.compile_commit, &e.source) == "blob" {
            is(Act::Unresolved, "inside a synced file's dest")
        } else {
            (Act::New, t)
        }
    } else {
        is(Act::Local, "new file, not in a synced directory")
    }
}

/// One source edited in several dests: identical edits route once, differing ones don't.
fn merge_same_source(v: &mut [Item], tree: &Tree) {
    for i in 0..v.len() {
        if !matches!(v[i].act, Act::Update | Act::New) {
            continue;
        }
        let same: Vec<usize> = (i + 1..v.len()).filter(|&j| v[j].routed() && v[j].target == v[i].target).collect();
        if same.is_empty() {
            continue;
        }
        let blob = |k: usize| tree.get(&v[k].dest);
        if same.iter().all(|&j| blob(j) == blob(i)) {
            let why = format!("same edit as {}", v[i].dest);
            for j in same {
                (v[j].act, v[j].target) = (Act::Noop, why.clone());
            }
        } else {
            let all: Vec<usize> = std::iter::once(i).chain(same).collect();
            let dests = all.iter().map(|&k| v[k].dest.as_str()).collect::<Vec<_>>().join(", ");
            let why = format!("differing edits to one source {} ({dests})", v[i].target);
            for k in all {
                (v[k].act, v[k].target) = (Act::Unresolved, why.clone());
            }
        }
    }
}

pub fn plan(ws: &Ws) -> Result<Vec<Item>> {
    let (y, syncs) = ws.manifest("HEAD")?;
    let x = Ctx {
        compile_commit: ws.meta("compile_commit"),
        layout_path: ws.meta("layout_path"),
        lock: ws.lock("generated-merged"),
        has_instructions: !y.list("instructions").is_empty(),
        syncs,
        tree: ws.tree("HEAD"),
    };
    let mut v: Vec<Item> = ws
        .pending()
        .into_iter()
        .map(|(st, dest)| {
            let (act, target) = route(&x, &st, &dest);
            Item { act, dest, target }
        })
        .collect();
    merge_same_source(&mut v, &x.tree);
    // copies the user changed are listed as local
    for cp in ws.copied() {
        if !v.iter().any(|it| it.dest == cp.dest)
            && x.tree.get(&cp.dest).map(|(_, b)| b) != ws.copied_blob(&cp).as_ref()
        {
            v.push(Item { act: Act::Local, dest: cp.dest, target: "copy (yours)".into() });
        }
    }
    Ok(v)
}

/// Sources used by other layouts on origin/main.
pub struct Shared(Vec<(String, Vec<String>)>);

impl Shared {
    pub fn load(me: &str) -> Shared {
        let Ok(c) = delphi_commit("main") else { return Shared(vec![]) };
        let mut v = vec![];
        for f in layout_manifests(&c) {
            let Some(y) = show(&c, &f).and_then(|t| parse_text(&String::from_utf8_lossy(&t), &f).ok()) else {
                continue;
            };
            let name = y.get("name");
            if name != me {
                let srcs = ["instructions", "sync", "copy"].iter().flat_map(|k| y.list(k));
                v.push((name, srcs.map(|s| split_entry(&s).0).collect()));
            }
        }
        Shared(v)
    }

    /// `  (shared: a, b)` when other layouts use `src`, else "".
    pub fn tag(&self, src: &str) -> String {
        let n: Vec<&str> =
            self.0.iter().filter(|(_, s)| s.iter().any(|e| under(src, e).is_some())).map(|(n, _)| n.as_str()).collect();
        if n.is_empty() {
            String::new()
        } else {
            format!("  (shared: {})", n.join(", "))
        }
    }
}

/// The `workspace diff` / `propose --dry-run` listing.
pub fn listing(items: &[Item], sh: &Shared) -> String {
    let mut s = String::new();
    for it in items.iter().filter(|i| i.act != Act::Unresolved) {
        s += &match it.act {
            Act::Noop | Act::Local => format!("  {:<9} {}  ({})\n", it.act, it.dest, it.target),
            _ => format!("  {:<9} {} -> {}{}\n", it.act, it.dest, it.target, sh.tag(&it.target)),
        };
    }
    let un: Vec<&Item> = items.iter().filter(|i| i.act == Act::Unresolved).collect();
    if !un.is_empty() {
        s += "Unresolved:\n";
        for it in un {
            s += &format!("  {}: {}\n", it.dest, it.target);
        }
    }
    s
}

/// The PR body: routed items, then unresolved ones with their diffs.
pub fn pr_body(items: &[Item], ws: &Ws, sh: &Shared) -> String {
    let mut b = String::from("## Routed changes\n\n");
    for it in items.iter().filter(|i| i.routed()) {
        b += &format!("- {}: `{}` (from `{}`){}\n", it.act, it.target, it.dest, sh.tag(&it.target));
    }
    b += "\n## Unresolved\n\n";
    let un: Vec<&Item> = items.iter().filter(|i| i.act == Act::Unresolved).collect();
    if un.is_empty() {
        b += "None.\n";
    }
    for it in un {
        b += &format!("#### `{}`: {}\n\n```diff\n{}\n```\n\n", it.dest, it.target, ws.diff_of(&it.dest));
    }
    b
}

/// Write the routed items into the PR worktree and commit them. False if nothing changed.
pub fn apply(items: &[Item], ws: &Ws, pr: &Pr) -> Result<bool> {
    let ctx = pr.wt.join("context");
    let tree = ws.tree("HEAD");
    for it in items.iter().filter(|i| i.routed()) {
        let from = if it.act == Act::Manifest { MANIFEST } else { it.dest.as_str() };
        let Some(data) = ws.show("HEAD", from) else { die!("cannot read {from}") };
        let exec = tree.get(from).is_some_and(|(m, _)| m == "100755");
        write_file(&safe_path(&ctx, &it.target)?, &data, exec, &it.target)?;
    }
    pr.commit(&format!("delphi: changes from workspace {}", ws.name), "")
}
