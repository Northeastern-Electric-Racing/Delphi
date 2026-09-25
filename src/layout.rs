//! `delphi layout new|list` (port of lib/layout.sh). `new` is a basic y/n picker; the
//! delphi-new-layout skill drafts richer manifests and passes them with --from.

use crate::check::check_tree;
use crate::core::{
    ask, delphi_commit, delphi_fetch, dgit, is_tty, make_tmp, name_ok, ok_q, out, out_raw, path_ok, Opts,
};
use crate::harness::HARNESSES;
use crate::parse::parse_yaml;
use crate::{die, provenance, warn};
use anyhow::Result;
use std::fs;
use std::path::Path;

pub fn main(args: &[String]) -> Result<()> {
    let verb = args.first().map(String::as_str).unwrap_or("");
    let flags = if verb == "new" { "--from --model --effort --yes" } else { "" };
    let (o, pos) = crate::core::parse_args(flags, args.get(1..).unwrap_or(&[]))?;
    match (verb, pos.len()) {
        ("new", 2) => new(pos[0].strip_suffix('/').unwrap_or(&pos[0]), &pos[1], &o),
        ("list", 0) => list(),
        _ => die!("usage: delphi layout new <scope> <layout> [--from <file>] | delphi layout list"),
    }
}

/// Layout manifests on a commit, as paths.
fn manifests(c: &str) -> Vec<String> {
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

fn list() -> Result<()> {
    delphi_fetch();
    let c = delphi_commit("main")?;
    let m = make_tmp()?.join("m");
    for f in manifests(&c) {
        let (ok, data) = out_raw(&mut dgit(["show", &format!("{c}:{f}")]));
        let recs = match fs::write(&m, data).ok().filter(|_| ok).map(|_| parse_yaml(&m)) {
            Some(Ok(r)) => r,
            Some(Err(e)) => {
                eprintln!("{}", e.downcast_ref::<crate::core::Raw>().map_or(format!("delphi: {e}"), |r| r.0.clone()));
                warn!("cannot parse {f}");
                continue;
            }
            None => {
                warn!("cannot parse {f}");
                continue;
            }
        };
        let scope = f.strip_prefix("context/").unwrap_or(&f);
        let scope = crate::core::scope_of_layout(scope);
        let scope = scope.strip_suffix('/').unwrap_or(scope);
        println!("{}\t{}\t{}", recs.get("name"), if scope.is_empty() { "." } else { scope }, recs.get("harness"));
    }
    Ok(())
}

/// Interactive manifest (prompts on stderr).
fn pick(c: &str, scope: &str, name: &str, tmp: &Path) -> Result<String> {
    if !is_tty() {
        die!("non-interactive session: pass a drafted manifest with --from <file>");
    }
    let mut items: Vec<String> = vec![];
    let mut s = scope.to_string();
    loop {
        // recommendations, closest scope first
        let spec = if s.is_empty() { format!("{c}:context/scope.yml") } else { format!("{c}:context/{s}/scope.yml") };
        let (ok, data) = out_raw(dgit(["show", &spec]).stderr(std::process::Stdio::null()));
        let f = tmp.join("scope.yml");
        if ok && fs::write(&f, data).is_ok() {
            if let Ok(r) = parse_yaml(&f) {
                items.extend(r.list("recommend"));
            }
        }
        if s.is_empty() {
            break;
        }
        s = s.rfind('/').map_or(String::new(), |i| s[..i].to_string());
    }
    let blocks = out(&mut dgit(["ls-tree", "-r", "--name-only", c, "--", &format!("context/{scope}/blocks")]))
        .unwrap_or_default();
    items.extend(blocks.lines().map(|l| l.strip_prefix("context/").unwrap_or(l).to_string()));
    let mut seen: Vec<String> = vec![];
    let mut sel: Vec<(&str, String)> = vec![];
    for it in items {
        if it.trim().is_empty() || seen.contains(&it) {
            continue;
        }
        seen.push(it.clone());
        let p = format!("/{it}");
        let g = |pat: &str| crate::core::glob(pat, &p);
        let key = if g("*/harness/instructions/*") {
            "instructions"
        } else if g("*/harness/skills/*") {
            "skills"
        } else if g("*/harness/mcp/*") {
            "mcp"
        } else if g("*/harness/settings/*") {
            "settings"
        } else if g("*/blocks/*") {
            "blocks"
        } else if g("*/docs/*") {
            "docs"
        } else {
            warn!("skipping '{it}': not a block or harness path");
            continue;
        };
        if !matches!(ask(&format!("Include {it}? [y/N]"), "")?.as_str(), "y" | "Y" | "yes") {
            continue;
        }
        if key == "settings" && sel.iter().any(|(k, _)| *k == "settings") {
            warn!("only one settings file; keeping the first");
            continue;
        }
        sel.push((key, it));
    }
    let hs: Vec<&str> = HARNESSES.iter().map(|h| h.name).collect();
    let h = if hs.len() > 1 { ask(&format!("Harness ({})?", hs.join(" ")), "claude-code")? } else { hs[0].to_string() };
    let mut m = format!("name: {name}\nharness: {h}\n");
    for k in ["instructions", "blocks", "docs", "skills", "mcp"] {
        let l: Vec<String> = sel.iter().filter(|(x, _)| *x == k).map(|(_, v)| format!("  - {v}")).collect();
        if !l.is_empty() {
            m.push_str(&format!("{k}:\n{}\n", l.join("\n")));
        }
    }
    if let Some((_, v)) = sel.iter().find(|(k, _)| *k == "settings") {
        m.push_str(&format!("settings: {v}\n"));
    }
    let mut repos = String::new();
    loop {
        let line = ask("Repo as 'name url' (blank to finish):", "")?;
        if line.is_empty() {
            break;
        }
        match line.split_once(' ') {
            Some((n, u)) if !u.is_empty() => repos.push_str(&format!("\n  {n}: {u}")),
            _ => warn!("expected 'name url'"),
        }
    }
    if !repos.is_empty() {
        m.push_str(&format!("repos:{repos}\n"));
    }
    Ok(m)
}

fn new(scope: &str, name: &str, o: &Opts) -> Result<()> {
    if !name_ok(name) {
        die!("invalid layout name: '{name}' (use a-z, 0-9, -)");
    }
    if !path_ok(scope) {
        die!("invalid scope: '{scope}'");
    }
    if !o.from.is_empty() && !Path::new(&o.from).is_file() {
        die!("no such file: {}", o.from);
    }
    delphi_fetch();
    let c = delphi_commit("main")?;
    if !ok_q(&mut dgit(["cat-file", "-e", &format!("{c}:context/{scope}/scope.yml")])) {
        die!("not a scope on origin/main: {scope}");
    }
    if manifests(&c).iter().any(|f| f.ends_with(&format!("/layouts/{name}/manifest.yml"))) {
        die!("layout name already used: {name}");
    }
    let tmp = make_tmp()?;
    let mf = tmp.join("manifest.yml");
    if !o.from.is_empty() {
        if fs::copy(&o.from, &mf).is_err() {
            die!("cannot read {}", o.from);
        }
    } else {
        let m = pick(&c, scope, name, &tmp)?;
        fs::write(&mf, m)?;
    }
    let recs = parse_yaml(&mf)?;
    if recs.get("name") != name {
        die!("manifest name must be '{name}'");
    }
    let h = recs.get("harness");
    if h.is_empty() {
        die!("manifest has no harness");
    }
    let prov = provenance::resolve(&o.model, &o.effort, &h)?;
    let mut pr = crate::pr::begin(&format!("delphi/layout/{name}"), &c, prov)?;
    let dir = pr.wt.join("context").join(scope).join("layouts").join(name);
    if fs::create_dir_all(&dir).is_err() || fs::copy(&mf, dir.join("manifest.yml")).is_err() {
        die!("cannot write manifest");
    }
    if !check_tree(&pr.wt)? {
        die!("layout fails check; nothing pushed");
    }
    if !pr.commit(&format!("delphi: add layout {name}"), "")? {
        die!("nothing to commit");
    }
    let yaml = fs::read_to_string(&mf).unwrap_or_default();
    let body = format!("Adds layout `{name}` in scope `{scope}`:\n\n```yaml\n{}\n```", yaml.trim_end_matches('\n'));
    pr.finish(&format!("delphi: add layout {name}"), &body, None)?;
    println!("{}", pr.branch);
    Ok(())
}
