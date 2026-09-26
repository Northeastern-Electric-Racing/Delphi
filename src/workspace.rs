//! `delphi workspace new|open|refresh|diff|propose|status` (alias: ws).
//!
//! A workspace is its own git repo outside Delphi. Refs: branch `generated` (compiles only), tag
//! `generated-merged` (latest compile merged into `working`), branch `working` (the user's).
//! Bookkeeping lives in `.git/delphi/`: `meta` (key=value; compile_commit is authoritative) and
//! `copied` (`dest<TAB>source<TAB>delphi-commit`, one row per copied file).

use crate::check::check_tree;
use crate::compile::{compile, entries, parse_lock, Entry, Kind, Row, LOCK, MANIFEST};
use crate::core::{
    ask, blob, conf_get, cwd, delphi_commit, delphi_fetch, delphi_worktree, dgit, env_nonempty, exit, find_layout, git,
    is_tty, join, kv, make_tmp, move_path, moves_since, now, ok, ok_q, out, out_q, out_stdin, parse_args,
    rewrite_moves, run, run_deferred, safe_path, show, show_in, under, unmove_path, workspace_root, write_file,
    write_replace, Opts,
};
use crate::harness::{self, Harness};
use crate::parse::{parse_text, parse_yaml, Yaml};
use crate::pr::{gh_user, open_pr};
use crate::route::{self, Act, Item, Shared};
use crate::{die, info, provenance, warn};
use anyhow::Result;
use std::collections::HashMap;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub fn main(args: &[String]) -> Result<()> {
    let verb = args.first().map(String::as_str).unwrap_or("");
    let flags = match verb {
        "new" => "--as --ref",
        "open" => "--model --effort --shell",
        "refresh" => "--ref",
        "diff" => "--upstream --offline",
        "propose" => "--model --effort --yes --dry-run",
        "status" => "--offline",
        _ => die!("usage: delphi workspace new|open|refresh|diff|propose|status (see: delphi help)"),
    };
    let (o, pos) = parse_args(flags, &args[1..])?;
    if pos.len() > 1 {
        die!("too many arguments (see: delphi help)");
    }
    let name = pos.first().map(String::as_str).unwrap_or("");
    match verb {
        "new" if pos.is_empty() => die!("usage: delphi workspace new <layout> [--as <ws>] [--ref <branch>]"),
        "new" => ws_new(name, &o),
        "open" => ws_open(&resolve(name)?, &o),
        "refresh" => {
            let ws = resolve(name)?;
            delphi_fetch();
            refresh(&ws, &o.ref_)
        }
        "diff" if o.upstream => diff_upstream(&resolve(name)?),
        "diff" => diff(&resolve(name)?),
        "propose" => propose(&resolve(name)?, &o),
        _ if !pos.is_empty() => die!("usage: delphi workspace status [--offline]"),
        _ => status(),
    }
}

// ---- the workspace ----
/// path -> (mode, blob) at a revision.
pub type Tree = HashMap<String, (String, String)>;

/// A `.git/delphi/copied` row: the source path is as of compile_commit.
pub struct Copied {
    pub dest: String,
    pub source: String,
    /// The Delphi commit it was copied from.
    pub commit: String,
}

pub struct Ws {
    pub dir: PathBuf,
    pub name: String,
}

impl Ws {
    fn at(name: &str) -> Ws {
        Ws { dir: workspace_root().join(name), name: name.into() }
    }

    fn git(&self) -> Command {
        git(&self.dir)
    }

    fn bookkeeping(&self, f: &str) -> PathBuf {
        self.dir.join(".git/delphi").join(f)
    }

    pub fn meta(&self, k: &str) -> String {
        let text = fs::read_to_string(self.bookkeeping("meta")).unwrap_or_default();
        kv(&text, k).unwrap_or("").to_string()
    }

    fn meta_set(&self, k: &str, v: &str) -> Result<()> {
        let f = self.bookkeeping("meta");
        let text = fs::read_to_string(&f).unwrap_or_default();
        let mut found = false;
        let mut res: String = text
            .lines()
            .map(|l| match l.split_once('=') {
                Some((key, _)) if key == k => {
                    found = true;
                    format!("{k}={v}\n")
                }
                _ => format!("{l}\n"),
            })
            .collect();
        if !found {
            res += &format!("{k}={v}\n");
        }
        if write_replace(&f, res.as_bytes()).is_err() {
            die!("cannot write {}", f.display());
        }
        Ok(())
    }

    /// A file at a workspace revision.
    pub fn show(&self, rev: &str, path: &str) -> Option<Vec<u8>> {
        show_in(&self.dir, rev, path)
    }

