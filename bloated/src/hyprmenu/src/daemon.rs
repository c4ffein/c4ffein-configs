//! The resident process: Wayland connection, window show/hide, control socket,
//! inotify on flatpak's instance directory, timers. One thread, one poll loop.

use crate::data::{self, Entry};
use crate::gfx::{Gfx, Rgb, Surface};
use crate::help;
use crate::text::Fonts;
use crate::ui::{self, Action, Key, Ui};
use inotify::{Inotify, WatchMask};
use std::io::{BufRead, BufReader, Write};
use std::os::fd::AsRawFd;
use std::os::unix::net::UnixListener;
use std::time::{Duration, Instant};
use wayland_client::globals::{registry_queue_init, GlobalListContents};
use wayland_client::protocol::{wl_callback, wl_compositor, wl_keyboard, wl_registry, wl_seat, wl_surface};
use wayland_client::{delegate_noop, Connection, Dispatch, EventQueue, QueueHandle, WEnum};
use wayland_protocols::wp::fractional_scale::v1::client::{wp_fractional_scale_manager_v1, wp_fractional_scale_v1};
use wayland_protocols::wp::viewporter::client::{wp_viewport, wp_viewporter};
use wayland_protocols::xdg::shell::client::{xdg_surface, xdg_toplevel, xdg_wm_base};
use xkbcommon::xkb;

pub const APP_ID: &str = "hyprmenu"; // the hyprland.conf window rules match this class
const DEFAULT_W: i32 = 720;
const DEFAULT_H: i32 = 440;
const SPIN: Duration = Duration::from_millis(90);
const RELIST: Duration = Duration::from_secs(60); // flatpak list (installs/removals) is also refreshed on inotify

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Mode { Launcher, Help }

struct Window {
    mode: Mode,
    surface: wl_surface::WlSurface,
    xdg_surface: xdg_surface::XdgSurface,
    toplevel: xdg_toplevel::XdgToplevel,
    viewport: Option<wp_viewport::WpViewport>,
    fscale: Option<wp_fractional_scale_v1::WpFractionalScaleV1>,
    gl: Option<Surface>,
    configured: bool,
    frame_pending: bool,
    lw: i32, lh: i32,
}

struct State {
    qh: QueueHandle<State>,
    compositor: wl_compositor::WlCompositor,
    wm_base: xdg_wm_base::XdgWmBase,
    viewporter: Option<wp_viewporter::WpViewporter>,
    fsm: Option<wp_fractional_scale_manager_v1::WpFractionalScaleManagerV1>,
    keyboard: Option<wl_keyboard::WlKeyboard>,
    xkb_ctx: xkb::Context,
    keymap: Option<xkb::Keymap>,
    xkb_state: Option<xkb::State>,
    repeat: (i32, i32), // rate, delay
    repeat_key: Option<(xkb::Keycode, Instant)>,
    scale: f64,
    fonts: Fonts,
    gfx: Option<Gfx>,
    window: Option<Window>,
    entries: Vec<Entry>,
    ui: Ui,
    dirty: bool,
    running: bool,
    next_spin: Instant,
    next_relist: Instant,
    pending_ps: Option<Instant>, // debounce for inotify-triggered `flatpak ps`
}

impl State {
    fn mode(&self) -> Option<Mode> { self.window.as_ref().map(|w| w.mode) }

    fn show(&mut self, conn: &Connection, mode: Mode) -> Result<(), String> {
        if self.mode() == Some(mode) { return Ok(()); }
        self.hide(); // a window of the other mode: replace it
        if self.gfx.is_none() {
            let ptr = conn.backend().display_ptr() as *mut std::ffi::c_void;
            let mut g = Gfx::new(ptr)?;
            g.atlas_reset();
            self.gfx = Some(g);
        }
        let (app_id, (lw, lh)) = match mode {
            Mode::Launcher => { self.ui.reset(&self.entries); (APP_ID, (DEFAULT_W, DEFAULT_H)) }
            Mode::Help => (help::APP_ID, help::logical_size(&self.fonts, self.scale)),
        };
        let surface = self.compositor.create_surface(&self.qh, ());
        let fscale = self.fsm.as_ref().map(|m| m.get_fractional_scale(&surface, &self.qh, ()));
        let viewport = self.viewporter.as_ref().map(|v| v.get_viewport(&surface, &self.qh, ()));
        let xdg_surface = self.wm_base.get_xdg_surface(&surface, &self.qh, ());
        let toplevel = xdg_surface.get_toplevel(&self.qh, ());
        toplevel.set_app_id(app_id.into());
        toplevel.set_title(app_id.into());
        xdg_surface.set_window_geometry(0, 0, lw, lh);
        surface.commit();
        self.window = Some(Window { mode, surface, xdg_surface, toplevel, viewport, fscale, gl: None, configured: false, frame_pending: false, lw, lh });
        Ok(())
    }

