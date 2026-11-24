#!/bin/bash
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# The compositor's logical output description (xdg-output) as the displays of CoreGraphics and the screens of
# AppKit see it. Builds logical-server.c (a minimal compositor with one wl_output and the xdg-output manager,
# which checks on the wire that every xdg_output child has the version the protocol requires) and runs the guest
# program logical-probe against it for the manager and output versions it supports, with the manager announced
# before or after the output. With the lifecycle argument the server also removes the manager (the existing child
# must keep working), announces it again and adds a second output, which the probe has to see.
# Needs wayland-server, wayland-scanner and wayland-protocols.
#
# Usage: logical-probe.sh <guest command that runs logical-probe, e.g. "darling shell /path/to/logical-probe">
# The command is run with WAYLAND_DISPLAY (a host path), DARLING_APPKIT_BACKEND=wayland, EXPECTED_SCALE and,
# for the lifecycle runs, PROBE_LIFECYCLE=1.
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
wayland-scanner server-header "$protocols/unstable/xdg-output/xdg-output-unstable-v1.xml" "$work/xdg-output-server.h"
wayland-scanner private-code "$protocols/unstable/xdg-output/xdg-output-unstable-v1.xml" "$work/xdg-output.c"
wayland-scanner server-header "$protocols/stable/xdg-shell/xdg-shell.xml" "$work/xdg-shell-server.h"
wayland-scanner private-code "$protocols/stable/xdg-shell/xdg-shell.xml" "$work/xdg-shell.c"
cc -Wall -I"$work" -o "$work/server" "$here/logical-server.c" "$work/xdg-output.c" "$work/xdg-shell.c" \
    $(pkg-config --cflags --libs wayland-server) || exit 2

fail=0
run() { # <manager version> <output version> <reverse> [lifecycle]
    mkdir -m 700 "$work/run"
    XDG_RUNTIME_DIR="$work/run" "$work/server" "$@" > "$work/server.log" 2>&1 &
    server_pid=$!
    for _ in $(seq 50); do grep -q READY "$work/server.log" && break; sleep 0.1; done
    grep -q READY "$work/server.log" || { echo "server did not start" >&2; cat "$work/server.log"; exit 2; }
    socket=$(sed -n 's/^READY //p' "$work/server.log")
    lifecycle=()
    [ $# -ge 4 ] && lifecycle=(PROBE_LIFECYCLE=1)
    env WAYLAND_DISPLAY="$work/run/$socket" DARLING_APPKIT_BACKEND=wayland EXPECTED_SCALE=4 "${lifecycle[@]}" \
        "${COMMAND[@]}" > "$work/probe.out" 2>&1
    status=$?
    sleep 0.5
    kill "$server_pid"; wait "$server_pid" 2>/dev/null; server_pid=
    if [ $status != 0 ] || ! grep -q 'PROBE failures=0' "$work/probe.out" || grep -q 'failures=[1-9]' "$work/server.log"; then
        echo "FAIL: manager $1 output $2 reverse $3 ${4:+lifecycle}"; cat "$work/probe.out" "$work/server.log"; fail=1
    fi
    rm -rf "$work/run"
}
COMMAND=("$@")
for manager in 1 2 3; do
    for output in 1 2; do
        for reverse in 0 1; do
            run $manager $output $reverse
        done
    done
done
run 3 2 0 lifecycle
run 2 2 0 lifecycle
run 3 1 1 lifecycle
[ $fail = 0 ] && echo PASS || { echo FAIL; exit 1; }
