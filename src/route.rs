//! A workspace's pending diff -> edits against the Delphi tree (spec §8). Port of lib/route.sh
//! and lib/route.awk.
//!
//! `plan` routes `generated-merged..HEAD` of a workspace. Plan rows:
//!   manifest <out> <layout manifest>
//!   patch    <out> <block> <patchfile>
//!   key      <out> <spec> <key> <value>
//!   new      <out> <target> [<manifest key> <entry>]
//!   fragment <out> <target> <file> <after: instructions entry or ->  (a new instruction section)
//!   noop     <out> <reason>
//!   unresolved <out> <reason>
//! `unresolved` holds one markdown section per unresolved item (for the PR body).
//! `apply` applies the plan inside the PR worktree, one commit per step (manifest, edits, new
//! files); rows that applied go to `applied`, failures to the unresolved items.

use crate::core::{
    awk_lines, basename, dgit, git_c, make_tmp, num, ok_q, out, path_ok, safe_path, scope_of_layout, substr,
    write_replace,
};
use crate::die;
use crate::harness::{self, Harness};
use crate::parse::parse_yaml;
use crate::pr::Pr;
use crate::workspace::Ws;
use anyhow::Result;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

pub struct Route {
    dir: PathBuf,
    pub plan: Vec<Vec<String>>,
    pub unresolved: String,
    pub applied: Vec<Vec<String>>,
    lock: Vec<Vec<String>>,
    entries: Vec<String>,
    h: &'static Harness,
}

fn row(v: &[&str]) -> Vec<String> {
    v.iter().map(|s| s.to_string()).collect()
}

fn field(r: &[String], i: usize) -> &str {
    r.get(i).map_or("", String::as_str)
}

/// An entry names the path, a parent dir, or a `*/` glob over it.
pub fn covered(p: &str, entries: &[String]) -> bool {
    entries.iter().any(|e| {
        if e == p || p.starts_with(&format!("{e}/")) {
            return true;
        }
        match e.strip_suffix('*') {
            Some(dir) if e.ends_with("/*") => p.starts_with(dir) && !p[dir.len()..].contains('/'),
            _ => false,
        }
    })
}

fn upstream_has(commit: &str, path: &str) -> bool {
    ok_q(&mut dgit(["cat-file", "-e", &format!("{commit}:context/{path}")]))
}

impl Route {
    fn row(&mut self, v: &[&str]) {
        self.plan.push(row(v));
    }

    /// File-level unresolved item, with the file's diff.
    fn unres(&mut self, ws: &Ws, o: &str, reason: &str) {
        self.row(&["unresolved", o, reason]);
        let d = out(ws.git().args([
            "diff",
            "--no-renames",
            "--no-ext-diff",
            "--no-color",
            "generated-merged",
            "HEAD",
            "--",
            o,
        ]))
        .unwrap_or_default();
        let mut p = false;
        let d: Vec<&str> = awk_lines(&d)
            .into_iter()
            .filter(|l| {
                p |= l.starts_with("@@") || l.starts_with("Binary");
                p
            })
            .collect();
        self.unresolved.push_str(&format!("#### `{o}`: {reason}\n\n```diff\n{}\n```\n\n", d.join("\n")));
    }

    /// Source of the compiled skill dir holding <out>: a .skill spec (built), a native skill dir,
    /// or empty when that skill dir is not compiled.
    fn skill_src(&self, o: &str) -> String {
        let sk = format!("{}/", self.h.skills_dir);
        let rest = o.strip_prefix(&sk).unwrap_or(o);
        let p = format!("{sk}{}/", rest.split('/').next().unwrap_or(""));
        let (mut g, mut d) = (String::new(), String::new());
        for r in &self.lock {
            let (out1, src) = (field(r, 0), field(r, 3));
            if !out1.starts_with(&p) {
                continue;
            }
            if let Some(s) = src.strip_prefix("@gen:") {
                g = s.to_string();
            }
            if !src.starts_with('@') && d.is_empty() {
                let n = |s: &str| s.chars().count() as i64;
                d = substr(src, 1, Some(n(src) - n(out1) + n(&p) - 1));
            }
        }
        if g.is_empty() {
            d
        } else {
            g
        }
    }

