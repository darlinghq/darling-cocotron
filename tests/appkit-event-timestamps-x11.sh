#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
# Runs tests/appkit-event-timestamps.m ($1, in input mode) against the X11 display $DISPLAY: when the test reports READY, a
# click and a key press are injected at the global top-left point 960,540 with xdotool. $2 is the command that
# runs the guest binary, such as "darling shell"; the test's output goes to $3.
set -euo pipefail
test_binary=$1
runner=$2
out=$3
: > "$out"
$runner "$test_binary" input 960 540 > "$out" 2>&1 < /dev/null &
guest=$!
trap 'set +e; kill "$guest" 2>/dev/null' EXIT
for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
xdotool mousemove 960 540
sleep 0.5
xdotool click 1
sleep 0.5
xdotool key a
wait "$guest" || true
cat "$out"
grep -q '^PASS' "$out"
