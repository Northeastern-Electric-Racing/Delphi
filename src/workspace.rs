//! Workspace folders (spec §2): `context/<scope>/workspaces/<name>/workspace.yml` with `name`,
//! `harness`, `instructions`, `links` (`<source> [-> <dest>]`) and `repos`. Paths in a `Ws` are
//! relative to `context/`; link dests are relative to the folder.

use crate::core::{basename, delphi_commit, git, out, path_ok, root, show_in, under};
use crate::die;
use crate::harness::{self, Harness};
use crate::parse::{parse_text, Yaml};
use anyhow::Result;
use std::path::Path;

pub const YML: &str = "workspace.yml";
pub const KEYS: &[&str] = &["name", "harness", "instructions", "links", "repos"];

pub struct Ws {
    /// Folder relative to context/, e.g. `software/argos/workspaces/argos-dev`.
    pub folder: String,
    pub y: Yaml,
    pub h: &'static Harness,
    pub parts: Vec<String>,
    /// (source, dest in the folder)
    pub links: Vec<(String, String)>,
}

impl Ws {
    pub fn name(&self) -> &str {
        basename(&self.folder)
    }
    /// The workspace's scope ("." for the root scope).
    pub fn scope(&self) -> &str {
        let s = &self.folder[..self.folder.len() - self.name().len()];
        let s = s.trim_end_matches('/').trim_end_matches("workspaces").trim_end_matches('/');
        if s.is_empty() {
            "."
        } else {
            s
        }
    }
    /// Repo-relative path of a file in the folder.
    pub fn path(&self, rel: &str) -> String {
        format!("context/{}/{rel}", self.folder)
    }
}

/// The folder (relative to context/) when `p` is `context/<…>/workspaces/<name>/workspace.yml`.
pub fn folder_of(p: &str) -> Option<&str> {
    let f = p.strip_prefix("context/")?.strip_suffix("/workspace.yml")?;
    let (parent, name) = f.rsplit_once('/')?;
    (basename(parent) == "workspaces" && !name.is_empty()).then_some(f)
}

/// Where a link's source goes when it has no `-> dest`.
pub fn default_dest(src: &str, h: &Harness) -> String {
    let c: Vec<&str> = src.split('/').collect();
    if let Some(i) = c.windows(2).position(|w| w == ["harness", "skills"]).filter(|i| i + 2 < c.len()) {
        return format!("{}/{}", h.skills_dir, c[i + 2..].join("/"));
    }
    match c.iter().position(|&x| x == "docs") {
        Some(i) => [&["docs"][..], &c[i + 1..]].concat().join("/"),
        None => format!("context/{src}"),
    }
}

/// A link's source and explicit dest (trimmed, trailing `/` dropped).
pub fn split_link(raw: &str) -> (String, Option<String>) {
    let t = |x: &str| x.trim_matches(' ').trim_end_matches('/').to_string();
    raw.split_once(" -> ").map_or_else(|| (t(raw), None), |(s, d)| (t(s), Some(t(d))))
}

/// Parse a workspace.yml (`label` names it in errors).
pub fn load(folder: &str, text: &str, label: &str) -> Result<Ws> {
    let y = parse_text(text, label)?;
    let h = harness::load(&y.get("harness")).map_err(|e| anyhow::anyhow!("{label}: {e}"))?;
    let parts = y.list("instructions");
    if let Some(p) = parts.iter().find(|p| !path_ok(p)) {
        die!("{label}: instructions: unsafe path '{p}'");
    }
    let mut links = vec![];
    for raw in y.list("links") {
        let (src, dest) = split_link(&raw);
        let dest = dest.unwrap_or_else(|| default_dest(&src, h));
        let reserved = [".git", "repos"].contains(&dest.split('/').next().unwrap_or("")) || dest == YML;
        if !path_ok(&src) || !path_ok(&dest) || reserved {
            die!("{label}: links: unsafe or reserved path in '{raw}'");
        }
        links.push((src, dest));
    }
    Ok(Ws { folder: folder.into(), y, h, parts, links })
}

/// workspace.yml paths (repo-relative) at a revision of the repo at `dir`.
pub fn ymls_at(dir: &Path, rev: &str) -> Vec<String> {
    let t = out(git(dir).args(["ls-tree", "-r", "--name-only", rev, "--", "context"])).unwrap_or_default();
    t.lines().filter(|p| folder_of(p).is_some()).map(String::from).collect()
}

/// Every workspace at a revision; unparsable ones are skipped (or reported, if `warn`).
pub fn all_at(dir: &Path, rev: &str, warn: bool) -> Vec<Ws> {
    let mut v = vec![];
    for p in ymls_at(dir, rev) {
        let text = String::from_utf8_lossy(&show_in(dir, rev, &p).unwrap_or_default()).into_owned();
        match load(folder_of(&p).unwrap_or(""), &text, &p) {
            Ok(w) => v.push(w),
            Err(e) if warn => crate::warn!("skipping {p}: {e:#}"),
            Err(_) => {}
        }
    }
    v
}

/// Workspaces on the Delphi repo's origin/main.
pub fn on_main() -> Result<Vec<Ws>> {
    Ok(all_at(root(), &delphi_commit("main")?, true))
}

/// Workspaces (other than `me`) whose links cover source `src`.
pub fn sharing<'a>(all: &'a [Ws], src: &str, me: &str) -> Vec<&'a str> {
    all.iter()
        .filter(|w| w.folder != me && w.links.iter().any(|(s, _)| under(src, s).is_some()))
        .map(|w| w.name())
        .collect()
}
