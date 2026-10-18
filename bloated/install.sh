#!/bin/sh
# Install the "bloated" Hyprland desktop on Alpine from this repo.
#
#   ./install.sh            check packages (installing missing ones as root), deploy dotfiles,
#                           build hyprmenu and the Mono cursor theme, reload Hyprland
#   ./install.sh --link     same, but symlink dotfiles into $HOME instead of copying them
#   ./install.sh check      only report missing packages / tools / fonts
#   ./install.sh diff       show how the live files in $HOME differ from the repo
#
# Safe to re-run. A live file that differs from the repo is moved to <file>.bak.<timestamp>
# before being replaced, so local edits are never lost: run `diff` first to pull them back.
# GPU / audio drivers and flatpaks stay in .local/bin/install-root and install-user.

set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
BUILD_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/c4ffein-configs
STAMP=$(date +%Y%m%d-%H%M%S)

# desktop + tools the configs call
PKGS="hyprland alacritty swaybg dbus pipewire wireplumber pipewire-pulse pulsemixer flatpak
      fontconfig python3 chromium git curl unzip"
# hyprmenu build and runtime (libEGL / libwayland are dlopen'ed)
PKGS="$PKGS gcc musl-dev pkgconf freetype-dev libxkbcommon-dev
      mesa-egl mesa-gles wayland-libs-client wayland-libs-egl"
OPTIONAL="grim slurp"                  # screenshots: nice to have, not required
FONT="Hack Nerd Font"                  # alacritty + hyprmenu; install-user downloads it

say()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }

find_cargo() {
    for c in cargo "$HOME/.cargo/bin/cargo"; do
        command -v "$c" >/dev/null 2>&1 && { command -v "$c"; return; }
    done
}

missing_pkgs() {
    m=""
    for p in $PKGS; do apk info -e "$p" >/dev/null 2>&1 || m="$m $p"; done
    [ -n "$(find_cargo)" ] || m="$m rust cargo"     # rustup in ~/.cargo is fine too
    echo $m
}

as_root() {
    if   [ "$(id -u)" = 0 ];               then "$@"
    elif command -v doas >/dev/null 2>&1;  then doas "$@"
    elif command -v sudo >/dev/null 2>&1;  then sudo "$@"
    else echo "root password for: $*" >&2; su -c "$*"
    fi
}

check() {
    say "Checking packages"
    m=$(missing_pkgs)
    if [ -n "$m" ]; then warn "missing:$m"; else echo "  all required packages present"; fi
    for p in $OPTIONAL; do apk info -e "$p" >/dev/null 2>&1 || echo "  optional, not installed: $p"; done
    command -v bun >/dev/null 2>&1 || [ -x "$HOME/.bun/bin/bun" ] || echo "  optional, not installed: bun (only install-user uses it)"
    if fc-match -f '%{family}' "$FONT" 2>/dev/null | grep -q "$FONT"; then echo "  font ok: $FONT"
    else warn "font '$FONT' not found: run .local/bin/install-user or unpack Hack.zip into ~/.local/share/fonts"; fi
    [ -z "$m" ]
}

# every tracked dotfile, relative to bloated/ (src/ and this script are not deployed)
dotfiles() { cd "$HERE" && find .config .local -type f | sort; }

diff_live() {
    dotfiles | while read -r f; do
        if [ ! -e "$HOME/$f" ]; then echo "only in repo: $f"
        elif ! cmp -s "$HERE/$f" "$HOME/$f"; then diff -u "$HERE/$f" "$HOME/$f" --label "repo/$f" --label "live/$f" || true
        fi
    done
}

deploy() {
    say "Deploying dotfiles ($MODE)"
    dotfiles | while read -r f; do
        src="$HERE/$f"; dst="$HOME/$f"
        [ "$MODE" = link ] && [ "$(readlink "$dst" 2>/dev/null)" = "$src" ] && continue
        [ "$MODE" = copy ] && cmp -s "$src" "$dst" 2>/dev/null && [ ! -L "$dst" ] && continue
        mkdir -p "$(dirname "$dst")"
        if [ -e "$dst" ] || [ -L "$dst" ]; then
            if ! cmp -s "$src" "$dst" 2>/dev/null; then mv "$dst" "$dst.bak.$STAMP"; warn "$f differed, kept as $f.bak.$STAMP"
            else rm -f "$dst"; fi
        fi
        if [ "$MODE" = link ]; then ln -s "$src" "$dst"; else cp -p "$src" "$dst"; fi
        echo "  $f"
    done
}

build_hyprmenu() {
    say "Building hyprmenu"
    cargo=$(find_cargo)
    CARGO_TARGET_DIR="$BUILD_DIR/hyprmenu-target" "$cargo" build --release --locked \
        --manifest-path "$HERE/src/hyprmenu/Cargo.toml"
    install -Dm755 "$BUILD_DIR/hyprmenu-target/release/hyprmenu" "$HOME/.local/bin/hyprmenu"
    # the running daemon keeps the old binary; the next Super+R starts the new one
    pkill -x hyprmenu 2>/dev/null && echo "  stopped the old daemon" || true
}

build_cursors() {
    say "Building the Mono cursor theme"
    python3 "$HERE/.local/bin/mkcursors" build
}

reload() {
    [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || { echo "  not inside Hyprland: log in to apply"; return; }
    say "Reloading Hyprland"
    hyprctl reload >/dev/null && hyprctl setcursor Mono 32 >/dev/null && echo "  done (log out and back in once so XWayland apps get the cursor)"
}

MODE=copy
CMD=install
for a in "$@"; do
    case $a in
        --link) MODE=link ;;
        check|diff|install) CMD=$a ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "unknown argument: $a" >&2; exit 2 ;;
    esac
done

case $CMD in
    check) check ;;
    diff)  diff_live ;;
    install)
        if ! check; then
            say "Installing missing packages"
            m=$(missing_pkgs)
            as_root apk add $m
        fi
        deploy
        build_hyprmenu
        build_cursors
        reload
        ;;
esac
