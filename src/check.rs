//! Repo-wide validation (port of lib/check.sh). `check_tree(root)` prints every violation and
//! returns false if any. Layouts are validated by compiling them; the rules here cover what
//! compile doesn't enforce.

use crate::compile::compile;
use crate::core::{basename, find, find_into, glob, glob_dir, have, make_tmp, path_ok, root, Exit, Raw};
use crate::harness::HARNESSES;
use crate::parse::parse_yaml;
use crate::{die, info};
use anyhow::Result;
use std::fs;
use std::path::Path;
use std::process::{Command, Stdio};

pub fn main(args: &[String]) -> Result<()> {
    if !args.is_empty() {
        die!("usage: delphi check");
    }
    if check_tree(root())? {
        info!("check: ok");
        Ok(())
    } else {
        Err(Exit(1).into())
    }
}

struct Ck<'a> {
    root: &'a str,
    errs: Vec<String>,
}

impl Ck<'_> {
    fn e(&mut self, m: String) {
        self.errs.push(m);
    }

    /// `${f#$root/}`.
    fn rel(&self, p: &Path) -> String {
        let s = p.to_string_lossy();
        s.strip_prefix(&format!("{}/", self.root)).unwrap_or(&s).to_string()
    }

    /// Placement rule for the kind (instructions|skills|mcp|settings|body); `body` (skill specs)
    /// and `any` (recommendations) must also exist.
    fn entry(&mut self, f: &str, key: &str, p: &str, kind: &str) {
        if !path_ok(p.strip_suffix("/*").unwrap_or(p)) {
            return self.e(format!("{f}: {key}: unsafe path '{p}'"));
        }
        let want = match kind {
            "instructions" => "*/harness/instructions/*",
            "skills" => "*/harness/skills/*",
            "mcp" => "*/harness/mcp/*.json",
            "settings" => "*/harness/settings/*",
            "body" => "*/blocks/*",
            _ => "*",
        };
        if !glob(want, &format!("/{p}")) {
            let w = want.strip_prefix("*/").unwrap_or(want);
            self.e(format!("{f}: {key}: '{p}' is not under {w}"));
        }
        if matches!(kind, "body" | "any") && !Path::new(&format!("{}/context/{p}", self.root)).exists() {
            self.e(format!("{f}: {key}: missing '{p}'"));
        }
    }
}

