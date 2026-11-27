#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# The X11 counterpart of wayland-tablet-session.sh: runs tablet-session-probe.m on the X11 backend, with the same pen
# stroke. A private Xwayland (a rootful X server of its own, never the desktop's) runs on the private compositor of
# wayland-color-session-server.c ("tablet-signal" scenario); Xwayland turns the compositor's zwp_tablet_v2 tool into
# XInput2 tablet devices (pressure, tilt and wheel valuators, no proximity events) and so the X11 backend gets what an X
# server with a tablet gives it, without hardware or uinput devices. The compositor plays the stroke when the probe
# says READY. Usage:
#   x11-tablet-session.sh <command that runs the guest probe>
# The command's arguments get the number of seconds to wait appended, and DARLING_APPKIT_BACKEND=x11 and DISPLAY (the
# private Xwayland's) are set in its environment. Compile the probe first, for example:
#   scripts/guest-cc.sh -o /tmp/tablet-session-probe tests/tablet-session-probe.m -framework AppKit
#   x11-tablet-session.sh darling shell /Volumes/SystemRoot/tmp/tablet-session-probe
# Needs Xwayland, wayland-scanner, wayland-protocols and a C compiler for wayland-server.
set -u
here=$(cd "$(dirname "$0")" && pwd)
protocols_dir="$here/../../../CoreGraphics/WaylandSupport/protocols"
work=$(mktemp -d)
server_pid=
xwl_pid=
cleanup() {
    [ -n "$xwl_pid" ] && kill "$xwl_pid" 2>/dev/null
    [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

for tool in Xwayland wayland-scanner pkg-config cc timeout; do
    command -v "$tool" >/dev/null || { echo "need $tool" >&2; exit 2; }
done
[ $# -ge 1 ] || { echo "usage: $0 command..." >&2; exit 2; }

protocols=$(pkg-config --variable=pkgdatadir wayland-protocols)
for pair in \
    "$protocols/stable/xdg-shell/xdg-shell.xml:xdg-shell" \
    "$protocols/unstable/tablet/tablet-unstable-v2.xml:tablet-unstable-v2" \
    "$protocols_dir/color-management-v1.xml:color-management-v1" \
    "$protocols_dir/color-representation-v1.xml:color-representation-v1" \
    "$protocols_dir/xdg-session-management-v1.xml:xdg-session-management-v1" \
    "$protocols_dir/linux-dmabuf-v1.xml:linux-dmabuf-v1" \
    "$protocols_dir/linux-drm-syncobj-v1.xml:linux-drm-syncobj-v1" \
    "$protocols_dir/fifo-v1.xml:fifo-v1"; do
    xml=${pair%%:*}
    name=${pair##*:}
    wayland-scanner server-header "$xml" "$work/$name-server-protocol.h" || exit 2
    wayland-scanner private-code "$xml" "$work/$name.c" || exit 2
done
cc -Wall -Wno-incompatible-pointer-types -I"$work" -o "$work/server" \
    "$here/wayland-color-session-server.c" "$work/xdg-shell.c" "$work/tablet-unstable-v2.c" \
    "$work/color-management-v1.c" "$work/color-representation-v1.c" \
    "$work/xdg-session-management-v1.c" "$work/linux-dmabuf-v1.c" \
    "$work/linux-drm-syncobj-v1.c" "$work/fifo-v1.c" \
    $(pkg-config --cflags --libs wayland-server) || exit 2

mkdir -m 700 "$work/r"
export XDG_RUNTIME_DIR="$work/r"
"$work/server" w tablet-signal > "$work/server.out" 2>&1 &
server_pid=$!
for _ in $(seq 50); do [ -S "$work/r/w" ] && break; sleep 0.1; done
[ -S "$work/r/w" ] || { echo "FAIL: the compositor did not start"; cat "$work/server.out"; exit 1; }

# A display number nobody uses.
num=
for n in $(seq 120 160); do
    [ -e "/tmp/.X11-unix/X$n" ] || [ -e "/tmp/.X$n-lock" ] || { num=$n; break; }
done
[ -n "$num" ] || { echo "FAIL: no free display number"; exit 1; }
WAYLAND_DISPLAY="$work/r/w" Xwayland ":$num" -geometry 1024x768 -shm -noreset -nolisten tcp > "$work/xwl.out" 2>&1 &
xwl_pid=$!
for _ in $(seq 100); do [ -S "/tmp/.X11-unix/X$num" ] && break; sleep 0.1; done
[ -S "/tmp/.X11-unix/X$num" ] || { echo "FAIL: Xwayland did not start"; cat "$work/xwl.out"; exit 1; }

env DARLING_APPKIT_BACKEND=x11 DISPLAY=":$num" \
    timeout -s KILL 90 "$@" 9 > "$work/guest.out" 2>&1 < /dev/null &
guest_pid=$!
for _ in $(seq 300); do grep -q -E '^(READY|SKIP)' "$work/guest.out" && break; sleep 0.1; done
if grep -q '^READY' "$work/guest.out"; then
    sleep 1 # the window is on the screen
    kill -USR1 "$server_pid"
fi
wait "$guest_pid"
guest_status=$?
if grep -q '^SKIP' "$work/guest.out"; then
    echo "SKIP: $(grep '^SKIP' "$work/guest.out" | head -n 1)"
    exit 0
fi
# XTS_KEEP=<file> keeps the client's whole log for inspection.
[ -n "${XTS_KEEP:-}" ] && cp "$work/guest.out" "$XTS_KEEP"
grep -E '^(PASS|FAIL|PROBE)' "$work/guest.out"
status=0
grep -q '^PROBE done' "$work/guest.out" || { echo "FAIL: the probe did not finish"; status=1; }
[ "$guest_status" = 0 ] || { echo "FAIL: the probe exited with status $guest_status"; status=1; }
if grep -q '^TABLET done' "$work/server.out"; then echo "PASS: the compositor played the whole stroke"
else echo "FAIL: the compositor did not play the whole stroke"; status=1; fi
exit $status
