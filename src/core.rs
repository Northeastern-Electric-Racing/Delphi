//! Shared helpers: messages, deferred cleanup, prompts, config, repo-root discovery, path safety,
//! running git, Delphi repo access, moves, flag parsing, and small path helpers.

use anyhow::Result;
use std::collections::hash_map::RandomState;
use std::fmt;
use std::fs;
use std::hash::BuildHasher;
use std::io::{self, BufRead, IsTerminal, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};

/// Return an error printed as `delphi: <msg>` (exit status 1).
#[macro_export]
macro_rules! die {
    ($($t:tt)*) => { return Err(anyhow::anyhow!($($t)*)) };
}

/// Print `delphi: warning: <msg>` to stderr.
#[macro_export]
macro_rules! warn {
    ($($t:tt)*) => { eprintln!("delphi: warning: {}", format!($($t)*)) };
}

/// Print a plain message to stderr.
#[macro_export]
macro_rules! info {
    ($($t:tt)*) => { eprintln!($($t)*) };
}

/// An error printed verbatim, without the `delphi: ` prefix (nothing if empty), exiting with
/// this status: `Fail(2, "")` after a refresh conflict, `Fail(1, "file:line: msg")`.
#[derive(Debug)]
pub struct Fail(pub i32, pub String);
impl fmt::Display for Fail {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str(&self.1)
    }
}
impl std::error::Error for Fail {}

pub fn exit(code: i32) -> anyhow::Error {
    Fail(code, String::new()).into()
}

// ---- globals ----
static ROOT: OnceLock<PathBuf> = OnceLock::new();
pub static YES: AtomicBool = AtomicBool::new(false);
pub static OFFLINE: AtomicBool = AtomicBool::new(false);

/// The Delphi repo root (DELPHI_ROOT).
pub fn root() -> &'static Path {
    ROOT.get().expect("Delphi root not resolved")
}
pub fn yes() -> bool {
    YES.load(Ordering::Relaxed)
}

