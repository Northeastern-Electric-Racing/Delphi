//! Local checkouts (spec §4) and the commands on them: checkout, open, refresh, diff, status. A
//! checkout is a single-branch clone of Delphi's origin at `ws/<name>` (the workspace is the repo
//! root) on branch `edit/<user>/<checkout>`, with the workspace's repos cloned into `repos/`
//! (excluded) and the provenance commit hook. Bookkeeping: `.git/delphi/meta` (key=value:
//! workspace; proposed = the last proposed commit; pushed = the propose branch commit pushed then).

use crate::core::{
    ask, cwd, env_nonempty, exit, fetch, fetch_main, git, is_tty, kv, ok, ok_q, out, out_q, parse_args, root,
    run_deferred, workspace_root, write_file, write_replace, Opts,
};
use crate::harness::{self, Harness};
use crate::parse::parse_yaml;
use crate::pr::user;
use crate::workspace::{self, YML};
use crate::{die, info, warn};
use anyhow::Result;
use std::fs;
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::Command;

pub fn main(cmd: &str, args: &[String]) -> Result<()> {
    let flags = match cmd {
        "checkout" => "--as --offline",
        "open" => "--model --effort --shell --offline",
        "diff" => "--upstream --offline",
        _ => "--offline",
    };
    let (o, pos) = parse_args(flags, args)?;
    if pos.len() > 1 || (cmd == "status" && !pos.is_empty()) {
        die!("too many arguments (see: delphi help)");
    }
    let name = pos.first().map(String::as_str).unwrap_or("");
    match cmd {
        "checkout" if name.is_empty() => die!("usage: delphi checkout <workspace> [--as <checkout>]"),
        "checkout" => checkout(name, &o),
        "status" => status(),
        "open" => open(&resolve(name)?, &o),
        "refresh" => refresh(&resolve(name)?),
        _ => diff(&resolve(name)?, o.upstream),
    }
}

pub struct Co {
    pub dir: PathBuf,
    pub name: String,
}

impl Co {
    fn at(name: &str) -> Co {
        Co { dir: workspace_root().join(name), name: name.into() }
    }
    pub fn git(&self) -> Command {
        git(&self.dir)
    }
    fn meta_file(&self) -> PathBuf {
        self.dir.join(".git/delphi/meta")
    }
    pub fn meta(&self, k: &str) -> String {
        kv(&fs::read_to_string(self.meta_file()).unwrap_or_default(), k).unwrap_or("").to_string()
    }
    pub fn meta_set(&self, k: &str, v: &str) -> Result<()> {
        let text = fs::read_to_string(self.meta_file()).unwrap_or_default();
        let mut res: String =
            text.lines().filter(|l| !l.starts_with(&format!("{k}="))).map(|l| format!("{l}\n")).collect();
        res += &format!("{k}={v}\n");
        write_replace(&self.meta_file(), res.as_bytes())
    }
    /// `origin/ws/<workspace>`.
    pub fn upstream(&self) -> String {
        format!("origin/ws/{}", self.meta("workspace"))
    }
    fn harness(&self) -> Result<&'static Harness> {
        harness::load(&parse_yaml(&self.dir.join(YML))?.get("harness"))
    }
    fn rev(&self, r: &str) -> String {
        out_q(self.git().args(["rev-parse", r])).unwrap_or_default()
    }
    pub fn clean(&self) -> bool {
        out(self.git().args(["status", "--porcelain"])).is_some_and(|s| s.is_empty())
    }
    fn merging(&self) -> bool {
        self.dir.join(".git/MERGE_HEAD").is_file()
    }
    fn fetch(&self) {
        fetch(&self.dir, &format!(" in {}", self.name));
    }
    fn count(&self, revs: &[&str]) -> usize {
        let c = out_q(self.git().args(["rev-list", "--count", "--no-merges"]).args(revs));
        c.and_then(|n| n.parse().ok()).unwrap_or(0)
    }
    /// Commits on origin/ws/<workspace> that HEAD lacks.
    fn behind(&self) -> usize {
        self.count(&[&format!("HEAD..{}", self.upstream())])
    }
    /// Own commits not proposed yet (not on the workspace branch, not in the last proposed commit).
    fn ahead(&self) -> usize {
        let p = self.meta("proposed");
        let p = if p.is_empty() { self.upstream() } else { p };
        self.count(&["HEAD", &format!("^{}", self.upstream()), &format!("^{p}")])
    }
    pub fn warn_uncommitted(&self) {
        if !self.clean() {
            warn!("uncommitted changes in {} are not included; commit them first", self.dir.display());
        }
    }
}

/// A checkout or repo directory name: letters, digits, `._-`, not starting with `.`.
fn plain_name(n: &str) -> bool {
    !n.is_empty() && !n.starts_with('.') && n.bytes().all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b))
}

