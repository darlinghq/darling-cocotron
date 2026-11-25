#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drags from the window "source" of tests/appkit-dragging-session-drop.m to its window "target" with
# XTest (xdotool) on $DISPLAY, and checks that the drag ran as a session: the source heard only the
# session's messages, the target got the dragged string, and the drag ended as a copy. Usage:
#   appkit-dragging-session-x11.sh <command that runs "appkit-dragging-session-drop <seconds>">
# for example: appkit-dragging-session-x11.sh darling shell /path/appkit-dragging-session-drop 30
# Needs xdotool.
set -u
out=$(mktemp)
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$out"' EXIT

for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 1

center() {
    local id
    id=$(xdotool search --name "^$1\$" | head -1)
    [ -n "$id" ] || { echo "FAIL: no window $1" >&2; return 1; }
    eval "$(xdotool getwindowgeometry --shell "$id")"
    echo $((X + WIDTH / 2)) $((Y + HEIGHT / 2))
}
read -r sx sy < <(center source) || exit 1
read -r tx ty < <(center target) || exit 1

xdotool mousemove $sx $sy
sleep 0.3
xdotool mousedown 1
sleep 0.2
for i in $(seq 1 12); do
    xdotool mousemove $((sx + (tx - sx) * i / 12)) $((sy + (ty - sy) * i / 12))
    sleep 0.1
done
sleep 0.5
xdotool mouseup 1

for _ in $(seq 100); do grep -q '^ended\|^timeout' "$out" && break; sleep 0.1; done
wait $pid

status=0
check() {
    if grep -q "$1" "$out"; then echo "PASS: $2"; else echo "FAIL: $2"; status=1; fi
}
check '^mask ' "the source is asked for its operations through the session"
check '^began$' "the source hears the session begin"
check '^entered 1$' "the target sees one valid item"
check '^dropped payload$' "the target enumerates the dragged string"
check '^ended copy$' "the session ends with the target's operation"
if grep -q '^legacy$' "$out"; then echo "FAIL: a session sent a pre-10.7 source message"; status=1
else echo "PASS: no pre-10.7 source message"; fi
[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
exit $status
