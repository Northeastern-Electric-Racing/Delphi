//! Strict YAML-subset parser and record accessors.
//!
//! Supported: full-line and trailing ` #` comments; top-level `key: value`; top-level `key:`
//! followed by two-space-indented `- item` lines (list) or `sub: value` lines (one-level map).
//! Anything else is a parse error reported as `file:line: msg`.

use crate::core::{awk_lines, Raw};
use anyhow::Result;
use std::collections::HashSet;
use std::path::Path;

/// One record: scalar/list item (`sub` = None) or map entry.
pub struct Rec {
    pub key: String,
    pub sub: Option<String>,
    pub val: String,
}

pub struct Yaml(pub Vec<Rec>);

fn is_key(s: &str) -> Option<usize> {
    let n = s.bytes().take_while(|b| b.is_ascii_alphanumeric() || *b == b'_' || *b == b'-').count();
    (n > 0 && s.as_bytes().get(n) == Some(&b':')).then_some(n)
}

fn unquote(s: &str) -> String {
    if s.len() >= 2 && s.starts_with('"') && s.ends_with('"') {
        s[1..s.len() - 1].to_string()
    } else {
        s.to_string()
    }
}

fn nocomment(s: &str) -> Result<String, String> {
    if s.trim_start_matches(' ').starts_with('"') {
        let q1 = s.find('"').unwrap_or(0);
        let Some(q2) = s[q1 + 1..].find('"') else { return Err("unterminated quote".into()) };
        let i = q1 + 1 + q2;
        let rest = &s[i + 1..];
        if rest.bytes().all(|b| b == b' ') || (rest.starts_with(' ') && rest.trim_start_matches(' ').starts_with('#')) {
            return Ok(s[..=i].to_string());
        }
        return Err("text after closing quote".into());
    }
    Ok(match s.find(" #") {
        Some(i) => s[..i].to_string(),
        None => s.to_string(),
    })
}

fn value(raw: &str) -> Result<String, String> {
    let v = nocomment(raw)?.trim_matches(' ').to_string();
    if v.starts_with(['[', '{', '&', '*', '|', '>', '!']) {
        return Err(format!("unsupported YAML syntax: {v}"));
    }
    Ok(v)
}

/// Parse a file; errors are `Raw("<file>:<line>: <msg>")`.
pub fn parse_yaml(path: &Path) -> Result<Yaml> {
    if !path.is_file() {
        crate::die!("no such file: {}", path.display());
    }
    parse_text(&String::from_utf8_lossy(&std::fs::read(path)?), &path.display().to_string())
}

/// Parse text; `name` labels errors.
pub fn parse_text(text: &str, name: &str) -> Result<Yaml> {
    let mut recs = Vec::new();
    let mut seen = HashSet::new();
    let mut cur = String::new();
    for (i, line) in awk_lines(text).into_iter().enumerate() {
        let fail = |m: String| -> anyhow::Error { Raw(format!("{name}:{}: {m}", i + 1)).into() };
        if line.contains('\t') {
            return Err(fail("tabs are not allowed".into()));
        }
        let t = line.trim_start_matches(' ');
        if t.starts_with('#') || t.is_empty() {
            continue;
        }
        if let Some(n) = is_key(line) {
            let k = &line[..n];
            if !seen.insert(k.to_string()) {
                return Err(fail(format!("duplicate key: {k}")));
            }
            let v = value(&line[n + 1..]).map_err(fail)?;
            if v.is_empty() {
                cur = k.to_string();
            } else {
                recs.push(Rec { key: k.into(), sub: None, val: unquote(&v) });
                cur.clear();
            }
        } else if let Some(item) = line.strip_prefix("  - ") {
            if cur.is_empty() {
                return Err(fail("list item without a parent key".into()));
            }
            let v = value(item).map_err(fail)?;
            recs.push(Rec { key: cur.clone(), sub: None, val: unquote(&v) });
        } else if let Some(n) = line.strip_prefix("  ").and_then(is_key) {
            if cur.is_empty() {
                return Err(fail("map entry without a parent key".into()));
            }
            let s = &line[2..];
            let v = value(&s[n + 1..]).map_err(fail)?;
            if v.is_empty() {
                return Err(fail("nested maps are not supported".into()));
            }
            recs.push(Rec { key: cur.clone(), sub: Some(s[..n].into()), val: unquote(&v) });
        } else {
            return Err(fail("unsupported indentation or syntax".into()));
        }
    }
    Ok(Yaml(recs))
}

impl Yaml {
    /// First scalar value of a key ("" if none).
    pub fn get(&self, k: &str) -> String {
        self.list(k).into_iter().next().unwrap_or_default()
    }
    /// All non-empty scalar/list values of a key.
    pub fn list(&self, k: &str) -> Vec<String> {
        self.0.iter().filter(|r| r.sub.is_none() && r.key == k && !r.val.is_empty()).map(|r| r.val.clone()).collect()
    }
    /// Map entries of a key.
    pub fn map(&self, k: &str) -> Vec<(String, String)> {
        self.0
            .iter()
            .filter_map(|r| r.sub.as_ref().filter(|_| r.key == k).map(|s| (s.clone(), r.val.clone())))
            .collect()
    }
    /// Sorted distinct keys.
    pub fn keys(&self) -> Vec<String> {
        let mut v: Vec<String> = self.0.iter().map(|r| r.key.clone()).collect();
        v.sort();
        v.dedup();
        v
    }
}
