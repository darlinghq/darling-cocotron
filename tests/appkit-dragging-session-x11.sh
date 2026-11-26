#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drags from the "drag-source" window of tests/appkit-dragging-session-live.m to its "drag-target" window with XTest
# (xdotool) on $DISPLAY, which must have a window manager: once plainly, once holding Option (Alt), and checks the
# session callbacks (only the session's: a pre-10.7 source message would show in their order as "legacy"), the mask
# the target saw and what it read. Usage:
#   appkit-dragging-session-x11.sh <command that runs "appkit-dragging-session-live <seconds>">
# for example: appkit-dragging-session-x11.sh darling shell /path/appkit-dragging-session-live 30
# Needs xdotool.
set -u
out=$(mktemp)
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$out"' EXIT

for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 2

center() { # print "x y" of the middle of the window with this title
    local id
    id=$(xdotool search --name "^$1\$" | head -1)
    [ -n "$id" ] || return 1
    eval "$(xdotool getwindowgeometry --shell "$id")"
    echo $((X + WIDTH / 2)) $((Y + HEIGHT / 2))
}

status=0
# name, modifier key held while dropping (or "none"), mask the target should see, operation the source should get
for spec in "plain none 17 16" "option alt 1 1"; do
    set -- $spec
    name=$1 key=$2 mask=$3 op=$4
    from=$(center drag-source) && to=$(center drag-target) || { echo "FAIL: $name: no windows"; status=1; continue; }
    set -- $from; sx=$1 sy=$2
    set -- $to; tx=$1 ty=$2
    start=$(wc -l < "$out")
    xdotool mousemove $sx $sy
    sleep 0.3
    xdotool mousedown 1
    sleep 0.3
    for i in 1 2 3 4 5 6 7 8 9 10; do
        xdotool mousemove $((sx + (tx - sx) * i / 10)) $((sy + (ty - sy) * i / 10))
        sleep 0.1
    done
    [ $key = none ] || { xdotool keydown $key; sleep 0.2; xdotool mousemove $((tx + 3)) $ty; sleep 0.3; }
    xdotool mouseup 1
    sleep 0.3
    [ $key = none ] || xdotool keyup $key
    sleep 1
    lines=$(tail -n +$((start + 1)) "$out" | grep '^SOURCE\|^TARGET')
    order=$(echo "$lines" | grep '^SOURCE' | sed 's/^SOURCE //' | uniq | tr '\n' ' ')
    if [ "$order" = "willBegin moved ended op=$op " ]; then echo "PASS: $name: source callbacks: $order"
    else echo "FAIL: $name: source callbacks: $order; expected willBegin moved ended op=$op"; status=1; fi
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
