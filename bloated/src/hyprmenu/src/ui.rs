//! Launcher UI: filter state, key handling, painting. Knows nothing about Wayland.

use crate::data::{self, Entry};
use crate::gfx::{Gfx, Rgb};
use crate::text::Fonts;

pub const MX: f64 = 3.0; // margin, in cells
pub const MY: f64 = 1.0; // margin, in rows
pub const BG: u32 = 0x111111;      // alacritty colors.primary.background
pub const BG_ALPHA: f32 = 0.77;    // alacritty window.opacity
const FG: u32 = 0xd8d8d8;
const SEL: u32 = 0xff5555;         // selected row text
const BORDER: u32 = 0x830808;      // general:col.active_border → chevron + spinner
const COMMENT: u32 = 0x6272a4;     // separator, tags, status
pub const MAX_QUERY: usize = 64;

#[derive(Default)]
pub struct Ui {
    pub query: String,
    pub filtered: Vec<usize>,
    pub sel: usize,
    pub flash: String,
    pending_kill: Option<String>,
    pub tick: u32,
}

/// What the daemon should do after a key.
pub enum Action { Nothing, Hide, Launched, Stopped }

#[derive(Clone, Copy, PartialEq)]
pub enum Key { Char(char), Enter, Esc, Up, Down, Backspace, Ctrl(char) }

impl Ui {
    pub fn reset(&mut self, entries: &[Entry]) {
        self.query.clear(); self.sel = 0; self.flash.clear(); self.pending_kill = None;
        self.apply_filter(entries);
    }

    pub fn apply_filter(&mut self, entries: &[Entry]) {
        let mut scored: Vec<(f32, usize)> = entries.iter().enumerate().filter_map(|(i, e)| {
            if let Some((s, _)) = data::fuzzy(&self.query, &e.name) { return Some((s, i)); }
            data::fuzzy(&self.query, &e.tag).map(|(s, _)| (s - 20.0, i)) // weak fallback on the visible tag
        }).collect();
        scored.sort_by(|a, b| {
            b.0.partial_cmp(&a.0).unwrap()
                .then(entries[b.1].running().cmp(&entries[a.1].running()))
                .then_with(|| entries[a.1].name.to_lowercase().cmp(&entries[b.1].name.to_lowercase()))
        });
        self.filtered = scored.into_iter().map(|(_, i)| i).collect();
        if self.sel >= self.filtered.len() { self.sel = self.filtered.len().saturating_sub(1); }
    }

    pub fn any_running(&self, entries: &[Entry]) -> bool { self.filtered.iter().any(|&i| entries[i].running() > 0) }

    pub fn key(&mut self, k: Key, shift: bool, entries: &[Entry]) -> Action {
        let was_pending = self.pending_kill.take();
        self.flash.clear();
        let cur = self.filtered.get(self.sel).map(|&i| &entries[i]);
        match k {
            Key::Esc | Key::Ctrl('c') | Key::Ctrl('q') | Key::Ctrl('d') => return Action::Hide,
            Key::Enter => {
                let Some(e) = cur else { return Action::Nothing };
                data::launch(e);
                if !shift { return Action::Hide; }
                self.flash = format!("launched {}", e.name);
                return Action::Launched;
            }
            Key::Up | Key::Ctrl('k') | Key::Ctrl('p') => { self.sel = self.sel.saturating_sub(1); }
            Key::Down | Key::Ctrl('j') | Key::Ctrl('n') => { if self.sel + 1 < self.filtered.len() { self.sel += 1; } }
            Key::Backspace => { self.query.pop(); self.apply_filter(entries); }
            Key::Ctrl('u') => { self.query.clear(); self.apply_filter(entries); }
            Key::Ctrl('w') => {
                let t = self.query.trim_end().to_string();
                self.query = match t.rfind(' ') { Some(i) => t[..=i].to_string(), None => String::new() };
                self.apply_filter(entries);
            }
            Key::Ctrl('x') => {
                let Some(e) = cur else { return Action::Nothing };
                if !e.flatpak { return Action::Nothing; }
                if e.running() == 0 { self.flash = format!("{} is not running", e.name); return Action::Nothing; }
                if was_pending.as_deref() != Some(&e.id) {
                    self.pending_kill = Some(e.id.clone());
                    self.flash = format!("stop {} ({} instance{})? ctrl+x again to confirm", e.name, e.running(), if e.running() > 1 { "s" } else { "" });
                    return Action::Nothing;
                }
                data::stop(e);
                self.flash = format!("stopped {}", e.name);
                return Action::Stopped;
            }
            Key::Char(c) => {
                if self.query.chars().count() < MAX_QUERY { self.query.push(c); self.apply_filter(entries); }
            }
            Key::Ctrl(_) => {}
        }
        Action::Nothing
    }

    pub fn paint(&mut self, g: &mut Gfx, fonts: &Fonts, entries: &[Entry], pw: i32, ph: i32, scale: f64) {
        let (cw, lh, asc) = (fonts.cell_w, fonts.line_h, fonts.ascent);
        let rows = (ph as f64 / lh) as i32;
        let list_rows = (rows as f64 - MY - 4.0).max(1.0) as usize;
        let mx = (MX * cw) as f32;
        let right = (pw as f64 - MX * cw) as f32;
        let px1 = scale.max(1.0) as f32;
        let (fg, sel, border, comment) = (Rgb(FG), Rgb(SEL), Rgb(BORDER), Rgb(COMMENT));

        // prompt
        let ybase = (MY * lh + asc) as f32;
        let mut x = mx;
        x += g.text(fonts, x, ybase, "\u{203a}", &border, 1.0, &[0]);
        x += cw as f32;
        x += g.text(fonts, x, ybase, &self.query, &fg, 1.0, &[]);
        g.rect(x, (ybase as f64 - asc + lh * 0.15) as f32, px1, (lh * 0.75) as f32, &fg, 0.6);

        // separator
        g.rect(mx, ((MY + 1.0) * lh + lh / 2.0) as f32, right - mx, px1, &comment, 1.0);

        // list
        let n = self.filtered.len();
        let start = self.sel.saturating_sub(list_rows / 2).min(n.saturating_sub(list_rows));
        let mut spinners = Vec::new();
        for r in 0..list_rows {
            let i = start + r; if i >= n { break; }
            let e = &entries[self.filtered[i]];
            let is_sel = i == self.sel;
            let y = ((MY + 2.0 + r as f64) * lh + asc) as f32;
            if e.running() > 0 { spinners.push(((mx as f64 + cw / 2.0) as f32, (y as f64 - asc + lh / 2.0) as f32)); }
            let marks = data::fuzzy(&self.query, &e.name).map(|(_, m)| m).unwrap_or_default();
            g.text(fonts, (mx as f64 + 2.0 * cw) as f32, y, &e.name, if is_sel { &sel } else { &fg }, 1.0, &marks);
            let tw = (e.tag.chars().count() as f64 * cw) as f32;
            g.text(fonts, right - tw, y, &e.tag, if is_sel { &sel } else { &comment }, if is_sel { 0.6 } else { 1.0 }, &[]);
        }

        // status
        let msg = if self.flash.is_empty() { "enter: launch   shift+enter: launch, stay   ctrl+x: stop   esc: close" } else { self.flash.as_str() };
        g.text(fonts, mx, ((rows - 1) as f64 * lh + asc) as f32, msg, &comment, 1.0, &[]);

        g.flush_text();
        for (cx, cy) in spinners { g.spinner(cx, cy, (lh * 0.9) as f32, self.tick, &border); }
    }
}