    fn toggle(&mut self, conn: &Connection, mode: Mode) -> &'static str {
        if self.mode() == Some(mode) { self.hide(); return "hidden"; }
        match self.show(conn, mode) { Ok(()) => "shown", Err(e) => { eprintln!("{e}"); "error" } }
    }

    fn hide(&mut self) {
        let Some(w) = self.window.take() else { return };
        if let (Some(g), Some(s)) = (self.gfx.as_mut(), w.gl) { g.destroy_surface(s); }
        if let Some(f) = w.fscale { f.destroy(); }
        if let Some(v) = w.viewport { v.destroy(); }
        w.toplevel.destroy();
        w.xdg_surface.destroy();
        w.surface.destroy();
        self.repeat_key = None;
    }

    fn render(&mut self) {
        let Some(w) = self.window.as_mut() else { return };
        if !w.configured || w.frame_pending { return; }
        let Some(g) = self.gfx.as_mut() else { return };
        let (pw, ph) = ((w.lw as f64 * self.scale).round() as i32, (w.lh as f64 * self.scale).round() as i32);
        if w.gl.is_none() {
            match g.create_surface(&w.surface, pw, ph) { Ok(s) => w.gl = Some(s), Err(e) => { eprintln!("{e}"); return; } }
        }
        let s = w.gl.as_mut().unwrap();
        g.resize(s, pw, ph);
        g.begin(s, Rgb(ui::BG), ui::BG_ALPHA);
        match w.mode {
            Mode::Launcher => self.ui.paint(g, &self.fonts, &self.entries, pw, ph, self.scale),
            Mode::Help => help::paint(g, &self.fonts, pw, ph),
        }
        if let Some(v) = &w.viewport { v.set_destination(w.lw, w.lh); }
        w.surface.frame(&self.qh, ());
        w.frame_pending = true;
        self.dirty = false;
        if let Err(e) = g.end(s) { eprintln!("{e}"); }
    }

    fn set_scale(&mut self, s: f64) {
        if (s - self.scale).abs() < 1e-6 { return; }
        self.scale = s;
        if let Err(e) = self.fonts.set_scale(s) { eprintln!("{e}"); }
        if let Some(g) = self.gfx.as_mut() { g.atlas_reset(); }
        self.dirty = true;
    }

    fn key(&mut self, code: xkb::Keycode) {
        let Some(st) = self.xkb_state.as_ref() else { return };
        let sym = st.key_get_one_sym(code);
        if self.mode() == Some(Mode::Help) {
            // any key closes, except a bare modifier (Super is usually still held from the bind)
            if !(xkb::Keysym::Shift_L..=xkb::Keysym::Hyper_R).contains(&sym) { self.hide(); }
            return;
        }
        let ctrl = st.mod_name_is_active(xkb::MOD_NAME_CTRL, xkb::STATE_MODS_EFFECTIVE);
        let shift = st.mod_name_is_active(xkb::MOD_NAME_SHIFT, xkb::STATE_MODS_EFFECTIVE);
        let k = match sym {
            xkb::Keysym::Escape => Key::Esc,
            xkb::Keysym::Return | xkb::Keysym::KP_Enter => Key::Enter,
            xkb::Keysym::Up => Key::Up,
            xkb::Keysym::Down => Key::Down,
            xkb::Keysym::BackSpace => Key::Backspace,
            _ if ctrl => match sym.key_char() { Some(c) => Key::Ctrl(c.to_ascii_lowercase()), None => return },
            _ => {
                let s = st.key_get_utf8(code);
                match s.chars().next() { Some(c) if !c.is_control() => Key::Char(c), _ => return }
            }
        };
        self.dirty = true;
        match self.ui.key(k, shift, &self.entries) {
            Action::Hide => self.hide(),
            Action::Launched | Action::Stopped => { self.pending_ps = Some(Instant::now() + Duration::from_millis(700)); }
            Action::Nothing => {}
        }
    }

    fn refresh_ps(&mut self) {
        if data::refresh_running(&mut self.entries) { self.ui.apply_filter(&self.entries); self.dirty = true; }
    }
    fn relist(&mut self) {
        let mut fresh = data::load_entries();
        for e in fresh.iter_mut() { if let Some(old) = self.entries.iter().find(|o| o.id == e.id) { e.instances = old.instances.clone(); } }
        self.entries = fresh;
        self.ui.apply_filter(&self.entries);
        self.dirty = true;
    }
}

