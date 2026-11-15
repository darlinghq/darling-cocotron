#!/bin/bash
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Display mode switching through wlr-output-management on a Wayland compositor.
# Builds tests/wlr-output-server.c (a minimal compositor with one output, four modes and the
# wlr-output-management protocol; it needs wayland-server, wayland-scanner and wayland-protocols)
# and runs the guest test tests/coregraphics-display-mode-switch against it, then checks the
# modes the compositor was asked for: switched to the mode, back at release, and back at process
# exit. A real headless sway cannot stand in: its headless outputs have no mode list (only the
# current custom mode), so there is nothing to switch between.
#
# Usage: wlr-output-mode-switch.sh <guest test command, e.g. "darling /path/to/coregraphics-display-mode-switch">
# The command is run with WAYLAND_DISPLAY (a host path), DARLING_APPKIT_BACKEND=wayland and CG_TEST_MODE set.
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
wlr="$here/../../../CoreGraphics/WaylandSupport/protocols/wlr-output-management-unstable-v1.xml"
wayland-scanner server-header "$wlr" "$work/wlr-output-management-unstable-v1-server.h"
wayland-scanner private-code "$wlr" "$work/wlr.c"
wayland-scanner server-header "$protocols/stable/xdg-shell/xdg-shell.xml" "$work/xdg-shell-server.h"
wayland-scanner private-code "$protocols/stable/xdg-shell/xdg-shell.xml" "$work/xdg.c"
cc -Wall -I"$work" -o "$work/server" "$here/wlr-output-server.c" "$work/wlr.c" "$work/xdg.c" \
    $(pkg-config --cflags --libs wayland-server) || exit 2

fail=0
run() { # <name> <server argument> <test argument>
    mkdir -m 700 "$work/run-$1"
    XDG_RUNTIME_DIR="$work/run-$1" "$work/server" $2 > "$work/$1.log" 2>&1 &
    server_pid=$!
    for _ in $(seq 50); do grep -q READY "$work/$1.log" && break; sleep 0.1; done
    grep -q READY "$work/$1.log" || { echo "server did not start" >&2; cat "$work/$1.log"; exit 2; }
    socket=$(sed -n 's/^READY //p' "$work/$1.log")
    env WAYLAND_DISPLAY="$work/run-$1/$socket" DARLING_APPKIT_BACKEND=wayland CG_TEST_MODE=1024x768 \
        "${@:3}" > "$work/$1.out" 2>&1
    status=$?
    kill "$server_pid"; wait "$server_pid" 2>/dev/null; server_pid=
    echo "== $1 (exit $status)"; cat "$work/$1.out"; cat "$work/$1.log"
    return $status
}

# The full test, with the compositor refusing the first configuration as outdated for the
# second variant.
for variant in plain cancel-once; do
    run $variant "$([ $variant = plain ] || echo cancel-once)" "$@" || fail=1
    grep -q '^PASS' "$work/$variant.out" || fail=1
    # Switched, restored by release, switched again, restored by CGReleaseAllDisplays, ...
    [ "$(grep -c '^APPLIED 1024x768@60000' "$work/$variant.log")" -ge 3 ] || { echo "FAIL: $variant: no switch"; fail=1; }
    [ "$(grep -c '^APPLIED 1280x720@60000' "$work/$variant.log")" -ge 3 ] || { echo "FAIL: $variant: no restore"; fail=1; }
    grep -q '^FINAL 1280x720@60000' "$work/$variant.log" || { echo "FAIL: $variant: final mode"; fail=1; }
done
grep -q '^CANCELLED' "$work/cancel-once.log" || { echo "FAIL: no cancelled configuration"; fail=1; }

# Process exit without release restores the mode.
run exit "" "$@" exit || fail=1
grep -q '^switched' "$work/exit.out" || fail=1
grep -q '^FINAL 1280x720@60000' "$work/exit.log" || { echo "FAIL: exit: mode not restored at exit"; fail=1; }

[ $fail = 0 ] && echo PASS || { echo FAIL; exit 1; }
