//! Shared helpers (port of lib/core.sh): messages, deferred cleanup, prompts, config, repo-root
//! discovery, path safety, Delphi git access, moves, flag parsing, and small awk/sh equivalents.

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

/// Exit silently with this status (any message was already printed).
#[derive(Debug)]
pub struct Exit(pub i32);
impl fmt::Display for Exit {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "exit {}", self.0)
    }
}
impl std::error::Error for Exit {}

/// An error printed verbatim, without the `delphi: ` prefix (e.g. `file:line: msg`).
#[derive(Debug)]
pub struct Raw(pub String);
impl fmt::Display for Raw {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for Raw {}

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
pub fn offline() -> bool {
    OFFLINE.load(Ordering::Relaxed)
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
        let f = root_config_file();
        let rec = fs::read_to_string(&f).unwrap_or_default();
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
    let phys = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("/"));
    if let Some(p) = env_nonempty("PWD") {
        let p = PathBuf::from(p);
        if let (true, Ok(a), Ok(b)) = (p.is_absolute(), fs::metadata(&p), fs::metadata(".")) {
            if a.dev() == b.dev() && a.ino() == b.ino() {
                return p;
            }
        }
    }
    phys
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
    loop {
        let f = DEFERRED.lock().unwrap().pop();
        match f {
            Some(f) => f(),
            None => break,
        }
    }
}