fn names() -> Vec<String> {
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

/// The checkout from a name, the current directory, or a picker.
pub fn resolve(name: &str) -> Result<Co> {
    let dir = if !name.is_empty() {
        if !plain_name(name) {
            die!("invalid checkout name: '{name}'");
        }
        workspace_root().join(name)
    } else if let Some(d) = cwd().ancestors().find(|d| d.join(".git/delphi/meta").is_file()) {
        d.to_path_buf()
    } else {
        let list = names();
        if list.is_empty() {
            die!("no checkouts in {} (make one: delphi checkout <workspace>)", workspace_root().display());
        }
        if !is_tty() {
            die!("not inside a checkout; name one (see: delphi status)");
        }
        for (i, n) in list.iter().enumerate() {
            info!("  {}) {n}", i + 1);
        }
        let n = ask("Checkout number?")?;
        match n.parse::<usize>().ok().filter(|&i| i >= 1).and_then(|i| list.get(i - 1)) {
            Some(d) => workspace_root().join(d),
            None => die!("no checkout #{n}"),
        }
    };
    if !dir.join(".git/delphi/meta").is_file() {
        die!("not a Delphi checkout: {}", dir.display());
    }
    let name = dir.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    Ok(Co { dir, name })
}

// ---- checkout ----
const HOOK: &str = r#"#!/bin/sh
# Delphi: append provenance trailers from DELPHI_* env vars when set and not already present.
for kv in "Delphi-Harness=$DELPHI_HARNESS" "Delphi-Model=$DELPHI_MODEL" "Delphi-Effort=$DELPHI_EFFORT"; do
  k=${kv%%=*} v=${kv#*=}
  if [ -n "$v" ] && ! grep -q "^$k:" "$1"; then git interpret-trailers --in-place --trailer "$k: $v" "$1"; fi
done
exit 0
"#;

/// Delphi's origin URL; a relative local path is resolved against the Delphi repo.
fn origin_url() -> Result<String> {
    let Some(u) = out_q(git(root()).args(["remote", "get-url", "origin"])) else {
        die!("the Delphi repo has no origin remote")
    };
    let scp = u.find(':').is_some_and(|i| !u[..i].contains('/'));
    if u.contains("://") || scp || u.starts_with('/') {
        return Ok(u);
    }
    Ok(root().join(&u).display().to_string())
}

fn checkout(name: &str, o: &Opts) -> Result<()> {
    let cname = if o.as_.is_empty() { name } else { &o.as_ };
    if !plain_name(cname) {
        die!("invalid checkout name: '{cname}'");
    }
    let co = Co::at(cname);
    if co.dir.exists() {
        die!("checkout already exists: {}", co.dir.display());
    }
    let w = workspace::named(root(), &fetch_main()?, name)?;
    let (url, ws, branch) = (origin_url()?, format!("ws/{name}"), format!("edit/{}/{cname}", user()));
    let _ = fs::create_dir_all(workspace_root());
    let clone = ["clone", "--quiet", "--single-branch", "--branch", &ws, "--"];
    if !ok_q(Command::new("git").args(clone).arg(&url).arg(&co.dir)) {
        die!("cannot clone {ws} from {url} (not split yet? CI runs delphi split on every push to main)");
    }
    let track = ["switch", "--quiet", "--create", &branch, "--track", &format!("origin/{ws}")];
    if !(ok_q(co.git().args(track)) && ok_q(co.git().args(["branch", "--quiet", "--delete", "--force", &ws]))) {
        die!("cannot create branch {branch} in {}", co.dir.display());
    }
    let g = co.dir.join(".git");
    let mut ex = fs::read(g.join("info/exclude")).unwrap_or_default();
    ex.extend(format!("/repos/\n/{}\n", w.h.ignore).bytes());
    fs::write(g.join("info/exclude"), ex)?;
    write_file(&g.join("hooks/commit-msg"), HOOK.as_bytes(), true, "the commit-msg hook")?;
    write_file(&co.meta_file(), format!("workspace={name}\nproposed=\n").as_bytes(), false, "the checkout's meta")?;
    clone_repos(&co)?;
    info!("checkout ready: {} (branch {branch})\nnext: delphi open {cname}", co.dir.display());
    Ok(())
}

/// Clone the workspace's `repos:` into `repos/`; failures are only warnings.
fn clone_repos(co: &Co) -> Result<()> {
    let mut failed = String::new();
    for (n, url) in parse_yaml(&co.dir.join(YML))?.map("repos") {
        if !plain_name(&n) {
            warn!("skipping repo with invalid name '{n}'");
            continue;
        }
        info!("cloning {n}…");
        if !ok(Command::new("git").args(["clone", "-q", "--", &url]).arg(co.dir.join("repos").join(&n))) {
            warn!("clone failed: {n} ({url})");
            failed += &format!(" {n}");
        }
    }
    if !failed.is_empty() {
        warn!("repos not cloned:{failed} (clone them into repos/ yourself)");
    }
    Ok(())
}

// ---- open ----
fn open(co: &Co, o: &Opts) -> Result<()> {
    co.fetch();
    if co.behind() > 0 {
        warn!("{} is behind {}; run: delphi refresh {}", co.name, co.upstream(), co.name);
    }
    let h = co.harness()?;
    let [dh, _, _] = (h.provenance)();
    let pick = |flag: &str, var| if flag.is_empty() { std::env::var(var).unwrap_or_default() } else { flag.into() };
    let (model, effort) = (pick(&o.model, "DELPHI_MODEL"), pick(&o.effort, "DELPHI_EFFORT"));
    let mut cmd = if o.shell {
        Command::new(env_nonempty("SHELL").unwrap_or_else(|| "/bin/sh".into()))
    } else {
        (h.launch)(&model, &effort)
    };
    cmd.current_dir(&co.dir).env("PWD", &co.dir).env("DELPHI_HARNESS", dh).env("DELPHI_MODEL", &model);
    cmd.env("DELPHI_EFFORT", &effort);
    run_deferred();
    let e = cmd.exec();
    die!("cannot start {:?}: {e}", cmd.get_program())
}

// ---- refresh ----
/// Fetch and merge origin/ws/<workspace> into the checkout's branch; exit 2 on conflicts.
fn refresh(co: &Co) -> Result<()> {
    co.fetch();
    let up = co.upstream();
    if co.merging() {
        die!(
            "merge in progress in {}: resolve conflicts, commit, then re-run: delphi refresh {}",
            co.dir.display(),
            co.name
        );
    }
    if !co.clean() {
        die!("{} has uncommitted changes; commit or stash them first", co.dir.display());
    }
    if ok(co.git().args(["merge-base", "--is-ancestor", &up, "HEAD"])) {
        info!("{}: up to date with {up}", co.name);
        return Ok(());
    }
    let old = co.rev("HEAD");
    if !ok_q(co.git().args(["merge", "--quiet", "--no-edit", "-m", &format!("delphi: refresh from {up}"), &up])) {
        if !co.merging() {
            die!("git merge failed in {}", co.dir.display());
        }
        info!("conflicts in {}:", co.name);
        for l in out(co.git().args(["diff", "--name-only", "--diff-filter=U"])).unwrap_or_default().lines() {
            info!("  {l}");
        }
        info!("resolve them with git in {}, commit, then re-run: delphi refresh {}", co.dir.display(), co.name);
        return Err(exit(2));
    }
    info!("{}: merged {up} ({})", co.name, &co.rev(&up)[..7]);
    for p in out(co.git().args(["diff", "--name-only", &old, "HEAD"])).unwrap_or_default().lines() {
        info!("  updated {p}");
    }
    Ok(())
}

// ---- diff ----
fn diff(co: &Co, upstream: bool) -> Result<()> {
    co.fetch();
    let up = co.upstream();
    let Some(base) = out_q(co.git().args(["merge-base", "HEAD", &up])) else {
        die!("no common history of HEAD and {up} in {}", co.dir.display())
    };
    let (to, none) = if upstream { (up.as_str(), "up to date with") } else { ("HEAD", "no changes vs") };
    if !upstream {
        co.warn_uncommitted();
    }
    let d = out(co.git().args(["diff", "--name-status", "--no-renames", &base, to])).unwrap_or_default();
    if d.is_empty() {
        info!("{}: {none} {up}", co.name);
    }
    for (st, p) in d.lines().filter_map(|l| l.split_once('\t')) {
        let who = upstream.then(|| {
            let log = ["log", "-1", "--format=%an: %s", &format!("{base}..{up}"), "--", p];
            format!("  ({})", out_q(co.git().args(log)).unwrap_or_default())
        });
        println!("  {st} {p}{}", who.unwrap_or_default());
    }
    Ok(())
}

// ---- status ----
fn status() -> Result<()> {
    let row = |c: [&str; 6]| println!("{:<16} {:<16} {:<5} {:<5} {:<6} {}", c[0], c[1], c[2], c[3], c[4], c[5]);
    row(["CHECKOUT", "WORKSPACE", "DIRTY", "AHEAD", "BEHIND", "NEXT"]);
    for name in names() {
        let co = Co::at(&name);
        co.fetch();
        let (dirty, ahead, behind) = (!co.clean(), co.ahead(), co.behind());
        let next = if co.merging() {
            format!("resolve conflicts in {}, commit, then: delphi refresh {name}", co.dir.display())
        } else if dirty {
            format!("commit your changes in {}", co.dir.display())
        } else if behind > 0 {
            format!("delphi refresh {name}")
        } else if ahead > 0 {
            format!("delphi propose {name}")
        } else {
            format!("delphi open {name}")
        };
        let yn = |b: bool| if b { "yes" } else { "no" };
        let (a, b) = (ahead.to_string(), behind.to_string());
        row([&name, &co.meta("workspace"), yn(dirty), &a, &b, &next]);
    }
    Ok(())
}
