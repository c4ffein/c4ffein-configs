//! Hyprland keyboard cheatsheet (SUPER+H): a second window mode of the daemon.
//! The window is sized from the font so the text sits centered with a margin.

use crate::gfx::{Gfx, Rgb};
use crate::text::Fonts;

pub const APP_ID: &str = "hypr-help"; // hyprland.conf: float + center on this class
pub const MX: f64 = 4.0; // margin, in cells
pub const MY: f64 = 2.0; // margin, in rows
const FG: u32 = 0xd8d8d8;
const FRAME: u32 = 0x6272a4; // box drawing, same as the launcher's separator

pub const TEXT: &str = "\
╔════════════════════════════════════════════════════════════╗
║           HYPRLAND KEYBOARD SHORTCUTS (SUPER = ⊞)          ║
╚════════════════════════════════════════════════════════════╝

┌─ APPLICATIONS ─────────────────────────────────────────────┐
│ SUPER + T        Open terminal (alacritty)                 │
│ SUPER + A        Open audio mixer (pulsemixer)             │
│ SUPER + B        Open browser (LibreWolf)                  │
│ SUPER + C        Open Discord                              │
│ SUPER + R/Enter  Open app launcher (hyprmenu)              │
│ SUPER + H        Show this help                            │
│ SUPER + Space    Toggle keyboard layout (us/fr)            │
└────────────────────────────────────────────────────────────┘

┌─ WINDOW MANAGEMENT ────────────────────────────────────────┐
│ SUPER + Q        Close active window                       │
│ SUPER + V        Toggle floating mode                      │
│ SUPER + P        Toggle pseudo-tiling (dwindle)            │
│ SUPER + D        Toggle split direction (dwindle)          │
│ SUPER + F        Maximize (SHIFT: fullscreen)              │
│ SUPER + M        Exit Hyprland                             │
└────────────────────────────────────────────────────────────┘

┌─ FOCUS & NAVIGATION ───────────────────────────────────────┐
│ SUPER + Tab            Cycle to next window                │
│ SUPER + SHIFT + Tab    Cycle to previous window            │
│ SUPER + ←/→/↑/↓        Move focus between windows          │
│ SUPER + I/K/J/L        Move focus (vim-style: up/dn/lt/rt) │
│ SUPER + 1-9/0          Switch to workspace 1-10            │
│ SUPER + S              Toggle special workspace            │
│ SUPER + Scroll         Cycle through workspaces            │
└────────────────────────────────────────────────────────────┘

┌─ MOVE WINDOWS ─────────────────────────────────────────────┐
│ SUPER + SHIFT + ←→↑↓   Move window in workspace            │
│ SUPER + SHIFT + IKJL   Move window (vim-style)             │
│ SUPER + SHIFT + 1-9/0  Move window to workspace 1-10       │
│ SUPER + SHIFT + S      Move window to special workspace    │
│ SUPER + LMB (drag)     Move window                         │
│ SUPER + RMB (drag)     Resize window                       │
└────────────────────────────────────────────────────────────┘";

/// Content size in cells: (columns, rows).
pub fn cells() -> (usize, usize) {
    let lines: Vec<&str> = TEXT.lines().collect();
    (lines.iter().map(|l| l.chars().count()).max().unwrap_or(0), lines.len())
}

/// Window size in logical pixels for the current font metrics (which are in physical px at `scale`).
pub fn logical_size(fonts: &Fonts, scale: f64) -> (i32, i32) {
    let (cols, rows) = cells();
    let w = (cols as f64 + 2.0 * MX) * fonts.cell_w / scale;
    let h = (rows as f64 + 2.0 * MY) * fonts.line_h / scale;
    (w.ceil() as i32, h.ceil() as i32)
}

fn is_frame(c: char) -> bool { ('\u{2500}'..='\u{257f}').contains(&c) }

pub fn paint(g: &mut Gfx, fonts: &Fonts, pw: i32, ph: i32) {
    let (cols, rows) = cells();
    let (cw, lh, asc) = (fonts.cell_w, fonts.line_h, fonts.ascent);
    // center in whatever size we actually got
    let x0 = ((pw as f64 - cols as f64 * cw) / 2.0).max(0.0).floor() as f32;
    let y0 = ((ph as f64 - rows as f64 * lh) / 2.0).max(0.0).floor();
    let (fg, frame) = (Rgb(FG), Rgb(FRAME));
    for (r, line) in TEXT.lines().enumerate() {
        let y = (y0 + r as f64 * lh + asc) as f32;
        // split into runs of frame vs text so each run keeps its own color
        let mut run = String::new();
        let mut run_frame = false;
        let mut x = x0;
        let mut flush = |run: &mut String, run_frame: bool, x: &mut f32| {
            if run.is_empty() { return; }
            *x += g.text(fonts, *x, y, run, if run_frame { &frame } else { &fg }, 1.0, &[]);
            run.clear();
        };
        for c in line.chars() {
            let f = is_frame(c);
            if f != run_frame { flush(&mut run, run_frame, &mut x); run_frame = f; }
            run.push(c);
        }
        flush(&mut run, run_frame, &mut x);
    }
    g.flush_text();
}