/// New temp dir, removed on exit.
pub fn make_tmp() -> Result<PathBuf> {
    let base = env_nonempty("TMPDIR").unwrap_or_else(|| "/tmp".into());
    const CH: &[u8] = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    for i in 0..100u32 {
        let mut x = RandomState::new().hash_one((std::process::id(), i));
        let suffix: String = (0..6)
            .map(|_| {
                let c = CH[(x % CH.len() as u64) as usize] as char;
                x /= CH.len() as u64;
                c
            })
            .collect();
        let p = PathBuf::from(format!("{base}/delphi.{suffix}"));
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

/// Yes if --yes / DELPHI_YES=1; fails fast when non-interactive.
pub fn confirm(q: &str) -> Result<bool> {
    if yes() {
        return Ok(true);
    }
    if !is_tty() {
        die!("non-interactive session: re-run with --yes (or DELPHI_YES=1)");
    }
    Ok(matches!(read_answer(&format!("{q} [y/N] ")).as_deref(), Some("y" | "Y" | "yes")))
}

/// Ask a question; empty answer gives the default.
pub fn ask(q: &str, default: &str) -> Result<String> {
    if !is_tty() {
        die!("non-interactive session: cannot ask '{q}'");
    }
    let prompt = if default.is_empty() { format!("{q} ") } else { format!("{q} [{default}] ") };
    match read_answer(&prompt) {
        None => Err(Exit(1).into()),
        Some(a) if a.is_empty() => Ok(default.to_string()),
        Some(a) => Ok(a),
    }
}

// ---- config ----
/// Reads delphi.conf (key=value lines; `#` comments).
pub fn conf_get(key: &str, default: &str) -> String {
    let text = fs::read_to_string(root().join("delphi.conf")).unwrap_or_default();
    let v = awk_lines(&text)
        .into_iter()
        .filter(|l| !l.starts_with('#'))
        .map(|l| l.split_once('=').unwrap_or((l, l)))
        .find(|(k, _)| *k == key)
        .map(|(_, v)| v.to_string())
        .unwrap_or_default();
    if v.is_empty() {
        default.to_string()
    } else {
        v
    }
}

pub fn workspace_root() -> PathBuf {
    let r = env_nonempty("DELPHI_WORKSPACE_ROOT").unwrap_or_else(|| conf_get("workspace_root", "../Delphi-workspaces"));
    let r = if r.starts_with('/') { r } else { format!("{}/{r}", root().display()) };
    let p = PathBuf::from(&r);
    if p.is_dir() {
        return fs::canonicalize(&p).unwrap_or(p);
    }
    if let Some(i) = r.rfind('/') {
        let (dir, base) = (&r[..i], &r[i + 1..]);
        if !dir.is_empty() && Path::new(dir).is_dir() {
            if let Ok(d) = fs::canonicalize(dir) {
                return d.join(base);
            }
        }
    }
    p
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
    let full = PathBuf::from(format!("{}/{rel}", rroot.display()));
    let mut probe = full.clone();
    if fs::symlink_metadata(&probe).map(|m| m.file_type().is_symlink()).unwrap_or(false) {
        die!("unsafe path (symlink): '{rel}'");
    }
    while !probe.exists() {
        probe = probe.parent().map(Path::to_path_buf).unwrap_or_else(|| PathBuf::from("/"));
    }
    if !probe.is_dir() {
        probe = probe.parent().map(Path::to_path_buf).unwrap_or_else(|| PathBuf::from("/"));
    }
    let real = fs::canonicalize(&probe)?;
    if !format!("{}/", real.display()).starts_with(&format!("{}/", rroot.display())) {
        die!("unsafe path (escapes {}): '{rel}'", root.display());
    }
    Ok(full)
}

// ---- running commands ----
/// `git -c core.quotePath=false -C <dir>`.
pub fn git_in(dir: &Path) -> Command {
    let mut c = Command::new("git");
    c.args(["-c", "core.quotePath=false", "-C"]).arg(dir);
    c
}

/// Plain `git -C <dir>`.
pub fn git_c(dir: &Path) -> Command {
    let mut c = Command::new("git");
    c.arg("-C").arg(dir);
    c
}

/// git on the Delphi repo.
pub fn dgit<I: IntoIterator<Item = S>, S: AsRef<std::ffi::OsStr>>(args: I) -> Command {
    let mut c = git_in(root());
    c.args(args);
    c
}

pub fn trim_nl(s: &str) -> &str {
    s.trim_end_matches('\n')
}

/// Like `$(cmd)`: stdout with trailing newlines stripped, stderr passed through; None on failure.
pub fn out(c: &mut Command) -> Option<String> {
    let o = c.stdin(Stdio::inherit()).stderr(Stdio::inherit()).output().ok()?;
    o.status.success().then(|| trim_nl(&String::from_utf8_lossy(&o.stdout)).to_string())
}

/// Like `$(cmd 2>/dev/null)`.
pub fn out_q(c: &mut Command) -> Option<String> {
    c.stderr(Stdio::null());
    let o = c.stdin(Stdio::null()).output().ok()?;
    o.status.success().then(|| trim_nl(&String::from_utf8_lossy(&o.stdout)).to_string())
}

/// Raw stdout bytes (stderr passed through), with the exit status.
pub fn out_raw(c: &mut Command) -> (bool, Vec<u8>) {
    match c.stdin(Stdio::inherit()).stderr(Stdio::inherit()).output() {
        Ok(o) => (o.status.success(), o.stdout),
        Err(_) => (false, Vec::new()),
    }
}

/// Run with stdin fed from `input`; stdout captured like `out`.
pub fn out_stdin(c: &mut Command, input: &[u8]) -> Option<String> {
    let mut ch = c.stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::inherit()).spawn().ok()?;
    ch.stdin.take()?.write_all(input).ok()?;
    let o = ch.wait_with_output().ok()?;
    o.status.success().then(|| trim_nl(&String::from_utf8_lossy(&o.stdout)).to_string())
}

/// Run with inherited stdio; true on success.
pub fn ok(c: &mut Command) -> bool {
    c.status().map(|s| s.success()).unwrap_or(false)
}

/// Run with stdout and stderr discarded; true on success.
pub fn ok_q(c: &mut Command) -> bool {
    c.stdout(Stdio::null()).stderr(Stdio::null()).status().map(|s| s.success()).unwrap_or(false)
}

/// Whether a command is on PATH (`command -v`).
pub fn have(prog: &str) -> bool {
    std::env::var_os("PATH").map(|p| std::env::split_paths(&p).any(|d| is_exec(&d.join(prog)))).unwrap_or(false)
}

pub fn is_exec(p: &Path) -> bool {
    fs::metadata(p).map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0).unwrap_or(false)
}

/// `date +<fmt>` (local time).
pub fn date(fmt: &str) -> String {
    out(Command::new("date").arg(format!("+{fmt}"))).unwrap_or_default()
}

// ---- Delphi repo access ----
pub fn delphi_fetch() {
    if offline() {
        return;
    }
    if !dgit(["fetch", "--prune", "--quiet", "origin"]).stderr(Stdio::null()).status().is_ok_and(|s| s.success()) {
        warn!("git fetch failed; using local refs");
    }
}

/// Full sha of origin/<branch>.
pub fn delphi_commit(branch: &str) -> Result<String> {
    match out(&mut dgit(["rev-parse", "--verify", "--quiet", &format!("origin/{branch}^{{commit}}")])) {
        Some(c) => Ok(c),
        None => die!("no such Delphi branch: origin/{branch}"),
    }
}

