//! Which harness, model, and effort produced a change.
//!
//! Resolution per field: CLI flag -> DELPHI_* env (set by `workspace open`) -> adapter fallback
//! -> interactive prompt (accepts "none") -> error. Never records "unknown". `extra` holds extra
//! trailer lines; `rows` extra table rows ("harness|model|effort" lines) from other sessions.

use crate::core::{ask, env_nonempty, is_tty};
use crate::{die, harness};
use anyhow::Result;

pub struct Prov {
    pub harness: String,
    pub model: String,
    pub effort: String,
    pub extra: String,
    pub rows: String,
}

/// Flag, else env var, else fallback, else ask; `flag_name` is suggested when asking fails.
fn field(field: &str, flag: &str, var: &str, fallback: String, flag_name: &str) -> Result<String> {
    let v = if flag.is_empty() { env_nonempty(var).unwrap_or(fallback) } else { flag.to_string() };
    if !v.is_empty() {
        return Ok(v);
    }
    if !is_tty() {
        let pass = if flag_name.is_empty() { String::new() } else { format!("pass {flag_name} or ") };
        die!("provenance: {field} unknown — {pass}set {var}");
    }
    let a = ask(&format!("Which {field} made this change? ('none' if no AI was used)"), "")?;
    if a.is_empty() {
        die!("provenance: {field} is required");
    }
    Ok(a)
}

pub fn resolve(flag_model: &str, flag_effort: &str, adapter: &str) -> Result<Prov> {
    let [fh, fm, fe] = (harness::load(adapter)?.provenance)();
    Ok(Prov {
        harness: field("harness", "", "DELPHI_HARNESS", fh, "")?,
        model: field("model", flag_model, "DELPHI_MODEL", fm, "--model")?,
        effort: field("effort", flag_effort, "DELPHI_EFFORT", fe, "--effort")?,
        extra: String::new(),
        rows: String::new(),
    })
}

impl Prov {
    /// Commit trailers (no trailing newline).
    pub fn trailers(&self) -> String {
        let s =
            format!("Delphi-Harness: {}\nDelphi-Model: {}\nDelphi-Effort: {}", self.harness, self.model, self.effort);
        if self.extra.is_empty() {
            s
        } else {
            format!("{s}\n{}", self.extra.trim_end_matches('\n'))
        }
    }

    /// Markdown table of this session plus `rows` (no trailing newline).
    pub fn table(&self) -> String {
        let mut s = format!(
            "| Harness | Model | Effort |\n|---|---|---|\n| {} | {} | {} |",
            self.harness, self.model, self.effort
        );
        for l in self.rows.lines() {
            s += &format!("\n| {} |", l.replace('|', " | "));
        }
        s
    }
}
