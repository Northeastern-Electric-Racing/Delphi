//! Workspace folders (spec §2): `context/<scope>/workspaces/<name>/workspace.yml` with `name`,
//! `harness`, `instructions`, `mcp` (generated files), `blocks`, `docs`, `skills`, `settings`
//! (links: `<source> [-> <dest>]`) and `repos`. Paths in a `Ws` are relative to `context/`; link
//! dests are relative to the folder.

use crate::core::{basename, git, join, out, path_ok, run, under};
use crate::die;
use crate::harness::{self, Harness};
use crate::parse::{parse_text, Yaml};
use anyhow::Result;
use std::path::Path;

pub const YML: &str = "workspace.yml";
/// A skill directory's `name`, `description` and `body` (blocks) its `SKILL.md` is generated from.
pub const SKILL_YML: &str = "skill.yml";
pub const KEYS: &[&str] = &["name", "harness", "instructions", "mcp", "blocks", "docs", "skills", "settings", "repos"];
pub const LINK_KEYS: &[&str] = &["blocks", "docs", "skills", "settings"];

pub struct Ws {
    /// Folder relative to context/, e.g. `software/argos/workspaces/argos-dev`.
    pub folder: String,
    pub y: Yaml,
    pub h: &'static Harness,
    pub parts: Vec<String>,
    pub mcp: Vec<String>,
    /// (key, source, dest in the folder)
    pub links: Vec<(&'static str, String, String)>,
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
    /// Generated files that are set: (key, parts, file in the folder, what a part is called).
    pub fn generated(&self) -> Vec<(&'static str, &[String], &'static str, &'static str)> {
        let g = [
            ("instructions", &self.parts[..], self.h.instructions, "part"),
            ("mcp", &self.mcp[..], self.h.mcp, "fragment"),
        ];
        g.into_iter().filter(|g| !g.1.is_empty()).collect()
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

/// The part of `src` below its scope's `dir` (e.g. `harness/skills`), if it sits there. The scope
/// ends at the first `blocks`, `docs`, `harness` or `workspaces` component.
pub fn below<'a>(src: &'a str, dir: &str) -> Option<&'a str> {
    let i = src.split('/').position(|c| ["blocks", "docs", "harness", "workspaces"].contains(&c))?;
    under(&src[src.split('/').take(i).map(|c| c.len() + 1).sum::<usize>()..], dir)
}

/// Where a `key:` entry's source goes when it has no `-> dest`.
pub fn default_dest(key: &str, src: &str, h: &Harness) -> String {
    match (key, below(src, "docs"), below(src, "harness/skills")) {
        ("docs", Some(r), _) => join("docs", r),
        ("skills", _, Some(r)) => join(h.skills_dir, r),
        ("settings", ..) => h.settings.into(),
        _ => format!("context/{src}"),
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
    let (parts, mcp) = (y.list("instructions"), y.list("mcp"));
    for (k, v) in [("instructions", &parts), ("mcp", &mcp)] {
        if let Some(p) = v.iter().find(|p| !path_ok(p)) {
            die!("{label}: {k}: unsafe path '{p}'");
        }
    }
    let mut links = vec![];
    for &key in LINK_KEYS {
        for raw in y.list(key) {
            let (src, dest) = split_link(&raw);
            let dest = dest.unwrap_or_else(|| default_dest(key, &src, h));
            let reserved = [".git", "repos"].contains(&dest.split('/').next().unwrap_or("")) || dest == YML;
            if !path_ok(&src) || !path_ok(&dest) || reserved {
                die!("{label}: {key}: unsafe or reserved path in '{raw}'");
            }
            links.push((key, src, dest));
        }
    }
    Ok(Ws { folder: folder.into(), y, h, parts, mcp, links })
}

/// Every workspace at a revision of the repo at `dir`; unparsable ones are skipped (or reported,
/// if `warn`).
pub fn all_at(dir: &Path, rev: &str, warn: bool) -> Vec<Ws> {
    let t = out(git(dir).args(["ls-tree", "-r", "--name-only", rev, "--", "context"])).unwrap_or_default();
    let mut v = vec![];
    for p in t.lines() {
        let Some(f) = folder_of(p) else { continue };
        let blob = run(git(dir).args(["show", &format!("{rev}:{p}")]), true).unwrap_or_default();
        let text = String::from_utf8_lossy(&blob).into_owned();
        match load(f, &text, p) {
            Ok(w) => v.push(w),
            Err(e) if warn => crate::warn!("skipping {p}: {e:#}"),
            Err(_) => {}
        }
    }
    v
}

/// Workspaces (other than `me`) whose links cover source `src`.
pub fn sharing<'a>(all: &'a [Ws], src: &str, me: &str) -> Vec<&'a str> {
    all.iter()
        .filter(|w| w.folder != me && w.links.iter().any(|(_, s, _)| under(src, s).is_some()))
        .map(|w| w.name())
        .collect()
}