/// Detached temp worktree of Delphi at a commit.
pub fn delphi_worktree_at(c: &str) -> Result<PathBuf> {
    let d = make_tmp()?.join("src");
    if !ok_q(dgit(["worktree", "add", "--quiet", "--detach"]).arg(&d).arg(c)) {
        die!("cannot check out Delphi at {c}");
    }
    let dd = d.clone();
    defer(move || {
        ok_q(git_c(root()).args(["worktree", "remove", "--force"]).arg(&dd));
    });
    Ok(d)
}

pub fn name_ok(name: &str) -> bool {
    !name.is_empty() && name.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
}

/// The layout dir (relative to context/) of layout <name> in a tree.
pub fn find_layout(tree: &Path, name: &str) -> Result<String> {
    if !name_ok(name) {
        die!("invalid layout name: '{name}'");
    }
    let suffix = format!("/layouts/{name}/manifest.yml");
    let ctx = tree.join("context");
    let hits: Vec<String> = find(&ctx)
        .into_iter()
        .filter(|(_, ft)| ft.is_file())
        .map(|(p, _)| format!("./{}", rel_to(&p, &ctx)))
        .filter(|p| p.ends_with(&suffix))
        .map(|p| p[2..p.len() - "/manifest.yml".len()].to_string())
        .collect();
    match hits.len() {
        1 => Ok(hits[0].clone()),
        0 => die!("layout not found: {name}"),
        _ => die!("layout name not unique: {name}"),
    }
}

// ---- moves (moves.tsv is append-only; rows apply in order, each once) ----
pub type Moves = Vec<(String, String)>;

pub fn parse_moves(text: &str) -> Moves {
    awk_lines(text)
        .into_iter()
        .filter(|l| !l.starts_with('#'))
        .filter_map(|l| {
            let f: Vec<&str> = l.split('\t').collect();
            (!l.is_empty() && f.len() >= 2).then(|| (f[0].to_string(), f[1].to_string()))
        })
        .collect()
}

/// Rows of moves.tsv added between two Delphi commits.
pub fn moves_since(old: &str, new: &str) -> Moves {
    let show = |c: &str| {
        let o = dgit(["show", &format!("{c}:moves.tsv")]).stderr(Stdio::null()).output();
        o.map(|o| String::from_utf8_lossy(&o.stdout).into_owned()).unwrap_or_default()
    };
    let n = awk_lines(&show(old)).len();
    parse_moves(&awk_lines(&show(new)).into_iter().skip(n).collect::<Vec<_>>().join("\n"))
}

pub fn move_path(rows: &Moves, p: &str) -> String {
    let mut p = p.to_string();
    for (o, n) in rows {
        if &p == o {
            p = n.clone();
        } else if p.starts_with(&format!("{o}/")) {
            p = format!("{n}{}", &p[o.len()..]);
        }
    }
    p
}

/// Apply move rows to `  - item` lines and `settings:` values in place (trailing comments on
/// rewritten lines are dropped). True if anything changed.
pub fn rewrite_moves(rows: &Moves, file: &Path) -> Result<bool> {
    let text = String::from_utf8_lossy(&fs::read(file)?).into_owned();
    let mut ch = false;
    let mut res = String::new();
    for l in awk_lines(&text) {
        let pre = if l.starts_with("  - ") {
            "  - "
        } else if l.starts_with("settings: ") {
            "settings: "
        } else {
            ""
        };
        let mut line = l.to_string();
        if !pre.is_empty() {
            let mut v = &l[pre.len()..];
            if let Some(i) = v.find(" #") {
                v = &v[..i];
            }
            let v = v.trim_end_matches(' ');
            let m = move_path(rows, v);
            if m != v {
                line = format!("{pre}{m}");
                ch = true;
            }
        }
        res.push_str(&line);
        res.push('\n');
    }
    if ch {
        write_replace(file, res.as_bytes())?;
    }
    Ok(ch)
}

/// Write `<file>.tmp` then rename it over `<file>`.
pub fn write_replace(file: &Path, data: &[u8]) -> Result<()> {
    let tmp = PathBuf::from(format!("{}.tmp", file.display()));
    fs::write(&tmp, data)?;
    fs::rename(&tmp, file)?;
    Ok(())
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
}

