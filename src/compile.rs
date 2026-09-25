//! Layout -> workspace files + `.delphi/lock.tsv` (segment map). Deterministic. Port of
//! lib/compile.sh.
//!
//! `compile(src, layout, out)`: `src` is a checked-out Delphi tree (usually a temp worktree at a
//! specific commit), `layout` the layout dir relative to context/, `out` an empty directory.
//! Returns the layout's harness.

use crate::core::{basename, find, glob, glob_dir, out_q, safe_path};
use crate::harness::{self, Harness};
use crate::parse::parse_yaml;
use anyhow::Result;
use std::fmt::Write as _;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

struct Compiler<'a> {
    ctx: PathBuf,
    out: &'a Path,
    lock: String,
}

fn count(p: &Path) -> usize {
    fs::read(p).map(|b| b.iter().filter(|&&c| c == b'\n').count()).unwrap_or(0)
}

fn append(p: &Path, data: &[u8]) -> Result<()> {
    if let Some(d) = p.parent() {
        fs::create_dir_all(d)?;
    }
    OpenOptions::new().create(true).append(true).open(p)?.write_all(data)?;
    Ok(())
}

impl Compiler<'_> {
    fn seg(&mut self, out: &str, start: usize, end: usize, src: &str, sha: &str) {
        let _ = writeln!(self.lock, "{out}\t{start}\t{end}\t{src}\t{sha}");
    }

    /// Append a source file (relative to context/) to an output file.
    fn file(&mut self, out: &str, src: &str) -> Result<()> {
        let o = self.out.join(out);
        let s = safe_path(&self.ctx, src)?;
        if !s.is_file() {
            crate::die!("compile: missing file context/{src}");
        }
        let data = fs::read(&s)?;
        if data.is_empty() {
            crate::die!("compile: empty file context/{src}");
        }
        let start = count(&o) + 1;
        append(&o, &data)?;
        if data.last() != Some(&b'\n') {
            append(&o, b"\n")?;
        }
        let sha = out_q(Command::new("git").arg("hash-object").arg(&s)).unwrap_or_default();
        self.seg(out, start, count(&o), src, &sha);
        Ok(())
    }

    /// 1:1 copy (keeps the executable bit); the output path must not already exist.
    fn copy(&mut self, out: &str, src: &str) -> Result<()> {
        if self.out.join(out).exists() {
            crate::die!("compile: two sources map to the same output '{out}'");
        }
        self.file(out, src)?;
        let exec = fs::metadata(self.ctx.join(src)).map(|m| m.permissions().mode() & 0o111 != 0).unwrap_or(false);
        if exec {
            let o = self.out.join(out);
            let mode = fs::metadata(&o)?.permissions().mode();
            if fs::set_permissions(&o, fs::Permissions::from_mode(mode | 0o111)).is_err() {
                crate::die!("compile: cannot chmod {out}");
            }
        }
        Ok(())
    }

    /// Append generated (`@gen:…`) or separator (`@glue`) lines.
    fn text(&mut self, out: &str, label: &str, text: &str) -> Result<()> {
        let o = self.out.join(out);
        let start = count(&o) + 1;
        append(&o, format!("{text}\n").as_bytes())?;
        self.seg(out, start, count(&o), label, "-");
        Ok(())
    }

    /// The files an entry names (a file, or a trailing `/*` glob).
    fn expand(&self, entry: &str) -> Result<Vec<String>> {
        let Some(dir) = entry.strip_suffix("/*") else { return Ok(vec![entry.to_string()]) };
        let abs = safe_path(&self.ctx, dir)?;
        if !abs.is_dir() {
            crate::die!("compile: no such directory context/{dir}");
        }
        let v: Vec<String> =
            glob_dir(&abs).into_iter().filter(|n| abs.join(n).is_file()).map(|n| format!("{dir}/{n}")).collect();
        if v.is_empty() {
            crate::die!("compile: glob matches nothing: {entry}");
        }
        Ok(v)
    }
}

fn header(name: &str) -> String {
    format!(
        "<!-- Compiled by Delphi from layout '{name}'. Edit freely: every line is traced to its source block. -->\n\
         <!-- When your work is done, commit it; 'delphi workspace propose' sends block changes upstream. -->"
    )
}

