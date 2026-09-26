//! Per-file routing (spec §5): a workspace's pending diff -> items, and applying them to a PR
//! worktree. Item kinds: `update` (copy over its source), `new` (create a source), `manifest`
//! (replace the layout manifest), `noop`, `unresolved`, `local` (never proposed).

use crate::compile::{entries, Row};
use crate::core::{delphi_commit, dgit, layout_manifests, out_q, path_ok, safe_path, show, under};
use crate::die;
use crate::harness;
use crate::parse::parse_text;
use crate::pr::Pr;
use crate::workspace::Ws;
use anyhow::Result;
use std::fs;
use std::os::unix::fs::PermissionsExt;

pub struct Item {
    pub kind: &'static str,
    pub dest: String,
    /// The source (relative to context/) for routed items, else the reason.
    pub target: String,
}

impl Item {
    pub fn routed(&self) -> bool {
        matches!(self.kind, "update" | "new" | "manifest")
    }
}

const MANIFEST: &str = ".delphi/manifest.yml";

/// What `git cat-file -t` says about `context/<p>` at a Delphi commit ("" if absent).
fn upstream_type(c: &str, p: &str) -> String {
    out_q(&mut dgit(["cat-file", "-t", &format!("{c}:context/{p}")])).unwrap_or_default()
}

fn join(d: &str, rel: &str) -> String {
    if rel.is_empty() {
        d.to_string()
    } else {
        format!("{d}/{rel}")
    }
}