// ---------------------------------------------------------------- wayland dispatch

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for State {
    fn event(_: &mut Self, _: &wl_registry::WlRegistry, _: wl_registry::Event, _: &GlobalListContents, _: &Connection, _: &QueueHandle<Self>) {}
}
delegate_noop!(State: ignore wl_compositor::WlCompositor);
delegate_noop!(State: ignore wl_surface::WlSurface);
delegate_noop!(State: ignore wp_viewporter::WpViewporter);
delegate_noop!(State: ignore wp_viewport::WpViewport);
delegate_noop!(State: ignore wp_fractional_scale_manager_v1::WpFractionalScaleManagerV1);

impl Dispatch<xdg_wm_base::XdgWmBase, ()> for State {
    fn event(_: &mut Self, b: &xdg_wm_base::XdgWmBase, ev: xdg_wm_base::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {
        if let xdg_wm_base::Event::Ping { serial } = ev { b.pong(serial); }
    }
}
impl Dispatch<xdg_surface::XdgSurface, ()> for State {
    fn event(st: &mut Self, s: &xdg_surface::XdgSurface, ev: xdg_surface::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {
        if let xdg_surface::Event::Configure { serial } = ev {
            s.ack_configure(serial);
            if let Some(w) = st.window.as_mut() { if w.xdg_surface == *s { w.configured = true; st.dirty = true; } }
        }
    }
}
impl Dispatch<xdg_toplevel::XdgToplevel, ()> for State {
    fn event(st: &mut Self, t: &xdg_toplevel::XdgToplevel, ev: xdg_toplevel::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {
        match ev {
            xdg_toplevel::Event::Configure { width, height, .. } => {
                if let Some(w) = st.window.as_mut() {
                    if w.toplevel == *t && width > 0 && height > 0 && (w.lw, w.lh) != (width, height) { w.lw = width; w.lh = height; st.dirty = true; }
                }
            }
            xdg_toplevel::Event::Close => { if st.window.as_ref().map_or(false, |w| w.toplevel == *t) { st.hide(); } }
            _ => {}
        }
    }
}
impl Dispatch<wp_fractional_scale_v1::WpFractionalScaleV1, ()> for State {
    fn event(st: &mut Self, _: &wp_fractional_scale_v1::WpFractionalScaleV1, ev: wp_fractional_scale_v1::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {
        if let wp_fractional_scale_v1::Event::PreferredScale { scale } = ev { st.set_scale(scale as f64 / 120.0); }
    }
}
impl Dispatch<wl_callback::WlCallback, ()> for State {
    fn event(st: &mut Self, _: &wl_callback::WlCallback, ev: wl_callback::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {
        if let wl_callback::Event::Done { .. } = ev {
            if let Some(w) = st.window.as_mut() { w.frame_pending = false; }
            if st.dirty { st.render(); }
        }
    }
}
impl Dispatch<wl_seat::WlSeat, ()> for State {
    fn event(st: &mut Self, seat: &wl_seat::WlSeat, ev: wl_seat::Event, _: &(), _: &Connection, qh: &QueueHandle<Self>) {
        if let wl_seat::Event::Capabilities { capabilities: WEnum::Value(caps) } = ev {
            let has = caps.contains(wl_seat::Capability::Keyboard);
            if has && st.keyboard.is_none() { st.keyboard = Some(seat.get_keyboard(qh, ())); }
            if !has { if let Some(k) = st.keyboard.take() { k.release(); } }
        }
    }
}
impl Dispatch<wl_keyboard::WlKeyboard, ()> for State {
    fn event(st: &mut Self, _: &wl_keyboard::WlKeyboard, ev: wl_keyboard::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {
        use wl_keyboard::Event::*;
        match ev {
            Keymap { format: WEnum::Value(wl_keyboard::KeymapFormat::XkbV1), fd, size } => {
                match unsafe { xkb::Keymap::new_from_fd(&st.xkb_ctx, fd, size as usize, xkb::KEYMAP_FORMAT_TEXT_V1, xkb::KEYMAP_COMPILE_NO_FLAGS) } {
                    Ok(Some(km)) => { st.xkb_state = Some(xkb::State::new(&km)); st.keymap = Some(km); }
                    _ => eprintln!("bad keymap"),
                }
            }
            Key { key, state: WEnum::Value(ks), .. } => {
                let code = xkb::Keycode::new(key + 8);
                if ks == wl_keyboard::KeyState::Pressed {
                    st.key(code);
                    let repeats = st.keymap.as_ref().map_or(false, |k| k.key_repeats(code));
                    if repeats && st.repeat.0 > 0 { st.repeat_key = Some((code, Instant::now() + Duration::from_millis(st.repeat.1.max(0) as u64))); }
                } else if st.repeat_key.map_or(false, |(c, _)| c == code) { st.repeat_key = None; }
            }
            Modifiers { mods_depressed, mods_latched, mods_locked, group, .. } => {
                if let Some(s) = st.xkb_state.as_mut() { s.update_mask(mods_depressed, mods_latched, mods_locked, 0, 0, group); }
            }
            RepeatInfo { rate, delay } => st.repeat = (rate, delay),
            Leave { .. } => st.repeat_key = None,
            _ => {}
        }
    }
}

// ---------------------------------------------------------------- control socket

fn bind_socket() -> std::io::Result<UnixListener> {
    let path = crate::socket_path();
    if std::os::unix::net::UnixStream::connect(&path).is_ok() {
        return Err(std::io::Error::new(std::io::ErrorKind::AddrInUse, "another hyprmenu daemon is running"));
    }
    let _ = std::fs::remove_file(&path);
    let l = UnixListener::bind(&path)?;
    l.set_nonblocking(true)?;
    Ok(l)
}

fn watch_flatpak(ino: &mut Inotify) {
    let inst = crate::runtime_dir().join(".flatpak");
    let _ = std::fs::create_dir_all(&inst);
    if let Err(e) = ino.watches().add(&inst, WatchMask::CREATE | WatchMask::DELETE | WatchMask::MOVED_FROM | WatchMask::MOVED_TO) { eprintln!("inotify {}: {e}", inst.display()); }
    if let Some(home) = std::env::var_os("HOME") {
        let apps = std::path::PathBuf::from(home).join(".local/share/flatpak/exports/share/applications");
        let _ = ino.watches().add(&apps, WatchMask::CREATE | WatchMask::DELETE | WatchMask::MOVED_FROM | WatchMask::MOVED_TO | WatchMask::CLOSE_WRITE);
    }
}

// ---------------------------------------------------------------- main loop

pub fn run() -> Result<(), String> {
    let listener = bind_socket().map_err(|e| e.to_string())?;
    let conn = Connection::connect_to_env().map_err(|e| format!("wayland: {e}"))?;
    let (globals, mut queue): (_, EventQueue<State>) = registry_queue_init(&conn).map_err(|e| format!("registry: {e}"))?;
    let qh = queue.handle();
    let compositor: wl_compositor::WlCompositor = globals.bind(&qh, 4..=6, ()).map_err(|e| format!("wl_compositor: {e}"))?;
    let wm_base: xdg_wm_base::XdgWmBase = globals.bind(&qh, 1..=6, ()).map_err(|e| format!("xdg_wm_base: {e}"))?;
    let _seat: wl_seat::WlSeat = globals.bind(&qh, 1..=9, ()).map_err(|e| format!("wl_seat: {e}"))?;
    let viewporter = globals.bind::<wp_viewporter::WpViewporter, _, _>(&qh, 1..=1, ()).ok();
    let fsm = globals.bind::<wp_fractional_scale_manager_v1::WpFractionalScaleManagerV1, _, _>(&qh, 1..=1, ()).ok();

    let mut ino = Inotify::init().map_err(|e| format!("inotify: {e}"))?;
    watch_flatpak(&mut ino);

    let mut entries = data::load_entries();
    data::refresh_running(&mut entries);
    let now = Instant::now();
    let mut st = State {
        qh: qh.clone(), compositor, wm_base, viewporter, fsm, keyboard: None,
        xkb_ctx: xkb::Context::new(xkb::CONTEXT_NO_FLAGS), keymap: None, xkb_state: None, repeat: (25, 400), repeat_key: None,
        scale: 1.0, fonts: Fonts::load()?, gfx: None, window: None, entries, ui: Ui::default(),
        dirty: false, running: true, next_spin: now + SPIN, next_relist: now + RELIST, pending_ps: None,
    };
    st.ui.apply_filter(&st.entries);
    eprintln!("hyprmenu daemon ready (pid {})", std::process::id());

    let mut ino_buf = [0u8; 4096];
    while st.running {
        // dispatch anything pending, render if needed, then flush before sleeping
        queue.dispatch_pending(&mut st).map_err(|e| format!("dispatch: {e}"))?;
        if st.dirty { st.render(); }
        let guard = loop {
            match queue.prepare_read() { Some(g) => break g, None => { queue.dispatch_pending(&mut st).map_err(|e| format!("dispatch: {e}"))?; } }
        };
        queue.flush().map_err(|e| format!("flush: {e}"))?;

        let now = Instant::now();
        let mut next = st.next_relist;
        if st.mode() == Some(Mode::Launcher) && st.ui.any_running(&st.entries) { next = next.min(st.next_spin); }
        if let Some((_, t)) = st.repeat_key { next = next.min(t); }
        if let Some(t) = st.pending_ps { next = next.min(t); }
        let timeout = next.saturating_duration_since(now).as_millis().min(i32::MAX as u128) as i32;

        let mut fds = [
            libc::pollfd { fd: guard.connection_fd().as_raw_fd(), events: libc::POLLIN, revents: 0 },
            libc::pollfd { fd: listener.as_raw_fd(), events: libc::POLLIN, revents: 0 },
            libc::pollfd { fd: ino.as_raw_fd(), events: libc::POLLIN, revents: 0 },
        ];
        let r = unsafe { libc::poll(fds.as_mut_ptr(), 3, timeout) };
        if r < 0 && std::io::Error::last_os_error().raw_os_error() != Some(libc::EINTR) { return Err("poll failed".into()); }

        if fds[0].revents & libc::POLLIN != 0 { guard.read().map_err(|e| format!("read: {e}"))?; } else { drop(guard); }
        queue.dispatch_pending(&mut st).map_err(|e| format!("dispatch: {e}"))?;

        if fds[1].revents & libc::POLLIN != 0 {
            while let Ok((stream, _)) = listener.accept() {
                let mut line = String::new();
                let _ = stream.set_read_timeout(Some(Duration::from_millis(200)));
                let _ = BufReader::new(&stream).read_line(&mut line);
                let cmd = line.trim();
                let reply = match cmd {
                    "toggle" => st.toggle(&conn, Mode::Launcher),
                    "help" => st.toggle(&conn, Mode::Help),
                    "show" => { match st.show(&conn, Mode::Launcher) { Ok(()) => "shown", Err(e) => { eprintln!("{e}"); "error" } } }
                    "hide" => { st.hide(); "hidden" }
                    "quit" => { st.running = false; "bye" }
                    _ => "unknown",
                };
                let _ = (&stream).write_all(reply.as_bytes());
            }
        }
        if fds[2].revents & libc::POLLIN != 0 {
            let mut relist = false;
            if let Ok(events) = ino.read_events(&mut ino_buf) {
                for ev in events { if ev.name.as_ref().map_or(false, |n| n.to_string_lossy().ends_with(".desktop")) { relist = true; } }
            }
            if relist { st.relist(); }
            // instance dirs appear/disappear slightly before `flatpak ps` reflects them
            st.pending_ps = Some(Instant::now() + Duration::from_millis(250));
        }

        let now = Instant::now();
        if let Some((code, t)) = st.repeat_key { if now >= t { st.key(code); let rate = st.repeat.0.max(1) as u64; st.repeat_key = st.repeat_key.map(|(c, _)| (c, now + Duration::from_millis(1000 / rate))); } }
        if st.mode() == Some(Mode::Launcher) && st.ui.any_running(&st.entries) && now >= st.next_spin { st.ui.tick += 1; st.next_spin = now + SPIN; st.dirty = true; }
        if st.pending_ps.map_or(false, |t| now >= t) { st.pending_ps = None; st.refresh_ps(); }
        if now >= st.next_relist { st.next_relist = now + RELIST; st.relist(); st.refresh_ps(); }
        if st.dirty { st.render(); }
    }
    st.hide();
    let _ = std::fs::remove_file(crate::socket_path());
    Ok(())
}
