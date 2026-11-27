#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs wayland-format-client.c against wayland-color-session-server.c in its "formats" scenario.
# The fake compositor advertises 8-bit and half-float dma-buf formats with a linear modifier;
# the client checks that the format table can be read with the 16-byte entries required by
# linux-dmabuf-v1.xml. No guest or real compositor is needed.
#
# Needs wayland-scanner, wayland-protocols and C compiler support for wayland-client/server.
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
wayland-scanner client-header "$protocols_dir/linux-dmabuf-v1.xml" \
    "$work/linux-dmabuf-v1-client-protocol.h" || exit 2

cc -Wall -Wno-incompatible-pointer-types -I"$work" -o "$work/server" \
    "$here/wayland-color-session-server.c" "$work/xdg-shell.c" "$work/tablet-unstable-v2.c" \
    "$work/color-management-v1.c" "$work/color-representation-v1.c" \
    "$work/xdg-session-management-v1.c" "$work/linux-dmabuf-v1.c" \
    "$work/linux-drm-syncobj-v1.c" "$work/fifo-v1.c" \
    $(pkg-config --cflags --libs wayland-server) || exit 2
cc -Wall -I"$work" -o "$work/client" \
    "$here/wayland-format-client.c" "$work/linux-dmabuf-v1.c" \
    $(pkg-config --cflags --libs wayland-client) || exit 2

mkdir -m 700 "$work/r"
sock="$work/r/w"
server_out="$work/server.out"
client_out="$work/client.out"
export XDG_RUNTIME_DIR="$work/r"
"$work/server" w formats > "$server_out" 2>&1 &
server_pid=$!
for _ in $(seq 50); do [ -S "$sock" ] && break; sleep 0.1; done
[ -S "$sock" ] || { echo "FAIL: the compositor did not start"; cat "$server_out"; exit 1; }

status=0
fail() { echo "FAIL: $*"; status=1; }
wait_for() {
    for _ in $(seq 100); do grep -q "$2" "$1" && return 0; sleep 0.1; done
    return 1
}

WAYLAND_DISPLAY="$sock" timeout -s KILL 15 "$work/client" > "$client_out" 2>&1
client_status=$?
wait_for "$client_out" '^CLIENT done' || {
    echo "FAIL: the client did not finish"; cat "$client_out" "$server_out"; exit 1;
}

grep -q '^DMABUF_FEEDBACK surface=1 entries=4$' "$server_out" || fail "the compositor did not advertise four formats"
grep -q '^CLIENT done entries=4$' "$client_out" || fail "the client did not read four formats"
for spec in \
    '0 format=34325241 modifier=0000000000000000' \
    '1 format=34325258 modifier=0000000000000000' \
    '2 format=48345241 modifier=0000000000000000' \
    '3 format=48345258 modifier=0000000000000000'; do
    grep -q "^CLIENT_FORMAT index=$spec\$" "$client_out" || fail "missing table entry $spec"
done
[ "$client_status" = 0 ] || fail "client exited with status $client_status"
kill -0 "$server_pid" 2>/dev/null || fail "the compositor exited (protocol error?)"
grep -qi 'error' "$server_out" && { fail "the compositor reported an error"; grep -i error "$server_out"; }
if [ $status = 0 ]; then echo "PASS: dma-buf wide formats"; fi
exit $status
