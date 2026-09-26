//! `delphi create | list | mv`: workspace folders on origin/main. `create` and `mv` edit a temp
//! worktree of Delphi, run sync and check there, and open a PR.

use crate::check::check_tree;
use crate::core::{
    basename, fetch_main, find, git, join, ok, ok_q, parse_args, path_ok, root, safe_path, under, write_replace, Opts,
};
use crate::parse::parse_yaml;
use crate::pr::{self, Pr};
use crate::sync::sync;
use crate::workspace::{self, default_dest, split_link, LINK_KEYS, SKILL_YML, YML};
use crate::{die, harness, info, provenance};
use anyhow::Result;
use std::fs;
use std::path::Path;

pub fn main(cmd: &str, args: &[String]) -> Result<()> {
    let flags = if cmd == "list" { "" } else { "--from --model --effort --yes" };
    let (o, pos) = parse_args(flags, args)?;
    let t = |s: &String| s.strip_suffix('/').unwrap_or(s).to_string();
    match (cmd, pos.len()) {
        ("list", 0) => list(),
        ("create", 2) => create(&t(&pos[0]), &pos[1], &o),
        ("mv", 2) => mv(&t(&pos[0]), &t(&pos[1]), &o),
        ("list", _) => die!("usage: delphi list"),
        ("create", _) => die!("usage: delphi create <scope> <name> --from <workspace.yml>"),
        _ => die!("usage: delphi mv <old> <new>"),
    }
}

/// `<name>\t<scope>\t<harness>` per workspace on origin/main.
fn list() -> Result<()> {
    for w in workspace::all_at(root(), &fetch_main()?, true) {
        println!("{}\t{}\t{}", w.name(), w.scope(), w.h.name);
    }
    Ok(())
}

/// Sync (against origin/main), check, commit and open the PR.
fn finish(pr: &Pr, base: &str, title: &str, body: &str) -> Result<()> {
    let r = sync(&pr.wt, &[base.to_string()], false)?;
    r.print(false);
    if !r.conflicts.is_empty() {
        die!("sync found conflicts; nothing pushed");
    }
    if !check_tree(&pr.wt)? {
        die!("check failed; nothing pushed");
    }
    if !pr.commit(title)? {
        die!("nothing to commit");
    }
    pr.finish(title, body, None)?;
    println!("{}", pr.branch);
    Ok(())
}

fn create(scope: &str, name: &str, o: &Opts) -> Result<()> {
    if name.is_empty() || !name.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-') {
        die!("invalid workspace name: '{name}' (use a-z, 0-9, -)");
    }
    if !path_ok(scope) && scope != "." {
        die!("invalid scope: '{scope}'");
    }
    if o.from.is_empty() {
        die!("usage: delphi create <scope> <name> --from <workspace.yml> (draft one with the delphi-new-workspace skill)");
    }
    let from = Path::new(&o.from);
    let y = parse_yaml(from)?;
    if y.get("name") != name {
        die!("{}: name must be '{name}'", o.from);
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
    let pr = pr::begin(&format!("delphi/create/{name}"), &c, prov)?;
    let dir = safe_path(&pr.wt.join("context"), &folder)?;
    if fs::create_dir_all(&dir).is_err() || fs::copy(from, dir.join(YML)).is_err() {
        die!("cannot write {folder}/{YML}");
    }
    let yaml = fs::read_to_string(from).unwrap_or_default();
    let body = format!("Adds workspace `{name}` in `{scope}`:\n\n```yaml\n{}\n```", yaml.trim_end_matches('\n'));
    finish(&pr, &c, &format!("delphi: create workspace {name}"), &body)
}

/// Rewrite `old` -> `new` in path entries (and keep default link dests stable).
fn rewrite(file: &Path, old: &str, new: &str) -> Result<()> {
    let text = fs::read_to_string(file)?;
    let h = harness::load(&parse_yaml(file).map(|y| y.get("harness")).unwrap_or_default()).ok();
    let (mut key, mut res) = (String::new(), String::new());
    for l in text.lines() {
        let bare = l.split(" #").next().unwrap_or("").trim_end();
        if !l.starts_with(' ') {
            key = bare.split_once(':').map_or("", |x| x.0).to_string();
        }
        let link = LINK_KEYS.contains(&key.as_str());
        let item = match bare.strip_prefix("  - ") {
            Some(v) if link || ["instructions", "mcp", "recommend", "body"].contains(&key.as_str()) => {
                Some(("  - ", v))
            }
            _ => bare.strip_prefix("settings: ").map(|v| ("settings: ", v)),
        };
        let Some((pre, (src, dest))) =
            item.map(|(p, v)| (p, split_link(v))).filter(|(_, (s, _))| under(s, old).is_some())
        else {
            res += &format!("{l}\n");
            continue;
        };
        let moved = join(new, under(&src, old).unwrap_or(""));
        let dest = match (dest, &h) {
            (None, Some(h)) if link && default_dest(&key, &src, h) != default_dest(&key, &moved, h) => {
                Some(default_dest(&key, &src, h))
            }
            (d, _) => d,
        };
        res += &dest.map_or_else(|| format!("{pre}{moved}\n"), |d| format!("{pre}{moved} -> {d}\n"));
    }
    if res != text {
        write_replace(file, res.as_bytes())?;
    }
    Ok(())
}

fn mv(old: &str, new: &str, o: &Opts) -> Result<()> {
    for p in [old, new] {
        if !path_ok(p) {
            die!("unsafe path: '{p}'");
        }
        if basename(p) == "scope.yml" || basename(p) == YML {
            die!("'{p}' is a scope or workspace file; move its directory instead");
        }
    }
    let c = fetch_main()?;
    let prov = provenance::resolve(&o.model, &o.effort, "claude-code")?;
    let time = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs());
    let pr = pr::begin(&format!("delphi/mv/{}-{time}", basename(old)), &c, prov)?;
    let ctx = pr.wt.join("context");
    let (src, dst) = (safe_path(&ctx, old)?, safe_path(&ctx, new)?);
    if !src.exists() {
        die!("no such path on origin/main: context/{old}");
    }
    if dst.exists() {
        die!("already exists on origin/main: context/{new}");
    }
    let moved = dst.parent().is_some_and(|d| fs::create_dir_all(d).is_ok())
        && ok(git(&pr.wt).args(["mv", &format!("context/{old}"), &format!("context/{new}")]));
    if !moved {
        die!("git mv failed");
    }
    for (f, ft) in find(&ctx, &|_| false) {
        if ft.is_file() && f.file_name().is_some_and(|n| n == YML || n == "scope.yml" || n == SKILL_YML) {
            rewrite(&f, old, new)?;
        }
    }
    let wy = dst.join(YML);
    if wy.is_file() {
        let text = fs::read_to_string(&wy)?;
        let named: String = text
            .lines()
            .map(|l| if l.starts_with("name:") { format!("name: {}\n", basename(new)) } else { format!("{l}\n") })
            .collect();
        write_replace(&wy, named.as_bytes())?;
    }
    info!("moved context/{old} -> context/{new}");
    let body =
        format!("Moves `context/{old}` to `context/{new}` and rewrites the `workspace.yml`, `scope.yml` and `skill.yml` entries that use it.");
    finish(&pr, &c, &format!("delphi: move {old} -> {new}"), &body)
}
