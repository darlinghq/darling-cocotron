#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# The Wayland counterpart of appkit-dragging-session-x11.sh: drags from the "drag-source" window of
# tests/appkit-dragging-session-live.m to its "drag-target" window with a virtual pointer
# (tests/wayland-virtual-pointer.c, in $VIRTUAL_POINTER), once plainly and once holding Option (Alt,
# through wtype's virtual keyboard), and checks the
# session callbacks, the mask the target saw and what it read. Core Wayland reports no pointer positions to
# a drag's source, so no "moved" callbacks are expected here. $WAYLAND_DISPLAY, $XDG_RUNTIME_DIR and
# $SWAYSOCK must name a headless sway (darling-skills' wayland.sh). Usage:
#   appkit-dragging-session-wayland.sh <command that runs "appkit-dragging-session-live <seconds>">
# Needs swaymsg, wtype and python3.
set -u
pointer=${VIRTUAL_POINTER:?path of the built wayland-virtual-pointer helper}
work=$(mktemp -d)
out=$work/out vpout=$work/pointer
mkfifo "$work/fifo"
"$pointer" < "$work/fifo" > "$vpout" 2>&1 &
vp=$!
exec 3> "$work/fifo"
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'exec 3>&-; kill $pid $vp 2>/dev/null; rm -rf "$work"' EXIT
for _ in $(seq 50); do grep -q '^READY' "$vpout" && break; sleep 0.1; done
grep -q '^READY' "$vpout" || { echo "FAIL: no virtual pointer"; cat "$vpout"; exit 1; }

for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 2
swaymsg -q '[title="drag-source"] move position 100 100, focus'
swaymsg -q '[title="drag-target"] move position 600 100'
sleep 0.5

center() { # print "x y" of the middle of the window with this title, in layout coordinates
    swaymsg -t get_tree | python3 -I -c '
import json, sys
def walk(n):
    if n.get("name") == sys.argv[1] and n.get("shell") == "xdg_shell":
        r = n["rect"]
        print(r["x"] + r["width"] // 2, r["y"] + r["height"] // 2)
        return True
    return any(walk(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
walk(json.load(sys.stdin))' "$1"
}

status=0
# name, modifier key held (or "none"), mask the target should see, operation the source should get
for spec in "plain none 17 16" "option alt 1 1"; do
    set -- $spec
    name=$1 key=$2 mask=$3 op=$4
    from=$(center drag-source) to=$(center drag-target)
    [ -n "$from" ] && [ -n "$to" ] || { echo "FAIL: $name: no windows"; status=1; continue; }
    set -- $from; sx=$1 sy=$2
    set -- $to; tx=$1 ty=$2
    start=$(wc -l < "$out")
    dragged=$(grep -c '^DRAGGED' "$vpout")
    [ $key = none ] || { wtype -M $key -s 4000 -m $key & held=$!; sleep 0.3; }
    echo "drag $sx $sy $((tx - sx)) $((ty - sy))" >&3
    for _ in $(seq 100); do [ "$(grep -c '^DRAGGED' "$vpout")" -gt "$dragged" ] && break; sleep 0.1; done
    sleep 1
    [ $key = none ] || wait $held
    lines=$(tail -n +$((start + 1)) "$out" | grep '^SOURCE\|^TARGET')
    order=$(echo "$lines" | grep '^SOURCE' | sed 's/^SOURCE //' | grep -v '^moved$' | tr '\n' ' ')
    if [ "$order" = "willBegin ended op=$op " ]; then echo "PASS: $name: source callbacks: $order"
    else echo "FAIL: $name: source callbacks: $order; expected willBegin ended op=$op"; status=1; fi
    seen=$(echo "$lines" | grep '^TARGET mask=' | tail -1)
    if [ "$seen" = "TARGET mask=$mask" ]; then echo "PASS: $name: $seen"
    else echo "FAIL: $name: last mask '$seen'; expected TARGET mask=$mask"; status=1; fi
    drop=$(echo "$lines" | grep '^TARGET drop')
    want="TARGET drop source=yes valid=2 enumerated=2 urls=/private/var/tmp/drag-a,/private/var/tmp/drag-b"
    if [ "$drop" = "$want" ]; then echo "PASS: $name: $drop"
    else echo "FAIL: $name: '$drop'; expected $want"; status=1; fi
done
kill $pid 2>/dev/null
wait $pid 2>/dev/null
[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
exit $status