    pub fn lock(&self, rev: &str) -> Vec<Row> {
        parse_lock(&String::from_utf8_lossy(&self.show(rev, LOCK).unwrap_or_default()))
    }

    /// `.delphi/manifest.yml` at a revision, and its `sync:` entries.
    pub fn manifest(&self, rev: &str) -> Result<(Yaml, Vec<Entry>)> {
        let Some(m) = self.show(rev, MANIFEST) else { die!("cannot read {MANIFEST}") };
        let y = parse_text(&String::from_utf8_lossy(&m), MANIFEST)?;
        let syncs = entries(&y, harness::load(&self.meta("harness"))?, MANIFEST)?;
        Ok((y, syncs.into_iter().filter(|e| e.kind == Kind::Sync).collect()))
    }

    pub fn tree(&self, rev: &str) -> Tree {
        let t = out(self.git().args(["ls-tree", "-r", rev])).unwrap_or_default();
        t.lines()
            .filter_map(|l| {
                let (meta, path) = l.split_once('\t')?;
                let mut f = meta.split(' ');
                let (mode, blob) = (f.next()?, f.nth(1)?);
                Some((path.to_string(), (mode.to_string(), blob.to_string())))
            })
            .collect()
    }

    pub fn copied(&self) -> Vec<Copied> {
        let text = fs::read_to_string(self.bookkeeping("copied")).unwrap_or_default();
        text.lines()
            .filter_map(|l| match l.split('\t').collect::<Vec<_>>()[..] {
                [d, s, c] => Some(Copied { dest: d.into(), source: s.into(), commit: c.into() }),
                _ => None,
            })
            .collect()
    }

    fn save_copied(&self, rows: &[Copied]) -> Result<()> {
        let text: String = rows.iter().map(|r| format!("{}\t{}\t{}\n", r.dest, r.source, r.commit)).collect();
        fs::write(self.bookkeeping("copied"), text)?;
        Ok(())
    }

    /// Blob of a copied source at the commit it was copied from (moves since then are undone).
    pub fn copied_blob(&self, cp: &Copied) -> Option<String> {
        blob(&cp.commit, &unmove_path(&moves_since(&cp.commit, &self.meta("compile_commit")), &cp.source))
    }

    /// Committed changes since the latest merged compile: (status, path), without bookkeeping
    /// (the lock, copied files).
    pub fn pending(&self) -> Vec<(String, String)> {
        let copied: Vec<String> = self.copied().into_iter().map(|c| c.dest).collect();
        let d = out(self.git().args(["diff", "--name-status", "--no-renames", "generated-merged", "HEAD"]));
        d.unwrap_or_default()
            .lines()
            .filter_map(|l| l.split_once('\t').map(|(s, p)| (s.to_string(), p.to_string())))
            .filter(|(_, p)| p != LOCK && !copied.contains(p))
            .collect()
    }

    /// The diff of one path since the latest merged compile, from its first hunk.
    pub fn diff_of(&self, path: &str) -> String {
        let args = ["diff", "--no-renames", "--no-ext-diff", "--no-color", "generated-merged", "HEAD", "--", path];
        let d = out(self.git().args(args)).unwrap_or_default();
        let start = d.lines().position(|l| l.starts_with("@@") || l.starts_with("Binary"));
        d.lines().skip(start.unwrap_or(usize::MAX)).collect::<Vec<_>>().join("\n")
    }

    /// Hash of the pending diff of `paths` (hunk headers and index lines dropped).
    fn hash(&self, paths: &[String]) -> String {
        let mut c = self.git();
        c.args(["--literal-pathspecs", "diff", "-U0", "--no-renames", "--no-ext-diff", "--no-color"]);
        c.args(["generated-merged", "HEAD", "--"]).args(paths);
        let p = String::from_utf8_lossy(&run(&mut c, false).unwrap_or_default()).into_owned();
        let kept: String =
            p.lines().filter(|l| !l.starts_with("@@") && !l.starts_with("index ")).map(|l| format!("{l}\n")).collect();
        out_stdin(Command::new("git").args(["hash-object", "--stdin"]), kept.as_bytes()).unwrap_or_default()
    }

    fn clean(&self) -> bool {
        out(self.git().args(["status", "--porcelain"])).unwrap_or_default().is_empty()
    }

    fn merging(&self) -> bool {
        self.dir.join(".git/MERGE_HEAD").is_file()
    }

    fn rev(&self, r: &str) -> String {
        out(self.git().args(["rev-parse", r])).unwrap_or_default()
    }

    /// origin/<ref>, if the branch still exists.
    fn tip(&self) -> Option<String> {
        delphi_commit(&self.meta("ref")).ok()
    }

