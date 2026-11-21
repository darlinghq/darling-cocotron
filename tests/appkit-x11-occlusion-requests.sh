#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
# Runs tests/appkit-x11-occlusion-requests.m (built as $1) on $DISPLAY: when the test reports READY, a helper
# client makes its window the focused one and streams repeated ConfigureNotify events and stacking-list
# rewrites. $2 is the command that runs the guest binary, such as "darling shell"; output goes to $3.
# Needs cc and Xlib headers for the helper.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_binary=$1
runner=$2
out=$3
work=$(mktemp -d)
helper=
guest=
trap 'set +e; [ -z "$helper" ] || kill "$helper" 2>/dev/null; [ -z "$guest" ] || kill "$guest" 2>/dev/null; rm -rf "$work"' EXIT
cc -Wall "$here/x11-active-window.c" -lX11 -o "$work/active"
: > "$out"
$runner "$test_binary" > "$out" 2>&1 < /dev/null &
guest=$!
for _ in $(seq 300); do grep -q '^READY\|^SKIP' "$out" && break; sleep 0.1; done
grep -q '^READY\|^SKIP' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
"$work/active" 6 &
helper=$!
wait "$guest" || true
kill "$helper" 2>/dev/null || true
cat "$out"
grep -q '^PASS' "$out"