    fn in_skill_dir(&self, o: &str) -> bool {
        o.strip_prefix(&format!("{}/", self.h.skills_dir)).is_some_and(|r| r.contains('/'))
    }

    /// The deleted output's sources are gone from the workspace manifest. Anything in a built
    /// skill's dir counts as dropped only when its .skill spec is.
    fn dropped(&self, o: &str) -> bool {
        if self.in_skill_dir(o) {
            let s = self.skill_src(o);
            if s.ends_with(".skill") {
                return !covered(&s, &self.entries);
            }
        }
        !self
            .lock
            .iter()
            .any(|r| field(r, 0) == o && !field(r, 3).starts_with('@') && covered(field(r, 3), &self.entries))
    }

    /// A new file, unless the target exists upstream.
    fn new_file(&mut self, ws: &Ws, o: &str, target: &str, extra: &[&str]) {
        if upstream_has(&ws.meta("compile_commit"), target) {
            self.unres(ws, o, "exists upstream; add it via the manifest instead");
        } else {
            let mut v = vec!["new", o, target];
            v.extend_from_slice(extra);
            self.row(&v);
        }
    }

    /// A new instruction fragment at the layout scope's harness/instructions/<slug>.md, suffixed
    /// -2, -3, … past names taken upstream or in this plan.
    fn fragment(&mut self, rc: &str, lp: &str, o: &str, slug: &str, file: &str, after: &str) {
        let base = format!("{}harness/instructions/{slug}", scope_of_layout(lp));
        let mut t = format!("{base}.md");
        let mut n = 1;
        while upstream_has(rc, &t) || self.plan.iter().any(|r| field(r, 0) == "fragment" && field(r, 2) == t) {
            n += 1;
            t = format!("{base}-{n}.md");
        }
        self.row(&["fragment", o, &t, file, after]);
    }
}