    fn tip_or_die(&self) -> Result<String> {
        match self.tip() {
            Some(t) => Ok(t),
            None => die!("branch '{}' is gone — run: delphi workspace refresh --ref main", self.meta("ref")),
        }
    }

    /// The error for a workspace created by the v1 CLI (line-level lock), if this is one.
    fn v1_error(&self) -> Option<String> {
        self.show("generated", LOCK).filter(|l| l.starts_with(b"# output\t")).map(|_| {
            format!(
                "{} is a v1 workspace, which this Delphi no longer supports; recreate it: delphi workspace new {} --as <new-name> (then move your edits over)",
                self.name,
                self.meta("layout")
            )
        })
    }
}

/// Dests whose changes count as proposable (everything but local files).
fn proposable(items: &[Item]) -> Vec<String> {
    items.iter().filter(|i| i.act != Act::Local).map(|i| i.dest.clone()).collect()
}

fn ws_names() -> Vec<String> {
    let r = workspace_root();
    let mut v: Vec<String> = fs::read_dir(&r)
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|n| !n.starts_with('.') && r.join(n).join(".git/delphi/meta").is_file())
        .collect();
    v.sort();
    v
}

/// A workspace or repo directory name: letters, digits, `._-`, not starting with `.`.
fn plain_name(n: &str) -> bool {
    !n.is_empty() && !n.starts_with('.') && n.bytes().all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b))
}

/// The workspace from a name, the current directory, or a picker.
fn resolve(name: &str) -> Result<Ws> {
    let dir = if !name.is_empty() {
        if !plain_name(name) {
            die!("invalid workspace name: '{name}'");
        }
        workspace_root().join(name)
    } else if let Some(d) = cwd().ancestors().find(|d| d.join(".git/delphi/meta").is_file()) {
        d.to_path_buf()
    } else {
        let list = ws_names();
        if list.is_empty() {
            die!("no workspaces in {} (create one: delphi workspace new <layout>)", workspace_root().display());
        }
        if !is_tty() {
            die!("not inside a workspace; name one (see: delphi workspace status)");
        }
        for (i, n) in list.iter().enumerate() {
            info!("  {}) {n}", i + 1);
        }
        let n = ask("Workspace number?", "")?;
        match n.parse::<usize>().ok().filter(|&i| i >= 1).and_then(|i| list.get(i - 1)) {
            Some(d) => workspace_root().join(d),
            None => die!("no workspace #{n}"),
        }
    };
    if !dir.join(".git/delphi/meta").is_file() {
        die!("not a Delphi workspace: {}", dir.display());
    }
    let name = dir.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let ws = Ws { dir, name };
    if let Some(e) = ws.v1_error() {
        die!("{e}");
    }
    Ok(ws)
}

// ---- compiling into the workspace ----
/// Compile into a temp dir; returns (dir, harness).
fn ws_compile(src: &Path, lp: &str) -> Result<(PathBuf, &'static Harness)> {
    let d = make_tmp()?.join("out");
    let h = compile(src, lp, &d)?;
    Ok((d, h))
}

/// Commit outdir as the next `generated` commit (plumbing, so no worktree or hooks). False when
/// the content equals the current `generated`.
fn commit_compile(ws: &Ws, outdir: &Path, c: &str) -> Result<bool> {
    let idx = make_tmp()?.join("index");
    let gd = format!("--git-dir={}", ws.dir.join(".git").display());
    if !ok(git(outdir).env("GIT_INDEX_FILE", &idx).args([gd.as_str(), "--work-tree=.", "add", "-A", "-f"])) {
        die!("cannot stage compile");
    }
    let Some(tree) = out(Command::new("git").env("GIT_INDEX_FILE", &idx).args([gd.as_str(), "write-tree"])) else {
        die!("cannot write compile tree")
    };
    let mut ct = ws.git();
    ct.args(["commit-tree"]);
    if let Some(parent) = out(ws.git().args(["rev-parse", "-q", "--verify", "generated^{commit}"])) {
        if tree == ws.rev("generated^{tree}") {
            return Ok(false);
        }
        ct.args(["-p", &parent]);
    }
    let msg = format!("delphi: compile {}@{}\n\nDelphi-Compile: {c}\n", ws.meta("layout"), &c[..c.len().min(7)]);
    let Some(commit) = out_stdin(ct.arg(&tree), msg.as_bytes()) else { die!("cannot commit compile") };
    if !ok(ws.git().args(["update-ref", "refs/heads/generated", &commit])) {
        die!("cannot update generated");
    }
    Ok(true)
}

