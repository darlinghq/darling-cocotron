#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
# Runs tests/appkit-window-occlusion-state.m ($1, in external mode) against a small test compositor
# (wayland-suspended-server.c) that offers xdg_wm_base version 6 and sends the xdg_toplevel suspended state for a
# while to every toplevel, as a compositor does for one it stops repainting. A headless sway only offers version 5
# and never suspends. $2 is the command that runs the guest binary; it has to give the program the DARLING_APPKIT_BACKEND,
# WAYLAND_DISPLAY and XDG_RUNTIME_DIR this script exports. The test's output goes to $3. Needs cc, wayland-scanner,
# wayland-protocols and the libwayland server library.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_binary=$1
runner=$2
out=$3
work=$(mktemp -d)
server=
guest=
trap 'set +e; [ -z "$server" ] || kill "$server" 2>/dev/null; [ -z "$guest" ] || kill "$guest" 2>/dev/null; rm -rf "$work"' EXIT
protocols=$(pkg-config --variable=pkgdatadir wayland-protocols)
wayland-scanner server-header "$protocols/stable/xdg-shell/xdg-shell.xml" "$work/xdg-shell-server-protocol.h"
wayland-scanner private-code "$protocols/stable/xdg-shell/xdg-shell.xml" "$work/xdg-shell-server.c"
cc -Wall -I"$work" -o "$work/server" "$here/wayland-suspended-server.c" "$work/xdg-shell-server.c" -lwayland-server
# A Wayland socket path is limited to 107 bytes: keep TMPDIR short.
mkdir -m 700 "$work/run"
XDG_RUNTIME_DIR="$work/run" "$work/server" test-wayland-1 > "$work/server.out" 2>&1 &
server=$!
for _ in $(seq 50); do grep -q '^LISTENING' "$work/server.out" && break; sleep 0.1; done
grep -q '^LISTENING' "$work/server.out" || { echo "FAIL: the test compositor did not start"; cat "$work/server.out"; exit 1; }
export DARLING_APPKIT_BACKEND=wayland WAYLAND_DISPLAY="$work/run/test-wayland-1" XDG_RUNTIME_DIR="$work/run"
: > "$out"
$runner "$test_binary" external > "$out" 2>&1 < /dev/null &
guest=$!
wait "$guest" || true
cat "$out"
grep -q '^SUSPENDED' "$work/server.out" || { echo "FAIL: the window was never suspended"; exit 1; }
grep -q '^PASS' "$out"
