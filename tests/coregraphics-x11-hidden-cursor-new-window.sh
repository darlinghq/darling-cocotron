#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of coregraphics-x11-hidden-cursor-new-window: moves the pointer over each window of the program on $DISPLAY
# (which must have a window manager), asks the server which cursor it shows there (XFixes), and gives the program its
# commands as keys (XTest). Usage:
#   coregraphics-x11-hidden-cursor-new-window.sh <command that runs coregraphics-x11-hidden-cursor-new-window>
# Needs xdotool (the window geometry and focus) and a C compiler with the Xlib, XTest and XFixes headers.
set -u
work=$(mktemp -d)
out=$work/out
here=$(cd "$(dirname "$0")" && pwd)
cc -o "$work/xptr" "$here/x11-xtest-pointer.c" -lX11 -lXtst || { echo "FAIL: cannot build the pointer injector"; exit 1; }
cc -o "$work/cursor" "$here/x11-cursor-image.c" -lX11 -lXtst -lXfixes || { echo "FAIL: cannot build the cursor probe"; exit 1; }
# The X key codes of the command letters (evdev): h s n q
key() { "$work/xptr" 250 k:$1:1 k:$1:0; }
h=43 s=39 n=57 q=24

"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$work"' EXIT

for _ in $(seq 600); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
first=$(sed -n 's/^READY \([0-9]*\) .*/\1/p' "$out" | head -1)
second=$(sed -n 's/^READY [0-9]* \([0-9]*\)/\1/p' "$out" | head -1)
sleep 1

failures=0
check() { # <what> <window> <expected: blank|visible>
    eval "$(xdotool getwindowgeometry --shell "$2")"
    got=$("$work/cursor" $((X + 150)) $((Y + 120)))
    if [ "${got%% *}" = "$3" ]; then echo "PASS $1: $got"; else echo "FAIL $1: expected $3, got $got"; failures=$((failures + 1)); fi
}
xdotool windowfocus --sync "$first" 2>/dev/null
sleep 0.3

check "the window that was there when the cursor was hidden shows the blank cursor" "$first" blank
check "the window made while the cursor was hidden shows the blank cursor" "$second" blank
key $n
for _ in $(seq 50); do grep -q '^NEW' "$out" && break; sleep 0.1; done
third=$(sed -n 's/^NEW \([0-9]*\)/\1/p' "$out" | head -1)
if [ -z "$third" ] || [ "$third" = 0 ]; then echo "FAIL: no third window"; failures=$((failures + 1)); else
    sleep 0.5
    check "a window made later, while the cursor is still hidden, shows the blank cursor" "$third" blank
fi
xdotool windowfocus --sync "$first" 2>/dev/null
key $s
sleep 0.3
check "after the show the first window has a cursor again" "$first" visible
check "after the show the window made while hidden has a cursor again" "$second" visible
[ -n "$third" ] && check "after the show the third window has a cursor again" "$third" visible
key $q

for _ in $(seq 100); do grep -q '^DONE' "$out" && break; sleep 0.1; done
wait $pid
status=$?
grep -v -E '^(READY|NEW|DONE)' "$out"
if [ $failures -eq 0 ] && [ $status -eq 0 ]; then echo "ALL PASSED"; exit 0; fi
echo "FAILED $failures"
exit 1
