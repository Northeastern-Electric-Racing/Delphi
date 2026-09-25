//! Test sandbox, like dev/sandbox.sh: a temp dir with a bare Delphi origin, a Delphi clone with
//! sample content, a bare code repo, a stub `gh` on PATH (logs to gh.log, remembers PRs in
//! gh.prs), and a workspace root. Runs the Rust binary and, when available, the bash CLI
//! (`/bin/bash <sandbox>/Delphi/bin/delphi`) against the same sandbox.
#![allow(dead_code)]

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

const BUILD: &str = r#"
set -euo pipefail
SB=$1 here=$2
git init -q --bare -b main "$SB/origin.git"
git clone -q "$SB/origin.git" "$SB/Delphi" 2>/dev/null
if [ -f "$here/lib/core.sh" ]; then cp -R "$here/bin" "$here/lib" "$SB/Delphi/"; fi
cp "$here/delphi.conf" "$here/moves.tsv" "$SB/Delphi/"

C="$SB/Delphi/context"
A="$C/software/application-software/argos"
mkdir -p "$C/software/harness/instructions" "$C/software/harness/mcp" \
         "$A/blocks" "$A/harness/instructions" "$A/harness/skills/run-tests" "$A/layouts/argos-dev"

printf 'name: NER\n' > "$C/scope.yml"
printf 'name: Software\nrecommend:\n  - software/harness/instructions/base.md\n' > "$C/software/scope.yml"
printf 'name: Application Software\n' > "$C/software/application-software/scope.yml"
cat > "$A/scope.yml" <<'EOF'
name: Argos
recommend:
  - software/application-software/argos/blocks/overview.md
  - software/application-software/argos/harness/skills/run-tests
EOF
printf '# Software conventions\n\n- Use conventional commits.\n- Open PRs against develop.\n' \
  > "$C/software/harness/instructions/base.md"
printf '"github": {\n  "command": "gh-mcp",\n  "args": []\n}\n' > "$C/software/harness/mcp/github.json"
printf '# Argos\n\nArgos is the telemetry dashboard.\nIt has an Angular client and a Rust server.\n' \
  > "$A/harness/instructions/argos.md"
printf '# Argos overview\n\nLine one.\nLine two.\nLine three.\n' > "$A/blocks/overview.md"
printf '# Testing\n\nRun `npm test` in angular-client.\nRun `cargo test` in the server.\n' > "$A/blocks/testing.md"
printf -- '---\nname: run-tests\ndescription: Run the Argos test suites.\n---\n\nRun both suites and summarize failures.\n' \
  > "$A/harness/skills/run-tests/SKILL.md"
mkdir -p "$A/harness/skills/run-tests/scripts"
printf '#!/bin/sh\necho running tests\n' > "$A/harness/skills/run-tests/scripts/run.sh"
chmod +x "$A/harness/skills/run-tests/scripts/run.sh"
cat > "$A/harness/skills/triage.skill" <<'EOF'
name: triage
description: Triage a failing Argos test.
body:
  - software/application-software/argos/blocks/testing.md
EOF

git init -q -b main "$SB/argos-src"
printf '# Argos code\n' > "$SB/argos-src/README.md"
git -C "$SB/argos-src" add -A && git -C "$SB/argos-src" commit -qm init
git clone -q --bare "$SB/argos-src" "$SB/argos.git"

cat > "$A/layouts/argos-dev/manifest.yml" <<EOF
name: argos-dev
harness: claude-code
instructions:
  - software/harness/instructions/base.md
  - software/application-software/argos/harness/instructions/argos.md
