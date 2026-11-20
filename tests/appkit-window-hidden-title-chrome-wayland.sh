#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Checks which windows of tests/appkit-window-hidden-title-chrome.m get a frame from sway: a framed window
# asks for server-side decorations (sway border "normal"), a window without one declares that it draws its
# own (border "csd") and the backend draws none, so its surface is as big as the frame AppKit reports.
# Usage: appkit-window-hidden-title-chrome-wayland.sh <command that runs "appkit-window-hidden-title-chrome 5">
# with DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY in the command's environment. Needs swaymsg, python3
# and SWAYSOCK.
set -u
out=$(mktemp)
swaymsg -q default_floating_border normal
swaymsg -q default_border normal
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$out"' EXIT

wait_for() {
    for _ in $(seq 300); do grep -q "^$1\$" "$out" && return 0; sleep 0.1; done
    echo "FAIL: the test never printed $1"; cat "$out"; exit 1
}

state() { # "<name> <border> <surface width - frame width>x<surface height - frame height>" per window
    swaymsg -t get_tree | python3 -I -c '
import json, sys
sizes = {}
for line in open(sys.argv[1]):
    f = line.split()
    if len(f) == 6 and f[0] == "win":
        sizes[f[1]] = (int(f[4]), int(f[5]))
def walk(n):
    if n.get("name") in sizes and n.get("shell") == "xdg_shell":
        r = n["window_rect"]
        w, h = sizes[n["name"]]
        print(n["name"], n.get("border"), "%dx%d" % (r["width"] - w, r["height"] - h))
    for c in n.get("nodes", []) + n.get("floating_nodes", []):
        walk(c)
walk(json.load(sys.stdin))' "$out"
}

status=0
check() { # phase name border size
    local line
    line=$(printf '%s\n' "$STATE" | grep "^$2 ")
    if [ "$line" = "$2 $3 $4" ]; then echo "PASS: $1 $2: $3 $4"
    else echo "FAIL: $1 $2: got '${line#"$2 "}', expected '$3 $4'"; status=1; fi
}

wait_for shown
sleep 0.5
STATE=$(state)
check shown hidden-all csd 0x0
check shown hidden-title normal 0x0
check shown transparent normal 0x0
check shown opaque-hidden normal 0x0
check shown late-hidden normal 0x0
# untitled resizable windows: framed only in a program built against an SDK older than 10.7
if grep -q '^old-sdk 1$' "$out"; then untitled=normal; else untitled=csd; fi
check shown resizable $untitled 0x0
check shown mini-resizable $untitled 0x0
grep '^FAIL' "$out" && status=1
wait_for changed
sleep 0.5
STATE=$(state)
check changed late-hidden csd 0x0
check changed hidden-all csd 0x0
wait $pid
exit $status
