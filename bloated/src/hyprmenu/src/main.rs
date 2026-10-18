//! hyprmenu — resident fuzzy launcher for Hyprland.
//!
//!   hyprmenu            toggle the launcher (starts the daemon if it isn't running)
//!   hyprmenu help       toggle the keyboard cheatsheet (SUPER+H)
//!   hyprmenu daemon     run the resident process (exec-once in hyprland.conf)
//!   hyprmenu quit       stop the daemon
//!
//! The daemon keeps the Wayland connection, GL context, font atlas and the flatpak
//! state warm, so a toggle shows a window in the time of one frame.

mod daemon;
mod data;
mod gfx;
mod help;
mod text;
mod ui;

use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

pub fn runtime_dir() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/tmp"))
}
pub fn socket_path() -> PathBuf {
    runtime_dir().join("hyprmenu.sock")
}

fn send(msg: &str) -> std::io::Result<String> {
    let mut s = UnixStream::connect(socket_path())?;
    s.set_read_timeout(Some(Duration::from_secs(2)))?;
    s.write_all(msg.as_bytes())?;
    s.write_all(b"\n")?;
    let mut reply = String::new();
    s.read_to_string(&mut reply)?;
    Ok(reply)
}

fn spawn_daemon() -> std::io::Result<()> {
    let exe = std::env::current_exe()?;
    let log = std::fs::File::create(runtime_dir().join("hyprmenu.log"))?;
    let mut cmd = Command::new(exe);
    cmd.arg("daemon").stdin(Stdio::null()).stdout(Stdio::null()).stderr(log);
    // own session so it survives whatever spawned the toggle
    unsafe { cmd.pre_exec(|| { libc::setsid(); Ok(()) }); }
    cmd.spawn()?;
    Ok(())
}

fn client(msg: &str) {
    match send(msg) {
        Ok(_) => return,
        Err(_) if msg == "quit" => { eprintln!("hyprmenu: no daemon running"); return; }
        Err(_) => {}
    }
    if let Err(e) = spawn_daemon() { eprintln!("hyprmenu: cannot start daemon: {e}"); std::process::exit(1); }
    let deadline = Instant::now() + Duration::from_secs(3);
    while Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(20));
        if send(msg).is_ok() { return; }
    }
    eprintln!("hyprmenu: daemon did not come up; see {}", runtime_dir().join("hyprmenu.log").display());
    std::process::exit(1);
}

fn main() {
    let arg = std::env::args().nth(1);
    match arg.as_deref() {
        None | Some("toggle") => client("toggle"),
        Some("show") => client("show"),
        Some("hide") => client("hide"),
        Some("help") => client("help"),
        Some("quit") => client("quit"),
        Some("daemon") => {
            if let Err(e) = daemon::run() { eprintln!("hyprmenu daemon: {e}"); std::process::exit(1); }
        }
        Some(x) => { eprintln!("hyprmenu: unknown command {x}\nusage: hyprmenu [toggle|show|hide|help|quit|daemon]"); std::process::exit(2); }
    }
}