pub fn plan(ws: &Ws) -> Result<Vec<Item>> {
    let h = harness::load(&ws.meta("harness"))?;
    let cc = ws.meta("compile_commit");
    let lp = ws.meta("layout_path");
    let lock: Vec<Row> = ws.lock("generated-merged");
    let Some(m) = ws.show("HEAD", MANIFEST) else { die!("cannot read {MANIFEST}") };
    let y = parse_text(&String::from_utf8_lossy(&m), MANIFEST)?;
    let syncs: Vec<_> = entries(&y, h, MANIFEST)?.into_iter().filter(|e| e.key == "sync").collect();
    let tree = ws.tree("HEAD");
    let mut v: Vec<Item> = vec![];
    for (st, o) in ws.pending() {
        let it = |kind, t: &str| Item { kind, dest: o.clone(), target: t.to_string() };
        let row = lock.iter().find(|r| r.dest == o);
        let link = tree.get(&o).is_some_and(|(mode, _)| mode == "120000");
        v.push(if o == MANIFEST && st == "M" {
            it("manifest", &format!("{lp}/manifest.yml"))
        } else if o.starts_with(".delphi/") {
            it("unresolved", "Delphi bookkeeping; only .delphi/manifest.yml edits are proposed")
        } else if link || !matches!(st.as_str(), "A" | "M" | "D") {
            it("unresolved", "symlink or unsupported change type")
        } else if row.is_some_and(|r| r.kind == "assembled") {
            if st == "D" && y.list("instructions").is_empty() {
                it("noop", "deleted; instructions were dropped from .delphi/manifest.yml")
            } else {
                it("unresolved", "generated; sync a part to edit it")
            }
        } else if let Some(r) = row {
            if st == "M" {
                it("update", &r.source)
            } else if r.kind == "sync" && !syncs.iter().any(|e| under(&r.source, &e.source).is_some()) {
                it("noop", "deleted; its entry was removed from .delphi/manifest.yml")
            } else if r.kind == "sync" {
                it("unresolved", "deleted, but still listed in .delphi/manifest.yml (remove its entry to drop it)")
            } else {
                it("unresolved", "deleted, but still one of the layout's files/")
            }
        } else if st != "A" {
            it("local", "not synced")
        } else if let Some(e) = syncs.iter().filter(|e| under(&o, &e.dest).is_some()).max_by_key(|e| e.dest.len()) {
            let t = join(&e.source, under(&o, &e.dest).unwrap_or(""));
            let up = upstream_type(&cc, &e.source);
            if !path_ok(&t) {
                it("unresolved", "unsafe source path")
            } else if !upstream_type(&cc, &t).is_empty() {
                it("unresolved", "its source already exists in Delphi; refresh after the manifest change merges")
            } else if up == "blob" {
                it("unresolved", "inside a synced file's dest")
            } else {
                it("new", &t)
            }
        } else {
            it("local", "new file, not in a synced directory")
        });
    }
    // one source edited in several dests: identical edits route once, differing ones don't
    for i in 0..v.len() {
        if !matches!(v[i].kind, "update" | "new") {
            continue;
        }
        let same: Vec<usize> = (i + 1..v.len()).filter(|&j| v[j].routed() && v[j].target == v[i].target).collect();
        if same.is_empty() {
            continue;
        }
        let blob = |k: usize| tree.get(&v[k].dest).cloned();
        if same.iter().all(|&j| blob(j) == blob(i)) {
            for j in same {
                v[j] = Item { kind: "noop", dest: v[j].dest.clone(), target: format!("same edit as {}", v[i].dest) };
            }
        } else {
            let all: Vec<usize> = std::iter::once(i).chain(same).collect();
            let dests = all.iter().map(|&k| v[k].dest.clone()).collect::<Vec<_>>().join(", ");
            let why = format!("differing edits to one source {} ({dests})", v[i].target);
            for k in all {
                v[k] = Item { kind: "unresolved", dest: v[k].dest.clone(), target: why.clone() };
            }
        }
    }
    // copies the user changed are listed as local
    for (d, s, c) in ws.copied() {
        let theirs = ws.copied_blob(&s, &c);
        if !v.iter().any(|it| it.dest == d) && tree.get(&d).map(|(_, b)| b) != theirs.as_ref() {
            v.push(Item { kind: "local", dest: d, target: "copy (yours)".into() });
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
                let srcs = srcs.map(|s| s.split(" -> ").next().unwrap_or("").trim_end_matches('/').to_string());
                v.push((name, srcs.collect()));
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
    for it in items.iter().filter(|i| i.kind != "unresolved") {
        s.push_str(&match it.kind {
            "noop" | "local" => format!("  {:<9} {}  ({})\n", it.kind, it.dest, it.target),
            _ => format!("  {:<9} {} -> {}{}\n", it.kind, it.dest, it.target, sh.tag(&it.target)),
        });
    }
    let un: Vec<&Item> = items.iter().filter(|i| i.kind == "unresolved").collect();
    if !un.is_empty() {
        s.push_str("Unresolved:\n");
        for it in un {
            s.push_str(&format!("  {}: {}\n", it.dest, it.target));
        }
    }
    s
}

/// The PR body: routed items, then unresolved ones with their diffs.
pub fn pr_body(items: &[Item], ws: &Ws, sh: &Shared) -> String {
    let mut b = String::from("## Routed changes\n\n");
    for it in items.iter().filter(|i| i.routed()) {
        b.push_str(&format!("- {}: `{}` (from `{}`){}\n", it.kind, it.target, it.dest, sh.tag(&it.target)));
    }
    b.push_str("\n## Unresolved\n\n");
    let un: Vec<&Item> = items.iter().filter(|i| i.kind == "unresolved").collect();
    if un.is_empty() {
        b.push_str("None.\n");
    }
    for it in un {
        let d = ws.diff_of(&it.dest);
        b.push_str(&format!("#### `{}`: {}\n\n```diff\n{d}\n```\n\n", it.dest, it.target));
    }
    b
}

/// Write the routed items into the PR worktree and commit them.
pub fn apply(items: &[Item], ws: &Ws, pr: &Pr) -> Result<()> {
    let ctx = pr.wt.join("context");
    let tree = ws.tree("HEAD");
    for it in items.iter().filter(|i| i.routed()) {
        let from = if it.kind == "manifest" { MANIFEST } else { it.dest.as_str() };
        let dst = safe_path(&ctx, &it.target)?;
        let Some(data) = ws.show("HEAD", from) else { die!("cannot read {from}") };
        let mode = if tree.get(from).is_some_and(|(m, _)| m == "100755") { 0o755 } else { 0o644 };
        let wrote = dst.parent().is_some_and(|p| fs::create_dir_all(p).is_ok())
            && fs::write(&dst, data).is_ok()
            && fs::set_permissions(&dst, fs::Permissions::from_mode(mode)).is_ok();
        if !wrote {
            die!("cannot write {}", it.target);
        }
    }
    pr.commit(&format!("delphi: changes from workspace {}", ws.name), "")?;
    Ok(())
}
