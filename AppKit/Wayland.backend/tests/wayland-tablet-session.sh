#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/tablet-session-probe.m against the "tablet" scenario of wayland-color-session-server.c, a
# private compositor that offers zwp_tablet_manager_v2 and plays one pen stroke on the first toplevel
# (proximity in, hover, tip down with pressure and tilt, a side button, tip up, proximity out). No tablet
# hardware and nothing of the desktop session is involved. Usage:
#   wayland-tablet-session.sh <command that runs the guest probe>
# The command's arguments get the number of seconds to wait appended, and DARLING_APPKIT_BACKEND=wayland and
# WAYLAND_DISPLAY (an absolute host path) are set in its environment. Compile the probe first, for example:
#   scripts/guest-cc.sh -o /tmp/tablet-session-probe tests/tablet-session-probe.m -framework AppKit
#   wayland-tablet-session.sh darling shell /Volumes/SystemRoot/tmp/tablet-session-probe
# Needs wayland-scanner, wayland-protocols and a C compiler for wayland-server.
set -u
here=$(cd "$(dirname "$0")" && pwd)
protocols_dir="$here/../../../CoreGraphics/WaylandSupport/protocols"
work=$(mktemp -d)
server_pid=
cleanup() {
    [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

for tool in wayland-scanner pkg-config cc timeout; do
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
sock="$work/r/w"
export XDG_RUNTIME_DIR="$work/r"
"$work/server" w tablet > "$work/server.out" 2>&1 &
server_pid=$!
for _ in $(seq 50); do [ -S "$sock" ] && break; sleep 0.1; done
[ -S "$sock" ] || { echo "FAIL: the compositor did not start"; cat "$work/server.out"; exit 1; }

env DARLING_APPKIT_BACKEND=wayland WAYLAND_DISPLAY="$sock" \
    timeout -s KILL 60 "$@" 6 > "$work/guest.out" 2>&1 < /dev/null
guest_status=$?
if grep -q '^SKIP' "$work/guest.out"; then
    echo "SKIP: $(grep '^SKIP' "$work/guest.out" | head -n 1)"
    exit 0
fi
# WPT_KEEP=<file> keeps the client's whole log (for example with WAYLAND_DEBUG=1) for inspection.
[ -n "${WPT_KEEP:-}" ] && cp "$work/guest.out" "$WPT_KEEP"
grep -E '^(PASS|FAIL|PROBE)' "$work/guest.out"
status=0
grep -q '^PROBE done' "$work/guest.out" || { echo "FAIL: the probe did not finish"; status=1; }
[ "$guest_status" = 0 ] || { echo "FAIL: the probe exited with status $guest_status"; status=1; }
if grep -q '^TABLET done' "$work/server.out"; then echo "PASS: the compositor played the whole stroke"
else echo "FAIL: the compositor did not play the whole stroke"; status=1; fi
exit $status
