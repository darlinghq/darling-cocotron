#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
# Runs tests/appkit-wayland-ping.m ($1, with the mode $4: stall or fork) against a small test compositor
# (wayland-ping-server.c) that pings the client every 400 ms from its first acknowledged configure on, and passes when
# the client answered every ping within 1000 ms although its main thread was blocked for 2.5 s. $2 is the command that
# runs the guest binary; it has to give the program the DARLING_APPKIT_BACKEND, WAYLAND_DISPLAY and XDG_RUNTIME_DIR
# this script exports. The test's output goes to $3. Needs cc, wayland-scanner, wayland-protocols and the libwayland
# server library.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_binary=$1
runner=$2
out=$3
mode=${4:-stall}
work=$(mktemp -d)
server=
guest=
trap 'set +e; [ -z "$server" ] || kill "$server" 2>/dev/null; [ -z "$guest" ] || kill "$guest" 2>/dev/null; rm -rf "$work"' EXIT
protocols=$(pkg-config --variable=pkgdatadir wayland-protocols)
wayland-scanner server-header "$protocols/stable/xdg-shell/xdg-shell.xml" "$work/xdg-shell-server-protocol.h"
wayland-scanner private-code "$protocols/stable/xdg-shell/xdg-shell.xml" "$work/xdg-shell-server.c"
cc -Wall -I"$work" -o "$work/server" "$here/wayland-ping-server.c" "$work/xdg-shell-server.c" -lwayland-server
# A Wayland socket path is limited to 107 bytes: keep TMPDIR short.
mkdir -m 700 "$work/run"
XDG_RUNTIME_DIR="$work/run" "$work/server" test-wayland-1 > "$work/server.out" 2>&1 &
server=$!
for _ in $(seq 50); do grep -q '^LISTENING' "$work/server.out" && break; sleep 0.1; done
grep -q '^LISTENING' "$work/server.out" || { echo "FAIL: the test compositor did not start"; cat "$work/server.out"; exit 1; }
export DARLING_APPKIT_BACKEND=wayland WAYLAND_DISPLAY="$work/run/test-wayland-1" XDG_RUNTIME_DIR="$work/run"
: > "$out"
$runner "$test_binary" "$mode" > "$out" 2>&1 < /dev/null &
guest=$!
wait "$guest" || true
cat "$out"
if grep -q '^SKIP' "$out"; then exit 0; fi
for _ in $(seq 50); do grep -q '^SUMMARY' "$work/server.out" && break; sleep 0.1; done
cat "$work/server.out"
grep -q '^PASS' "$out" || { echo "FAIL: the program failed"; exit 1; }
summary=$(grep '^SUMMARY' "$work/server.out") || { echo "FAIL: the compositor saw no disconnect"; exit 1; }
pings=$(sed -n 's/.*pings=\([0-9]*\).*/\1/p' <<< "$summary")
answered=$(sed -n 's/.*answered=\([0-9]*\).*/\1/p' <<< "$summary")
latency=$(sed -n 's/.*max_latency_ms=\([0-9]*\).*/\1/p' <<< "$summary")
[ "$pings" -ge 4 ] || { echo "FAIL: only $pings pings were sent"; exit 1; }
[ "$answered" -eq "$pings" ] || { echo "FAIL: $((pings - answered)) of $pings pings were never answered"; exit 1; }
[ "$latency" -lt 1000 ] || { echo "FAIL: a ping took $latency ms to be answered"; exit 1; }
echo "PASS: $pings pings answered, slowest $latency ms"