pub fn plan(ws: &Ws) -> Result<Route> {
    let dir = make_tmp()?;
    fs::create_dir_all(dir.join("p"))?;
    let rc = ws.meta("compile_commit");
    let lp = ws.meta("layout_path");
    let h = harness::load(&ws.meta("harness"))?;
    let Some(lock) = out(ws.git().args(["show", "generated-merged:.delphi/lock.tsv"])) else {
        die!("cannot read lock")
    };
    let lock = awk_lines(&lock)
        .into_iter()
        .filter(|l| !l.starts_with('#'))
        .map(|l| l.split('\t').map(String::from).collect())
        .collect();
    let (ok, m) = crate::core::out_raw(ws.git().args(["show", "HEAD:.delphi/manifest.yml"]));
    let mpath = dir.join("manifest.yml");
    fs::write(&mpath, &m)?;
    if !ok {
        die!("cannot read .delphi/manifest.yml");
    }
    let entries = parse_yaml(&mpath)?.values();
    let mut rt = Route { dir, plan: vec![], unresolved: String::new(), applied: vec![], lock, entries, h };
    let numstat = ws.pending(&["--numstat"]);
    let files = ws.pending(&["--name-status"]);
    let sk = h.skills_dir;
    let mut n = 0;
    for line in awk_lines(&files) {
        let line = line.trim_matches('\t');
        let (st, o) = line.split_once('\t').map_or((line, ""), |(a, b)| (a, b.trim_start_matches('\t')));
        if st == "M" && o == ".delphi/manifest.yml" {
            rt.row(&["manifest", o, &format!("{lp}/manifest.yml")]);
            continue;
        }
        if o.starts_with(".delphi/") {
            rt.unres(ws, o, "Delphi bookkeeping file; only .delphi/manifest.yml edits are proposed");
            continue;
        }
        let binary = awk_lines(&numstat).iter().any(|l| {
            let f: Vec<&str> = l.split('\t').collect();
            f.get(2) == Some(&o) && f[0] == "-"
        });
        if binary {
            rt.unres(ws, o, "binary file");
            continue;
        }
        match st {
            "D" => {
                if rt.dropped(o) {
                    rt.row(&["noop", o, "deleted; its source was dropped from .delphi/manifest.yml"]);
                } else {
                    rt.unres(
                        ws,
                        o,
                        "deleted, but still compiled by .delphi/manifest.yml (drop blocks by editing the manifest)",
                    );
                }
            }
            "M" => {
                let seg: Vec<Vec<String>> = rt.lock.iter().filter(|r| field(r, 0) == o).cloned().collect();
                if seg.is_empty() {
                    rt.unres(ws, o, "not a compiled file");
                    continue;
                }
                n += 1;
                let (_, diff) = crate::core::out_raw(ws.git().args([
                    "diff",
                    "-U0",
                    "--no-renames",
                    "--no-ext-diff",
                    "--no-color",
                    "generated-merged",
                    "HEAD",
                    "--",
                    o,
                ]));
                let diff = String::from_utf8_lossy(&diff).into_owned();
                if !diff.lines().any(|l| l.starts_with("@@")) {
                    rt.unres(ws, o, "mode-only change");
                    continue;
                }
                let rows = route_file(o, &seg, &diff, &rt.dir.join("p"), n, o == h.instructions, &mut rt.unresolved)?;
                rt.plan.extend(rows.iter().filter(|r| r[0] != "fragment").cloned());
                for r in rows.iter().filter(|r| r[0] == "fragment") {
                    rt.fragment(&rc, &lp, &r[1], &r[2], &r[3], &r[4]);
                }
            }
            "A" => {
                if let Some(p) = o.strip_prefix("context/") {
                    let s = format!("/{p}");
                    let scope = s.find("/blocks/").map(|i| s[..i].strip_prefix('/').unwrap_or(&s[..i]).to_string());
                    let scope_yml =
                        |sc: &str| if sc.is_empty() { "scope.yml".to_string() } else { format!("{sc}/scope.yml") };
                    match scope {
                        Some(sc) if path_ok(p) && upstream_has(&rc, &scope_yml(&sc)) => {
                            rt.new_file(ws, o, p, &["blocks", p])
                        }
                        _ => rt.unres(ws, o, "new file: must be under context/<existing scope>/blocks/"),
                    }
                } else if o.len() > 5 && o.starts_with("docs/") {
                    let d = format!("{}/", &o[..o.rfind('/').unwrap_or(0)]);
                    let hit = rt.lock.iter().find(|r| {
                        let (o1, s) = (field(r, 0), field(r, 3));
                        o1.starts_with(&d) && !o1[d.len()..].contains('/') && s.contains("/docs/")
                    });
                    let p = match hit {
                        Some(r) => {
                            let s = field(r, 3);
                            format!("{}{}", &s[..s.rfind('/').map_or(0, |i| i + 1)], basename(o))
                        }
                        None => format!("{}{o}", scope_of_layout(&lp)),
                    };
                    if path_ok(&p) {
                        rt.new_file(ws, o, &p, &["docs", &p]);
                    } else {
                        rt.unres(ws, o, "unsafe path");
                    }
                } else if rt.in_skill_dir(o) {
                    let rest = &o[sk.len() + 1..];
                    let name = rest.split('/').next().unwrap_or("");
                    let rest = &rest[name.len() + 1..];
                    let src = rt.skill_src(o);
                    if src.is_empty() {
                        let src = format!("{}harness/skills/{name}", scope_of_layout(&lp));
                        rt.new_file(ws, o, &format!("{src}/{rest}"), &["skills", &src]);
                    } else if src.ends_with(".skill") {
                        rt.unres(
                            ws,
                            o,
                            "new file in a built (.skill) skill: add it as a block and list it in the spec",
                        );
                    } else {
                        rt.new_file(ws, o, &format!("{src}/{rest}"), &[]);
                    }
                } else {
                    rt.unres(
                        ws,
                        o,
                        &format!("new file: must be under context/<scope>/blocks/, docs/, or {sk}/<name>/"),
                    );
                }
            }
            _ => rt.unres(ws, o, &format!("unsupported change type '{st}'")),
        }
    }
    Ok(rt)
}