/// `$XDG_CONFIG_HOME/delphi/root` (default `~/.config/delphi/root`), written by `delphi setup`.
pub fn root_config_file() -> PathBuf {
    let base = env_nonempty("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env_nonempty("HOME").unwrap_or_default()).join(".config"));
    base.join("delphi").join("root")
}

pub fn is_delphi_repo(d: &Path) -> bool {
    d.join("delphi.conf").is_file() && d.join("context").is_dir()
}

/// Resolve the repo root: DELPHI_ROOT, else the nearest ancestor of the current directory
/// holding delphi.conf and context/, else the path recorded by `delphi setup`.
pub fn resolve_root() -> Result<()> {
    let found = if let Some(r) = env_nonempty("DELPHI_ROOT") {
        match fs::canonicalize(&r) {
            Ok(p) if p.is_dir() => p,
            _ => die!("DELPHI_ROOT is not a directory: {r}"),
        }
    } else if let Some(p) = cwd().ancestors().find(|d| is_delphi_repo(d)) {
        fs::canonicalize(p)?
    } else {
        let rec = fs::read_to_string(root_config_file()).unwrap_or_default();
        let rec = rec.trim();
        match fs::canonicalize(rec) {
            Ok(p) if !rec.is_empty() && is_delphi_repo(&p) => p,
            _ => die!(
                "cannot find the Delphi repo: set DELPHI_ROOT, run inside a Delphi checkout, or run 'delphi setup' in one"
            ),
        }
    };
    std::env::set_var("DELPHI_ROOT", &found);
    let _ = ROOT.set(found);
    Ok(())
}

/// The current directory, preferring a valid logical $PWD like the shell does.
pub fn cwd() -> PathBuf {
    use std::os::unix::fs::MetadataExt;
    if let Some(p) = env_nonempty("PWD").map(PathBuf::from) {
        if let (true, Ok(a), Ok(b)) = (p.is_absolute(), fs::metadata(&p), fs::metadata(".")) {
            if a.dev() == b.dev() && a.ino() == b.ino() {
                return p;
            }
        }
    }
    std::env::current_dir().unwrap_or_else(|_| PathBuf::from("/"))
}

pub fn env_nonempty(k: &str) -> Option<String> {
    std::env::var(k).ok().filter(|v| !v.is_empty())
}

// ---- cleanup: deferred actions run LIFO before exit ----
type Deferred = Box<dyn FnOnce() + Send>;
static DEFERRED: Mutex<Vec<Deferred>> = Mutex::new(Vec::new());

pub fn defer(f: impl FnOnce() + Send + 'static) {
    DEFERRED.lock().unwrap().push(Box::new(f));
}

pub fn run_deferred() {
    while let Some(f) = DEFERRED.lock().unwrap().pop() {
        f();
    }
}

/// New private temp dir, removed on exit.
pub fn make_tmp() -> Result<PathBuf> {
    let base = env_nonempty("TMPDIR").unwrap_or_else(|| "/tmp".into());
    for i in 0..100u32 {
        let p = PathBuf::from(format!("{base}/delphi.{:x}", RandomState::new().hash_one((std::process::id(), i))));
        match fs::create_dir(&p) {
            Ok(()) => {
                let _ = fs::set_permissions(&p, fs::Permissions::from_mode(0o700));
                let q = p.clone();
                defer(move || {
                    let _ = fs::remove_dir_all(&q);
                });
                return Ok(p);
            }
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(_) => break,
        }
    }
    die!("mktemp failed")
}

// ---- prompts (stdin + stderr) ----
pub fn is_tty() -> bool {
    io::stdin().is_terminal() && io::stderr().is_terminal()
}

fn read_answer(prompt: &str) -> Option<String> {
    eprint!("{prompt}");
    let _ = io::stderr().flush();
    let mut s = String::new();
    match io::stdin().lock().read_line(&mut s) {
        Ok(0) | Err(_) => None,
        Ok(_) => Some(s.trim_end_matches('\n').trim_matches([' ', '\t']).to_string()),
    }
}

/// Fails fast when a confirmation would be needed but cannot be asked.
pub fn need_yes_or_tty() -> Result<()> {
    if !yes() && !is_tty() {
        die!("non-interactive session: re-run with --yes (or DELPHI_YES=1)");
    }
    Ok(())
}

/// Yes if --yes / DELPHI_YES=1; fails fast when non-interactive.
pub fn confirm(q: &str) -> Result<bool> {
    need_yes_or_tty()?;
    Ok(yes() || matches!(read_answer(&format!("{q} [y/N] ")).as_deref(), Some("y" | "Y" | "yes")))
}

/// Ask a question; empty answer gives the default.
pub fn ask(q: &str, default: &str) -> Result<String> {
    if !is_tty() {
        die!("non-interactive session: cannot ask '{q}'");
    }
    let prompt = if default.is_empty() { format!("{q} ") } else { format!("{q} [{default}] ") };
    match read_answer(&prompt) {
        None => Err(exit(1)),
        Some(a) if a.is_empty() => Ok(default.to_string()),
        Some(a) => Ok(a),
    }
}

// ---- config ----
/// The value of `key` in `key=value` lines (`#` lines are comments).
pub fn kv<'a>(text: &'a str, key: &str) -> Option<&'a str> {
    text.lines().filter(|l| !l.starts_with('#')).find_map(|l| l.split_once('=').filter(|(k, _)| *k == key)).map(|x| x.1)
}

/// A delphi.conf value, or `default` when unset or empty.
pub fn conf_get(key: &str, default: &str) -> String {
    let text = fs::read_to_string(root().join("delphi.conf")).unwrap_or_default();
    kv(&text, key).filter(|v| !v.is_empty()).unwrap_or(default).to_string()
}

pub fn workspace_root() -> PathBuf {
    let r = env_nonempty("DELPHI_WORKSPACE_ROOT").unwrap_or_else(|| conf_get("workspace_root", "../Delphi-workspaces"));
    let p = root().join(r);
    if p.is_dir() {
        return fs::canonicalize(&p).unwrap_or(p);
    }
    match (p.parent().map(fs::canonicalize), p.file_name()) {
        (Some(Ok(dir)), Some(base)) => dir.join(base),
        _ => p,
    }
}

// ---- path safety ----
/// Relative, no `..` or `.` components, not empty.
pub fn path_ok(rel: &str) -> bool {
    if rel.is_empty() || rel.starts_with('/') {
        return false;
    }
    let s = format!("/{rel}/");
    !(s.contains("/../") || s.contains("/./") || s.contains("//"))
}