pub fn compile(src: &Path, layout: &str, out: &Path) -> Result<&'static Harness> {
    if fs::create_dir_all(out.join(".delphi")).is_err() {
        crate::die!("compile: cannot write {}", out.display());
    }
    let mut c = Compiler { ctx: src.join("context"), out, lock: String::new() };
    let mf = safe_path(&c.ctx, &format!("{layout}/manifest.yml"))?;
    let recs = parse_yaml(&mf)?;
    let hname = recs.get("harness");
    if hname.is_empty() {
        crate::die!("compile: {layout}/manifest.yml has no harness");
    }
    let h = harness::load(&hname)?;
    let nonempty = |k: &str| recs.list(k).into_iter().filter(|s| !s.is_empty()).collect::<Vec<_>>();

    // instructions: header, then fragments separated by one blank line
    c.text(h.instructions, "@gen:delphi", &header(&recs.get("name")))?;
    for item in nonempty("instructions") {
        c.text(h.instructions, "@glue", "")?;
        c.file(h.instructions, &item)?;
    }

    // blocks: mirrored at context/<path>
    for item in nonempty("blocks") {
        for f in c.expand(&item)? {
            if !glob("*/blocks/*", &format!("/{f}")) {
                crate::die!("compile: '{f}' is listed under blocks: but is not in a blocks/ directory");
            }
            c.copy(&format!("context/{f}"), &f)?;
        }
    }

    // docs: at docs/<path below the scope's docs/>
    for item in nonempty("docs") {
        for f in c.expand(&item)? {
            let sub = format!("/{f}");
            if !glob("*/docs/?*", &sub) {
                crate::die!("compile: '{f}' is listed under docs: but is not in a docs/ directory");
            }
            let below = &sub[sub.find("/docs/").unwrap_or(0) + 6..];
            c.copy(&format!("docs/{below}"), &f)?;
        }
    }

    // skills: native dirs copied 1:1; .skill specs assembled
    for item in nonempty("skills") {
        if item.ends_with(".skill") {
            let spec = safe_path(&c.ctx, &item)?;
            let srecs = parse_yaml(&spec)?;
            let (sname, sdesc) = (srecs.get("name"), srecs.get("description"));
            if sname.is_empty() || sdesc.is_empty() {
                crate::die!("compile: {item} needs name and description");
            }
            let skdir = format!("{}/{sname}", h.skills_dir);
            if out.join(&skdir).exists() {
                crate::die!("compile: two skills named '{sname}'");
            }
            let md = format!("{skdir}/SKILL.md");
            c.text(&md, &format!("@gen:{item}"), &format!("---\nname: {sname}\ndescription: {sdesc}\n---"))?;
            for f in srecs.list("body").into_iter().filter(|s| !s.is_empty()) {
                c.text(&md, "@glue", "")?;
                c.file(&md, &f)?;
            }
            for f in srecs.list("references").into_iter().filter(|s| !s.is_empty()) {
                c.copy(&format!("{skdir}/references/{}", basename(&f)), &f)?;
            }
        } else {
            let abs = safe_path(&c.ctx, &item)?;
            if !abs.join("SKILL.md").is_file() {
                crate::die!("compile: skill '{item}' has no SKILL.md");
            }
            let skdir = format!("{}/{}", h.skills_dir, basename(&item));
            if out.join(&skdir).exists() {
                crate::die!("compile: two skills named '{}'", basename(&item));
            }
            let mut subs: Vec<String> = find(&abs)
                .into_iter()
                .filter(|(_, ft)| ft.is_file())
                .map(|(p, _)| crate::core::rel_to(&p, &abs))
                .collect();
            subs.sort();
            for sub in subs {
                c.copy(&format!("{skdir}/{sub}"), &format!("{item}/{sub}"))?;
            }
        }
    }

    // mcp: fragments wrapped in {"mcpServers": { … }}, omitted when empty
    let mut first = true;
    for item in nonempty("mcp") {
        if first {
            c.text(h.mcp_file, "@gen:delphi", "{\"mcpServers\": {")?;
            first = false;
        } else {
            c.text(h.mcp_file, "@glue", ",")?;
        }
        c.file(h.mcp_file, &item)?;
    }
    if !first {
        c.text(h.mcp_file, "@gen:delphi", "}}")?;
    }

    // settings: single file copied 1:1
    let item = recs.get("settings");
    if !item.is_empty() {
        c.copy(h.settings_file, &item)?;
    }

    // the layout manifest itself, editable in the workspace
    c.copy(".delphi/manifest.yml", &format!("{layout}/manifest.yml"))?;

    fs::write(out.join(".delphi/lock.tsv"), format!("# output\tstart\tend\tsource\tsha\n{}", c.lock))?;
    Ok(h)
}
