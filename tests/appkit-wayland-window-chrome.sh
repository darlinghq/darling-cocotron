#!/bin/bash
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Checks which Wayland windows of appkit-wayland-window-chrome get a frame, in sway's own view
# (border state) and by the size of each surface against the window size AppKit reports. Usage:
#   appkit-wayland-window-chrome.sh server|client <command that runs "appkit-wayland-window-chrome <hold>">
# "server": the compositor draws frames (sway reports border "normal" for a framed window and "csd"
#   for a window that declared it draws its own) and every window's surface is as big as AppKit's
#   window frame. "client": the client draws the frames itself (run the command with
#   DARLING_WAYLAND_DECORATIONS=client); every window is "csd", the surface of a framed window is
#   12x40 points bigger than AppKit's window frame (6 point borders and a 28 point title bar inside
#   the surface), that of a chromeless one is as big as the frame. Optional GRIM_DIR: a directory
#   for screenshots taken at each phase.
# Needs swaymsg, python3, SWAYSOCK and WAYLAND_DISPLAY set for the headless sway.
set -u
mode=$1; shift
out=$(mktemp)
swaymsg -q default_floating_border normal
swaymsg -q default_border normal
"$@" > "$out" 2>&1 &
pid=$!

state() { # print "<name> <border> <surface width - window width>x<surface height - window height>"
    swaymsg -t get_tree | python3 -I -c '
import json, sys
sizes = {}
for line in open(sys.argv[1]):
    f = line.split()
    if len(f) == 4 and f[0] == "win":
        sizes[f[1]] = (int(f[2]), int(f[3]))
def walk(n):
    if n.get("name") in sizes and n.get("shell") == "xdg_shell":
        r = n["window_rect"]
        w, h = sizes[n["name"]]
        print(n["name"], n.get("border"), "%dx%d" % (r["width"] - w, r["height"] - h))
    for c in n.get("nodes", []) + n.get("floating_nodes", []):
        walk(c)
walk(json.load(sys.stdin))' "$out" | sort
}

wait_for() {
    for i in $(seq 120); do grep -q "^$1\$" "$out" && return 0; grep -q SKIP "$out" && return 1; sleep 0.5; done
    return 1
}

status=0
check() { # phase name border size
    local line
    line=$(printf '%s\n' "$STATE" | grep "^$2 ")
    if [ "$line" = "$2 $3 $4" ]; then echo "PASS: $1 $2: $3 $4"
    else echo "FAIL: $1 $2: got '${line#"$2 "}', expected '$3 $4'"; status=1; fi
}

shot() { # spread the windows out side by side, then take a screenshot when asked for
    local x=20 t
    for t in plain fullsize-only transparent-only chromeless late-transparent; do
        swaymsg -q "[title=\"$t\"] move position $x 100"
        x=$((x + 380))
    done
    [ -n "${GRIM_DIR:-}" ] && grim "$GRIM_DIR/$mode-$1.png"
    return 0
}

if [ "$mode" = server ]; then
    framed="normal 0x0"; bare="csd 0x0"
else
    framed="csd 12x40"; bare="csd 0x0"
fi
set -- $framed; fb=$1; fs=$2
set -- $bare; bb=$1; bs=$2

wait_for shown || { cat "$out"; kill $pid 2>/dev/null; exit 1; }
STATE=$(state); shot shown
check shown plain $fb $fs
check shown fullsize-only $fb $fs
check shown transparent-only $fb $fs
check shown chromeless $bb $bs
check shown late-transparent $fb $fs
wait_for changed || { cat "$out"; kill $pid 2>/dev/null; exit 1; }
STATE=$(state); shot changed
check changed plain $fb $fs
check changed chromeless $bb $bs
check changed late-transparent $bb $bs
wait "$pid"
rm -f "$out"
exit $status
