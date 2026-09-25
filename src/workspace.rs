//! `delphi workspace new|open|refresh|propose|status` (alias: ws). Port of lib/workspace.sh.
//!
//! A workspace is its own git repo outside Delphi. Refs: branch `generated` (compiles only), tag
//! `generated-merged` (latest compile merged into `working`), branch `working` (the user's).
//! Bookkeeping lives in .git/delphi/meta (key=value); meta.compile_commit is authoritative.

use crate::check::check_tree;
use crate::compile::compile;
use crate::core::{
    ask, awk_lines, conf_get, cwd, delphi_commit, delphi_fetch, delphi_worktree_at, dgit, find_layout, git_c, git_in,
    glob_dir, is_tty, make_tmp, move_path, moves_since, now, ok, ok_q, out, out_q, out_raw, out_stdin, parse_args,
    rewrite_moves, root, run_deferred, workspace_root, write_replace, Exit, Opts,
};
use crate::harness::{self, Harness};
use crate::parse::parse_yaml;
use crate::provenance::{self};
use crate::route;
use crate::{die, info, warn};
use anyhow::Result;
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
        "propose" => "--model --effort --yes --dry-run",
        "status" => "--offline",
        _ => die!("usage: delphi workspace new|open|refresh|propose|status (see: delphi help)"),
    };
    let (o, pos) = parse_args(flags, &args[1..])?;
    if pos.len() > 1 {
        die!("too many arguments (see: delphi help)");
    }
    let name = pos.first().map(String::as_str).unwrap_or("");
    match verb {
        "new" => {
            if pos.len() != 1 {
                die!("usage: delphi workspace new <layout> [--as <ws>] [--ref <branch>]");
            }
            ws_new(name, &o)
        }
        "open" => ws_open(&resolve(name)?, &o),
        "refresh" => {
            let ws = resolve(name)?;
            delphi_fetch();
            refresh(&ws, &o.ref_)
        }
        "propose" => propose(&resolve(name)?, &o),
        _ => {
            if !pos.is_empty() {
                die!("usage: delphi workspace status [--offline]");
            }
            status()
        }
    }
}

// ---- helpers ----
pub struct Ws {
    pub dir: PathBuf,
    pub name: String,
}

impl Ws {
    fn at(name: &str) -> Ws {
        Ws { dir: workspace_root().join(name), name: name.into() }
    }

    pub fn git(&self) -> Command {
        git_in(&self.dir)
    }

    fn meta_file(&self) -> PathBuf {
        self.dir.join(".git/delphi/meta")
    }

    pub fn meta(&self, k: &str) -> String {
        let text = fs::read_to_string(self.meta_file()).unwrap_or_default();
        awk_lines(&text)
            .into_iter()
            .map(|l| l.split_once('=').unwrap_or((l, l)))
            .find(|(key, _)| *key == k)
            .map(|(_, v)| v.to_string())
            .unwrap_or_default()
    }

    pub fn meta_set(&self, k: &str, v: &str) -> Result<()> {
        let f = self.meta_file();
        let text = fs::read_to_string(&f).unwrap_or_default();
        let mut d = false;
        let mut res = String::new();
        for l in awk_lines(&text) {
            if l.split_once('=').map_or(l, |x| x.0) == k {
                res.push_str(&format!("{k}={v}\n"));
                d = true;
            } else {
                res.push_str(l);
                res.push('\n');
            }
        }
        if !d {
            res.push_str(&format!("{k}={v}\n"));
        }
        if write_replace(&f, res.as_bytes()).is_err() {
            die!("cannot write {}", f.display());
        }
        Ok(())
    }

    /// The pending diff (everything changed since the latest merged compile).
    pub fn pending(&self, opts: &[&str]) -> String {
        let mut c = self.git();
        c.args(["diff", "--no-renames", "--no-ext-diff", "--no-color"]).args(opts);
        c.args(["generated-merged", "HEAD", "--", ".", ":(exclude).delphi/lock.tsv"]);
        String::from_utf8_lossy(&out_raw(&mut c).1).into_owned()
    }

