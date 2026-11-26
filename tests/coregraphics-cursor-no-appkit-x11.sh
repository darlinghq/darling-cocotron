#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of coregraphics-cursor-no-appkit on X11: moves the pointer over the window of the program on $DISPLAY (which
# must have a window manager) and, when the program announces a step, asks the server which cursor image it shows there
# (XFixes). Usage:
#   coregraphics-cursor-no-appkit-x11.sh <command that runs coregraphics-cursor-no-appkit>
# Needs xdotool and a C compiler with the Xlib, XTest and XFixes headers.
set -u
work=$(mktemp -d)
out=$work/out
here=$(cd "$(dirname "$0")" && pwd)
cc -o "$work/cursor" "$here/x11-cursor-image.c" -lX11 -lXtst -lXfixes || { echo "FAIL: cannot build the cursor probe"; exit 1; }

"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$work"' EXIT

for _ in $(seq 600); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
grep -q '^NOSPI' "$out" && echo "FAIL: the cursor SPI is missing"
win=$(sed -n 's/^WINDOW \([0-9]*\)/\1/p' "$out" | head -1)
eval "$(xdotool getwindowgeometry --shell "$win")"
sleep 1
# The first probe moves the pointer into the window, which starts the steps.
"$work/cursor" $((X + 200)) $((Y + 150)) > /dev/null

failures=0
grep -q '^NOSPI' "$out" && failures=1
probe() { "$work/cursor" $((X + 200)) $((Y + 150)); }
check() { # <step> <what> <pattern, an extended regular expression the cursor description has to match>
    for _ in $(seq 300); do grep -q "^STEP $1 " "$out" && break; sleep 0.1; done
    got=$(probe)
    if [[ $got =~ $3 ]]; then echo "PASS $2: $got"; else echo "FAIL $2: expected /$3/, got $got"; failures=$((failures + 1)); fi
}
check 1 "hidden: nothing is shown" '^blank$'
check 2 "shown again with no cursor selected: the default cursor" '^visible'
check 3 "the I-beam shape is not the default one's image" '^visible .*'
check 4 "the image cursor, 16x16, hot spot 3,5, red" '^visible 16x16 hot=3,5 pixel=ffff0000$'
check 5 "hidden again" '^blank$'
check 6 "an image selected while hidden stays hidden" '^blank$'
check 7 "shown: the image selected meanwhile, 16x16 points, hot spot 4,6, green" '^visible 16x16 hot=4,6 pixel=ff00ff00$'
check 8 "no cursor selected: the default cursor" '^visible [0-9]+x[0-9]+ hot=[0-9]+,[0-9]+ pixel=[0-9a-f]{8}$'
for _ in $(seq 100); do grep -q '^DONE' "$out" && break; sleep 0.1; done
wait $pid
if [ $failures -eq 0 ]; then echo "ALL PASSED"; exit 0; fi
echo "FAILED $failures"
exit 1
