#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/color-session-probe.m against tests/wayland-color-session-server.c, a private compositor
# that offers color management (including v3 surface feedback and HDR), session management,
# dma-buf, explicit synchronization and fifo. Usage:
#   wayland-color-session.sh <scenario> <command that runs color-session-probe>
# The script appends the scenario and the number of seconds to the command's arguments, and sets
# DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY (an absolute host path) in its environment.
# Scenarios:
#   color      an HDR P3 output: NSScreen reports P3 and EDR headroom, and the toplevel surface gets a
#              P3 description and the premultiplied-electrical alpha mode
#   launch     no saved state and no marker: the compositor session starts with reason=launch
#   restore    saved state naming a session and a toplevel: reason=session_restore, and the saved
#              toplevel is restored before its first surface commit
#   recover    a leftover running marker without saved state: reason=recover, with a new toplevel
# Compile the guest probe first, for example:
#   scripts/guest-cc.sh -o /tmp/color-session-probe tests/color-session-probe.m -framework AppKit
#   wayland-color-session.sh color darling shell /Volumes/SystemRoot/tmp/color-session-probe
# Needs wayland-scanner, wayland-protocols and a C compiler for wayland-server.
set -u
scenario=$1; shift
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
case "$scenario" in color|launch|restore|recover) ;; *) echo "unknown scenario $scenario" >&2; exit 2 ;; esac

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
server_out="$work/server.out"
guest_out="$work/guest.out"
export XDG_RUNTIME_DIR="$work/r"
"$work/server" w > "$server_out" 2>&1 &
server_pid=$!
for _ in $(seq 50); do [ -S "$sock" ] && break; sleep 0.1; done
[ -S "$sock" ] || { echo "FAIL: the compositor did not start"; cat "$server_out"; exit 1; }

status=0
fail() { echo "FAIL: $*"; status=1; }
wait_for() {
    for _ in $(seq 300); do grep -q "$2" "$1" && return 0; sleep 0.1; done
    return 1
}

env DARLING_APPKIT_BACKEND=wayland WAYLAND_DISPLAY="$sock" \
    timeout -s KILL 60 "$@" "$scenario" 8 > "$guest_out" 2>&1 < /dev/null
guest_status=$?
if grep -q '^SKIP ' "$guest_out"; then
    echo "SKIP: $scenario: $(head -n 1 "$guest_out")"
    exit 0
fi
wait_for "$guest_out" '^PROBE done' || {
    echo "FAIL: the probe did not finish"; cat "$guest_out" "$server_out"; exit 1;
}
sleep 0.5

expect_server() { # regex, description
    if grep -Eq "$1" "$server_out"; then
        echo "PASS: $2: $(grep -E "$1" "$server_out" | head -n 1)"
    else
        fail "$2: expected /$1/"; fi
}
expect_guest() { # regex, description
    if grep -Eq "$1" "$guest_out"; then
        echo "PASS: $2: $(grep -E "$1" "$guest_out" | head -n 1)"
    else
        fail "$2: expected /$1/"; fi
}

case "$scenario" in
color)
    expect_server '^OUTPUT_INFO primaries=9 tf=9 max=400 reference=203 target=1000$' "output color description"
    expect_server '^SURFACE_COLOR color-test primaries=9 tf=9$' "surface color description"
    expect_server '^SURFACE_ALPHA .*mode=0$' "surface alpha mode"
    expect_server '^COLOR_FEEDBACK get_preferred_parametric identity=1$' "v3 parametric surface feedback"
    expect_server '^HDR_LUMINANCES min=1 max=400 reference=203$' "primary-volume HDR luminances"
    expect_server '^HDR_MAX_CLL 1000$' "HDR MaxCLL"
    expect_server '^HDR_MAX_FALL 400$' "HDR MaxFALL"
    expect_server '^DMABUF_FEEDBACK surface=1 entries=1$' "surface dma-buf feedback"
    expect_server '^FIFO_BARRIER set$' "fifo frame barrier"
    expect_guest '^SCREEN p3=1 edr=1\.97 potential=4\.93 reference=4\.93$' "NSScreen color space and EDR"
    ;;
launch)
    expect_server '^SESSION reason=1 id=[^ ]+ op=add name=darling-[^ ]+ before_commit=1$' "launch session"
    ;;
restore)
    expect_server '^SESSION reason=3 id=test-session-1 op=restore name=saved-window before_commit=1$' "restored session toplevel"
    ;;
recover)
    expect_server '^SESSION reason=2 id=test-session-1 op=add name=darling-[^ ]+ before_commit=1$' "recovered session"
    ;;
esac
expect_guest '^RUNNING_MARKER present=1$' "running marker kept while the application runs (the compositor has sessions)"
expect_guest '^MARKER absent=1$' "running marker removed on quit"
expect_guest '^PROBE done failures=0$' "guest checks"
[ $guest_status = 0 ] || fail "guest exited with status $guest_status"
kill -0 "$server_pid" 2>/dev/null || fail "the compositor exited (protocol error?)"
grep -qi 'error' "$server_out" && { fail "the compositor reported an error"; grep -i error "$server_out"; }
if [ $status = 0 ]; then echo "PASS: $scenario"; fi
exit $status
