//! Test sandbox: a temp dir with a bare Delphi origin, a Delphi clone with sample content (two
//! self-contained workspaces, argos-dev and nero-dev, split into `ws/*` on origin), a bare code
//! repo, a stub `gh` on PATH (logs to gh.log, remembers PRs in gh.prs), and a checkout root.
//! Nothing touches GitHub.
#![allow(dead_code)]

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

const BUILD: &str = r#"
set -euo pipefail
SB=$1 here=$2 delphi=$3
git init -q --bare -b main "$SB/origin.git"
git clone -q "$SB/origin.git" "$SB/Delphi" 2>/dev/null
cp "$here/delphi.conf" "$SB/Delphi/"
printf '# Delphi development\n' > "$SB/Delphi/CLAUDE.md"

C="$SB/Delphi/context" S=software/application-software
AD="$C/$S/argos/workspaces/argos-dev" ND="$C/$S/nero/workspaces/nero-dev"
mkdir -p "$AD/.claude/skills/open-pr" "$AD/.claude/skills/run-tests/scripts" "$AD/docs" "$ND/.claude/skills/run-tests"
printf 'name: NER\n' > "$C/scope.yml"
printf 'name: Software\n' > "$C/software/scope.yml"
printf 'name: Application Software\n' > "$C/$S/scope.yml"
printf 'name: Argos\n' > "$C/$S/argos/scope.yml"
printf 'name: NERO\n' > "$C/$S/nero/scope.yml"
printf '# Argos\n\nArgos is the telemetry stack.\n' > "$AD/CLAUDE.md"
printf -- '---\nname: open-pr\ndescription: Open a PR.\n---\n\nOpen a draft PR.\n' > "$AD/.claude/skills/open-pr/SKILL.md"
printf '#!/bin/sh\necho running tests\n' > "$AD/.claude/skills/run-tests/scripts/run.sh"
chmod +x "$AD/.claude/skills/run-tests/scripts/run.sh"
printf '# Guide\n\nLine one.\nLine two.\n' > "$AD/docs/guide.md"
printf '# NERO\n\nNERO is the dashboard firmware.\n' > "$ND/CLAUDE.md"
printf -- '---\nname: run-tests\ndescription: Run the test suites.\n---\n\nRun both suites.\n' > "$ND/.claude/skills/run-tests/SKILL.md"
printf 'name: argos-dev\nharness: claude-code\nrepos:\n  argos: file://%s/argos.git\n' "$SB" > "$AD/workspace.yml"
printf 'name: nero-dev\nharness: claude-code\n' > "$ND/workspace.yml"

git init -q -b main "$SB/argos-src"
printf '# Argos code\n' > "$SB/argos-src/README.md"
git -C "$SB/argos-src" add -A && git -C "$SB/argos-src" commit -qm init
git clone -q --bare "$SB/argos-src" "$SB/argos.git"

cd "$SB/Delphi"
git add -A && git commit -qm "sandbox: workspaces"
printf 'More.\n' >> CLAUDE.md && git commit -qam "sandbox: outside the workspaces"
git push -q origin HEAD:main 2>/dev/null
git branch -q -u origin/main 2>/dev/null || true
DELPHI_ROOT="$SB/Delphi" "$delphi" split --push > /dev/null

mkdir -p "$SB/bin"; : > "$SB/gh.prs"
{ printf '#!/bin/sh\nSB=%q\n' "$SB"; cat <<'EOF'; } > "$SB/bin/gh"
# stub gh for the Delphi sandbox: never contacts GitHub
echo "gh $*" >> "$SB/gh.log"
n=$(awk -v b="$4" '$1 == b { print $2 }' "$SB/gh.prs")   # args: pr list|create --head <branch> …
case "$1 $2" in
  "api user") echo sandbox-user ;;
  "pr list") echo "$n" ;;
  "pr view") awk -v b="$3" '$1 == b { print "https://github.invalid/pr/" $2 }' "$SB/gh.prs" ;;
  "pr create") n=$(($(wc -l < "$SB/gh.prs") + 1)); echo "$4 $n" >> "$SB/gh.prs"; echo "https://github.invalid/pr/$n" ;;
