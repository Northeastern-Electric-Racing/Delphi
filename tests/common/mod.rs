//! Test sandbox: a temp dir with a bare Delphi origin, a Delphi clone with sample content (two
//! layouts), a bare code repo, a stub `gh` on PATH (logs to gh.log, remembers PRs in gh.prs), and
//! a workspace root. Nothing touches GitHub.
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
cp "$here/delphi.conf" "$here/moves.tsv" "$SB/Delphi/"

C="$SB/Delphi/context"
S=software/application-software
A="$C/$S/argos" N="$C/$S/nero"
mkdir -p "$C/software/harness/instructions" "$C/software/harness/settings" "$A/blocks" "$A/docs" \
         "$A/harness/instructions" "$A/harness/skills/run-tests/scripts" \
         "$A/layouts/argos-dev/files/.claude/skills/argos-notes" "$N/layouts/nero-dev/files"

printf 'name: NER\n' > "$C/scope.yml"
printf 'name: Software\nrecommend:\n  - software/harness/instructions/base.md\n' > "$C/software/scope.yml"
printf 'name: Application Software\n' > "$C/$S/scope.yml"
printf 'name: Argos\nrecommend:\n  - %s/argos/harness/skills/run-tests\n' "$S" > "$A/scope.yml"
printf 'name: NERO\n' > "$N/scope.yml"
printf '# Software conventions\n\n- Use conventional commits.\n- Open PRs against develop.\n' \
  > "$C/software/harness/instructions/base.md"
printf '{\n  "model": "sonnet"\n}\n' > "$C/software/harness/settings/settings.json"
printf '# Argos\n\nArgos is the telemetry dashboard.\n' > "$A/harness/instructions/argos.md"
printf -- '---\nname: run-tests\ndescription: Run the Argos test suites.\n---\n\nRun both suites.\n' \
  > "$A/harness/skills/run-tests/SKILL.md"
printf '#!/bin/sh\necho running tests\n' > "$A/harness/skills/run-tests/scripts/run.sh"
chmod +x "$A/harness/skills/run-tests/scripts/run.sh"
printf '# Guide\n\nLine one.\nLine two.\n' > "$A/docs/guide.md"
printf '\211PNG\r\n\0\1\2' > "$A/docs/logo.png"
printf '**PR body:** fill the template.\n' > "$A/blocks/pr-body.md"
printf '# Style\n\nTabs.\n' > "$A/blocks/style.md"
printf -- '---\nname: argos-notes\ndescription: Notes.\n---\n\nArgos notes.\n' \
  > "$A/layouts/argos-dev/files/.claude/skills/argos-notes/SKILL.md"
printf '# NERO\n' > "$N/layouts/nero-dev/files/CLAUDE.md"

git init -q -b main "$SB/argos-src"
printf '# Argos code\n' > "$SB/argos-src/README.md"
git -C "$SB/argos-src" add -A && git -C "$SB/argos-src" commit -qm init
git clone -q --bare "$SB/argos-src" "$SB/argos.git"

cat > "$A/layouts/argos-dev/manifest.yml" <<EOF
name: argos-dev
harness: claude-code
instructions:
  - software/harness/instructions/base.md
  - $S/argos/harness/instructions/argos.md
sync:
  - $S/argos/harness/skills/run-tests
  - $S/argos/docs
  - $S/argos/blocks/style.md
  - $S/argos/blocks/pr-body.md -> .claude/skills/open-pr/pr-body.md
  - $S/argos/blocks/pr-body.md -> .claude/skills/update-pr/pr-body.md
copy:
  - software/harness/settings/settings.json -> .claude/settings.json
repos:
  argos: file://$SB/argos.git
EOF
cat > "$N/layouts/nero-dev/manifest.yml" <<EOF
name: nero-dev
harness: claude-code
sync:
  - $S/argos/blocks/pr-body.md -> .claude/skills/pr/pr-body.md
EOF

git -C "$SB/Delphi" add -A
git -C "$SB/Delphi" commit -qm "sandbox: sample content"
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

pub const S: &str = "software/application-software";
pub const A: &str = "software/application-software/argos";
pub const LAYOUT: &str = "software/application-software/argos/layouts/argos-dev";

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
        // outside this repo, so walking up from a workspace never finds the real checkout
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
        let mut c = Command::new(env!("CARGO_BIN_EXE_delphi"));
        c.args(args);
        self.env(&mut c);
        c.env("DELPHI_ROOT", self.root()).current_dir(cwd);
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

    /// `workspace new argos-dev --as <name>`, asserting success.
    pub fn new_ws(&self, name: &str) -> PathBuf {
        self.ok(&self.dir, &["workspace", "new", "argos-dev", "--as", name]);
        self.ws(name)
    }

    /// Run a shell script in a directory; must succeed. Returns stdout.
    pub fn sh(&self, cwd: &Path, script: &str) -> String {
        let mut c = Command::new("bash");
        c.arg("-c").arg(format!("set -euo pipefail\n{script}"));
        let o = self.run(c, cwd);
        assert_eq!(o.code, 0, "script failed: {script}\n{}", o.stderr);
        o.stdout
    }

    /// Edits in a workspace, committed.
    pub fn edit(&self, ws: &Path, script: &str) {
        self.sh(ws, &format!("{script}\ngit add -A\ngit commit -qm edits"));
    }

    pub fn git(&self, cwd: &Path, args: &[&str]) -> String {
        let mut c = Command::new("git");
        c.args(args);
        let o = self.run(c, cwd);
        assert_eq!(o.code, 0, "git {args:?} failed: {}", o.stderr);
        o.stdout.trim_end().to_string()
    }

    /// Commit a change to origin/main from a separate clone, as Alice.
    pub fn upstream(&self, subject: &str, script: &str) {
        let up = self.dir.join("up");
        if !up.exists() {
            self.git(&self.dir, &["clone", "-q", "origin.git", "up"]);
        }
        self.sh(
            &up,
            &format!(
                "git pull -q --no-rebase origin main\n{script}\ngit add -A\n\
                 git diff --cached --quiet || git -c user.name=Alice commit -qm '{subject}'\ngit push -q origin HEAD:main"
            ),
        );
    }

    pub fn read(&self, p: &Path) -> String {
        fs::read_to_string(p).unwrap_or_else(|e| panic!("{}: {e}", p.display()))
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