pub fn check_tree(root_dir: &Path) -> Result<bool> {
    let root_s = root_dir.to_string_lossy().into_owned();
    let mut ck = Ck { root: &root_s, errs: vec![] };
    let ctx = Path::new(&format!("{root_s}/context")).to_path_buf();
    if !ctx.is_dir() {
        eprintln!("missing context/ directory");
        return Ok(false);
    }

    // scopes: every non-reserved directory needs scope.yml
    let reserved = |p: &Path| matches!(basename(&p.to_string_lossy()), "blocks" | "docs" | "harness" | "layouts");
    let mut dirs = vec![];
    find_into(&ctx, &reserved, &mut dirs);
    let dirs = std::iter::once(ctx.clone()).chain(dirs.into_iter().filter(|(_, ft)| ft.is_dir()).map(|(p, _)| p));
    for d in dirs {
        if !d.join("scope.yml").is_file() {
            ck.e(format!("{}: scope directory has no scope.yml", ck.rel(&d)));
        }
        for n in glob_dir(&d) {
            if d.join(&n).is_file() && n != "scope.yml" {
                let r = ck.rel(&d.join(&n));
                ck.e(format!(
                    "{r}: stray file (scopes hold only scope.yml, blocks/, docs/, harness/, layouts/, child scopes)"
                ));
            }
        }
    }

    // files: no symlinks, no empty files, trailing newline, no harness instruction file names
    let all = find(&ctx);
    let links: Vec<String> =
        all.iter().filter(|(_, ft)| ft.is_symlink()).map(|(p, _)| format!("{} ", ck.rel(p))).collect();
    if !links.is_empty() {
        ck.e(format!("context/ must not contain symlinks: {}", links.concat()));
    }
    let files: Vec<&Path> = all.iter().filter(|(_, ft)| ft.is_file()).map(|(p, _)| p.as_path()).collect();
    for f in &files {
        let r = ck.rel(f);
        let data = fs::read(f).unwrap_or_default();
        if data.is_empty() {
            ck.e(format!("{r}: empty file"));
            continue;
        }
        if data.last() != Some(&b'\n') {
            ck.e(format!("{r}: missing trailing newline"));
        }
        let name = basename(&r);
        if HARNESSES.iter().any(|h| h.instructions == name) {
            ck.e(format!("{r}: harness instruction file names are not allowed under context/"));
        }
    }
    let named = |pat: &str| -> Vec<&Path> {
        files.iter().copied().filter(|f| glob(pat, basename(&f.to_string_lossy()))).collect()
    };

    // every yml/skill parses
    for f in files.iter().filter(|f| {
        let n = f.to_string_lossy();
        glob("*.yml", basename(&n)) || glob("*.skill", basename(&n))
    }) {
        if let Err(e) = parse_yaml(f) {
            ck.e(e.to_string());
        }
    }

    // scope recommendations exist
    for f in named("scope.yml") {
        let Ok(recs) = parse_yaml(f) else { continue };
        let r = ck.rel(f);
        for p in recs.list("recommend").into_iter().filter(|p| !p.is_empty()) {
            ck.entry(&r, "recommend", &p, "any");
        }
    }

    // skill specs
    for f in named("*.skill") {
        let Ok(recs) = parse_yaml(f) else { continue };
        let r = ck.rel(f);
        if recs.get("name").is_empty() {
            ck.e(format!("{r}: missing name"));
        }
        if recs.get("description").is_empty() {
            ck.e(format!("{r}: missing description"));
        }
        for k in recs.keys() {
            if !matches!(k.as_str(), "name" | "description" | "body" | "references") {
                ck.e(format!("{r}: unknown key '{k}'"));
            }
        }
        for p in recs.list("body").into_iter().chain(recs.list("references")).filter(|p| !p.is_empty()) {
            ck.entry(&r, "body", &p, "body");
        }
    }

    // layouts
    let tmp = make_tmp()?;
    let mut names = vec![String::new()];
    let mut i = 0;
    for f in files.iter().filter(|f| glob("*/layouts/*/manifest.yml", &f.to_string_lossy())) {
        let Ok(recs) = parse_yaml(f) else { continue };
        let r = ck.rel(f);
        let name = recs.get("name");
        let dir = f.parent().map(|p| basename(&p.to_string_lossy()).to_string()).unwrap_or_default();
        if name.is_empty() {
            ck.e(format!("{r}: missing name"));
        }
        if name != dir {
            ck.e(format!("{r}: name '{name}' must equal its directory '{dir}'"));
        }
        if names.contains(&name) {
            ck.e(format!("{r}: layout name '{name}' is not unique"));
        }
        names.push(name);
        let h = recs.get("harness");
        if h.is_empty() {
            ck.e(format!("{r}: missing harness"));
        } else if !HARNESSES.iter().any(|x| x.name == h) {
            ck.e(format!("{r}: unknown harness '{h}'"));
        } else {
            // compile it: catches missing paths, empty globs, duplicate outputs, bad skill specs
            i += 1;
            let out = tmp.join(format!("errs.{i}"));
            fs::create_dir(&out)?;
            let lay = r.strip_prefix("context/").unwrap_or(&r);
            let lay = &lay[..lay.rfind('/').unwrap_or(0)];
            if let Err(e) = compile(root_dir, lay, &out) {
                match e.downcast_ref::<Raw>() {
                    Some(raw) => ck.e(raw.0.clone()),
                    None => ck.e(format!("{r}: {e:#}")),
                }
            }
        }
        for k in recs.keys() {
            let known = ["name", "harness", "instructions", "blocks", "docs", "skills", "mcp", "settings", "repos"];
            if !known.contains(&k.as_str()) {
                ck.e(format!("{r}: unknown key '{k}'"));
            }
        }
        if recs.list("settings").iter().filter(|s| !s.trim().is_empty()).count() > 1 {
            ck.e(format!("{r}: at most one settings file"));
        }
        for k in ["instructions", "skills", "mcp", "settings"] {
            for p in recs.list(k).into_iter().filter(|p| !p.is_empty()) {
                ck.entry(&r, k, &p, k);
            }
        }
    }

    // moves.tsv: three fields
    if let Ok(m) = fs::read_to_string(format!("{root_s}/moves.tsv")) {
        for (n, l) in crate::core::awk_lines(&m).into_iter().enumerate() {
            if !l.starts_with('#') && !l.is_empty() && l.split('\t').count() != 3 {
                ck.e(format!("moves.tsv:{}: expected old<TAB>new<TAB>date", n + 1));
            }
        }
    }

    // MCP fragments are valid JSON (only if jq is installed)
    if have("jq") {
        for f in files.iter().filter(|f| glob("*/harness/mcp/*.json", &f.to_string_lossy())) {
            let mut doc = b"{".to_vec();
            doc.extend(fs::read(f).unwrap_or_default());
            doc.push(b'}');
            let valid = Command::new("jq")
                .arg("empty")
                .stdin(Stdio::piped())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()
                .and_then(|mut c| {
                    use std::io::Write;
                    if let Some(mut s) = c.stdin.take() {
                        let _ = s.write_all(&doc);
                    }
                    c.wait()
                })
                .is_ok_and(|s| s.success());
            if !valid {
                let r = ck.rel(f);
                ck.e(format!("{r}: not a valid mcpServers member"));
            }
        }
    } else {
        info!("check: jq not installed; skipping MCP JSON validation");
    }

    for e in &ck.errs {
        eprintln!("check: {e}");
    }
    Ok(ck.errs.is_empty())
}
