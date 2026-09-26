//! Which harness, model, and effort produced a change.
//!
//! Resolution per field: CLI flag -> DELPHI_* env (set by `workspace open`) -> adapter fallback
//! -> interactive prompt (accepts "none") -> error. Never records "unknown". `extra` holds extra
//! trailer lines; `rows` extra table rows ("harness|model|effort" lines) from other sessions.

use crate::core::{ask, env_nonempty, is_tty};
use crate::harness;
use anyhow::Result;

#[derive(Clone, Default)]
pub struct Prov {
    pub harness: String,
    pub model: String,
    pub effort: String,
    pub extra: String,
    pub rows: String,
}

fn prov_ask(field: &str, var: &str, flag: &str) -> Result<String> {
    if !is_tty() {
        let pass = if flag.is_empty() { String::new() } else { format!("pass {flag} or ") };
        crate::die!("provenance: {field} unknown — {pass}set {var}");
    }
    let a = ask(&format!("Which {field} made this change? ('none' if no AI was used)"), "")?;
    if a.is_empty() {
        crate::die!("provenance: {field} is required");
    }
    Ok(a)
}

pub fn resolve(flag_model: &str, flag_effort: &str, adapter: &str) -> Result<Prov> {
    let h = harness::load(adapter)?;
    let [fh, fm, fe] = (h.provenance)();
    let pick = |flag: &str, var: &str, fb: String| {
        if !flag.is_empty() {
            flag.to_string()
        } else {
            env_nonempty(var).unwrap_or(fb)
        }
    };
    let mut p = Prov {
        harness: pick("", "DELPHI_HARNESS", fh),
        model: pick(flag_model, "DELPHI_MODEL", fm),
        effort: pick(flag_effort, "DELPHI_EFFORT", fe),
        ..Default::default()
    };
    if p.harness.is_empty() {
        p.harness = prov_ask("harness", "DELPHI_HARNESS", "")?;
    }
    if p.model.is_empty() {
        p.model = prov_ask("model", "DELPHI_MODEL", "--model")?;
    }
    if p.effort.is_empty() {
        p.effort = prov_ask("effort", "DELPHI_EFFORT", "--effort")?;
    }
    Ok(p)
}

impl Prov {
    /// Commit trailers (no trailing newline).
    pub fn trailers(&self) -> String {
        let mut s =
            format!("Delphi-Harness: {}\nDelphi-Model: {}\nDelphi-Effort: {}", self.harness, self.model, self.effort);
        if !self.extra.is_empty() {
            s.push('\n');
            s.push_str(&self.extra);
        }
        s.trim_end_matches('\n').to_string()
    }

    /// Markdown table of this session plus `rows` (no trailing newline).
    pub fn table(&self) -> String {
        let mut s = format!(
            "| Harness | Model | Effort |\n|---|---|---|\n| {} | {} | {} |",
            self.harness, self.model, self.effort
        );
        if !self.rows.is_empty() {
            for l in crate::core::awk_lines(&format!("{}\n", self.rows)) {
                let mut f = l.splitn(3, '|');
                let (h, m, e) = (f.next().unwrap_or(""), f.next().unwrap_or(""), f.next().unwrap_or(""));
                s.push_str(&format!("\n| {h} | {m} | {e} |"));
            }
        }
        s
    }
}
