#!/bin/bash
# Copyright (C) 2026 Darling Developers
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Runs fractional-live.m or fractional-crop.m on a private headless sway whose output scale is stepped through
# 1.25, 1.5 and 2.25 while the window stays open, and checks what the compositor really shows:
#  - the fixture's own checks (backing scale factor, drawable size, redraw and reshape after every step);
#  - the window rectangle and pixels of a screenshot of each step (fractional-pixels.py or
#    fractional-crop-pixels.py; ImageMagick and grim are needed);
#  - for "crop" the client's wire trace (WAYLAND_DEBUG=client): buffer size, wp_viewport source and destination of
#    every surface (fractional-wire.py).
# The window scale factor is the output's scale rounded up to a whole number (NSWindow and NSScreen report whole
# scale factors); the buffers are drawn at that scale and shown at the logical size through wp_viewport.
# Needs sway, swaymsg, grim, magick and python3. Nothing of the running desktop session is used or touched.
#   fractional-run.sh <live|crop> <runner> <guest binary>
# <runner> runs a guest command (for example "darling shell"); the guest binary is the host path of the program
# built from fractional-live.m or fractional-crop.m (linked with -framework AppKit -framework OpenGL), run as
# <runner> env VAR=... /Volumes/SystemRoot<path>.
set -u
kind=${1:-}
runner=${2:-}
binary=${3:-}
case $kind in live|crop) ;; *) kind= ;; esac
[ -n "$kind" ] && [ -n "$runner" ] && [ -n "$binary" ] || { echo "usage: $0 <live|crop> <runner> <guest binary>" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
guest_root=${GUEST_ROOT:-/Volumes/SystemRoot}
# A Wayland socket path is limited to 107 bytes: keep the directory short.
work=$(mktemp -d)
sway_pid=
guest_pid=
cleanup() {
    [ -n "$guest_pid" ] && kill "$guest_pid" 2>/dev/null
    [ -n "$sway_pid" ] && kill "$sway_pid" 2>/dev/null
    wait 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT INT TERM
for tool in sway swaymsg grim magick python3; do
    command -v "$tool" >/dev/null || { echo "need $tool" >&2; exit 2; }
done

mkdir -m 700 "$work/run"
cat > "$work/sway.conf" <<CONF
default_border none
default_floating_border none
for_window [shell=".*"] floating enable, move position 50 50
output * resolution 2560x1440 scale 1.25
output * bg #000000 solid_color
CONF
unset DISPLAY WAYLAND_DISPLAY SWAYSOCK I3SOCK
export XDG_RUNTIME_DIR="$work/run" WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
sway -c "$work/sway.conf" > "$work/sway.log" 2>&1 &
sway_pid=$!
socket=
for _ in $(seq 100); do
    socket=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'wayland-*' | head -n 1)
    [ -n "$socket" ] && [ -n "$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null)" ] && break
    sleep 0.1
done
[ -n "$socket" ] || { cat "$work/sway.log"; echo "sway did not start" >&2; exit 2; }
export WAYLAND_DISPLAY="$socket" SWAYSOCK=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock)
mkdir "$work/cap"
echo 0 > "$work/control"

$runner env DARLING_APPKIT_BACKEND=wayland WAYLAND_DISPLAY="$WAYLAND_DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    WAYLAND_DEBUG=client FRACTIONAL_CONTROL="$guest_root$work/control" \
    "$guest_root$binary" > "$work/guest.out" 2>&1 < /dev/null &
guest_pid=$!

status=0
stage=0
for scale in 1.25 1.5 2.25; do
    # the fixture says CAPTURE <stage> when its own checks are done and the compositor shows the new scale
    for _ in $(seq 600); do
        grep -q "^CAPTURE $stage\$" "$work/guest.out" && break
        kill -0 "$guest_pid" 2>/dev/null || break
        sleep 0.25
    done
    if ! grep -q "^CAPTURE $stage\$" "$work/guest.out"; then
        tail -n 5 "$work/guest.out"
        if kill -0 "$guest_pid" 2>/dev/null; then kill "$guest_pid"; else wait "$guest_pid"; echo "the guest exited with status $?"; fi
        echo "FAIL: the fixture did not reach stage $stage"; status=1; break
    fi
    swaymsg -t get_tree > "$work/cap/scale-$scale-tree.json"
    grim "$work/cap/scale-$scale.png"
    stage=$((stage + 1))
    next=$(grep '^SCALE_READY ' "$work/guest.out" | sed -n "${stage}p" | cut -d' ' -f2)
    [ -n "$next" ] && swaymsg "output * scale $next" > /dev/null
    sleep 0.5
    echo "$stage" > "$work/control"
done
wait "$guest_pid"
guest_status=$?

grep -E '^(CHECK FAIL|DRAWABLE|RESULT)' "$work/guest.out"
[ "$guest_status" = 0 ] && echo "PASS: the fixture's own checks" || { echo "FAIL: the fixture's own checks"; status=1; }
pixels=fractional-pixels.py; [ "$kind" = crop ] && pixels=fractional-crop-pixels.py
if python3 -I "$here/$pixels" "$work/cap" > "$work/pixels.json" 2> "$work/pixels.err"; then
    echo "PASS: the compositor shows the expected pixels at every step"
else
    tail -n 3 "$work/pixels.err"; echo "FAIL: the compositor shows the expected pixels at every step"; status=1
fi
if [ "$kind" = crop ]; then
    if python3 -I "$here/fractional-wire.py" "$work/guest.out" > "$work/wire.json" 2> "$work/wire.err"; then
        echo "PASS: the client's buffers, sources and destinations match"
    else
        tail -n 3 "$work/wire.err"; echo "FAIL: the client's buffers, sources and destinations match"; status=1
    fi
fi
[ "$status" = 0 ] && echo PASS || echo FAIL
exit "$status"
