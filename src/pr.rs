//! The single path for writing to the Delphi monorepo.
//!
//! `begin` makes a temp worktree on a branch (reset to a start commit); the caller edits files
//! under `wt`; `commit` stages everything and commits with provenance trailers; `finish` shows,
//! confirms, pushes, and opens or updates the PR. With a lease (a sha, or empty = the branch must
//! be absent) it force-pushes. The user's own Delphi checkout is never touched.

use crate::core::{confirm, defer, dgit, git_c, is_tty, make_tmp, ok, ok_q, out, out_q, out_stdin, root, yes};
use crate::provenance::Prov;
use crate::{die, info};
use anyhow::Result;
use std::path::PathBuf;
use std::process::{Command, Stdio};

pub struct Pr {
    pub branch: String,
    pub wt: PathBuf,
    start: String,
    pub pushed: bool,
    pub prov: Prov,
}

pub fn begin(branch: &str, start: &str, prov: Prov) -> Result<Pr> {
    if !yes() && !is_tty() {
        die!("non-interactive session: re-run with --yes (or DELPHI_YES=1)");
    }
    let wt = make_tmp()?.join("wt");
    ok(&mut dgit(["worktree", "prune"]));
    if !ok_q(dgit(["worktree", "add", "--quiet", "-B", branch]).arg(&wt).arg(start)) {
        die!("cannot create branch {branch} (is it checked out elsewhere?)");
    }
    let w = wt.clone();
    defer(move || {
        ok_q(git_c(root()).args(["worktree", "remove", "--force"]).arg(&w));
    });
    let start = out(git_c(&wt).args(["rev-parse", "HEAD"])).unwrap_or_default();
    Ok(Pr { branch: branch.into(), wt, start, pushed: false, prov })
}

fn gh(wt: &PathBuf) -> Command {
    let mut c = Command::new("gh");
    c.current_dir(wt);
    c
}

impl Pr {
    /// Stage everything and commit. False (nothing committed) when nothing is staged.
    pub fn commit(&self, subject: &str, body: &str) -> Result<bool> {
        if !ok(git_c(&self.wt).args(["add", "-A"])) {
            die!("git add failed");
        }
        if ok(git_c(&self.wt).args(["diff", "--cached", "--quiet"])) {
            return Ok(false);
        }
        let body = if body.is_empty() { String::new() } else { format!("\n{body}\n") };
        let msg = format!("{subject}\n{body}\n{}\n", self.prov.trailers());
        if out_stdin(git_c(&self.wt).args(["commit", "--quiet", "-F", "-"]), msg.as_bytes()).is_none() {
            die!("git commit failed");
        }
        Ok(true)
    }

    pub fn has_commits(&self) -> bool {
        out(git_c(&self.wt).args(["rev-parse", "HEAD"])).unwrap_or_default() != self.start
    }

    pub fn finish(&mut self, title: &str, body: &str, lease: Option<&str>) -> Result<()> {
        let b = &self.branch;
        let body = format!("{body}\n\n{}", self.prov.table());
        info!("---- {title}");
        info!("{body}");
        info!("----");
        if !confirm(&format!("Push {b} and open/update its PR?"))? {
            info!("Not pushed. Branch {b} is committed locally in {}.", root().display());
            return Ok(());
        }
        let dst = format!("HEAD:refs/heads/{b}");
        if let Some(lease) = lease {
            let Some(me) = out_q(Command::new("gh").args(["api", "user", "--jq", ".login"])) else {
                die!("gh is not authenticated (run: gh auth login)")
            };
            let q = ".[0].author.login // empty";
            let author =
                out_q(gh(&self.wt).args(["pr", "list", "--head", b, "--state", "open", "--json", "author", "--jq", q]))
                    .unwrap_or_default();
            if !author.is_empty() && author != me {
                die!("open PR on {b} belongs to {author}; refusing to overwrite");
            }
            let l = format!("--force-with-lease=refs/heads/{b}:{lease}");
            if !ok(git_c(&self.wt).args(["push", "--quiet", &l, "origin", &dst])) {
                die!("the propose branch changed on GitHub (someone pushed to it); review the PR, then re-run");
            }
        } else if !ok(git_c(&self.wt).args(["push", "--quiet", "origin", &dst])) {
            die!("push failed");
        }
        self.pushed = true;
        let q = ".[0].number // empty";
        let num =
            out_q(gh(&self.wt).args(["pr", "list", "--head", b, "--state", "open", "--json", "number", "--jq", q]))
                .unwrap_or_default();
        if !num.is_empty() {
            if !ok(gh(&self.wt).args(["pr", "edit", &num, "--title", title, "--body", &body]).stdout(Stdio::null())) {
                die!("gh pr edit failed");
            }
            info!("Updated PR #{num}");
        } else if !ok(
            gh(&self.wt).args(["pr", "create", "--head", b, "--base", "main", "--title", title, "--body", &body])
        ) {
            die!("gh pr create failed");
        }
        Ok(())
    }
}