/// Commit copies listed in the compiled lock that were never copied (`delphi: copy …`); a dest
/// that already exists is left alone. Copies are never overwritten afterwards.
fn add_copies(ws: &Ws) -> Result<()> {
    let c = ws.meta("compile_commit");
    let mut rows = ws.copied();
    let mut added = vec![];
    for r in ws.lock("generated") {
        if r.kind != Kind::Copy || rows.iter().any(|x| x.dest == r.dest) {
            continue;
        }
        let p = safe_path(&ws.dir, &r.dest)?;
        if fs::symlink_metadata(&p).is_ok() {
            warn!("not copying context/{}: {} already exists", r.source, r.dest);
        } else {
            let path = format!("context/{}", r.source);
            let Some(data) = show(&c, &path) else { die!("cannot read {path} at {c}") };
            let exec = out(&mut dgit(["ls-tree", &c, "--", &path])).unwrap_or_default().starts_with("100755");
            write_file(&p, &data, exec, &r.dest)?;
            added.push(r.dest.clone());
        }
        rows.push(Copied { dest: r.dest, source: r.source, commit: c.clone() });
    }
    if !added.is_empty() {
        let msg = format!("delphi: copy {}", added.join(", "));
        let committed = ok(ws.git().args(["add", "-f", "--"]).args(&added))
            && ok_q(ws.git().args(["commit", "-q", "--no-verify", "-m", &msg]));
        if !committed {
            die!("cannot commit copies");
        }
        for d in &added {
            info!("  copied {d}");
        }
    }
    ws.save_copied(&rows)
}