/// Add `  - entry` to a top-level list, creating the key; after item <after> (- = first), else
/// at the end.
fn list_add(file: &Path, key: &str, v: &str, after: &str) -> Result<()> {
    let text = String::from_utf8_lossy(&fs::read(file)?).into_owned();
    let mut res = String::new();
    let (mut ins, mut done) = (false, false);
    let put = |res: &mut String, done: &mut bool| {
        if !*done {
            res.push_str(&format!("  - {v}\n"));
        }
        *done = true;
    };
    for l in awk_lines(&text) {
        if ins && !l.starts_with("  - ") {
            put(&mut res, &mut done);
            ins = false;
        }
        res.push_str(l);
        res.push('\n');
        if ins && !after.is_empty() && l == format!("  - {after}") {
            put(&mut res, &mut done);
        }
        let is_key = l.strip_prefix(key).and_then(|r| r.strip_prefix(':')).is_some_and(|r| {
            let r = r.trim_start_matches(' ');
            r.is_empty() || r.starts_with('#')
        });
        if is_key {
            ins = true;
            if after == "-" {
                put(&mut res, &mut done);
            }
        }
    }
    if ins {
        put(&mut res, &mut done);
    }
    if !done {
        res.push_str(&format!("{key}:\n  - {v}\n"));
    }
    if write_replace(file, res.as_bytes()).is_err() {
        die!("cannot update {}", file.display());
    }
    Ok(())
}

pub fn apply(rt: &mut Route, ws: &Ws, pr: &Pr) -> Result<()> {
    let lay = ws.meta("layout");
    let ctx = pr.wt.join("context");
    let mf = safe_path(&ctx, &format!("{}/manifest.yml", ws.meta("layout_path")))?;

    let manifest: Vec<Vec<String>> = rt.plan.iter().filter(|r| r[0] == "manifest").cloned().collect();
    if !manifest.is_empty() {
        rt.applied.extend(manifest);
        if fs::copy(ws.dir.join(".delphi/manifest.yml"), &mf).is_err() {
            die!("cannot copy manifest");
        }
        pr.commit(&format!("delphi: update layout {lay} from workspace {}", ws.name), "")?;
    }

    let mut patched: Vec<String> = vec![];
    for r in rt.plan.clone() {
        let (k, o, tgt, a, b) = (field(&r, 0), field(&r, 1), field(&r, 2), field(&r, 3), field(&r, 4));
        match k {
            "patch" => {
                if patched.iter().any(|p| p == tgt) || !ok_q(git_c(&pr.wt).args(["apply", "--unidiff-zero", a])) {
                    rt.row(&["unresolved", o, &format!("patch for {tgt} not applied")]);
                    let body = fs::read_to_string(a).unwrap_or_default();
                    let body: Vec<&str> = awk_lines(&body).into_iter().skip(2).collect();
                    rt.unresolved.push_str(&format!(
                        "#### `{o}`: patch for `{tgt}` not applied (one patch per block per propose; edit it in one place)\n\n```diff\n{}\n```\n\n",
                        body.join("\n")
                    ));
                    continue;
                }
                patched.push(tgt.to_string());
            }
            "key" => {
                if b.contains('"') {
                    rt.unres(ws, o, &format!("new {a} value contains a double quote (not supported)"));
                    continue;
                }
                let b = if b.contains(" #") || b.starts_with(['[', '{', '&', '*', '|', '>', '!', '#']) {
                    format!("\"{b}\"")
                } else {
                    b.to_string()
                };
                let dst = safe_path(&ctx, tgt)?;
                let text = fs::read_to_string(&dst).unwrap_or_default();
                let mut d = false;
                let mut res = String::new();
                for l in awk_lines(&text) {
                    if !d && l.starts_with(&format!("{a}:")) {
                        res.push_str(&format!("{a}: {b}\n"));
                        d = true;
                    } else {
                        res.push_str(l);
                        res.push('\n');
                    }
                }
                if write_replace(&dst, res.as_bytes()).is_err() {
                    die!("cannot update {tgt}");
                }
            }
            _ => continue,
        }
        rt.applied.push(row(&[k, o, tgt]));
    }
    pr.commit(&format!("delphi: route block edits from workspace {}", ws.name), "")?;

    let (mut fa, mut ft) = (String::new(), String::new());
    for r in rt.plan.clone() {
        let (k, o, tgt, a) = (field(&r, 0), field(&r, 1), field(&r, 2), field(&r, 3));
        let mut b = field(&r, 4).to_string();
        let src = match k {
            "new" => ws.dir.join(o),
            "fragment" => PathBuf::from(a),
            _ => continue,
        };
        let dst = safe_path(&ctx, tgt)?;
        let copied = dst.parent().is_some_and(|p| fs::create_dir_all(p).is_ok()) && fs::copy(&src, &dst).is_ok();
        if !copied {
            die!("cannot add {tgt}");
        }
        rt.applied.push(row(&[k, o, tgt]));
        if k == "fragment" {
            // fragments after the same entry keep their file order
            if b == fa {
                b = ft.clone();
            } else {
                fa = b.clone();
            }
            list_add(&mf, "instructions", tgt, &b)?;
            ft = tgt.to_string();
            continue;
        }
        if a.is_empty() {
            continue;
        }
        let entries = parse_yaml(&mf)?.list(a);
        if !covered(&b, &entries) {
            list_add(&mf, a, &b, "")?;
        }
    }
    pr.commit(&format!("delphi: add new files from workspace {}", ws.name), "")?;
    Ok(())
}