    fn hash(&self) -> String {
        let p = self.pending(&["-U0"]);
        let kept: String = awk_lines(&p)
            .into_iter()
            .filter(|l| !l.starts_with("@@") && !l.starts_with("index "))
            .map(|l| format!("{l}\n"))
            .collect();
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
}

fn ws_names() -> Vec<String> {
    let r = workspace_root();
    glob_dir(&r).into_iter().filter(|d| r.join(d).join(".git/delphi/meta").is_file()).collect()
}

fn ws_name_ok(n: &str) -> Result<()> {
    let bad =
        n.is_empty() || n.starts_with('.') || !n.bytes().all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b));
    if bad {
        die!("invalid workspace name: '{n}'");
    }
    Ok(())
}

/// The workspace from a name, the current directory, or a picker.
fn resolve(name: &str) -> Result<Ws> {
    let dir = if !name.is_empty() {
        ws_name_ok(name)?;
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
        if n.is_empty() || !n.bytes().all(|b| b.is_ascii_digit()) {
            die!("not a number: '{n}'");
        }
        match n.parse::<usize>().ok().filter(|&i| i >= 1).and_then(|i| list.get(i - 1)) {
            Some(d) => workspace_root().join(d),
            None => die!("no workspace #{n}"),
        }
    };
    if !dir.join(".git/delphi/meta").is_file() {
        die!("not a Delphi workspace: {}", dir.display());
    }
    let name = dir.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    Ok(Ws { dir, name })
}

// ---- compiling into the workspace ----
/// Compile into a temp dir; returns (dir, harness).
fn ws_compile(src: &Path, lp: &str) -> Result<(PathBuf, &'static Harness)> {
    let d = make_tmp()?.join("out");
    if fs::create_dir(&d).is_err() {
        die!("mkdir failed");
    }
    let h = compile(src, lp, &d)?;
    Ok((d, h))
}

