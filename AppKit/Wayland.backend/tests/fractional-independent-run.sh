#!/bin/bash
# Copyright (C) 2026 Darling Developers
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Runs fractional-independent.m on a private headless sway with two outputs of different scales, 1.25 on the
# left and 2.25 on the right, and moves a window with two GL views between them:
#   0 the window on the left output          (window and views at the whole scale 2)
#   1 moved to the right output              (3)
#   2 moved across the border                (the left view is on the left output, 2; the right view on the right, 3)
#   3 moved back to the left output          (2)
#   4 hidden, the outputs swap their scales, shown again at its pinned position (now on the 2.25 output: 3)
#   5 the left view hidden, the scales swapped back, the view shown again (2)
# NSScreen and NSWindow report the output's scale rounded up to a whole number; the buffers are drawn at that
# scale and shown at the logical size through wp_viewport. The program checks the scales it is given, the drawable
# sizes, the redraw of every view whose scale changed and the GL result; this script checks, from the compositor's
# side, the wire trace (buffer, viewport destination and preferred scale of every surface: fractional-independent-wire.py)
# and the pixels of a capture of each output (fractional-independent-pixels.py; ImageMagick and grim are needed).
# Needs sway, swaymsg, grim, magick and python3. Nothing of the running desktop session is used or touched.
#   fractional-independent-run.sh <runner> <guest binary>
# <runner> runs a guest command (for example "darling shell"); the guest binary is the host path of the program
# built from fractional-independent.m (linked with -framework AppKit -framework OpenGL), run as
# <runner> env VAR=... /Volumes/SystemRoot<path>.
set -u
runner=${1:-}
binary=${2:-}
[ -n "$runner" ] && [ -n "$binary" ] || { echo "usage: $0 <runner> <guest binary>" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
guest_root=${GUEST_ROOT:-/Volumes/SystemRoot}
title="Independent fractional fixture"
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
# The window is pinned to the same layout position every time it is mapped (the left output).
cat > "$work/sway.conf" <<CONF
default_border none
default_floating_border none
for_window [shell=".*"] floating enable, move absolute position 50 50
output HEADLESS-1 resolution 1920x1080 position 0 0 scale 1.25
output HEADLESS-2 resolution 1920x1080 position 1536 0 scale 2.25
output * bg #000000 solid_color
CONF
unset DISPLAY WAYLAND_DISPLAY SWAYSOCK I3SOCK
export XDG_RUNTIME_DIR="$work/run" WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 WLR_HEADLESS_OUTPUTS=2
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
# wait_for_line <line> : until the fixture printed the line (fails when it exits first)
wait_for_line() {
    local _
    for _ in $(seq 600); do
        grep -q "^$1\$" "$work/guest.out" && return 0
        kill -0 "$guest_pid" 2>/dev/null || return 1
        sleep 0.25
    done
    return 1
}
fail_stage() {
    tail -n 5 "$work/guest.out"
    if kill -0 "$guest_pid" 2>/dev/null; then kill "$guest_pid"; else wait "$guest_pid"; echo "the guest exited with status $?"; fi
    echo "FAIL: the fixture did not reach $1"; status=1
}
move() { swaymsg "[title=\"$title\"] move absolute position $1 $2" > /dev/null; }
capture() {
    swaymsg -t get_tree > "$work/cap/phase-$1-tree.json"
    swaymsg -t get_outputs > "$work/cap/phase-$1-outputs.json"
    grim -o HEADLESS-1 "$work/cap/phase-$1-HEADLESS-1.png"
    grim -o HEADLESS-2 "$work/cap/phase-$1-HEADLESS-2.png"
}
stage=0
step() { stage=$((stage + 1)); sleep 0.5; echo "$stage" > "$work/control"; }
# The fixture says CAPTURE <phase> when its own checks of the phase are done and the compositor shows the result.
for phase in 0 1 2 3 4 5; do
    wait_for_line "CAPTURE $phase" || { fail_stage "phase $phase"; break; }
    capture "$phase"
    case $phase in
        0) move 1586 50 ;;
        1) move 1236 50 ;;
        2) move 50 50 ;;
        3) ;;
        4|5) ;;
    esac
    case $phase in
        3)
            step # the fixture hides the window
            wait_for_line PARENT_HIDDEN || { fail_stage "PARENT_HIDDEN"; break; }
            swaymsg "output HEADLESS-1 scale 2.25; output HEADLESS-2 scale 1.25" > /dev/null
            ;;
        4)
            step # the fixture hides the left view
            wait_for_line CHILD_HIDDEN || { fail_stage "CHILD_HIDDEN"; break; }
            swaymsg "output HEADLESS-1 scale 1.25; output HEADLESS-2 scale 2.25" > /dev/null
            ;;
    esac
    step
done
wait "$guest_pid"
guest_status=$?

grep -E '^(CHECK FAIL|INDEPENDENT|RESULT)' "$work/guest.out"
[ "$guest_status" = 0 ] && echo "PASS: the fixture's own checks" || { echo "FAIL: the fixture's own checks"; status=1; }
if python3 -I "$here/fractional-independent-pixels.py" "$work/cap" > "$work/pixels.json" 2> "$work/pixels.err"; then
    echo "PASS: the compositor shows the expected pixels in every phase"
else
    tail -n 3 "$work/pixels.err"; echo "FAIL: the compositor shows the expected pixels in every phase"; status=1
fi
if python3 -I "$here/fractional-independent-wire.py" "$work/guest.out" > "$work/wire.json" 2> "$work/wire.err"; then
    echo "PASS: every surface's buffer is its destination at the whole scale of its own output"
else
    tail -n 3 "$work/wire.err"; echo "FAIL: every surface's buffer is its destination at the whole scale of its own output"; status=1
fi
[ "$status" = 0 ] && echo PASS || echo FAIL
exit "$status"
