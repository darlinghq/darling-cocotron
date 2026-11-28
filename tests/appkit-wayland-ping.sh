#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
# Runs tests/appkit-wayland-ping.m ($1, with the mode $4: stall or fork) against a small test compositor
# (wayland-ping-server.c) that pings the client every 400 ms from its first acknowledged configure on. xdg_wm_base.ping
# is answered from the main run loop only, so a client whose main thread is blocked must look hung. The test passes
# when every ping is answered promptly while the main thread is idle in the run loop, no pong is sent during the 2.5 s
# the main thread is blocked, and the pings that arrived during the block are answered once the run loop runs again.
# $2 is the command that runs the guest binary; it has to give the program the DARLING_APPKIT_BACKEND,
# WAYLAND_DISPLAY and XDG_RUNTIME_DIR this script exports. The test's output goes to $3. Needs cc, wayland-scanner,
# wayland-protocols and the libwayland server library.
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
field() { sed -n "s/.* $1=\([0-9]*\).*/\1/p" <<< "$summary"; }
idle_pings=$(field idle_pings); idle_answered=$(field idle_answered); idle_max=$(field idle_max_ms)
stall_pings=$(field stall_pings); stall_pongs=$(field stall_pongs)
late_pending=$(field late_pending); late_answered=$(field late_answered); late_max=$(field late_max_ms)
# While the main thread idles in the run loop, every ping is answered promptly.
[ "$idle_pings" -ge 3 ] || { echo "FAIL: only $idle_pings pings were sent while the run loop was idle"; exit 1; }
[ "$idle_answered" -eq "$idle_pings" ] || { echo "FAIL: $((idle_pings - idle_answered)) of $idle_pings idle pings were not answered"; exit 1; }
[ "$idle_max" -lt 300 ] || { echo "FAIL: an idle ping took $idle_max ms to be answered"; exit 1; }
# While the main thread is blocked, nothing answers: the client has to look hung.
[ "$stall_pings" -ge 3 ] || { echo "FAIL: only $stall_pings pings were sent during the block"; exit 1; }
[ "$stall_pongs" -eq 0 ] || { echo "FAIL: $stall_pongs pongs were sent while the main thread was blocked"; exit 1; }
# When the run loop runs again, the pending pings are answered.
[ "$late_pending" -ge "$stall_pings" ] || { echo "FAIL: only $late_pending pings were pending after the block"; exit 1; }
[ "$late_answered" -eq "$late_pending" ] || { echo "FAIL: $((late_pending - late_answered)) of $late_pending pending pings were never answered"; exit 1; }
[ "$late_max" -lt 1000 ] || { echo "FAIL: the pending pings took $late_max ms to be answered after the block"; exit 1; }
echo "PASS: $idle_pings idle pings answered (slowest $idle_max ms), no pong during $stall_pings stalled pings, $late_answered pending pings answered within $late_max ms of the end of the block"
