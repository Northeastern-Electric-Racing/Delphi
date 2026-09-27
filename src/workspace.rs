//! Workspace folders (spec §2): `context/<scope>/workspaces/<name>/workspace.yml` with `name`,
//! `harness` and `repos`. `folder` is repo-relative.

use crate::core::{basename, git, out, path_ok, run};
use crate::harness::{self, Harness};
use crate::parse::{parse_text, Yaml};
use anyhow::Result;
use std::path::Path;

pub const YML: &str = "workspace.yml";
pub const KEYS: &[&str] = &["name", "harness", "repos"];

pub struct Ws {
    /// Repo-relative folder, e.g. `context/software/workspaces/argos-dev`.
    pub folder: String,
    pub y: Yaml,
    pub h: &'static Harness,
}

impl Ws {
    pub fn name(&self) -> &str {
        basename(&self.folder)
    }
    /// The workspace's scope below context/ ("." for the root scope).
    pub fn scope(&self) -> &str {
        let s = self.folder.strip_prefix("context/").unwrap_or("");
        let s = s.strip_suffix(&format!("workspaces/{}", self.name())).unwrap_or(s).trim_end_matches('/');
        if s.is_empty() {
            "."
        } else {
            s
        }
    }
}

/// The folder when `p` is `context/<…>/workspaces/<name>/workspace.yml`.
pub fn folder_of(p: &str) -> Option<&str> {
    let f = p.strip_suffix("/workspace.yml").filter(|_| p.starts_with("context/"))?;
    let (parent, name) = f.rsplit_once('/')?;
    (basename(parent) == "workspaces" && !name.is_empty()).then_some(f)
}

/// Parse a workspace.yml (`label` names it in errors).
pub fn load(folder: &str, text: &str, label: &str) -> Result<Ws> {
    let y = parse_text(text, label)?;
    let h = harness::load(&y.get("harness")).map_err(|e| anyhow::anyhow!("{label}: {e}"))?;
    Ok(Ws { folder: folder.into(), y, h })
}

/// Every workspace at a revision of the repo at `dir`; unparsable ones are skipped (or reported,
/// if `warn`). A `workspace.yml` nested in another workspace folder is not a workspace.
pub fn all_at(dir: &Path, rev: &str, warn: bool) -> Vec<Ws> {
    let t = out(git(dir).args(["ls-tree", "-r", "--name-only", rev, "--", "context"])).unwrap_or_default();
    let found: Vec<&str> = t.lines().filter_map(folder_of).filter(|f| path_ok(f)).collect();
    let mut v = vec![];
    for f in found.iter().filter(|f| !found.iter().any(|o| f.starts_with(&format!("{o}/")))) {
        let p = format!("{f}/{YML}");
        let blob = run(git(dir).args(["show", &format!("{rev}:{p}")]), true).unwrap_or_default();
        match load(f, &String::from_utf8_lossy(&blob), &p) {
            Ok(w) => v.push(w),
            Err(e) if warn => crate::warn!("skipping {p}: {e:#}"),
            Err(_) => {}
        }
    }
    v
}

/// The workspace named `name` on a revision, or an error naming where to look.
pub fn named(dir: &Path, rev: &str, name: &str) -> Result<Ws> {
    match all_at(dir, rev, true).into_iter().find(|w| w.name() == name) {
        Some(w) => Ok(w),
        None => crate::die!("no workspace named '{name}' on origin/main (see: delphi list)"),
    }
}