/// `<root>/<rel>` after proving it stays inside `<root>` (lexically and through symlinks).
pub fn safe_path(root: &Path, rel: &str) -> Result<PathBuf> {
    if !path_ok(rel) {
        die!("unsafe path: '{rel}'");
    }
    let rroot = match fs::canonicalize(root) {
        Ok(p) if p.is_dir() => p,
        _ => die!("missing directory: {}", root.display()),
    };
    let full = rroot.join(rel);
    if fs::symlink_metadata(&full).is_ok_and(|m| m.file_type().is_symlink()) {
        die!("unsafe path (symlink): '{rel}'");
    }
    let mut probe = full.as_path();
    while !probe.exists() || !probe.is_dir() {
        probe = probe.parent().unwrap_or(Path::new("/"));
    }
    if !fs::canonicalize(probe)?.starts_with(&rroot) {
        die!("unsafe path (escapes {}): '{rel}'", root.display());
    }
    Ok(full)
}

/// Write a file (parents created), mode 755 if `exec` else 644; `what` names it in errors.
pub fn write_file(p: &Path, data: &[u8], exec: bool, what: &str) -> Result<()> {
    let mode = if exec { 0o755 } else { 0o644 };
    let wrote = p.parent().is_some_and(|d| fs::create_dir_all(d).is_ok())
        && fs::write(p, data).is_ok()
        && fs::set_permissions(p, fs::Permissions::from_mode(mode)).is_ok();
    if !wrote {
        die!("cannot write {what}");
    }
    Ok(())
}

/// Write `<file>.tmp` then rename it over `<file>`.
pub fn write_replace(file: &Path, data: &[u8]) -> Result<()> {
    let tmp = PathBuf::from(format!("{}.tmp", file.display()));
    fs::write(&tmp, data)?;
    fs::rename(&tmp, file)?;
    Ok(())
}

// ---- running commands ----
/// `git -c core.quotePath=false -C <dir>`.
pub fn git(dir: &Path) -> Command {
    let mut c = Command::new("git");
    c.args(["-c", "core.quotePath=false", "-C"]).arg(dir);
    c
}

/// git on the Delphi repo.
pub fn dgit<I: IntoIterator<Item = S>, S: AsRef<std::ffi::OsStr>>(args: I) -> Command {
    let mut c = git(root());
    c.args(args);
    c
}

/// Raw stdout on success. Quiet: no stdin, stderr discarded; else both inherited.
pub fn run(c: &mut Command, quiet: bool) -> Option<Vec<u8>> {
    let io = || if quiet { Stdio::null() } else { Stdio::inherit() };
    let o = c.stdin(io()).stderr(io()).output().ok()?;
    o.status.success().then_some(o.stdout)
}

fn text(b: Vec<u8>) -> String {
    String::from_utf8_lossy(&b).trim_end_matches('\n').to_string()
}

/// Like `$(cmd)`: stdout with trailing newlines stripped; None on failure.
pub fn out(c: &mut Command) -> Option<String> {
    run(c, false).map(text)
}

/// Like `$(cmd 2>/dev/null)`.
pub fn out_q(c: &mut Command) -> Option<String> {
    run(c, true).map(text)
}

/// Run with stdin fed from `input`; stdout captured like `out`.
pub fn out_stdin(c: &mut Command, input: &[u8]) -> Option<String> {
    let mut ch = c.stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::inherit()).spawn().ok()?;
    ch.stdin.take()?.write_all(input).ok()?;
    let o = ch.wait_with_output().ok()?;
    o.status.success().then(|| text(o.stdout))
}

/// Run with inherited stdio; true on success.
pub fn ok(c: &mut Command) -> bool {
    c.status().is_ok_and(|s| s.success())
}

/// Run with stdout and stderr discarded; true on success.
pub fn ok_q(c: &mut Command) -> bool {
    ok(c.stdout(Stdio::null()).stderr(Stdio::null()))
}

/// A file at a revision of the repo at `dir` (`git show <rev>:<path>`).
pub fn show_in(dir: &Path, rev: &str, path: &str) -> Option<Vec<u8>> {
    run(git(dir).args(["show", &format!("{rev}:{path}")]), true)
}

/// Whether a command is on PATH (`command -v`).
pub fn have(prog: &str) -> bool {
    let exec = |p: &Path| fs::metadata(p).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0);
    std::env::var_os("PATH").is_some_and(|p| std::env::split_paths(&p).any(|d| exec(&d.join(prog))))
}