esac
exit 0
EOF
chmod +x "$SB/bin/gh"
"#;

pub const AD: &str = "context/software/application-software/argos/workspaces/argos-dev";
pub const ND: &str = "context/software/application-software/nero/workspaces/nero-dev";

#[derive(Debug, Clone)]
pub struct Out {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

pub struct Sb {
    pub dir: PathBuf,
}

static N: AtomicUsize = AtomicUsize::new(0);

impl Sb {
    pub fn new(tag: &str) -> Sb {
        // outside this repo, so walking up from a checkout never finds the real one
        let dir =
            std::env::temp_dir().join(format!("sb-{tag}-{}-{}", std::process::id(), N.fetch_add(1, Ordering::SeqCst)));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("home")).unwrap();
        fs::create_dir_all(dir.join("tmp")).unwrap();
        let dir = fs::canonicalize(dir).unwrap();
        fs::write(
            dir.join("home/.gitconfig"),
            "[user]\n\tname = Sandbox\n\temail = sb@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n",
        )
        .unwrap();
        let sb = Sb { dir };
        let mut c = Command::new("bash");
        c.arg("-c").arg(BUILD).arg("build").arg(&sb.dir).arg(env!("CARGO_MANIFEST_DIR"));
        c.arg(env!("CARGO_BIN_EXE_delphi"));
        sb.env(&mut c);
        let o = c.output().unwrap();
        assert!(o.status.success(), "sandbox build failed: {}", String::from_utf8_lossy(&o.stderr));
        sb
    }

    pub fn root(&self) -> PathBuf {
        self.dir.join("Delphi")
    }

    /// A checkout's directory.
    pub fn co(&self, name: &str) -> PathBuf {
        self.dir.join("Delphi-workspaces").join(name)
    }

    pub fn env(&self, c: &mut Command) {
        for k in [
            "DELPHI_ROOT",
            "DELPHI_WORKSPACE_ROOT",
            "DELPHI_YES",
            "DELPHI_OFFLINE",
            "DELPHI_USER",
            "ANTHROPIC_MODEL",
            "CLAUDE_CODE_EFFORT_LEVEL",
            "GIT_DIR",
            "GIT_WORK_TREE",
            "GIT_INDEX_FILE",
            "GIT_CONFIG_GLOBAL",
            "XDG_CONFIG_HOME",
            "PWD",
        ] {
            c.env_remove(k);
        }
        let path = format!("{}:{}", self.dir.join("bin").display(), std::env::var("PATH").unwrap_or_default());
        c.env("PATH", path)
            .env("HOME", self.dir.join("home"))
            .env("TMPDIR", self.dir.join("tmp"))
            .env("USER", "tester")
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .env("DELPHI_MODEL", "sandbox-model")
            .env("DELPHI_EFFORT", "low")
            .env("DELPHI_HARNESS", "sandbox")
            .stdin(Stdio::null());
    }

    fn collect(mut c: Command) -> Out {
        let o = c.output().unwrap();
        Out {
            code: o.status.code().unwrap_or(-1),
            stdout: String::from_utf8_lossy(&o.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&o.stderr).into_owned(),
        }
    }

    fn run(&self, mut c: Command, cwd: &Path) -> Out {
        self.env(&mut c);
        c.current_dir(cwd);
        Self::collect(c)
    }

    /// The CLI with DELPHI_ROOT set to the sandbox's Delphi.
    pub fn d(&self, cwd: &Path, args: &[&str]) -> Out {
        self.d_env(cwd, args, &[])
    }

    /// Like `d`, with extra environment variables.
    pub fn d_env(&self, cwd: &Path, args: &[&str], env: &[(&str, &str)]) -> Out {
        let mut c = Command::new(env!("CARGO_BIN_EXE_delphi"));
        c.args(args);
        self.env(&mut c);
        c.env("DELPHI_ROOT", self.root()).envs(env.iter().copied()).current_dir(cwd);
        Self::collect(c)
    }

