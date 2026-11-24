#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Reads _NET_WM_ICON of the window of tests/appkit-window-icon.m on $DISPLAY (a display with a window
# manager) and checks it holds the application icon: for the "bundle" mode the green icon of the bundle,
# for "runtime" the red image given to -setApplicationIconImage:, and for "change" red first and blue after
# the image was replaced. Usage:
#   appkit-window-icon-x11.sh bundle|runtime|change|nested|nested-regular|nested-runtime|plain <command that runs the guest binary, such as "darling shell /path/appkit-window-icon">
# The program gets the mode and a duration of 14 seconds appended.
# The command's environment must have DARLING_APPKIT_BACKEND=x11 and DISPLAY. Needs xdotool, xprop and python3.
set -u
mode=$1; shift
out=$(mktemp)
"$@" "$mode" 14 > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$out"' EXIT

wait_for() {
    for _ in $(seq 200); do grep -q "^$1\$" "$out" && return 0; sleep 0.1; done
    return 1
}

# Prints "<number of sizes> <sizes> <colour at the centre of the largest, as AARRGGBB>" or "none".
icon() {
    local id
    id=$(xdotool search --name '^icon-test$' | head -1)
    [ -n "$id" ] || { echo none; return; }
    xprop -len 1000000 -id "$id" -f _NET_WM_ICON 32c -notype _NET_WM_ICON | python3 -I -c '
import sys
text = sys.stdin.read()
if "=" not in text:
    print("none"); sys.exit()
values = [int(v) for v in text.split("=", 1)[1].replace(",", " ").split()]
sizes, centre, i = [], 0, 0
while i + 2 <= len(values):
    w, h = values[i], values[i + 1]
    pixels = values[i + 2:i + 2 + w * h]
    if len(pixels) != w * h:
        print("truncated"); sys.exit()
    sizes.append(w)
    if w == max(sizes):
        centre = pixels[(h // 2) * w + w // 2]
    i += 2 + w * h
print(len(sizes), ",".join(str(s) for s in sizes), "%08X" % centre)'
}

status=0
check() { # what, expected colour
    local got
    got=$(icon)
    case "$got" in
    *" $2") echo "PASS: $1: $got" ;;
    *) echo "FAIL: $1: got '$got', expected a centre colour of $2"; status=1 ;;
    esac
}

wait_for READY || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 1
case "$mode" in
bundle) check "bundle icon" FF00FF00 ;;
runtime) check "runtime icon" FFFF0000 ;;
nested|nested-noext) check "icon of the enclosing application" FF00FF00 ;;
nested-runtime) check "the helper's own image wins" FFFF0000 ;;
plain|nested-regular)
    got=$(icon)
    [ "$got" = none ] && echo "PASS: no _NET_WM_ICON for $mode" || { echo "FAIL: $mode has an icon: $got"; status=1; } ;;
change)
    check "first icon" FFFF0000
    wait_for CHANGED || { echo "FAIL: the image was never changed"; status=1; }
    sleep 1
    check "icon after setApplicationIconImage:" FF0000FF
    ;;
esac
exit $status