/// `date +<fmt>` (local time).
pub fn date(fmt: &str) -> String {
    out(Command::new("date").arg(format!("+{fmt}"))).unwrap_or_default()
}

pub fn now() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

// ---- Delphi repo access ----
pub fn delphi_fetch() {
    if OFFLINE.load(Ordering::Relaxed) {
        return;
    }
    if !ok(dgit(["fetch", "--prune", "--quiet", "origin"]).stderr(Stdio::null())) {
        warn!("git fetch failed; using local refs");
    }
}

/// Full sha of origin/<branch>.
pub fn delphi_commit(branch: &str) -> Result<String> {
    match out_q(&mut dgit(["rev-parse", "--verify", "--quiet", &format!("origin/{branch}^{{commit}}")])) {
        Some(c) => Ok(c),
        None => die!("no such Delphi branch: origin/{branch}"),
    }
}

/// Temp worktree of Delphi (`git worktree add <opts> <dir> <start>`), removed on exit; `err` if
/// it cannot be made.
pub fn delphi_worktree(opts: &[&str], start: &str, err: &str) -> Result<PathBuf> {
    let d = make_tmp()?.join("wt");
    if !ok_q(dgit(["worktree", "add", "--quiet"]).args(opts).arg(&d).arg(start)) {
        die!("{err}");
    }
    let dd = d.clone();
    defer(move || {
        ok_q(dgit(["worktree", "remove", "--force"]).arg(&dd));
    });
    Ok(d)
}

/// A file at a Delphi commit.
pub fn show(c: &str, path: &str) -> Option<Vec<u8>> {
    show_in(root(), c, path)
}

/// Blob id of `context/<p>` at a Delphi commit.
pub fn blob(c: &str, p: &str) -> Option<String> {
    out_q(&mut dgit(["rev-parse", "-q", "--verify", &format!("{c}:context/{p}")]))
}

/// Layout manifests (`context/…/layouts/<name>/manifest.yml`) at a Delphi commit.
pub fn layout_manifests(c: &str) -> Vec<String> {
    let t = out(&mut dgit(["ls-tree", "-r", "--name-only", c, "--", "context"])).unwrap_or_default();
    t.lines()
        .filter(|f| {
            f.strip_suffix("/manifest.yml")
                .and_then(|d| d.rfind("/layouts/").map(|i| &d[i + 9..]))
                .is_some_and(|n| !n.is_empty() && !n.contains('/'))
        })
        .map(String::from)
        .collect()
}

pub fn name_ok(name: &str) -> bool {
    !name.is_empty() && name.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
}

/// The layout dir (relative to context/) of layout <name> at a Delphi commit.
pub fn find_layout(c: &str, name: &str) -> Result<String> {
    if !name_ok(name) {
        die!("invalid layout name: '{name}'");
    }
    let suffix = format!("/layouts/{name}/manifest.yml");
    let hits: Vec<String> = layout_manifests(c).into_iter().filter(|f| f.ends_with(&suffix)).collect();
    match hits.as_slice() {
        [f] => Ok(f["context/".len()..f.len() - "/manifest.yml".len()].to_string()),
        [] => die!("layout not found: {name}"),
        _ => die!("layout name not unique: {name}"),
    }
}

// ---- moves (moves.tsv is append-only; rows apply in order, each once) ----
pub type Moves = Vec<(String, String)>;

pub fn parse_moves(text: &str) -> Moves {
    text.lines()
        .filter(|l| !l.starts_with('#'))
        .filter_map(|l| {
            let mut f = l.split('\t');
            Some((f.next()?.to_string(), f.next()?.to_string()))
        })
        .collect()
}

/// Rows of moves.tsv added between two Delphi commits.
pub fn moves_since(old: &str, new: &str) -> Moves {
    let read = |c: &str| String::from_utf8_lossy(&show(c, "moves.tsv").unwrap_or_default()).into_owned();
    let n = read(old).lines().count();
    parse_moves(&read(new).lines().skip(n).collect::<Vec<_>>().join("\n"))
}

pub fn move_path(rows: &Moves, p: &str) -> String {
    let mut p = p.to_string();
    for (o, n) in rows {
        if let Some(rest) = under(&p, o) {
            p = join(n, rest);
        }
    }
    p
}

/// Undo move rows: where `p` was before them.
pub fn unmove_path(rows: &Moves, p: &str) -> String {
    let rev: Moves = rows.iter().rev().map(|(o, n)| (n.clone(), o.clone())).collect();
    move_path(&rev, p)
}