    /// Like `d`, asserting success.
    pub fn ok(&self, cwd: &Path, args: &[&str]) -> Out {
        let o = self.d(cwd, args);
        assert_eq!(o.code, 0, "{args:?} failed: {o:#?}");
        o
    }

    /// The CLI without DELPHI_ROOT (root discovery).
    pub fn d_noroot(&self, cwd: &Path, args: &[&str]) -> Out {
        let mut c = Command::new(env!("CARGO_BIN_EXE_delphi"));
        c.args(args);
        self.run(c, cwd)
    }

    /// `checkout <ws> --as <name>`, asserting success; returns the checkout directory.
    pub fn checkout(&self, ws: &str, name: &str) -> PathBuf {
        self.ok(&self.dir, &["checkout", ws, "--as", name]);
        self.co(name)
    }

    /// Run a shell script in a directory; must succeed. Returns stdout.
    pub fn sh(&self, cwd: &Path, script: &str) -> String {
        let mut c = Command::new("bash");
        c.arg("-c").arg(format!("set -euo pipefail\n{script}"));
        let o = self.run(c, cwd);
        assert_eq!(o.code, 0, "script failed: {script}\n{}", o.stderr);
        o.stdout
    }

    /// Edits in a directory, committed.
    pub fn edit(&self, dir: &Path, script: &str) {
        self.sh(dir, &format!("{script}\ngit add -A\ngit commit -qm edits"));
    }

    pub fn git(&self, cwd: &Path, args: &[&str]) -> String {
        let mut c = Command::new("git");
        c.args(args);
        let o = self.run(c, cwd);
        assert_eq!(o.code, 0, "git {args:?} failed: {}", o.stderr);
        o.stdout.trim_end().to_string()
    }

    /// A separate full clone of origin (created on first use), like CI's.
    pub fn up(&self) -> PathBuf {
        let up = self.dir.join("up");
        if !up.exists() {
            self.git(&self.dir, &["clone", "-q", "origin.git", "up"]);
        }
        up
    }

    /// Commit a change to origin/main from `up`, as Alice, then re-split like CI.
    pub fn upstream(&self, subject: &str, script: &str) {
        self.sh(
            &self.up(),
            &format!(
                "git pull -q --no-rebase origin main\n{script}\ngit add -A\n\
                 git diff --cached --quiet || git -c user.name=Alice commit -qm '{subject}'\ngit push -q origin HEAD:main"
            ),
        );
        self.ci_split();
    }

    /// CI's `delphi split --push` on the latest origin/main (in `up`).
    pub fn ci_split(&self) -> Out {
        let up = self.up();
        self.sh(&up, "git pull -q --no-rebase origin main");
        let mut c = Command::new(env!("CARGO_BIN_EXE_delphi"));
        c.args(["split", "--push"]).current_dir(&up);
        self.env(&mut c);
        c.env("DELPHI_ROOT", &up);
        let o = Self::collect(c);
        assert_eq!(o.code, 0, "ci split failed: {o:#?}");
        o
    }

    pub fn read(&self, p: &Path) -> String {
        fs::read_to_string(p).unwrap_or_else(|e| panic!("{}: {e}", p.display()))
    }

    pub fn write(&self, p: &Path, s: &str) {
        fs::create_dir_all(p.parent().unwrap()).unwrap();
        fs::write(p, s).unwrap();
    }

    pub fn gh_log(&self) -> String {
        fs::read_to_string(self.dir.join("gh.log")).unwrap_or_default()
    }

    /// No temp dirs or Delphi worktrees left behind by the CLI.
    pub fn assert_cleaned_up(&self) {
        let left: Vec<_> = fs::read_dir(self.dir.join("tmp")).unwrap().flatten().map(|e| e.path()).collect();
        assert!(left.is_empty(), "temp dirs left behind: {left:?}");
        let wt = self.git(&self.root(), &["worktree", "list"]);
        assert_eq!(wt.lines().count(), 1, "worktrees left behind:\n{wt}");
    }
}

impl Drop for Sb {
    fn drop(&mut self) {
        if !std::thread::panicking() {
            let _ = fs::remove_dir_all(&self.dir);
        }
    }
}
