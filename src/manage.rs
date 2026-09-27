//! `delphi create | list`: workspace folders on origin/main. `create` writes the new folder in a
//! temp worktree of Delphi, runs check there, and opens a PR.

use crate::check::check_tree;
use crate::core::{fetch_main, find, git, ok_q, parse_args, path_ok, rel_to, root, safe_path, write_file, Opts};
use crate::parse::parse_text;
use crate::workspace::{self, YML};
use crate::{die, harness, provenance};
use anyhow::Result;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

pub fn main(cmd: &str, args: &[String]) -> Result<()> {
    let flags = if cmd == "list" { "--offline" } else { "--from --model --effort --yes" };
    let (o, pos) = parse_args(flags, args)?;
    match (cmd, pos.len()) {
        ("list", 0) => list(),
        ("create", 2) => create(pos[0].strip_suffix('/').unwrap_or(&pos[0]), &pos[1], &o),
        ("list", _) => die!("usage: delphi list"),
        _ => die!("usage: delphi create <scope> <name> [--from <dir>]"),
    }
}

/// `<name>\t<scope>\t<harness>\tws/<name>` per workspace on origin/main.
fn list() -> Result<()> {
    for w in workspace::all_at(root(), &fetch_main()?, true) {
        println!("{}\t{}\t{}\tws/{}", w.name(), w.scope(), w.h.name, w.name());
    }
    Ok(())
}

fn create(scope: &str, name: &str, o: &Opts) -> Result<()> {
    if name.is_empty() || !name.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-') {
        die!("invalid workspace name: '{name}' (use a-z, 0-9, -)");
    }
    if !path_ok(scope) && scope != "." {
        die!("invalid scope: '{scope}'");
    }
    // the files: everything in --from (but .git and repos/), else just a workspace.yml
    let mut files: Vec<(String, Vec<u8>, bool)> = vec![];
    if !o.from.is_empty() {
        let from = Path::new(&o.from);
        if !from.is_dir() {
            die!("--from must be a directory: {}", o.from);
        }
        let skip = |p: &Path| p.parent() == Some(from) && p.file_name().is_some_and(|n| n == ".git" || n == "repos");
        for (p, ft) in find(from, &skip) {
            if ft.is_symlink() {
                die!("symlinks are not allowed: {}", p.display());
            }
            if ft.is_file() {
                let exec = fs::metadata(&p)?.permissions().mode() & 0o100 != 0;
                files.push((rel_to(&p, from), fs::read(&p)?, exec));
            }
        }
    }
    files.sort();
    if !files.iter().any(|f| f.0 == YML) {
        files.push((YML.into(), format!("name: {name}\nharness: claude-code\n").into_bytes(), false));
    }
    let yml = files.iter().find(|f| f.0 == YML).map(|f| String::from_utf8_lossy(&f.1).into_owned()).unwrap_or_default();
    let y = parse_text(&yml, YML)?;
    if y.get("name") != name {
        die!("{YML}: name must be '{name}'");
    }
    let h = harness::load(&y.get("harness"))?;
    let c = fetch_main()?;
    let folder = if scope == "." { format!("workspaces/{name}") } else { format!("{scope}/workspaces/{name}") };
    let scope_yml = if scope == "." { "context/scope.yml".into() } else { format!("context/{scope}/scope.yml") };
    if !ok_q(git(root()).args(["cat-file", "-e", &format!("{c}:{scope_yml}")])) {
        die!("not a scope on origin/main: {scope}");
    }
    if workspace::all_at(root(), &c, true).iter().any(|w| w.name() == name) {
        die!("workspace name already used: {name}");
    }
    let prov = provenance::resolve(&o.model, &o.effort, h.name)?;
    let pr = crate::pr::begin(&format!("delphi/create/{name}"), &c, prov)?;
    let dir = safe_path(&pr.wt.join("context"), &folder)?;
    fs::create_dir_all(&dir)?;
    for (rel, data, exec) in &files {
        write_file(&safe_path(&dir, rel)?, data, *exec, rel)?;
    }
    if !check_tree(&pr.wt)? {
        die!("check failed; nothing pushed");
    }
    let title = format!("delphi: create workspace {name}");
    if !pr.commit(&title)? {
        die!("nothing to commit");
    }
    let list: String = files.iter().map(|f| format!("- `{}`\n", f.0)).collect();
    let body = format!(
        "Adds workspace `{name}` in `{scope}` (`context/{folder}`):\n\n{list}\n```yaml\n{}\n```",
        yml.trim_end()
    );
    pr.finish(&title, &body, None)?;
    println!("{}", pr.branch);
    Ok(())
}
