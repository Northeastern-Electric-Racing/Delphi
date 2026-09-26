//! Harness adapters: file names, provenance fallback, launch. Adding a harness = one entry here.

use crate::core::{name_ok, out_q};
use anyhow::Result;
use std::process::Command;

pub struct Harness {
    pub name: &'static str,
    /// Instruction file at the workspace root.
    pub instructions: &'static str,
    /// Default dest for `…/harness/skills/<n>` sources.
    pub skills_dir: &'static str,
    /// Added to the workspace's .git/info/exclude.
    pub ignore: &'static str,
    /// Harness+version, model, effort (blank if unknown).
    pub provenance: fn() -> [String; 3],
    /// The command that starts the harness with a model and effort (either may be empty).
    pub launch: fn(&str, &str) -> Command,
}

pub const HARNESSES: &[Harness] = &[Harness {
    name: "claude-code",
    instructions: "CLAUDE.md",
    skills_dir: ".claude/skills",
    ignore: ".claude/settings.local.json",
    provenance: claude_provenance,
    launch: claude_launch,
}];

fn claude_provenance() -> [String; 3] {
    let v = out_q(Command::new("claude").arg("--version"))
        .and_then(|o| o.lines().next().and_then(|l| l.split_whitespace().next()).map(String::from))
        .unwrap_or_default();
    let env = |k| std::env::var(k).unwrap_or_default();
    let h = if v.is_empty() { "claude-code".to_string() } else { format!("claude-code {v}") };
    [h, env("ANTHROPIC_MODEL"), env("CLAUDE_CODE_EFFORT_LEVEL")]
}

fn claude_launch(model: &str, effort: &str) -> Command {
    let mut c = Command::new("claude");
    if !effort.is_empty() {
        c.env("CLAUDE_CODE_EFFORT_LEVEL", effort);
    }
    if !model.is_empty() {
        c.args(["--model", model]);
    }
    c
}

/// Look up an adapter by name.
pub fn load(name: &str) -> Result<&'static Harness> {
    if !name_ok(name) {
        crate::die!("invalid harness name: '{name}'");
    }
    match HARNESSES.iter().find(|h| h.name == name) {
        Some(h) => Ok(h),
        None => crate::die!("unknown harness: {name}"),
    }
}
