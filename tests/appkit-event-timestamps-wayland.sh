#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
# Runs tests/appkit-event-timestamps.m ($1, in input mode) against a headless sway (1920x1080 output) whose
# environment is exported (WAYLAND_DISPLAY with an absolute socket path, XDG_RUNTIME_DIR). When the test reports
# READY, a click is injected at the global top-left point 960,540 and then a key press (wtype). The click needs
# VIRTUAL_POINTER, the path of a built tests/wayland-virtual-pointer.c, because a headless sway has no pointer
# device. $2 is the command that runs the guest binary; the test's output goes to $3.
set -euo pipefail
test_binary=$1
runner=$2
out=$3
pointer=${VIRTUAL_POINTER:?path of the built wayland-virtual-pointer helper}
work=$(mktemp -d)
mkfifo "$work/clicks"
: > "$out"
$runner "$test_binary" input 960 540 > "$out" 2>&1 < /dev/null &
guest=$!
"$pointer" < "$work/clicks" > "$work/pointer.out" 2>&1 &
helper=$!
exec 3> "$work/clicks"
trap 'set +e; kill "$guest" "$helper" 2>/dev/null; rm -rf "$work"' EXIT
for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
for _ in $(seq 50); do grep -q '^READY' "$work/pointer.out" && break; sleep 0.1; done
echo "960 540" >&3
for _ in $(seq 50); do grep -q '^CLICKED' "$work/pointer.out" && break; sleep 0.1; done
sleep 0.5
wtype -s 200 a
wait "$guest" || true
cat "$out"
grep -q '^PASS' "$out"