// ---- route.awk: map one output file's `git diff -U0` hunks onto its lock segments ----

struct Hunk {
    pos: i64,
    n: i64,
    m: i64,
    body: String,
}

struct Awk<'a> {
    out: &'a str,
    pdir: &'a Path,
    pid: usize,
    newok: bool,
    s: Vec<i64>,
    e: Vec<i64>,
    src: Vec<String>,
    a: i64,
    n: i64,
    m: i64,
    body: Vec<String>,
    inh: bool,
    hunks: BTreeMap<usize, Vec<Hunk>>,
    rows: Vec<Vec<String>>,
    umd: &'a mut String,
}

/// Rows for one output file: `patch` (one combined patch per block), `key` (edited name:/
/// description: of a built skill), `fragment` (a new section; only when `newok`), `unresolved`
/// (also appended to `umd` as markdown).
fn route_file(
    out: &str,
    seg: &[Vec<String>],
    diff: &str,
    pdir: &Path,
    pid: usize,
    newok: bool,
    umd: &mut String,
) -> Result<Vec<Vec<String>>> {
    let mut w = Awk {
        out,
        pdir,
        pid,
        newok,
        s: vec![0],
        e: vec![0],
        src: vec![String::new()],
        a: 0,
        n: 0,
        m: 0,
        body: vec![],
        inh: false,
        hunks: BTreeMap::new(),
        rows: vec![],
        umd,
    };
    for r in seg {
        w.s.push(num(field(r, 1)));
        w.e.push(num(field(r, 2)));
        w.src.push(field(r, 3).to_string());
    }
    for l in awk_lines(diff) {
        if l.starts_with("@@ ") {
            w.flush()?;
            w.header(l);
            w.inh = true;
            w.body.clear();
        } else if w.inh && l.starts_with(['-', '+', ' ']) {
            // "\ No newline" lines are dropped: compiles end in one
            w.body.push(l.to_string());
        }
    }
    w.flush()?;
    w.emit()?;
    Ok(w.rows)
}

