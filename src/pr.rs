//! The single write path to Delphi. A `Pr` is a temp worktree (`begin`: of Delphi on a new branch;
//! or propose's worktree of a checkout), a branch and provenance. `commit` adds trailers; `finish`
//! confirms, pushes (with a lease: sha, or "" = branch must be absent), and opens or updates the
//! PR. The user's own Delphi checkout is never touched.

use crate::core::{confirm, env_nonempty, git, need_yes_or_tty, ok, out_q, out_stdin, root, worktree};
use crate::provenance::Prov;
use crate::{die, info};
use anyhow::Result;
use std::path::PathBuf;
use std::process::{Command, Stdio};

pub struct Pr {
    pub branch: String,
    pub wt: PathBuf,
    pub prov: Prov,
}

pub fn begin(branch: &str, start: &str, prov: Prov) -> Result<Pr> {
    need_yes_or_tty()?;
    ok(git(root()).args(["worktree", "prune"]));
    let err = format!("cannot create branch {branch} (is it checked out elsewhere?)");
    let wt = worktree(root(), &["-B", branch], start, &err)?;
    Ok(Pr { branch: branch.into(), wt, prov })
}

fn gh() -> Command {
    let mut c = Command::new("gh");
    c.current_dir(root());
    c
}

/// The GitHub login `gh` is authenticated as.
fn gh_user() -> Option<String> {
    out_q(gh().args(["api", "user", "--jq", ".login"])).filter(|u| !u.is_empty())
}

/// The user name in checkout branches: the GitHub login when origin is on GitHub, else $USER.
pub fn user() -> String {
    let on_github = out_q(git(root()).args(["remote", "get-url", "origin"])).unwrap_or_default().contains("github.com");
    let u = on_github.then(gh_user).flatten().or_else(|| env_nonempty("USER")).unwrap_or_default();
    let u: String = u.chars().filter(|c| c.is_ascii_alphanumeric() || "._-".contains(*c)).collect();
    if u.is_empty() || u.starts_with('.') {
        "me".into()
    } else {
        u
    }
}

/// A field (`number`, `author`) of the open PR from `branch`, or "".
pub fn open_pr(branch: &str, field: &str) -> String {
    let q = if field == "author" { ".[0].author.login // empty" } else { ".[0].number // empty" };
    out_q(gh().args(["pr", "list", "--head", branch, "--state", "open", "--json", field, "--jq", q]))
        .unwrap_or_default()
}

impl Pr {
    /// Stage everything and commit. False (nothing committed) when nothing is staged.
    pub fn commit(&self, subject: &str) -> Result<bool> {
        if !ok(git(&self.wt).args(["add", "-A"])) {
            die!("git add failed");
        }
        if ok(git(&self.wt).args(["diff", "--cached", "--quiet"])) {
            return Ok(false);
        }
        let msg = format!("{subject}\n\n{}\n", self.prov.trailers());
        if out_stdin(git(&self.wt).args(["commit", "--quiet", "-F", "-"]), msg.as_bytes()).is_none() {
            die!("git commit failed");
        }
        Ok(true)
    }

    /// Show, confirm, push, and open or update the PR. True if pushed.
    pub fn finish(&self, title: &str, body: &str, lease: Option<&str>) -> Result<bool> {
        let b = &self.branch;
        let body = format!("{body}\n\n{}", self.prov.table());
        info!("---- {title}\n{body}\n----");
        if !confirm(&format!("Push {b} and open/update its PR?"))? {
            info!("Not pushed.");
            return Ok(false);
        }
        let dst = format!("HEAD:refs/heads/{b}");
        if let Some(lease) = lease {
            let Some(me) = gh_user() else { die!("gh is not authenticated (run: gh auth login)") };
            let author = open_pr(b, "author");
            if !author.is_empty() && author != me {
                die!("open PR on {b} belongs to {author}; refusing to overwrite");
            }
            let l = format!("--force-with-lease=refs/heads/{b}:{lease}");
            if !ok(git(&self.wt).args(["push", "--quiet", &l, "origin", &dst])) {
                die!("the propose branch changed on GitHub (someone pushed to it); review the PR, then re-run");
            }
        } else if !ok(git(&self.wt).args(["push", "--quiet", "origin", &dst])) {
            die!("push failed");
        }
        let num = open_pr(b, "number");
        if num.is_empty() {
            if !ok(gh().args(["pr", "create", "--head", b, "--base", "main", "--title", title, "--body", &body])) {
                die!("gh pr create failed");
            }
        } else {
            if !ok(gh().args(["pr", "edit", &num, "--title", title, "--body", &body]).stdout(Stdio::null())) {
                die!("gh pr edit failed");
            }
            info!("Updated PR #{num}");
        }
        Ok(true)
    }
}
