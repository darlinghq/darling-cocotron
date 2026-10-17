#!/bin/sh
# Builds tests/wayland-pointer-lock.c and runs it against a private headless sway.
# Needs sway, swaymsg, wayland-scanner, wayland-protocols, wlr-protocols (for the
# virtual pointer) and a C compiler. Sway gets its own runtime directory and picks
# its own socket name; nothing of the running desktop session is used or touched.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# A Wayland socket path is limited to 107 bytes: keep TMPDIR short.
work=$(mktemp -d)
sway_pid=
cleanup() {
    if [ -n "$sway_pid" ]; then
        kill "$sway_pid" 2>/dev/null || true
        i=0
        while kill -0 "$sway_pid" 2>/dev/null && [ $i -lt 30 ]; do i=$((i + 1)); sleep 0.1; done
        kill -9 "$sway_pid" 2>/dev/null || true
    fi
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

wp=$(pkg-config --variable=pkgdatadir wayland-protocols)
wlr=${WLR_PROTOCOLS:-/usr/share/wlr-protocols}
for xml in "$wp/stable/xdg-shell/xdg-shell.xml" \
           "$wp/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml" \
           "$wp/unstable/relative-pointer/relative-pointer-unstable-v1.xml" \
           "$wlr/unstable/wlr-virtual-pointer-unstable-v1.xml"; do
    name=$(basename "$xml" .xml)
    wayland-scanner client-header "$xml" "$work/$name-client-protocol.h"
    wayland-scanner private-code "$xml" "$work/$name.c"
done
cc -Wall -I"$work" -o "$work/test" "$here/wayland-pointer-lock.c" "$work"/*.c \
    $(pkg-config --cflags --libs wayland-client xkbcommon wayland-cursor wayland-egl) -lm

mkdir -m 700 "$work/run"
cat > "$work/sway.conf" <<CONF
default_border none
default_floating_border none
output HEADLESS-1 mode 1280x720 pos 0 0
for_window [app_id="wl-lock-test"] floating enable
CONF
unset DISPLAY WAYLAND_DISPLAY SWAYSOCK I3SOCK
export XDG_RUNTIME_DIR="$work/run" WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
sway -c "$work/sway.conf" > "$work/sway.log" 2>&1 &
sway_pid=$!
i=0
socket=
while :; do
    socket=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'wayland-*' | head -n 1)
    [ -n "$socket" ] && [ -n "$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null)" ] && break
    i=$((i + 1)); [ $i -gt 100 ] && { cat "$work/sway.log"; echo "sway did not start" >&2; exit 2; }
    sleep 0.1
done
export WAYLAND_DISPLAY=$(basename "$socket")
export SWAYSOCK=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock)
"$work/test"