/// Parse flags allowed by `allowed` (space-separated); returns options and positionals.
pub fn parse_args(allowed: &str, args: &[String]) -> Result<(Opts, Vec<String>)> {
    let ok: Vec<&str> = allowed.split_whitespace().collect();
    let mut o = Opts::default();
    let mut pos = Vec::new();
    let mut i = 0;
    while i < args.len() {
        let a = args[i].as_str();
        if a.starts_with('-') && !ok.contains(&a) {
            die!("unknown flag for this command: {a} (allowed: {allowed})");
        }
        match a {
            "--as" | "--ref" | "--from" | "--model" | "--effort" => {
                let Some(v) = args.get(i + 1).cloned() else { die!("{a} needs a value") };
                match a {
                    "--as" => o.as_ = v,
                    "--ref" => o.ref_ = v,
                    "--from" => o.from = v,
                    "--model" => o.model = v,
                    _ => o.effort = v,
                }
                i += 1;
            }
            "--yes" => YES.store(true, Ordering::Relaxed),
            "--shell" => o.shell = true,
            "--dry-run" => o.dry = true,
            "--offline" => OFFLINE.store(true, Ordering::Relaxed),
            _ => pos.push(a.to_string()),
        }
        i += 1;
    }
    Ok((o, pos))
}

// ---- small awk / sh equivalents ----
/// Lines as awk reads them: split on '\n', no trailing empty record.
pub fn awk_lines(s: &str) -> Vec<&str> {
    let mut v: Vec<&str> = s.split('\n').collect();
    if v.last() == Some(&"") {
        v.pop();
    }
    v
}

/// awk `substr(s, m, n)` (1-based, clamped, characters).
pub fn substr(s: &str, m: i64, n: Option<i64>) -> String {
    let len = s.chars().count() as i64;
    let start = m.max(1);
    let end = n.map_or(len + 1, |n| (m + n).min(len + 1));
    if end <= start {
        return String::new();
    }
    s.chars().skip((start - 1) as usize).take((end - start) as usize).collect()
}

/// awk numeric conversion of a string (leading integer prefix, else 0).
pub fn num(s: &str) -> i64 {
    let s = s.trim_start();
    let (neg, d) = match s.strip_prefix('-') {
        Some(r) => (true, r),
        None => (false, s.strip_prefix('+').unwrap_or(s)),
    };
    let n: i64 = d.chars().take_while(char::is_ascii_digit).collect::<String>().parse().unwrap_or(0);
    if neg {
        -n
    } else {
        n
    }
}

/// Shell glob match where only `*` (anything, including `/`) and `?` are special.
pub fn glob(pat: &str, s: &str) -> bool {
    fn m(p: &[char], s: &[char]) -> bool {
        match p.first() {
            None => s.is_empty(),
            Some('*') => (0..=s.len()).any(|i| m(&p[1..], &s[i..])),
            Some('?') => !s.is_empty() && m(&p[1..], &s[1..]),
            Some(c) => s.first() == Some(c) && m(&p[1..], &s[1..]),
        }
    }
    m(&pat.chars().collect::<Vec<_>>(), &s.chars().collect::<Vec<_>>())
}

/// `${lp%layouts/*}`: the layout's scope prefix (with trailing slash).
pub fn scope_of_layout(lp: &str) -> &str {
    lp.rfind("layouts/").map_or(lp, |i| &lp[..i])
}

/// `${p##*/}`.
pub fn basename(p: &str) -> &str {
    p.rsplit('/').next().unwrap_or(p)
}

/// Path of `p` relative to `base`, as a string.
pub fn rel_to(p: &Path, base: &Path) -> String {
    p.strip_prefix(base).unwrap_or(p).to_string_lossy().into_owned()
}

/// Pre-order walk like `find <dir>` (symlinks not followed, readdir order), excluding <dir>.
pub fn find(dir: &Path) -> Vec<(PathBuf, fs::FileType)> {
    let mut v = Vec::new();
    find_into(dir, &|_| false, &mut v);
    v
}

/// Like `find`, but directories matching `prune` are neither listed nor entered.
pub fn find_into(dir: &Path, prune: &dyn Fn(&Path) -> bool, v: &mut Vec<(PathBuf, fs::FileType)>) {
    let Ok(rd) = fs::read_dir(dir) else { return };
    for e in rd.flatten() {
        let (p, Ok(ft)) = (e.path(), e.file_type()) else { continue };
        if ft.is_dir() && prune(&p) {
            continue;
        }
        v.push((p.clone(), ft));
        if ft.is_dir() {
            find_into(&p, prune, v);
        }
    }
}

/// Names in a directory as `dir/*` expands them: sorted, no dot-files.
pub fn glob_dir(dir: &Path) -> Vec<String> {
    let mut v: Vec<String> = fs::read_dir(dir)
        .map(|rd| rd.flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect())
        .unwrap_or_default();
    v.retain(|n| !n.starts_with('.'));
    v.sort();
    v
}

pub fn now() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}
