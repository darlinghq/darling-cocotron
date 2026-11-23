#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
# Runs tests/appkit-wayland-mouse-exited.m ($1) against a headless sway (1920x1080 output) whose environment is
# exported (WAYLAND_DISPLAY with an absolute socket path, XDG_RUNTIME_DIR). When the test reports READY, a virtual
# pointer (VIRTUAL_POINTER, the path of a built tests/wayland-virtual-pointer.c; a headless sway has no pointer
# device) is moved: out of the window, into its centre (the window is floating and centred), inside it, out through
# its left side, in again and out through its bottom, each time when the test has printed the STEP line of the previous
# move. $2 is the command that runs the guest binary; the test's
# output goes to $3.
set -euo pipefail
test_binary=$1
runner=$2
out=$3
pointer=${VIRTUAL_POINTER:?path of the built wayland-virtual-pointer helper}
work=$(mktemp -d)
mkfifo "$work/commands"
: > "$out"
$runner "$test_binary" > "$out" 2>&1 < /dev/null &
guest=$!
"$pointer" < "$work/commands" > "$work/pointer.out" 2>&1 &
helper=$!
exec 3> "$work/commands"
trap 'set +e; kill "$guest" "$helper" 2>/dev/null; rm -rf "$work"' EXIT
for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
for _ in $(seq 50); do grep -q '^READY' "$work/pointer.out" && break; sleep 0.1; done
# The test prints "STEP n" when it has checked what the previous move should have caused. A pointer that crosses
# into a window is followed by a small move, as a real pointer would, because the window evaluates its tracking
# areas for motion.
echo "move 100 100" >&3
n=1
for step in "move 960 540;move 962 542" "move 1000 560" "move 100 540" "move 960 540;move 962 542" "move 960 1060" "move 100 100"; do
    for _ in $(seq 200); do grep -q "^STEP $n\$" "$out" && break; sleep 0.1; done
    grep -q "^STEP $n\$" "$out" || { echo "FAIL: the test never reached step $n"; break; }
    IFS=';' read -ra moves <<< "$step"
    for move in "${moves[@]}"; do
        echo "$move" >&3
        sleep 0.3
    done
    n=$((n + 1))
done
wait "$guest" || true
cat "$out"
grep -q '^OK' "$out"
