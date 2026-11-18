#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
# Runs tests/appkit-window-occlusion-state.m (built as $1, in external mode) against a window manager on
# $DISPLAY: when the test reports READY, an opaque fullscreen window of another client covers the display
# until the test reports COVERED. $2 is the command that runs the guest binary, such as "darling shell";
# the test's output goes to $3. Needs cc and Xlib headers for the helper.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_binary=$1
runner=$2
out=$3
work=$(mktemp -d)
cover=
guest=
trap 'set +e; [ -z "$cover" ] || kill "$cover" 2>/dev/null; [ -z "$guest" ] || kill "$guest" 2>/dev/null; rm -rf "$work"' EXIT
cc -Wall "$here/x11-cover-window.c" -lX11 -o "$work/cover"
: > "$out"
$runner "$test_binary" external > "$out" 2>&1 < /dev/null &
guest=$!
for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
"$work/cover" 8 &
cover=$!
for _ in $(seq 300); do grep -q '^COVERED' "$out" && break; sleep 0.1; done
kill "$cover" 2>/dev/null || true
wait "$guest" || true
cat "$out"
grep -q '^PASS' "$out"