impl Awk<'_> {
    fn ns(&self) -> usize {
        self.s.len() - 1
    }

    fn header(&mut self, s: &str) {
        let p: Vec<&str> = s.split_whitespace().collect();
        let q = substr(p.get(1).unwrap_or(&""), 2, None);
        match q.split_once(',') {
            Some((a, n)) => (self.a, self.n) = (num(a), num(n)),
            None => (self.a, self.n) = (num(&q), 1),
        }
        let q = substr(p.get(2).unwrap_or(&""), 2, None);
        self.m = q.split_once(',').map_or(1, |(_, m)| num(m));
    }

    fn isblock(&self, i: usize) -> bool {
        i > 0 && !self.src[i].starts_with('@')
    }

    fn seg(&self, l: i64) -> usize {
        (1..=self.ns()).find(|&i| self.s[i] <= l && l <= self.e[i]).unwrap_or(0)
    }

    fn rng(&self, lo: usize, hi: usize) -> String {
        (lo..=hi).map(|k| format!("{}\n", self.body[k - 1])).collect()
    }

    fn all(&self) -> String {
        self.rng(1, self.body.len())
    }

    fn unresolved(&mut self, reason: &str) {
        self.rows.push(row(&["unresolved", self.out, reason]));
        let s = format!("#### `{}` (line {}): {reason}\n\n```diff\n{}```\n\n", self.out, self.a, self.all());
        self.umd.push_str(&s);
    }

    fn hunk(&mut self, t: usize, pos: i64, n: i64, m: i64, body: String) {
        self.hunks.entry(t).or_default().push(Hunk { pos, n, m, body });
    }

    fn blank(&self, k: usize) -> bool {
        self.body[k - 1].strip_prefix('+').is_some_and(|r| r.chars().all(|c| c == ' ' || c == '\t'))
    }

    fn flush(&mut self) -> Result<()> {
        if !self.inh {
            return Ok(());
        }
        self.inh = false;
        let (a, n, m) = (self.a, self.n, self.m);
        let (t, pos);
        if n > 0 {
            let (i, j) = (self.seg(a), self.seg(a + n - 1));
            if i > 0 && i == j && self.isblock(i) && m == 0 && a == self.s[i] && a + n - 1 == self.e[i] {
                self.unresolved("deletes a whole block; to drop a block, remove it from the manifest");
                return Ok(());
            }
            if i > 0 && i == j && self.isblock(i) {
                (t, pos) = (i, a - self.s[i] + 1);
            } else if i > 0 && i == j && self.src[i].starts_with("@gen:") && self.src[i].ends_with(".skill") {
                self.skillkeys(i);
                return Ok(());
            } else {
                self.unresolved("change spans segments or touches generated/separator lines");
                return Ok(());
            }
        } else if self.newok && self.fragment()? {
            return Ok(());
        } else if a == 0 {
            let i = self.seg(1);
            if self.isblock(i) {
                (t, pos) = (i, 0);
            } else {
                self.unresolved("insertion at the top of the file, before generated lines");
                return Ok(());
            }
        } else {
            let (i, j) = (self.seg(a), self.seg(a + 1));
            if self.isblock(i) && a < self.e[i] {
                (t, pos) = (i, a - self.s[i] + 1); // inside a block
            } else if self.isblock(i) && !self.isblock(j) {
                (t, pos) = (i, self.e[i] - self.s[i] + 1); // append to block
            } else if !self.isblock(i) && self.isblock(j) {
                (t, pos) = (j, 0); // prepend to next block
            } else {
                let r = if self.isblock(i) {
                    "insertion between two blocks"
                } else {
                    "insertion inside generated/separator lines"
                };
                self.unresolved(r);
                return Ok(());
            }
        }
        let b = self.all();
        self.hunk(t, pos, n, m, b);
        Ok(())
    }

    /// An insertion at a segment boundary is a new instruction fragment, except the lines touching
    /// a neighbouring block with no blank line between, which extend that block. Writes the
    /// fragment to a file and adds its row.
    fn fragment(&mut self) -> Result<bool> {
        let a = self.a;
        let (i, j) = (self.seg(a), self.seg(a + 1));
        if a > 0 && a != self.e[i] {
            return Ok(false);
        }
        let nb = self.body.len();
        let (mut lo, mut hi) = (1usize, nb);
        if self.isblock(i) {
            while lo <= nb && !self.blank(lo) {
                lo += 1;
            }
        }
        if self.isblock(j) {
            while hi >= 1 && !self.blank(hi) {
                hi -= 1;
            }
        }
        let (ea, z) = (lo - 1, hi + 1); // 1..ea extends block i, z..nb extends block j
        while lo <= hi && self.blank(lo) {
            lo += 1;
        }
        while hi >= lo && self.blank(hi) {
            hi -= 1;
        }
        if lo > hi {
            return Ok(false);
        }
        if ea > 0 {
            let b = self.rng(1, ea);
            self.hunk(i, self.e[i] - self.s[i] + 1, 0, ea as i64, b);
        }
        if z <= nb {
            let b = self.rng(z, nb);
            self.hunk(j, 0, 0, (nb - z + 1) as i64, b);
        }
        let t = (1..=self.ns()).rev().find(|&t| self.isblock(t) && self.e[t] <= a).unwrap_or(0);
        let mut s = String::new();
        let mut dash = false;
        let first = self.body[lo - 1][1..].to_ascii_lowercase();
        let first = first.trim_start_matches([' ', '\t']);
        let first = if first.starts_with('#') {
            first.trim_start_matches('#')
        } else {
            &self.body[lo - 1][1..].to_ascii_lowercase()
        };
        for c in first.chars() {
            if c.is_ascii_lowercase() || c.is_ascii_digit() {
                s.push(c);
                dash = false;
            } else if !dash {
                s.push('-');
                dash = true;
            }
        }
        let s = s.trim_matches('-');
        let s = substr(s, 1, Some(40));
        let s = s.trim_end_matches('-');
        let s = if s.is_empty() { "section" } else { s };
        let f = self.pdir.join(format!("{}.f{a}.md", self.pid));
        fs::write(&f, self.body[lo - 1..hi].iter().map(|l| format!("{}\n", &l[1..])).collect::<String>())?;
        let after = if t > 0 { self.src[t].clone() } else { "-".into() };
        self.rows.push(row(&["fragment", self.out, s, &f.to_string_lossy(), &after]));
        Ok(true)
    }

    fn skillkeys(&mut self, i: usize) {
        let ok = self.n == self.m
            && self.body.iter().all(|l| {
                let r = &l[1..];
                (l.starts_with('-') || l.starts_with('+'))
                    && (r.starts_with("name: ") || r.starts_with("description: "))
            });
        if !ok {
            self.unresolved("only name: and description: of a built skill's frontmatter can be edited");
            return;
        }
        let spec = substr(&self.src[i], 6, None);
        for l in self.body.clone() {
            let Some(l) = l.strip_prefix('+') else { continue };
            let key = l.split(':').next().unwrap_or("");
            let val = match l.find(':') {
                Some(c) if l[c..].starts_with(": ") => &l[c + 2..],
                _ => l,
            };
            self.rows.push(row(&["key", self.out, &spec, key, val]));
        }
    }

    fn emit(&mut self) -> Result<()> {
        for t in 1..=self.ns() {
            let Some(hs) = self.hunks.get(&t) else { continue };
            let src = &self.src[t];
            let f = self.pdir.join(format!("{}.{t}.patch", self.pid));
            let mut p = format!("--- a/context/{src}\n+++ b/context/{src}\n");
            let mut off = 0;
            for h in hs {
                let c = if h.n == 0 {
                    h.pos + off + 1
                } else if h.m == 0 {
                    h.pos + off - 1
                } else {
                    h.pos + off
                };
                p.push_str(&format!("@@ -{},{} +{c},{} @@\n{}", h.pos, h.n, h.m, h.body));
                off += h.m - h.n;
            }
            fs::write(&f, p)?;
            self.rows.push(row(&["patch", self.out, src, &f.to_string_lossy()]));
        }
        Ok(())
    }
}
