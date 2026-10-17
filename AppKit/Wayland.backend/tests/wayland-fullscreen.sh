#!/bin/sh
# Builds tests/wayland-fullscreen.c and runs it against a private headless sway
# with two outputs. Needs sway, swaymsg, jq, wayland-scanner, wayland-protocols and
# a C compiler. Sway gets its own runtime directory and picks its own socket name;
# nothing of the running desktop session is used or touched.
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

for tool in sway swaymsg jq wayland-scanner pkg-config cc; do
    command -v "$tool" >/dev/null || { echo "need $tool" >&2; exit 2; }
done

protocols=$(pkg-config --variable=pkgdatadir wayland-protocols)
wayland-scanner client-header "$protocols/stable/xdg-shell/xdg-shell.xml" "$work/xdg-shell-client-protocol.h"
wayland-scanner private-code "$protocols/stable/xdg-shell/xdg-shell.xml" "$work/xdg-shell.c"
cc -Wall -I"$work" -o "$work/test" "$here/wayland-fullscreen.c" "$work/xdg-shell.c" \
    $(pkg-config --cflags --libs wayland-client xkbcommon wayland-cursor wayland-egl) -lm

mkdir -m 700 "$work/run"
cat > "$work/sway.conf" <<CONF
default_border none
output HEADLESS-1 mode 1280x720 pos 1920 0
output HEADLESS-2 mode 1920x1080 pos 0 0
for_window [app_id="wl-fs-test"] floating enable
exec swaymsg create_output
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
i=0
while [ "$(swaymsg -t get_outputs 2>/dev/null | grep -c '"name"')" -lt 2 ]; do
    i=$((i + 1)); [ $i -gt 100 ] && { echo "second output did not appear" >&2; exit 2; }
    sleep 0.1
done
"$work/test"
