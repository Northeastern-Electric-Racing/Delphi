//! `delphi layout new|list`. `new` takes a drafted manifest (`--from`, e.g. from the
//! delphi-new-layout skill) and opens the layout PR.

use crate::check::check_tree;
use crate::core::{
    delphi_commit, delphi_fetch, dgit, layout_manifests, name_ok, ok_q, parse_args, path_ok, safe_path, show, Opts,
};
use crate::parse::{parse_text, parse_yaml};
use crate::{die, provenance, warn};
use anyhow::Result;
use std::fs;
use std::path::Path;

pub fn main(args: &[String]) -> Result<()> {
    let verb = args.first().map(String::as_str).unwrap_or("");
    let flags = if verb == "new" { "--from --model --effort --yes" } else { "" };
    let (o, pos) = parse_args(flags, args.get(1..).unwrap_or(&[]))?;
    match (verb, pos.len()) {
        ("new", 2) => new(pos[0].strip_suffix('/').unwrap_or(&pos[0]), &pos[1], &o),
        ("list", 0) => list(),
        _ => die!("usage: delphi layout new <scope> <layout> --from <manifest> | delphi layout list"),
    }
}

/// `<name>\t<scope>\t<harness>` per layout on origin/main.
fn list() -> Result<()> {
    delphi_fetch();
    let c = delphi_commit("main")?;
    for f in layout_manifests(&c) {
        let y = match show(&c, &f).map(|t| parse_text(&String::from_utf8_lossy(&t), &f)) {
            Some(Ok(y)) => y,
            other => {
                if let Some(Err(e)) = other {
                    eprintln!("{e:#}");
                }
                warn!("cannot parse {f}");
                continue;
            }
        };
        let rel = &f["context/".len()..];
        let scope = rel.rfind("layouts/").map_or("", |i| rel[..i].trim_end_matches('/'));
        println!("{}\t{}\t{}", y.get("name"), if scope.is_empty() { "." } else { scope }, y.get("harness"));
    }
    Ok(())
}

fn new(scope: &str, name: &str, o: &Opts) -> Result<()> {
    if !name_ok(name) {
        die!("invalid layout name: '{name}' (use a-z, 0-9, -)");
    }
    if !path_ok(scope) {
        die!("invalid scope: '{scope}'");
    }
    if o.from.is_empty() {
        die!(
            "usage: delphi layout new <scope> <layout> --from <manifest> (draft one with the delphi-new-layout skill)"
        );
    }
    let mf = Path::new(&o.from);
    if !mf.is_file() {
        die!("no such file: {}", o.from);
    }
    delphi_fetch();
    let c = delphi_commit("main")?;
    if !ok_q(&mut dgit(["cat-file", "-e", &format!("{c}:context/{scope}/scope.yml")])) {
        die!("not a scope on origin/main: {scope}");
    }
    if layout_manifests(&c).iter().any(|f| f.ends_with(&format!("/layouts/{name}/manifest.yml"))) {
        die!("layout name already used: {name}");
    }
    let y = parse_yaml(mf)?;
    if y.get("name") != name {
        die!("manifest name must be '{name}'");
    }
    let h = y.get("harness");
    if h.is_empty() {
        die!("manifest has no harness");
    }
    let prov = provenance::resolve(&o.model, &o.effort, &h)?;
    let pr = crate::pr::begin(&format!("delphi/layout/{name}"), &c, prov)?;
    let dir = safe_path(&pr.wt.join("context"), &format!("{scope}/layouts/{name}"))?;
    if fs::create_dir_all(&dir).is_err() || fs::copy(mf, dir.join("manifest.yml")).is_err() {
        die!("cannot write manifest");
    }
    if !check_tree(&pr.wt)? {
        die!("layout fails check; nothing pushed");
    }
    let title = format!("delphi: add layout {name}");
    if !pr.commit(&title, "")? {
        die!("nothing to commit");
    }
    let yaml = fs::read_to_string(mf).unwrap_or_default();
    let body = format!("Adds layout `{name}` in scope `{scope}`:\n\n```yaml\n{}\n```", yaml.trim_end_matches('\n'));
    pr.finish(&title, &body, None)?;
    println!("{}", pr.branch);
    Ok(())
}