/// Apply move rows to the source of `  - <source> [-> <dest>]` lines in place (trailing comments
/// on rewritten lines are dropped). True if anything changed.
pub fn rewrite_moves(rows: &Moves, file: &Path) -> Result<bool> {
    let text = String::from_utf8_lossy(&fs::read(file)?).into_owned();
    let mut changed = false;
    let mut res = String::new();
    for l in text.lines() {
        let mut line = l.to_string();
        if let Some(item) = l.strip_prefix("  - ") {
            let v = item.split(" #").next().unwrap_or("").trim_end_matches(' ');
            let (src, dest) = v.split_once(" -> ").map_or((v, None), |(a, b)| (a, Some(b)));
            let m = move_path(rows, src);
            if m != src {
                line = dest.map_or_else(|| format!("  - {m}"), |d| format!("  - {m} -> {d}"));
                changed = true;
            }
        }
        res.push_str(&line);
        res.push('\n');
    }
    if changed {
        write_replace(file, res.as_bytes())?;
    }
    Ok(changed)
}

// ---- flags ----
/// Parsed flags. --yes and --offline set the YES / OFFLINE globals.
#[derive(Default, Debug)]
pub struct Opts {
    pub as_: String,
    pub ref_: String,
    pub from: String,
    pub model: String,
    pub effort: String,
    pub shell: bool,
    pub dry: bool,
    pub upstream: bool,
}

/// Parse flags allowed by `allowed` (space-separated); returns options and positionals.
pub fn parse_args(allowed: &str, args: &[String]) -> Result<(Opts, Vec<String>)> {
    let mut o = Opts::default();
    let mut pos = Vec::new();
    let mut it = args.iter();
    while let Some(a) = it.next() {
        let a = a.as_str();
        if a.starts_with('-') && !allowed.split(' ').any(|f| f == a) {
            die!("unknown flag for this command: {a} (allowed: {allowed})");
        }
        let mut val = || match it.next() {
            Some(v) => Ok(v.clone()),
            None => Err(anyhow::anyhow!("{a} needs a value")),
        };
        match a {
            "--as" => o.as_ = val()?,
            "--ref" => o.ref_ = val()?,
            "--from" => o.from = val()?,
            "--model" => o.model = val()?,
            "--effort" => o.effort = val()?,
            "--yes" => YES.store(true, Ordering::Relaxed),
            "--offline" => OFFLINE.store(true, Ordering::Relaxed),
            "--shell" => o.shell = true,
            "--dry-run" => o.dry = true,
            "--upstream" => o.upstream = true,
            _ => pos.push(a.to_string()),
        }
    }
    Ok((o, pos))
}

// ---- small path helpers ----
/// `p` relative to `base` when `p` is `base` ("") or below it.
pub fn under<'a>(p: &'a str, base: &str) -> Option<&'a str> {
    match p.strip_prefix(base) {
        Some("") => Some(""),
        Some(r) => r.strip_prefix('/'),
        None => None,
    }
}

/// `d/rel`, or `d` when `rel` is empty.
pub fn join(d: &str, rel: &str) -> String {
    if rel.is_empty() {
        d.to_string()
    } else {
        format!("{d}/{rel}")
    }
}

/// `${p##*/}`.
pub fn basename(p: &str) -> &str {
    p.rsplit('/').next().unwrap_or(p)
}

/// Path of `p` relative to `base`, as a string.
pub fn rel_to(p: &Path, base: &Path) -> String {
    p.strip_prefix(base).unwrap_or(p).to_string_lossy().into_owned()
}

/// Pre-order walk like `find <dir>` (symlinks not followed, readdir order), excluding <dir>;
/// directories matching `prune` are neither listed nor entered.
pub fn find(dir: &Path, prune: &dyn Fn(&Path) -> bool) -> Vec<(PathBuf, fs::FileType)> {
    let mut v = Vec::new();
    for e in fs::read_dir(dir).into_iter().flatten().flatten() {
        let (p, Ok(ft)) = (e.path(), e.file_type()) else { continue };
        if ft.is_dir() && prune(&p) {
            continue;
        }
        v.push((p.clone(), ft));
        if ft.is_dir() {
            v.extend(find(&p, prune));
        }
    }
    v
}