const HOOK: &str = r#"#!/bin/sh
# Delphi: append provenance trailers from DELPHI_* env vars when set and not already present.
for kv in "Delphi-Harness=$DELPHI_HARNESS" "Delphi-Model=$DELPHI_MODEL" "Delphi-Effort=$DELPHI_EFFORT"; do
  k=${kv%%=*} v=${kv#*=}
  if [ -n "$v" ] && ! grep -q "^$k:" "$1"; then git interpret-trailers --in-place --trailer "$k: $v" "$1"; fi
done
exit 0
"#;

fn ws_new(layout: &str, o: &Opts) -> Result<()> {
    let r#ref = if o.ref_.is_empty() { "main" } else { &o.ref_ };
    let name = if o.as_.is_empty() { layout } else { &o.as_ };
    if !plain_name(name) {
        die!("invalid workspace name: '{name}'");
    }
    let ws = Ws::at(name);
    if ws.dir.exists() {
        die!("workspace already exists: {}", ws.dir.display());
    }
    delphi_fetch();
    let c = delphi_commit(r#ref)?;
    let lp = find_layout(&c, layout)?;
    let src = delphi_worktree(&["--detach"], &c, &format!("cannot check out Delphi at {c}"))?;
    let (outdir, h) = ws_compile(&src, &lp)?;

    if fs::create_dir_all(&ws.dir).is_err() || !ok(Command::new("git").args(["init", "-q"]).arg(&ws.dir)) {
        die!("git init failed: {}", ws.dir.display());
    }
    let g = ws.dir.join(".git");
    for d in [g.join("delphi"), g.join("info"), g.join("hooks"), ws.dir.join("repos"), ws.dir.join("worktrees")] {
        fs::create_dir_all(d)?;
    }
    let exclude = g.join("info/exclude");
    let mut ex = fs::read(&exclude).unwrap_or_default();
    ex.extend_from_slice(format!("repos/\nworktrees/\n{}\n", h.ignore).as_bytes());
    fs::write(&exclude, ex)?;
    let hook = g.join("hooks/commit-msg");
    fs::write(&hook, HOOK)?;
    fs::set_permissions(&hook, fs::Permissions::from_mode(0o755))?;
    let meta = format!(
        "layout={layout}\nlayout_path={lp}\nref={}\nharness={}\ncreated={}\ncompile_commit={c}\n",
        r#ref,
        h.name,
        now()
    );
    fs::write(ws.bookkeeping("meta"), meta)?;
    if !commit_compile(&ws, &outdir, &c)? {
        die!("empty compile");
    }
    if !(ok(ws.git().args(["tag", "generated-merged", "generated"]))
        && ok(ws.git().args(["checkout", "-q", "-B", "working", "generated"])))
    {
        die!("cannot create working branch");
    }
    add_copies(&ws)?;

    let mut failed = String::new();
    for (n, url) in parse_yaml(&outdir.join(MANIFEST))?.map("repos") {
        if !plain_name(&n) {
            warn!("skipping repo with invalid name '{n}'");
            continue;
        }
        info!("cloning {n}…");
        if !ok(Command::new("git").args(["clone", "-q", "--", &url]).arg(ws.dir.join("repos").join(&n))) {
            warn!("clone failed: {n} ({url})");
            failed += &format!(" {n}");
        }
    }
    info!("workspace ready: {}", ws.dir.display());
    if !failed.is_empty() {
        warn!("repos not cloned:{failed} (clone them into repos/ yourself)");
    }
    info!("next: delphi workspace open {}", ws.name);
    Ok(())
}

// ---- refresh ----
/// Compile origin/<meta.ref> onto `generated`. True if it changed.
fn compile_ref(ws: &Ws) -> Result<bool> {
    let c = ws.tip_or_die()?;
    let src = delphi_worktree(&["--detach"], &c, &format!("cannot check out Delphi at {c}"))?;
    let lp = move_path(&moves_since(&ws.meta("compile_commit"), &c), &ws.meta("layout_path"));
    ws.meta_set("layout_path", &lp)?;
    let (outdir, h) = ws_compile(&src, &lp)?;
    ws.meta_set("harness", h.name)?;
    if commit_compile(ws, &outdir, &c)? {
        return Ok(true);
    }
    apply_moves(ws, &c)?;
    Ok(false)
}

fn merge(ws: &Ws) -> Result<()> {
    if ok_q(ws.git().args(["merge", "-q", "--no-verify", "--no-edit", "generated"])) {
        return Ok(());
    }
    if !ws.merging() {
        die!("merge of generated failed in {}", ws.dir.display());
    }
    info!("conflicts in {}:", ws.name);
    for l in out(ws.git().args(["diff", "--name-only", "--diff-filter=U"])).unwrap_or_default().lines() {
        info!("  {l}");
    }
    info!("resolve them, commit, then re-run: delphi workspace refresh {}", ws.name);
    Err(exit(2))
}

/// Rewrite paths moved since compile_commit in .delphi/manifest.yml and the copied records; the
/// workspace's compile now corresponds to <c>.
fn apply_moves(ws: &Ws, c: &str) -> Result<()> {
    let rows = moves_since(&ws.meta("compile_commit"), c);
    ws.meta_set("compile_commit", c)?;
    if rows.is_empty() {
        return Ok(());
    }
    let mut copied = ws.copied();
    for cp in &mut copied {
        cp.source = move_path(&rows, &cp.source);
    }
    ws.save_copied(&copied)?;
    if rewrite_moves(&rows, &ws.dir.join(MANIFEST)).unwrap_or(false)
        && !ok(ws.git().args(["commit", "-q", "--no-verify", "-am", "delphi: apply moves"]))
    {
        die!("cannot commit moved paths");
    }
    Ok(())
}

/// `  (<author>: <subject>)` of the last Delphi commit in a range touching paths, or "".
fn who(range: &str, paths: &[String]) -> String {
    let w = out_q(dgit(["log", "-1", "--format=%an: %s", range, "--"]).args(paths)).unwrap_or_default();
    if w.is_empty() {
        w
    } else {
        format!("  ({w})")
    }
}

/// Move `generated-merged` to the merged compile, then list which files Delphi updated and who
/// changed them.
fn finalize(ws: &Ws) -> Result<()> {
    let old = ws.rev("generated-merged^{commit}");
    let old_cc = ws.meta("compile_commit");
    if !ok(ws.git().args(["tag", "-f", "generated-merged", "generated"]).stdout(Stdio::null())) {
        die!("cannot move generated-merged");
    }
    let t = out(ws.git().args(["log", "-1", "--format=%(trailers:key=Delphi-Compile,valueonly)", "generated"]));
    let c = t.unwrap_or_default().trim().to_string();
    apply_moves(ws, &c)?;
    info!("{}: merged compile of origin/{} ({})", ws.name, ws.meta("ref"), &c[..c.len().min(7)]);
    let names = out(ws.git().args(["diff", "--name-only", "--no-renames", &old, "generated"])).unwrap_or_default();
    let lock = ws.lock("generated");
    let sh = Shared::load(&ws.meta("layout"));
    for d in names.lines().filter(|d| *d != LOCK) {
        let srcs: Vec<&Row> = lock.iter().filter(|r| r.dest == d && r.kind != Kind::Copy).collect();
        match srcs.first() {
            None => info!("  removed {d}"),
            Some(r) => {
                let paths: Vec<String> = srcs.iter().map(|r| format!("context/{}", r.source)).collect();
                info!("  updated {d}{}{}", who(&format!("{old_cc}..{c}"), &paths), sh.tag(&r.source));
            }
        }
    }
    Ok(())
}

/// Merge a pending compile into HEAD (exits 2 on conflicts), then finalize it.
fn catch_up(ws: &Ws) -> Result<()> {
    if !ok(ws.git().args(["merge-base", "--is-ancestor", "generated", "HEAD"])) {
        merge(ws)?;
    }
    if ws.rev("generated") != ws.rev("generated-merged^{commit}") {
        finalize(ws)?;
    }
    Ok(())
}

/// Idempotent. Ok when up to date or finalized; exit 2 on conflicts.
fn refresh(ws: &Ws, new_ref: &str) -> Result<()> {
    ok(ws.git().args(["worktree", "prune"]));
    if ws.merging() {
        die!(
            "merge in progress in {}: resolve conflicts, commit, then re-run 'delphi workspace refresh'",
            ws.dir.display()
        );
    }
    if !ws.clean() {
        die!("{} has uncommitted changes; commit or stash them first", ws.dir.display());
    }
    if !new_ref.is_empty() {
        ws.meta_set("ref", new_ref)?;
    }
    catch_up(ws)?;
    if compile_ref(ws)? {
        catch_up(ws)?;
    } else {
        info!("{}: up to date with origin/{}", ws.name, ws.meta("ref"));
    }
    add_copies(ws)?;
    if route::plan(ws).is_ok_and(|v| proposable(&v).is_empty()) {
        ws.meta_set("pending_since", &ws.rev("HEAD"))?;
    }
    Ok(())
}

// ---- diff / status ----
/// Delphi paths whose changes reach this workspace on refresh.
fn watched(ws: &Ws) -> Vec<String> {
    let mut v = vec![ws.meta("layout_path")];
    v.extend(ws.lock("generated-merged").into_iter().filter(|r| r.kind != Kind::Copy).map(|r| r.source));
    if let Ok((_, syncs)) = ws.manifest("generated-merged") {
        v.extend(syncs.into_iter().map(|e| e.source));
    }
    let mut v: Vec<String> = v.into_iter().map(|p| format!("context/{p}")).collect();
    v.sort();
    v.dedup();
    v
}

/// "yes" if origin/<ref> has changes since compile_commit to this workspace's sources.
fn behind(ws: &Ws) -> &'static str {
    let rc = ws.meta("compile_commit");
    match ws.tip() {
        None => "gone",
        Some(t) if t == rc || ok_q(dgit(["diff", "--quiet", &rc, &t, "--"]).args(watched(ws))) => "no",
        Some(_) => "yes",
    }
}

/// Only committed changes are listed or proposed.
fn warn_dirty(ws: &Ws) {
    if !ws.clean() {
        warn!("uncommitted changes in {} are not included; commit them first", ws.dir.display());
    }
}

fn diff(ws: &Ws) -> Result<()> {
    delphi_fetch();
    warn_dirty(ws);
    let items = route::plan(ws)?;
    if items.is_empty() {
        info!("{}: no changes since the last refresh", ws.name);
    }
    print!("{}", route::listing(&items, &Shared::load(&ws.meta("layout"))));
    Ok(())
}

/// Sources changed on origin/<ref> since the compile, with the dests they reach; then copies whose
/// source moved on.
fn diff_upstream(ws: &Ws) -> Result<()> {
    delphi_fetch();
    let t = ws.tip_or_die()?;
    let sh = Shared::load(&ws.meta("layout"));
    let (cc, files) = (ws.meta("compile_commit"), format!("{}/files", ws.meta("layout_path")));
    let lock = ws.lock("generated-merged");
    let (_, syncs) = ws.manifest("generated-merged")?;
    let changed = if cc == t {
        String::new()
    } else {
        out(dgit(["diff", "--name-only", "--no-renames", &cc, &t, "--"]).args(watched(ws))).unwrap_or_default()
    };
    let mut s = String::new();
    for p in changed.lines() {
        let src = p.strip_prefix("context/").unwrap_or(p);
        let mut dests: Vec<(Kind, String)> =
            lock.iter().filter(|r| r.source == src && r.kind != Kind::Copy).map(|r| (r.kind, r.dest.clone())).collect();
        if dests.is_empty() {
            if let Some(rel) = under(src, &files) {
                dests.push((Kind::Layout, rel.into()));
            } else if let Some((e, rel)) = syncs.iter().find_map(|e| Some((e, under(src, &e.source)?))) {
                dests.push((Kind::Sync, join(&e.dest, rel)));
            }
        }
        let w = who(&format!("{cc}..{t}"), &[p.to_string()]);
        for (k, d) in dests {
            s += &format!("  {k:<9} {d} <- {src}{w}{}\n", sh.tag(src));
        }
    }
    let later = moves_since(&cc, &t);
    for cp in ws.copied() {
        let at_t = move_path(&later, &cp.source);
        if ws.copied_blob(&cp) != blob(&t, &at_t) {
            let w = who(&format!("{}..{t}", cp.commit), &[format!("context/{at_t}")]);
            s += &format!("  {:<9} {} <- {at_t}{w}  (your copy is not updated)\n", Kind::Copy, cp.dest);
        }
    }
    if s.is_empty() {
        info!("{}: up to date with origin/{}", ws.name, ws.meta("ref"));
    }
    print!("{s}");
    Ok(())
}

struct State {
    dirty: bool,
    state: &'static str,
    /// Days unproposed ("-" unless unproposed).
    age: String,
    stale: bool,
}

fn stale_days() -> i64 {
    conf_get("stale_days", "14").trim().parse().unwrap_or(14)
}

fn state(ws: &Ws) -> State {
    let paths = route::plan(ws).map(|v| proposable(&v)).unwrap_or_else(|_| vec![MANIFEST.into()]);
    let state = if paths.is_empty() {
        "clean"
    } else if ws.hash(&paths) == ws.meta("last_proposed_hash") {
        "proposed"
    } else {
        "unproposed"
    };
    let (mut age, mut stale) = ("-".to_string(), false);
    if state == "unproposed" {
        let base = Some(ws.meta("last_proposed")).filter(|b| !b.is_empty()).unwrap_or_else(|| ws.meta("created"));
        let days = (now() as i64 - base.trim().parse::<i64>().unwrap_or(0)) / 86400;
        stale = days > stale_days();
        age = format!("{days}d");
    }
    State { dirty: !ws.clean(), state, age, stale }
}

fn status() -> Result<()> {
    delphi_fetch();
    let row = |c: [&str; 8]| {
        println!("{:<22} {:<16} {:<8} {:<5} {:<10} {:<5} {:<6} {}", c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7])
    };
    row(["WORKSPACE", "LAYOUT", "REF", "DIRTY", "STATE", "AGE", "BEHIND", "NEXT"]);
    let (mut states, mut stale) = (vec![], 0);
    for name in ws_names() {
        let ws = Ws::at(&name);
        let (layout, r#ref) = (ws.meta("layout"), ws.meta("ref"));
        if let Some(e) = ws.v1_error() {
            row([&name, &layout, &r#ref, "-", "v1", "-", "-", &e]);
            continue;
        }
        let st = state(&ws);
        let b = behind(&ws);
        let next = if ws.merging() {
            format!("resolve conflicts, commit, then: delphi ws refresh {name}")
        } else if st.dirty {
            format!("commit your changes in {}", ws.dir.display())
        } else if b == "gone" {
            format!("delphi ws refresh {name} --ref main")
        } else if b == "yes" {
            format!("delphi ws refresh {name}")
        } else if st.state == "unproposed" {
            format!("delphi ws propose {name}")
        } else {
            format!("delphi ws open {name}")
        };
        let age = if st.stale { format!("{}!", st.age) } else { st.age };
        row([&name, &layout, &r#ref, if st.dirty { "yes" } else { "no" }, st.state, &age, b, &next]);
        states.push(st.state);
        stale += st.stale as usize;
    }
    let count = |k| states.iter().filter(|s| **s == k).count();
    println!(
        "{} workspace(s): {} clean, {} proposed, {} unproposed ({stale} stale: unproposed > {} days)",
        states.len(),
        count("clean"),
        count("proposed"),
        count("unproposed"),
        stale_days()
    );
    Ok(())
}

// ---- open ----
fn ws_open(ws: &Ws, o: &Opts) -> Result<()> {
    delphi_fetch();
    for name in ws_names() {
        let other = Ws::at(&name);
        if other.v1_error().is_none() {
            let st = state(&other);
            if st.stale {
                warn!("{name} has been unproposed for {}; run: delphi ws propose {name}", st.age);
            }
        }
    }
    if behind(ws) != "no" {
        let (n, r) = (&ws.name, ws.meta("ref"));
        warn!("{n} is behind origin/{r} (or its branch is gone); run: delphi ws refresh {n}");
    }
    let h = harness::load(&ws.meta("harness"))?;
    let [dh, _, _] = (h.provenance)();
    let pick = |flag: &str, var| if flag.is_empty() { std::env::var(var).unwrap_or_default() } else { flag.into() };
    let (model, effort) = (pick(&o.model, "DELPHI_MODEL"), pick(&o.effort, "DELPHI_EFFORT"));
    let mut cmd = if o.shell {
        Command::new(env_nonempty("SHELL").unwrap_or_else(|| "/bin/sh".into()))
    } else {
        (h.launch)(&model, &effort)
    };
    cmd.current_dir(&ws.dir)
        .env("PWD", &ws.dir)
        .env("DELPHI_HARNESS", dh)
        .env("DELPHI_MODEL", &model)
        .env("DELPHI_EFFORT", &effort);
    run_deferred();
    let e = cmd.exec();
    die!("cannot start {:?}: {e}", cmd.get_program())
}

// ---- propose ----
/// Distinct harness|model|effort trailers from workspace commits since pending_since.
fn prov_rows(ws: &Ws, me: &str) -> String {
    let f = "%(trailers:key=Delphi-Harness,valueonly,separator=)|%(trailers:key=Delphi-Model,valueonly,separator=)|%(trailers:key=Delphi-Effort,valueonly,separator=)";
    let since = ws.meta("pending_since");
    let range = if since.is_empty() { "HEAD".to_string() } else { format!("{since}..HEAD") };
    let log = out(ws.git().args(["log", "--no-merges", &format!("--format={f}"), &range])).unwrap_or_default();
    let mut seen: Vec<&str> = vec![];
    for l in log.lines() {
        if l != "||" && l != me && !seen.contains(&l) {
            seen.push(l);
        }
    }
    seen.join("\n")
}

/// After an earlier push, warn if that PR is still open.
fn warn_open_pr(ws: &Ws, branch: &str) {
    if ws.meta("last_pushed").is_empty() {
        return;
    }
    let n = open_pr(branch, "number");
    if !n.is_empty() {
        warn!("PR #{n} still contains earlier changes; close it with: gh pr close {n}");
    }
}

fn propose(ws: &Ws, o: &Opts) -> Result<()> {
    if o.dry {
        delphi_fetch();
        warn_dirty(ws);
        if behind(ws) != "no" {
            warn!("{} is behind origin/{}; planning against the last compile", ws.name, ws.meta("ref"));
        }
        print!("{}", route::listing(&route::plan(ws)?, &Shared::load(&ws.meta("layout"))));
        return Ok(());
    }
    if ws.meta("ref") != "main" {
        die!("layout not on main yet — merge its PR, then run: delphi workspace refresh --ref main");
    }
    delphi_fetch();
    refresh(ws, "")?;
    let items = route::plan(ws)?;
    let sh = Shared::load(&ws.meta("layout"));
    let on_github = out_q(&mut dgit(["remote", "get-url", "origin"])).unwrap_or_default().contains("github.com");
    let user = on_github.then(gh_user).flatten().or_else(|| env_nonempty("USER")).unwrap_or_else(|| "me".into());
    let branch = format!("delphi/propose/{user}/{}", ws.name);
    if !items.iter().any(Item::routed) {
        if items.iter().any(|i| i.act == Act::Unresolved) {
            eprint!("{}", route::listing(&items, &sh));
        }
        info!("nothing to propose");
        warn_open_pr(ws, &branch);
        return Ok(());
    }
    // lease: the branch must be absent or exactly what we last pushed
    let Some(ls) = out(&mut dgit(["ls-remote", "--heads", "origin", &format!("refs/heads/{branch}")])) else {
        die!("cannot reach origin")
    };
    let remote = ls.lines().map(|l| l.split('\t').next().unwrap_or("")).collect::<Vec<_>>().join("\n");
    if !remote.is_empty() && remote != ws.meta("last_pushed") {
        ws.meta_set("last_pushed", &remote)?;
        die!("the propose branch changed on GitHub (someone pushed to it); review the PR, then re-run to overwrite it");
    }
    let mut prov = provenance::resolve(&o.model, &o.effort, &ws.meta("harness"))?;
    let cc = ws.meta("compile_commit");
    prov.extra = format!(
        "Delphi-Layout: {}\nDelphi-Workspace: {}\nDelphi-Base: {}",
        ws.meta("layout_path"),
        ws.name,
        &cc[..cc.len().min(7)]
    );
    prov.rows = prov_rows(ws, &format!("{}|{}|{}", prov.harness, prov.model, prov.effort));
    let pr = crate::pr::begin(&branch, &cc, prov)?;
    if !route::apply(&items, ws, &pr)? {
        info!("nothing to propose: the routed files already match Delphi");
        warn_open_pr(ws, &branch);
        return Ok(());
    }
    if !check_tree(&pr.wt)? {
        die!("check failed on the proposed tree; not pushed (branch {} kept locally)", pr.branch);
    }
    let title = format!("delphi: changes from workspace {} ({})", ws.name, ws.meta("layout"));
    if pr.finish(&title, route::pr_body(&items, ws, &sh).trim_end_matches('\n'), Some(&remote))? {
        ws.meta_set("last_proposed", &now().to_string())?;
        ws.meta_set("last_proposed_hash", &ws.hash(&proposable(&items)))?;
        ws.meta_set("last_pushed", &out(git(&pr.wt).args(["rev-parse", "HEAD"])).unwrap_or_default())?;
    }
    Ok(())
}