/// Commit outdir as the next `generated` commit (plumbing, so no worktree or hooks). False when
/// the content equals the current `generated`.
fn commit_compile(ws: &Ws, outdir: &Path, c: &str) -> Result<bool> {
    let idx = make_tmp()?.join("index");
    let gd = format!("--git-dir={}", ws.dir.join(".git").display());
    if !ok(git_c(outdir).env("GIT_INDEX_FILE", &idx).args([gd.as_str(), "--work-tree=.", "add", "-A", "-f"])) {
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
    ws_name_ok(name)?;
    let ws = Ws::at(name);
    if ws.dir.exists() {
        die!("workspace already exists: {}", ws.dir.display());
    }
    delphi_fetch();
    let c = delphi_commit(r#ref)?;
    let src = delphi_worktree_at(&c)?;
    let lp = find_layout(&src, layout)?;
    let recs = parse_yaml(&src.join("context").join(&lp).join("manifest.yml"))?;
    let (outdir, h) = ws_compile(&src, &lp)?;

    if fs::create_dir_all(&ws.dir).is_err() || !ok(Command::new("git").args(["init", "-q"]).arg(&ws.dir)) {
        die!("git init failed: {}", ws.dir.display());
    }
    let g = ws.dir.join(".git");
    for d in [g.join("delphi"), g.join("info"), ws.dir.join("repos"), ws.dir.join("worktrees")] {
        fs::create_dir_all(d)?;
    }
    let exclude = g.join("info/exclude");
    let mut ex = fs::read(&exclude).unwrap_or_default();
    ex.extend_from_slice(format!("repos/\nworktrees/\n{}\n", h.ignore).as_bytes());
    fs::write(&exclude, ex)?;
    let hook = g.join("hooks/commit-msg");
    fs::create_dir_all(g.join("hooks"))?;
    fs::write(&hook, HOOK)?;
    fs::set_permissions(&hook, fs::Permissions::from_mode(0o755))?;
    fs::write(
        g.join("delphi/meta"),
        format!(
            "layout={layout}\nlayout_path={lp}\nref={}\nharness={}\ncreated={}\nlast_proposed=\nlast_proposed_hash=\npending_since=\ncompile_commit={c}\n",
            r#ref,
            h.name,
            now()
        ),
    )?;
    if !commit_compile(&ws, &outdir, &c)? {
        die!("empty compile");
    }
    if !(ok(ws.git().args(["tag", "generated-merged", "generated"]))
        && ok(ws.git().args(["checkout", "-q", "-B", "working", "generated"])))
    {
        die!("cannot create working branch");
    }

    let mut failed = String::new();
    for (n, url) in recs.map("repos") {
        if n.is_empty() {
            continue;
        }
        if n.starts_with('.') || !n.bytes().all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b)) {
            warn!("skipping repo with invalid name '{n}'");
            continue;
        }
        info!("cloning {n}…");
        if !ok(Command::new("git").args(["clone", "-q", &url]).arg(ws.dir.join("repos").join(&n))) {
            warn!("clone failed: {n} ({url})");
            failed.push_str(&format!(" {n}"));
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
    let r#ref = ws.meta("ref");
    let Some(c) = out(&mut dgit(["rev-parse", "-q", "--verify", &format!("origin/{}^{{commit}}", r#ref)])) else {
        die!("branch '{}' is gone — run: delphi workspace refresh --ref main", r#ref)
    };
    let src = delphi_worktree_at(&c)?;
    let rows = moves_since(&ws.meta("compile_commit"), &c);
    let lp = move_path(&rows, &ws.meta("layout_path"));
    ws.meta_set("layout_path", &lp)?;
    let (outdir, h) = ws_compile(&src, &lp)?;
    ws.meta_set("harness", h.name)?;
    if commit_compile(ws, &outdir, &c)? {
        Ok(true)
    } else {
        apply_moves(ws, &c)?;
        Ok(false)
    }
}

fn merge(ws: &Ws) -> Result<()> {
    if ok_q(ws.git().args(["merge", "-q", "--no-verify", "--no-edit", "generated"])) {
        return Ok(());
    }
    if !ws.merging() {
        die!("merge of generated failed in {}", ws.dir.display());
    }
    info!("conflicts in {}:", ws.name);
    let u = out(ws.git().args(["diff", "--name-only", "--diff-filter=U"])).unwrap_or_default();
    for l in awk_lines(&u) {
        info!("  {l}");
    }
    info!("resolve them, commit, then re-run: delphi workspace refresh {}", ws.name);
    Err(Exit(2).into())
}

/// Rewrite paths moved since compile_commit in .delphi/manifest.yml; the workspace's compile now
/// corresponds to <c>.
fn apply_moves(ws: &Ws, c: &str) -> Result<()> {
    let rows = moves_since(&ws.meta("compile_commit"), c);
    ws.meta_set("compile_commit", c)?;
    if rewrite_moves(&rows, &ws.dir.join(".delphi/manifest.yml")).unwrap_or(false)
        && !ok(ws.git().args(["commit", "-q", "--no-verify", "-am", "delphi: apply moves"]))
    {
        die!("cannot commit moved paths");
    }
    Ok(())
}

fn finalize(ws: &Ws) -> Result<()> {
    if !ok(ws.git().args(["tag", "-f", "generated-merged", "generated"]).stdout(Stdio::null())) {
        die!("cannot move generated-merged");
    }
    let t = out(ws.git().args(["log", "-1", "--format=%(trailers:key=Delphi-Compile,valueonly)", "generated"]))
        .unwrap_or_default();
    let c: Vec<&str> = awk_lines(&t).into_iter().filter(|l| !l.is_empty()).collect();
    apply_moves(ws, &c.join("\n"))?;
    let cc = ws.meta("compile_commit");
    info!("{}: merged compile of origin/{} ({})", ws.name, ws.meta("ref"), &cc[..cc.len().min(7)]);
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
    if ws.pending(&["--name-only"]).is_empty() {
        ws.meta_set("pending_since", &ws.rev("HEAD"))?;
    }
    Ok(())
}

// ---- status ----
/// "yes" if origin/<ref> has commits since compile_commit touching this workspace's sources.
fn behind(ws: &Ws) -> &'static str {
    let rc = ws.meta("compile_commit");
    let Some(tip) = out(&mut dgit(["rev-parse", "-q", "--verify", &format!("origin/{}^{{commit}}", ws.meta("ref"))]))
    else {
        return "gone";
    };
    if tip == rc {
        return "no";
    }
    let mut paths: Vec<String> = vec![];
    let lock = out(ws.git().args(["show", "generated-merged:.delphi/lock.tsv"])).unwrap_or_default();
    for l in awk_lines(&lock).into_iter().filter(|l| !l.starts_with('#')) {
        let mut s = l.split('\t').nth(3).unwrap_or("");
        if let Some(g) = s.strip_prefix("@gen:").filter(|g| g.contains('/')) {
            s = g;
        }
        if !s.starts_with('@') {
            paths.push(format!("context/{s}"));
        }
    }
    paths.push(format!("context/{}/manifest.yml", ws.meta("layout_path")));
    let mf = out(ws.git().args(["show", "generated-merged:.delphi/manifest.yml"])).unwrap_or_default();
    for l in awk_lines(&mf) {
        if let Some(d) = l.strip_prefix("  - ").and_then(|v| v.strip_suffix("/*")) {
            paths.push(format!("context/{d}"));
        }
    }
    paths.sort();
    paths.dedup();
    let range = format!("{rc}..{tip}");
    match out_q(dgit(["log", "-1", "--format=x", &range, "--"]).args(&paths)) {
        Some(s) if s.is_empty() => "no",
        _ => "yes",
    }
}

struct State {
    dirty: bool,
    state: &'static str,
    age: String,
    stale: bool,
}

fn stale_days() -> i64 {
    conf_get("stale_days", "14").trim().parse().unwrap_or(14)
}

fn state(ws: &Ws) -> State {
    let dirty = !ws.clean();
    let state = if ws.pending(&["--name-only"]).is_empty() {
        "clean"
    } else if ws.hash() == ws.meta("last_proposed_hash") {
        "proposed"
    } else {
        "unproposed"
    };
    let (mut age, mut stale) = ("-".to_string(), false);
    if state == "unproposed" {
        let mut base = ws.meta("last_proposed");
        if base.is_empty() {
            base = ws.meta("created");
        }
        let days = (now() as i64 - base.trim().parse::<i64>().unwrap_or(0)) / 86400;
        age = format!("{days}d");
        stale = days > stale_days();
    }
    State { dirty, state, age, stale }
}

fn status() -> Result<()> {
    delphi_fetch();
    let row = |c: [&str; 8]| {
        println!("{:<22} {:<16} {:<8} {:<5} {:<10} {:<5} {:<6} {}", c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7])
    };
    row(["WORKSPACE", "LAYOUT", "REF", "DIRTY", "STATE", "AGE", "BEHIND", "NEXT"]);
    let (mut n, mut c, mut p, mut u, mut s) = (0, 0, 0, 0, 0);
    for name in ws_names() {
        let ws = Ws::at(&name);
        let mut st = state(&ws);
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
        if st.stale {
            st.age.push('!');
            s += 1;
        }
        let dirty = if st.dirty { "yes" } else { "no" };
        row([&name, &ws.meta("layout"), &ws.meta("ref"), dirty, st.state, &st.age, b, &next]);
        n += 1;
        match st.state {
            "clean" => c += 1,
            "proposed" => p += 1,
            _ => u += 1,
        }
    }
    println!(
        "{n} workspace(s): {c} clean, {p} proposed, {u} unproposed ({s} stale: unproposed > {} days)",
        conf_get("stale_days", "14")
    );
    Ok(())
}

// ---- open ----
fn ws_open(me: &Ws, o: &Opts) -> Result<()> {
    delphi_fetch();
    for name in ws_names() {
        let st = state(&Ws::at(&name));
        if st.stale {
            warn!("{name} has been unproposed for {}; run: delphi ws propose {name}", st.age);
        }
    }
    let ws = Ws::at(&me.name);
    if behind(&ws) != "no" {
        warn!(
            "{} is behind origin/{} (or its branch is gone); run: delphi ws refresh {}",
            ws.name,
            ws.meta("ref"),
            ws.name
        );
    }
    let h = harness::load(&ws.meta("harness"))?;
    let [dh, _, _] = (h.provenance)();
    let pick =
        |flag: &str, var: &str| if flag.is_empty() { std::env::var(var).unwrap_or_default() } else { flag.to_string() };
    let (model, effort) = (pick(&o.model, "DELPHI_MODEL"), pick(&o.effort, "DELPHI_EFFORT"));
    let mut cmd = if o.shell {
        Command::new(crate::core::env_nonempty("SHELL").unwrap_or_else(|| "/bin/sh".into()))
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
fn print_plan(rt: &route::Route) {
    for r in rt.plan.iter().filter(|r| r[0] != "unresolved") {
        info!("  {:<9} {} -> {}", r[0], r.get(1).map_or("", |s| s), r.get(2).map_or("", |s| s));
    }
    if !rt.unresolved.is_empty() {
        info!("Unresolved:");
        eprint!("{}", rt.unresolved);
    }
}

/// Distinct harness|model|effort trailers from workspace commits since pending_since.
fn prov_rows(ws: &Ws, me: &str) -> String {
    let f = "%(trailers:key=Delphi-Harness,valueonly,separator=)|%(trailers:key=Delphi-Model,valueonly,separator=)|%(trailers:key=Delphi-Effort,valueonly,separator=)";
    let since = ws.meta("pending_since");
    let range = if since.is_empty() { "HEAD".to_string() } else { format!("{since}..HEAD") };
    let log = out(ws.git().args(["log", "--no-merges", &format!("--format={f}"), &range])).unwrap_or_default();
    let mut seen: Vec<&str> = vec![];
    for l in awk_lines(&log) {
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
    let q = ".[0].number // empty";
    let mut c = Command::new("gh");
    c.current_dir(root()).args(["pr", "list", "--head", branch, "--state", "open", "--json", "number", "--jq", q]);
    let n = out_q(&mut c).unwrap_or_default();
    if !n.is_empty() {
        warn!("PR #{n} still contains earlier changes; close it with: gh pr close {n}");
    }
}

fn propose(ws: &Ws, o: &Opts) -> Result<()> {
    if o.dry {
        delphi_fetch();
        if behind(ws) != "no" {
            warn!("{} is behind origin/{}; planning against the last compile", ws.name, ws.meta("ref"));
        }
        print_plan(&route::plan(ws)?);
        return Ok(());
    }
    if ws.meta("ref") != "main" {
        die!("layout not on main yet — merge its PR, then run: delphi workspace refresh --ref main");
    }
    delphi_fetch();
    refresh(ws, "")?;
    let mut rt = route::plan(ws)?;
    let mut user = String::new();
    if out_q(&mut dgit(["remote", "get-url", "origin"])).unwrap_or_default().contains("github.com") {
        user = out_q(Command::new("gh").args(["api", "user", "--jq", ".login"])).unwrap_or_default();
    }
    if user.is_empty() {
        user = crate::core::env_nonempty("USER").unwrap_or_else(|| "me".into());
    }
    let branch = format!("delphi/propose/{user}/{}", ws.name);
    if rt.plan.iter().all(|r| r[0] == "noop") {
        info!("nothing to propose");
        warn_open_pr(ws, &branch);
        return Ok(());
    }
    // lease: the branch must be absent or exactly what we last pushed
    let Some(ls) = out(&mut dgit(["ls-remote", "--heads", "origin", &format!("refs/heads/{branch}")])) else {
        die!("cannot reach origin")
    };
    let remote = awk_lines(&ls).iter().map(|l| l.split('\t').next().unwrap_or("")).collect::<Vec<_>>().join("\n");
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
    let mut pr = crate::pr::begin(&branch, &cc, prov)?;
    route::apply(&mut rt, ws, &pr)?;
    if !pr.has_commits() {
        print_plan(&rt);
        info!("nothing routable to propose; resolve the items above in the workspace");
        warn_open_pr(ws, &branch);
        return Ok(());
    }
    if !check_tree(&pr.wt)? {
        die!("check failed on the proposed tree; not pushed (branch {} kept locally)", pr.branch);
    }
    let mut body = String::from("## Routed changes\n\n");
    for r in &rt.applied {
        body.push_str(&format!("- {}: `{}` (from workspace `{}`)\n", r[0], r[2], r[1]));
    }
    body.push_str("\n## Unresolved\n\n");
    body.push_str(if rt.unresolved.is_empty() { "None.\n" } else { &rt.unresolved });
    let title = format!("delphi: changes from workspace {} ({})", ws.name, ws.meta("layout"));
    pr.finish(&title, body.trim_end_matches('\n'), Some(&remote))?;
    if pr.pushed {
        ws.meta_set("last_proposed", &now().to_string())?;
        ws.meta_set("last_proposed_hash", &ws.hash())?;
        ws.meta_set("last_pushed", &out(git_c(&pr.wt).args(["rev-parse", "HEAD"])).unwrap_or_default())?;
    }
    Ok(())
}