blocks:
  - software/application-software/argos/blocks/*
skills:
  - software/application-software/argos/harness/skills/run-tests
  - software/application-software/argos/harness/skills/triage.skill
mcp:
  - software/harness/mcp/github.json
repos:
  argos: file://$SB/argos.git
EOF

git -C "$SB/Delphi" add -A
git -C "$SB/Delphi" commit -qm "sandbox: code + sample content"
git -C "$SB/Delphi" push -q origin HEAD:main 2>/dev/null
git -C "$SB/Delphi" branch -q -u origin/main 2>/dev/null || true

mkdir -p "$SB/bin"; : > "$SB/gh.prs"
{ printf '#!/bin/sh\nSB=%q\n' "$SB"; cat <<'EOF'; } > "$SB/bin/gh"
# stub gh for the Delphi sandbox: never contacts GitHub
echo "gh $*" >> "$SB/gh.log"
n=$(awk -v b="$4" '$1 == b { print $2 }' "$SB/gh.prs")   # args: pr list|create --head <branch> …
case "$1 $2" in
  "api user") echo sandbox-user ;;
  "pr list") [ -z "$n" ] || { [ "$8" = author ] && echo sandbox-user || echo "$n"; } ;;
  "pr create") n=$(($(wc -l < "$SB/gh.prs") + 1)); echo "$4 $n" >> "$SB/gh.prs"; echo "https://github.invalid/pr/$n" ;;
esac
exit 0
EOF
chmod +x "$SB/bin/gh"
"#;

pub const LAYOUT: &str = "software/application-software/argos/layouts/argos-dev";
pub const BLOCKS: &str = "context/software/application-software/argos/blocks";

#[derive(Debug, Clone)]
pub struct Out {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

impl Out {
    /// Replace a workspace (or other) name so bash and Rust runs on sibling workspaces compare.
    pub fn norm(&self, from: &str, to: &str) -> Out {
        Out { code: self.code, stdout: self.stdout.replace(from, to), stderr: self.stderr.replace(from, to) }
    }
}

pub struct Sb {
    pub dir: PathBuf,
}

static N: AtomicUsize = AtomicUsize::new(0);

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

impl Sb {
    pub fn new(tag: &str) -> Sb {
        // outside this repo, so walking up from a workspace never finds the real checkout
        let base = std::env::temp_dir();
        let dir = base.join(format!("sb-{tag}-{}-{}", std::process::id(), N.fetch_add(1, Ordering::SeqCst)));
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
        c.arg("-c").arg(BUILD).arg("build").arg(&sb.dir).arg(repo());
        sb.env(&mut c);
        let o = c.output().unwrap();
        assert!(o.status.success(), "sandbox build failed: {}", String::from_utf8_lossy(&o.stderr));
        sb
    }

    pub fn root(&self) -> PathBuf {
        self.dir.join("Delphi")
    }

    pub fn ws(&self, name: &str) -> PathBuf {
        self.dir.join("Delphi-workspaces").join(name)
    }

    pub fn env(&self, c: &mut Command) {
        for k in [
            "DELPHI_ROOT",
            "DELPHI_WORKSPACE_ROOT",
            "DELPHI_YES",
            "DELPHI_OFFLINE",
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

    fn run(&self, mut c: Command, cwd: &Path) -> Out {
        self.env(&mut c);
        c.current_dir(cwd);
        let o = c.output().unwrap();
        Out {
            code: o.status.code().unwrap_or(-1),
            stdout: String::from_utf8_lossy(&o.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&o.stderr).into_owned(),
        }
    }

    /// The Rust CLI with DELPHI_ROOT set to the sandbox's Delphi.
    pub fn rust(&self, cwd: &Path, args: &[&str]) -> Out {
        let mut c = self.rust_cmd(args);
        self.env(&mut c);
        c.env("DELPHI_ROOT", self.root());
        c.current_dir(cwd);
        let o = c.output().unwrap();
        Out {
            code: o.status.code().unwrap_or(-1),
            stdout: String::from_utf8_lossy(&o.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&o.stderr).into_owned(),
        }
    }

    /// The Rust CLI without DELPHI_ROOT (root discovery).
    pub fn rust_noroot(&self, cwd: &Path, args: &[&str]) -> Out {
        self.run(self.rust_cmd(args), cwd)
    }

    fn rust_cmd(&self, args: &[&str]) -> Command {
        let mut c = Command::new(env!("CARGO_BIN_EXE_delphi"));
        c.args(args);
        c
    }

    pub fn has_bash(&self) -> bool {
        Path::new("/bin/bash").exists() && self.root().join("lib/core.sh").exists()
    }

    /// The bash CLI, or None when it (or /bin/bash) is unavailable.
    pub fn bash(&self, cwd: &Path, args: &[&str]) -> Option<Out> {
        if !self.has_bash() {
            return None;
        }
        let mut c = Command::new("/bin/bash");
        c.arg(self.root().join("bin/delphi")).args(args);
        Some(self.run(c, cwd))
    }

    /// Run a shell script in a directory; must succeed. Returns stdout.
    pub fn sh(&self, cwd: &Path, script: &str) -> String {
        let mut c = Command::new("bash");
        c.arg("-c").arg(format!("set -euo pipefail\n{script}"));
        let o = self.run(c, cwd);
        assert_eq!(o.code, 0, "script failed: {script}\n{}", o.stderr);
        o.stdout
    }

    pub fn git(&self, cwd: &Path, args: &[&str]) -> String {
        let mut c = Command::new("git");
        c.args(args);
        let o = self.run(c, cwd);
        assert_eq!(o.code, 0, "git {args:?} failed: {}", o.stderr);
        o.stdout.trim_end().to_string()
    }

    /// Commit a change to origin/main from a separate clone.
    pub fn upstream(&self, script: &str) {
        let up = self.dir.join("up");
        if !up.exists() {
            self.git(&self.dir, &["clone", "-q", "origin.git", "up"]);
        }
        self.sh(&up, &format!("git pull -q --no-rebase origin main\n{script}\ngit add -A\ngit diff --cached --quiet || git commit -qm upstream\ngit push -q origin HEAD:main"));
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

/// Assert two runs are identical (exit code, stdout, stderr).
pub fn same(r: &Out, b: &Option<Out>) {
    if let Some(b) = b {
        assert_eq!(r.code, b.code, "exit codes differ\nrust: {r:#?}\nbash: {b:#?}");
        assert_eq!(r.stdout, b.stdout, "stdout differs");
        assert_eq!(r.stderr, b.stderr, "stderr differs");
    }
}
