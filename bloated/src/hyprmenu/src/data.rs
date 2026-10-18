//! Entries (flatpaks + custom), running state, launching, stopping, fuzzy matching.

use serde::Deserialize;
use std::process::{Command, Stdio};

#[derive(Debug, Clone)]
pub struct Entry {
    pub id: String,
    pub name: String,
    pub exec: String,
    pub tag: String, // right-hand text: app id, or key hint / command for custom entries
    pub flatpak: bool,
    pub instances: Vec<String>, // flatpak instance ids
}
impl Entry {
    pub fn running(&self) -> usize { self.instances.len() }
}

#[derive(Deserialize)]
struct Custom { name: String, exec: String, key: Option<String> }

fn capture(args: &[&str]) -> String {
    Command::new(args[0]).args(&args[1..]).stderr(Stdio::null()).output()
        .map(|o| String::from_utf8_lossy(&o.stdout).into_owned()).unwrap_or_default()
}
fn quiet(args: &[&str]) {
    let _ = Command::new(args[0]).args(&args[1..]).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).status();
}

pub fn load_entries() -> Vec<Entry> {
    let mut out = Vec::new();
    if let Some(home) = std::env::var_os("HOME") {
        let p = std::path::PathBuf::from(home).join(".config/hyprmenu/entries.json");
        if let Ok(s) = std::fs::read_to_string(&p) {
            match serde_json::from_str::<Vec<Custom>>(&s) {
                Ok(list) => for c in list {
                    out.push(Entry { id: format!("custom:{}", c.name), tag: c.key.unwrap_or_else(|| c.exec.clone()), name: c.name, exec: c.exec, flatpak: false, instances: vec![] });
                },
                Err(e) => eprintln!("entries.json: {e}"),
            }
        }
    }
    for line in capture(&["flatpak", "list", "--app", "--columns=application,name"]).lines() {
        let mut it = line.split('\t');
        let (Some(id), name) = (it.next(), it.next()) else { continue };
        let name = name.map(str::trim).filter(|n| !n.is_empty()).unwrap_or(id);
        out.push(Entry { id: id.into(), name: name.into(), exec: format!("flatpak run {id}"), tag: id.into(), flatpak: true, instances: vec![] });
    }
    out
}

/// Re-read `flatpak ps`. Returns true if anything changed.
pub fn refresh_running(entries: &mut [Entry]) -> bool {
    let ps = capture(&["flatpak", "ps", "--columns=instance,application"]);
    let mut changed = false;
    for e in entries.iter_mut() {
        if !e.flatpak { continue; }
        let now: Vec<String> = ps.lines().filter_map(|l| { let mut it = l.split('\t'); let inst = it.next()?; (it.next()? == e.id).then(|| inst.to_string()) }).collect();
        if now != e.instances { e.instances = now; changed = true; }
    }
    changed
}

/// Hyprland forks the app, so the daemon is never its parent.
pub fn launch(e: &Entry) { quiet(&["hyprctl", "dispatch", "exec", "--", &e.exec]); }
/// Hard stop of every instance (`flatpak kill` is SIGKILL; the UI asks twice).
pub fn stop(e: &Entry) { for i in &e.instances { quiet(&["flatpak", "kill", i]); } }

/// Subsequence match on chars. Returns (score, matched char indices) or None.
pub fn fuzzy(query: &str, text: &str) -> Option<(f32, Vec<usize>)> {
    if query.is_empty() { return Some((0.0, vec![])); }
    let t: Vec<char> = text.chars().map(|c| c.to_ascii_lowercase()).collect();
    let mut idx = Vec::with_capacity(query.len());
    let (mut ti, mut prev, mut score) = (0usize, usize::MAX, 0f32);
    for q in query.chars().map(|c| c.to_ascii_lowercase()) {
        let pos = (ti..t.len()).find(|&k| t[k] == q)?;
        if prev != usize::MAX && pos == prev + 1 { score += 3.0; }
        if pos == 0 { score += 4.0; } else if matches!(t[pos - 1], ' ' | '-' | '_' | '.') { score += 2.0; }
        score -= (pos - ti) as f32 * 0.1;
        idx.push(pos); prev = pos; ti = pos + 1;
    }
    Some((score, idx))
}
