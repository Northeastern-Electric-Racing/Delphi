//! `delphi split [--check] [--push]` (spec §3): `ws/<name>` = `git subtree split --prefix=<folder>`
//! of HEAD for every workspace, done with plumbing so git-subtree is not needed. Same commits as
//! git subtree: each commit becomes its folder tree with mapped parents (author, committer and
//! message kept; signatures dropped), and a commit whose tree equals a mapped parent's is skipped.
//! Deterministic, so re-running only adds new commits. `--check` compares with the local `ws/*`
//! refs; otherwise they are updated, and `--push` force-updates origin's (deleting removed ones).

use crate::core::{commit, exit, git, ok, out, out_q, out_stdin, parse_args, root, run};
use crate::{die, info, workspace};
use anyhow::Result;
use std::collections::{BTreeMap, HashMap};
use std::path::Path;

pub fn main(args: &[String]) -> Result<()> {
    let (o, pos) = parse_args("--check --push", args)?;
    if !pos.is_empty() {
        die!("usage: delphi split [--check] [--push]");
    }
    let dir = root();
    let Some(head) = commit(dir, "HEAD") else { die!("no commits in {}", dir.display()) };
    let ws = workspace::all_at(dir, &head, true);
    let folders: Vec<&str> = ws.iter().map(|w| w.folder.as_str()).collect();
    let want: BTreeMap<String, String> =
        ws.iter().map(|w| format!("ws/{}", w.name())).zip(split(dir, &folders)?).collect();
    let refs = out(git(dir).args(["for-each-ref", "--format=%(refname:strip=2) %(objectname)", "refs/heads/ws/"]));
    let have: BTreeMap<String, String> =
        refs.unwrap_or_default().lines().filter_map(|l| l.split_once(' ')).map(|(b, s)| (b.into(), s.into())).collect();
    let gone: Vec<&String> = have.keys().filter(|b| !want.contains_key(*b)).collect();
    if o.check {
        let stale: Vec<&String> = want.iter().filter(|(b, s)| have.get(*b) != Some(s)).map(|x| x.0).collect();
        for b in stale.iter().chain(&gone) {
            info!("split: {b} is out of date (run: delphi split)");
        }
        if stale.is_empty() && gone.is_empty() {
            info!("split: ok");
            return Ok(());
        }
        return Err(exit(1));
    }
    for (b, s) in &want {
        ok(git(dir).args(["update-ref", &format!("refs/heads/{b}"), s]));
        println!("{s} {b}");
    }
    for b in &gone {
        ok(git(dir).args(["update-ref", "-d", &format!("refs/heads/{b}")]));
        println!("deleted {b}");
    }
    if o.push {
        let Some(ls) = out(git(dir).args(["ls-remote", "--heads", "origin"])) else { die!("cannot reach origin") };
        let mut specs: Vec<String> = want.iter().map(|(b, s)| format!("+{s}:refs/heads/{b}")).collect();
        let remote = ls.lines().filter_map(|l| l.split_once("\trefs/heads/")).map(|x| x.1.to_string());
        specs.extend(
            remote.filter(|b| b.starts_with("ws/") && !want.contains_key(b)).map(|b| format!(":refs/heads/{b}")),
        );
        if !ok(git(dir).args(["push", "--quiet", "--atomic", "origin"]).args(&specs)) {
            die!("push of ws/* branches failed");
        }
    }
    Ok(())
}

/// The split head of each folder (repo-relative) from HEAD's history.
pub fn split(dir: &Path, folders: &[&str]) -> Result<Vec<String>> {
    let list = out(git(dir).args(["rev-list", "--topo-order", "--reverse", "--parents", "HEAD"])).unwrap_or_default();
    let revs: Vec<Vec<&str>> = list.lines().map(|l| l.split(' ').collect()).collect();
    // every commit's folder tree, in one batch
    let q: String = folders.iter().flat_map(|f| revs.iter().map(move |r| format!("{}:{f}\n", r[0]))).collect();
    let Some(a) = out_stdin(git(dir).args(["cat-file", "--batch-check=%(objecttype) %(objectname)"]), q.as_bytes())
    else {
        die!("git cat-file failed")
    };
    let mut trees = a.lines().map(|l| l.strip_prefix("tree "));
    let mut tops = HashMap::new();
    let mut heads = vec![];
    for f in folders {
        let (mut map, mut last) = (HashMap::new(), None);
        for (r, t) in revs.iter().zip(trees.by_ref().take(revs.len())) {
            let parents: Vec<String> = r[1..].iter().filter_map(|p| map.get(p).cloned()).collect();
            let Some(t) = t else {
                if !parents.is_empty() {
                    map.insert(r[0], r[0].to_string()); // as git subtree does
                }
                continue;
            };
            let new = copy_or_skip(dir, r[0], t, &parents, &mut tops)?;
            map.insert(r[0], new.clone());
            last = Some(new);
        }
        heads.push(last.ok_or_else(|| anyhow::anyhow!("no history for {f}"))?);
    }
    Ok(heads)
}

/// A commit's root tree (`tops` caches them).
fn top(dir: &Path, c: &str, tops: &mut HashMap<String, String>) -> String {
    let t = tops.get(c).cloned().or_else(|| out_q(git(dir).args(["rev-parse", &format!("{c}^{{tree}}")])));
    tops.entry(c.into()).or_insert(t.unwrap_or_default()).clone()
}

/// git subtree's copy_or_skip: reuse a mapped parent with the same tree unless that would lose
/// history, else write `rev` with `tree` and the mapped parents.
fn copy_or_skip(
    dir: &Path,
    rev: &str,
    tree: &str,
    parents: &[String],
    tops: &mut HashMap<String, String>,
) -> Result<String> {
    let (mut same, mut other, mut ps, mut copy): (Option<&str>, Option<&str>, Vec<&str>, bool) =
        (None, None, vec![], false);
    let q = |args: &[&str]| out_q(git(dir).args(args)).unwrap_or_default();
    for p in parents {
        if top(dir, p, tops) == tree {
            match same {
                None => same = Some(p),
                Some(s) => match q(&["merge-base", s, p]) {
                    mb if mb == s => same = Some(p),
                    mb => copy |= mb != *p,
                },
            }
        } else {
            other = Some(p);
        }
        if !ps.contains(&p.as_str()) {
            ps.push(p);
        }
    }
    if let (Some(s), Some(o)) = (same, other) {
        copy |= q(&["rev-list", "--count", &format!("{s}..{o}")]) != "0";
    }
    if let Some(s) = same.filter(|_| !copy) {
        return Ok(s.to_string());
    }
    let Some(raw) = run(git(dir).args(["cat-file", "commit", rev]), true) else { die!("cannot read commit {rev}") };
    let end = raw.windows(2).position(|w| w == b"\n\n").map_or(raw.len(), |i| i + 1);
    let mut obj = format!("tree {tree}\n").into_bytes();
    for p in &ps {
        obj.extend(format!("parent {p}\n").bytes());
    }
    for l in raw[..end].split_inclusive(|b| *b == b'\n') {
        if l.starts_with(b"author ") || l.starts_with(b"committer ") {
            obj.extend(l);
        }
    }
    obj.extend(&raw[end..]);
    let Some(new) = out_stdin(git(dir).args(["hash-object", "-t", "commit", "-w", "--stdin"]), &obj) else {
        die!("cannot write the split of commit {rev}")
    };
    tops.insert(new.clone(), tree.into());
    Ok(new)
}
