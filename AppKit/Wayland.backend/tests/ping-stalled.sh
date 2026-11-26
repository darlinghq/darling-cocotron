#!/bin/bash
# Copyright (C) 2026 Darling Developers
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Verifies that xdg_wm_base.ping is answered with xdg_wm_base.pong even when
# the application's main thread is stalled and not pumping WaylandDisplay.
# Needs wayland-server, wayland-scanner and wayland-protocols.
#
# Usage: ping-stalled.sh <guest command that runs ping-stalled-probe>
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
server_pid=
cleanup() {
    [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT INT TERM
for tool in wayland-scanner pkg-config cc; do
    command -v "$tool" >/dev/null || { echo "need $tool" >&2; exit 2; }
done
protocols=$(pkg-config --variable=pkgdatadir wayland-protocols)
wayland-scanner server-header "$protocols/stable/xdg-shell/xdg-shell.xml" "$work/xdg-shell-server.h"
wayland-scanner private-code "$protocols/stable/xdg-shell/xdg-shell.xml" "$work/xdg-shell.c"
cc -Wall -I"$work" -o "$work/server" "$here/ping-stalled-server.c" "$work/xdg-shell.c" \
    $(pkg-config --cflags --libs wayland-server) || exit 2

mkdir -m 700 "$work/run"
XDG_RUNTIME_DIR="$work/run" "$work/server" > "$work/server.log" 2>&1 &
server_pid=$!
for _ in $(seq 50); do grep -q READY "$work/server.log" && break; sleep 0.1; done
grep -q READY "$work/server.log" || { echo "server did not start" >&2; cat "$work/server.log"; exit 2; }
socket=$(sed -n 's/^READY //p' "$work/server.log")

env WAYLAND_DISPLAY="$work/run/$socket" DARLING_APPKIT_BACKEND=wayland \
    "$@" > "$work/probe.out" 2>&1
probe_status=$?
wait "$server_pid"
server_status=$?
server_pid=

if [ "$probe_status" -ne 0 ] || [ "$server_status" -ne 0 ] || ! grep -q '^PONG_OK ' "$work/server.log"; then
    echo "FAIL: probe_status=$probe_status server_status=$server_status"
    cat "$work/probe.out"
    cat "$work/server.log"
    exit 1
fi
echo "PASS: $(grep '^PONG_OK ' "$work/server.log")"
