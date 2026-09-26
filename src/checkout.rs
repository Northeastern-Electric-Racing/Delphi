//! Local checkouts (spec §4) and the commands on them: checkout, open, refresh, diff, propose,
//! status. A checkout is a blob-filtered clone of Delphi's origin with a non-cone sparse pattern
//! for one workspace folder, on branch `ws/<user>/<checkout>`. Bookkeeping: `.git/delphi/meta`
//! (key=value: workspace, folder, harness, branch, last_pushed).

use crate::check::check_tree;
use crate::core::{
    ask, cwd, env_nonempty, exit, fetch, fetch_main, git, is_tty, join, kv, need_yes_or_tty, ok, ok_q, out, out_q,
    parse_args, root, run_deferred, safe_path, under, workspace_root, worktree, write_file, write_replace, Fail, Opts,
};
use crate::parse::parse_yaml;
use crate::pr::{open_pr, user, Pr};
use crate::sync::{merge_base, sync};
use crate::workspace::{self, sharing, YML};
use crate::{die, harness, info, provenance, warn};
use anyhow::Result;
use std::fs;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn main(cmd: &str, args: &[String]) -> Result<()> {
    let flags = match cmd {
        "checkout" => "--as --offline",
        "open" => "--model --effort --shell --offline",
        "diff" => "--upstream --offline",
        "propose" => "--model --effort --yes --dry-run --offline",
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
        _ => {
            let co = resolve(name)?;
            match cmd {
                "open" => open(&co, &o),
                "refresh" => refresh(&co),
                "diff" => diff(&co, o.upstream),
                _ => propose(&co, &o),
            }
        }
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
    fn git(&self) -> Command {
        git(&self.dir)
    }
    fn meta_file(&self) -> PathBuf {
        self.dir.join(".git/delphi/meta")
    }
    fn meta(&self, k: &str) -> String {
        kv(&fs::read_to_string(self.meta_file()).unwrap_or_default(), k).unwrap_or("").to_string()
    }
    fn meta_set(&self, k: &str, v: &str) -> Result<()> {
        let text = fs::read_to_string(self.meta_file()).unwrap_or_default();
        let mut res: String =
            text.lines().filter(|l| !l.starts_with(&format!("{k}="))).map(|l| format!("{l}\n")).collect();
        res += &format!("{k}={v}\n");
        write_replace(&self.meta_file(), res.as_bytes())
    }
    /// The workspace folder, repo-relative (`context/…/workspaces/<name>`).
    fn folder(&self) -> String {
        self.meta("folder")
    }
    fn folder_dir(&self) -> Result<PathBuf> {
        safe_path(&self.dir, &self.folder())
    }
    fn rev(&self, r: &str) -> String {
        out_q(self.git().args(["rev-parse", r])).unwrap_or_default()
    }
    fn clean(&self) -> bool {
        out(self.git().args(["status", "--porcelain"])).is_some_and(|s| s.is_empty())
    }
    fn merging(&self) -> bool {
        self.dir.join(".git/MERGE_HEAD").is_file()
    }
    fn fetch(&self) {
        fetch(&self.dir, &format!(" in {}", self.name));
    }
    fn count(&self, revs: &[&str], folder_only: bool) -> usize {
        let mut c = self.git();
        c.args(["rev-list", "--count", "--no-merges"]).args(revs).arg("--");
        if folder_only {
            c.arg(self.folder());
        }
        out_q(&mut c).and_then(|n| n.parse().ok()).unwrap_or(0)
    }
    /// Commits on origin/main touching the folder that HEAD lacks.
    fn behind(&self) -> usize {
        self.count(&["HEAD..origin/main"], true)
    }
    /// Own commits not pushed yet (not on origin/main, not in the last pushed commit).
    fn ahead(&self) -> usize {
        let lp = format!("^{}", self.meta("last_pushed"));
        self.count(&["HEAD", "^origin/main", if lp == "^" { "HEAD" } else { &lp }], false)
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
fn resolve(name: &str) -> Result<Co> {
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

/// Delphi's origin URL; local paths become `file://` so `--filter` works.
fn origin_url() -> Result<String> {
    let Some(u) = out_q(git(root()).args(["remote", "get-url", "origin"])) else {
        die!("the Delphi repo has no origin remote")
    };
    let scp = u.find(':').is_some_and(|i| !u[..i].contains('/'));
    if u.contains("://") || scp {
        return Ok(u);
    }
    match fs::canonicalize(root().join(&u)) {
        Ok(p) => Ok(format!("file://{}", p.display())),
        Err(_) => die!("cannot find Delphi's origin: {u}"),
    }
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
    let all = workspace::all_at(root(), &fetch_main()?, true);
    let Some(w) = all.iter().find(|w| w.name() == name) else {
        die!("no workspace named '{name}' on origin/main (see: delphi list)")
    };
    let (folder, branch) = (w.path("").trim_end_matches('/').to_string(), format!("ws/{}/{cname}", user()));
    let remote = clone_sparse(&co, &folder, &branch)?;
    let g = co.dir.join(".git");
    let mut ex = fs::read(g.join("info/exclude")).unwrap_or_default();
    ex.extend(format!("/{folder}/repos/\n/{folder}/{}\n", w.h.ignore).bytes());
    fs::write(g.join("info/exclude"), ex)?;
    write_file(&g.join("hooks/commit-msg"), HOOK.as_bytes(), true, "the commit-msg hook")?;
    let meta =
        format!("workspace={name}\nfolder={folder}\nharness={}\nbranch={branch}\nlast_pushed={remote}\n", w.h.name);
    write_file(&co.meta_file(), meta.as_bytes(), false, "the checkout's meta")?;
    if !remote.is_empty() {
        info!("continuing {branch} from origin");
    }
    let fd = co.folder_dir()?;
    clone_repos(&fd)?;
    info!("checkout ready: {}\nnext: delphi open {cname}", fd.display());
    Ok(())
}

/// Blob-filtered clone of Delphi's origin with a non-cone sparse pattern for `folder`, on
/// `branch` (continued from origin if it is there). Returns the branch's sha on origin, or "".
fn clone_sparse(co: &Co, folder: &str, branch: &str) -> Result<String> {
    let url = origin_url()?;
    let _ = fs::create_dir_all(workspace_root());
    let clone = ["clone", "--quiet", "--filter=blob:none", "--no-checkout", "--"];
    if !ok(Command::new("git").args(clone).arg(&url).arg(&co.dir)) {
        die!("cannot clone {url}");
    }
    let remote = co.rev(&format!("refs/remotes/origin/{branch}"));
    let start = if remote.is_empty() { "origin/main".to_string() } else { format!("origin/{branch}") };
    if !(ok(co.git().args(["sparse-checkout", "set", "--no-cone", &format!("/{folder}/")]))
        && ok_q(co.git().args(["switch", "--quiet", "--no-track", "-c", branch, &start])))
    {
        die!("cannot check out {folder} on {branch} in {}", co.dir.display());
    }
    Ok(remote)
}

/// Clone the workspace's `repos:` into `<folder>/repos/`; failures are only warnings.
fn clone_repos(fd: &Path) -> Result<()> {
    let mut failed = String::new();
    for (n, url) in parse_yaml(&fd.join(YML))?.map("repos") {
        if !plain_name(&n) {
            warn!("skipping repo with invalid name '{n}'");
            continue;
        }
        info!("cloning {n}…");
        if !ok(Command::new("git").args(["clone", "-q", "--", &url]).arg(fd.join("repos").join(&n))) {
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
        warn!("{} is behind origin/main; run: delphi refresh {}", co.name, co.name);
    }
    let h = harness::load(&co.meta("harness"))?;
    let [dh, _, _] = (h.provenance)();
    let pick = |flag: &str, var| if flag.is_empty() { std::env::var(var).unwrap_or_default() } else { flag.into() };
    let (model, effort) = (pick(&o.model, "DELPHI_MODEL"), pick(&o.effort, "DELPHI_EFFORT"));
    let mut cmd = if o.shell {
        Command::new(env_nonempty("SHELL").unwrap_or_else(|| "/bin/sh".into()))
    } else {
        (h.launch)(&model, &effort)
    };
    let fd = co.folder_dir()?;
    cmd.current_dir(&fd).env("PWD", &fd).env("DELPHI_HARNESS", dh).env("DELPHI_MODEL", &model);
    cmd.env("DELPHI_EFFORT", &effort);
    run_deferred();
    let e = cmd.exec();
    die!("cannot start {:?}: {e}", cmd.get_program())
}

// ---- refresh ----
/// Fetch and merge origin/main into the checkout's branch; exit 2 on conflicts.
fn refresh(co: &Co) -> Result<()> {
    co.fetch();
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
    if ok(co.git().args(["merge-base", "--is-ancestor", "origin/main", "HEAD"])) {
        info!("{}: up to date with origin/main", co.name);
        return Ok(());
    }
    let old = co.rev("HEAD");
    if !ok_q(co.git().args(["merge", "--quiet", "--no-edit", "-m", "delphi: refresh from origin/main", "origin/main"]))
    {
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
    info!("{}: merged origin/main ({})", co.name, &co.rev("origin/main")[..7]);
    let f = co.folder();
    for p in out(co.git().args(["diff", "--name-only", &old, "HEAD", "--", &f])).unwrap_or_default().lines() {
        info!("  updated {}", under(p, &f).unwrap_or(p));
    }
    Ok(())
}

// ---- diff ----
/// Changed files between two points of `dir` (git diff args), per file: own / linked (with the
/// workspaces sharing its source) / generated inside the folder, `sync` outside it.
fn listing(dir: &Path, folder: &str, args: &[&str], md: bool) -> Result<String> {
    let text = fs::read_to_string(safe_path(dir, &format!("{folder}/{YML}"))?).unwrap_or_default();
    let w = workspace::load(folder.strip_prefix("context/").unwrap_or(folder), &text, YML).ok();
    let all = workspace::all_at(dir, "origin/main", false);
    let d = out(git(dir).args(["diff", "--name-status", "--no-renames"]).args(args)).unwrap_or_default();
    let mut s = String::new();
    for (st, p) in d.lines().filter_map(|l| l.split_once('\t')) {
        let (mut kind, mut path, mut extra) = ("sync", p, String::new());
        if let Some(rel) = under(p, folder).filter(|r| !r.is_empty()) {
            (kind, path) = ("own", rel);
            if let Some(w) = &w {
                let link = w.links.iter().find_map(|(s, d)| under(rel, d).map(|r| join(s, r)));
                if let Some(src) = link {
                    let sh = sharing(&all, &src, &w.folder);
                    kind = "linked";
                    extra = if md { format!(" ← `{src}`") } else { format!(" <- {src}") };
                    if !sh.is_empty() {
                        extra += &format!(" (shared: {})", sh.join(", "));
                    }
                } else if rel == w.h.instructions && !w.parts.is_empty() {
                    kind = "generated";
                }
            }
        }
        s += &if md { format!("- {st} {kind} `{path}`{extra}\n") } else { format!("  {st} {kind:<9} {path}{extra}\n") };
    }
    Ok(s)
}

fn warn_uncommitted(co: &Co) {
    if !co.clean() {
        warn!("uncommitted changes in {} are not included; commit them first", co.dir.display());
    }
}

fn diff(co: &Co, upstream: bool) -> Result<()> {
    co.fetch();
    let (base, f) = (merge_base(&co.dir)?, co.folder());
    if upstream {
        let d = out(co.git().args(["diff", "--name-status", "--no-renames", &base, "origin/main", "--", &f]));
        let d = d.unwrap_or_default();
        if d.is_empty() {
            info!("{}: up to date with origin/main", co.name);
        }
        for (st, p) in d.lines().filter_map(|l| l.split_once('\t')) {
            let who = out_q(co.git().args(["log", "-1", "--format=%an: %s", &format!("{base}..origin/main"), "--", p]));
            println!("  {st} {}  ({})", under(p, &f).unwrap_or(p), who.unwrap_or_default());
        }
        return Ok(());
    }
    warn_uncommitted(co);
    let s = listing(&co.dir, &f, &[&base, "HEAD"], false)?;
    if s.is_empty() {
        info!("{}: no changes vs main", co.name);
    }
    print!("{s}");
    Ok(())
}

// ---- propose ----
/// A full temp worktree of the checkout at HEAD with shared files synced (not committed). Base:
/// the last pushed commit (already reconciled) merged with origin/main, so edits since it (even
/// reverts) are the new states; else the merge-base with origin/main (plus the last pushed commit
/// when that merge conflicts).
fn synced(co: &Co) -> Result<(PathBuf, String)> {
    let err = format!("cannot make a full worktree of {} (offline?)", co.dir.display());
    let wt = worktree(&co.dir, &["--detach"], "HEAD", &err)?;
    if !ok_q(git(&wt).args(["sparse-checkout", "disable"])) {
        die!("{err}");
    }
    let base = merge_base(&wt)?;
    let mut bases = vec![base.clone()];
    let lp = co.meta("last_pushed");
    if !lp.is_empty() && ok_q(git(&wt).args(["merge-base", "--is-ancestor", &lp, "HEAD"])) {
        match out_q(git(&wt).args(["merge-tree", "--write-tree", &lp, "origin/main"])) {
            Some(tree) => bases = vec![tree],
            None => bases.push(lp),
        }
    }
    let r = sync(&wt, &bases, false)?;
    r.print(false);
    if !r.conflicts.is_empty() {
        let m = "resolve them by making the copies agree (or edit only one), commit, then re-run";
        return Err(Fail(1, format!("sync: {} conflict(s); nothing proposed — {m}", r.conflicts.len())).into());
    }
    Ok((wt, base))
}

fn title(co: &Co) -> String {
    let ws = co.meta("workspace");
    let suffix = if ws == co.name { String::new() } else { format!(" (checkout {})", co.name) };
    format!("delphi: changes from workspace {ws}{suffix}")
}

fn body(co: &Co, list: &str) -> String {
    format!(
        "Changes to `{}` vs `main` (own = the workspace's file, linked = kept in sync with a source, sync = written by `delphi sync`):\n\n{}",
        co.folder(),
        list.trim_end_matches('\n')
    )
}

/// Distinct harness|model|effort trailers of the branch's commits since `base`, except `me`.
fn prov_rows(dir: &Path, base: &str, me: &str) -> Vec<String> {
    let f = "%(trailers:key=Delphi-Harness,valueonly,separator=)|%(trailers:key=Delphi-Model,valueonly,separator=)|%(trailers:key=Delphi-Effort,valueonly,separator=)";
    let log = out(git(dir).args(["log", "--no-merges", &format!("--format={f}"), &format!("{base}..HEAD")]));
    let mut seen: Vec<String> = vec![];
    for l in log.unwrap_or_default().lines() {
        if l != "||" && l != me && !seen.iter().any(|s| s == l) {
            seen.push(l.to_string());
        }
    }
    seen
}

/// `propose --dry-run`: no refresh or push; the sync writes, then the PR body.
fn propose_dry(co: &Co) -> Result<()> {
    co.fetch();
    warn_uncommitted(co);
    if co.behind() > 0 {
        warn!("{} is behind origin/main; propose will refresh (merge origin/main) first", co.name);
    }
    let (wt, base) = synced(co)?;
    ok(git(&wt).args(["add", "-A"]));
    let list = listing(&wt, &co.folder(), &["--cached", &base], true)?;
    if list.is_empty() {
        info!("nothing to propose");
        return Ok(());
    }
    let passed = check_tree(&wt)?;
    println!("---- {} (to {})\n{}\n----", title(co), co.meta("branch"), body(co, &list));
    if passed {
        Ok(())
    } else {
        Err(Fail(1, "check would fail; fix the errors above".into()).into())
    }
}

/// The branch's sha on origin ("" if absent); it must be absent or what we last pushed.
fn lease(wt: &Path, branch: &str, last_pushed: &str) -> Result<String> {
    let Some(ls) = out(git(wt).args(["ls-remote", "--heads", "origin", &format!("refs/heads/{branch}")])) else {
        die!("cannot reach origin")
    };
    let remote = ls.split('\t').next().unwrap_or("").to_string();
    if !remote.is_empty() && remote != last_pushed {
        die!("{branch} changed on origin (someone else pushed to it); review it, then merge it into your branch (git merge origin/{branch}) and re-run");
    }
    Ok(remote)
}

fn propose(co: &Co, o: &Opts) -> Result<()> {
    if o.dry {
        return propose_dry(co);
    }
    need_yes_or_tty()?;
    let (branch, last_pushed) = (co.meta("branch"), co.meta("last_pushed"));
    let mut prov = provenance::resolve(&o.model, &o.effort, &co.meta("harness"))?;
    refresh(co)?;
    let (wt, base) = synced(co)?;
    prov.workspace = co.folder();
    prov.rows = prov_rows(&wt, &base, &format!("{}|{}|{}", prov.harness, prov.model, prov.effort));
    let pr = Pr { branch: branch.clone(), wt: wt.clone(), prov };
    pr.commit("delphi: sync shared files")?;
    if ok_q(git(&wt).args(["diff", "--quiet", "origin/main", "HEAD"])) {
        info!("nothing to propose");
        if !last_pushed.is_empty() && !open_pr(&branch, "number").is_empty() {
            warn!("the open PR from {branch} still has earlier changes; close it if they are no longer wanted");
        }
        return Ok(());
    }
    if !check_tree(&wt)? {
        die!("check failed on the proposed tree; nothing pushed");
    }
    let remote = lease(&wt, &branch, &last_pushed)?;
    let list = listing(&wt, &co.folder(), &[&base, "HEAD"], true)?;
    if pr.finish(&title(co), &body(co, &list), Some(&remote))? {
        let head = out(git(&wt).args(["rev-parse", "HEAD"])).unwrap_or_default();
        co.meta_set("last_pushed", &head)?;
        if !ok_q(co.git().args(["merge", "--quiet", "--ff-only", &head])) {
            warn!("could not fast-forward {} to the pushed commit {head}", co.name);
        }
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
