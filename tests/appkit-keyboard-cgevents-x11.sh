#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of appkit-keyboard-cgevents-x11: types with XTest (xdotool) on $DISPLAY, which must have a window
# manager, into the window "kbd-cgevents-x11". Usage:
#   appkit-keyboard-cgevents-x11.sh <command that runs appkit-keyboard-cgevents-x11>
# Needs xdotool (windows) and a C compiler with the Xlib and XTest headers (for the window of another client and
# the key injector).
set -u
work=$(mktemp -d)
out=$work/out
here=$(cd "$(dirname "$0")" && pwd)
cc -o "$work/xkeys" "$here/x11-xtest-keys.c" -lX11 -lXtst || { echo "FAIL: cannot build the key injector"; exit 1; }
K() { "$work/xkeys" "$@"; }

# A window of another client, which takes the keyboard focus away from the application
cat > "$work/other.c" <<'C'
#include <X11/Xlib.h>
#include <stdio.h>
#include <unistd.h>
int main(void) {
    Display *d = XOpenDisplay(NULL);
    if (!d) return 1;
    Window w = XCreateSimpleWindow(d, DefaultRootWindow(d), 600, 400, 200, 100, 0, 0, 0xffffff);
    XStoreName(d, w, "kbd-other-client");
    XSelectInput(d, w, StructureNotifyMask | KeyPressMask);
    XMapWindow(d, w);
    XFlush(d);
    printf("mapped\n");
    fflush(stdout);
    for (;;) { XEvent e; XNextEvent(d, &e); }
}
C
cc -o "$work/other" "$work/other.c" -lX11 || { echo "FAIL: cannot build the other client"; exit 1; }
"$work/other" > "$work/other.out" 2>&1 &
other=$!

"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid $other 2>/dev/null; rm -rf "$work"' EXIT

for _ in $(seq 600); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 1.5

win=$(xdotool search --name '^kbd-cgevents-x11$' | head -1)
foreign=$(xdotool search --name '^kbd-other-client$' | head -1)
[ -n "$win" ] && [ -n "$foreign" ] || { echo "FAIL: no windows"; cat "$out"; exit 1; }
focus() {
    xdotool windowactivate --sync "$1" 2>/dev/null
    xdotool windowfocus --sync "$1" 2>/dev/null
    sleep 0.4
}
focus "$win"

K 150 38:1 38:0
sleep 0.3
K 150 50:1 38:1 38:0 50:0
sleep 0.3
K 150 62:1 62:0
sleep 0.3
K 150 37:1 38:1 38:0 37:0
sleep 0.3
K 150 64:1 64:0
sleep 0.3
K 1500 39:1
K 150 39:0
sleep 0.3
K 150 40:1 40:0
sleep 0.3
K 150 23:1 23:0
sleep 0.3
K 150 50:1 23:1 23:0 50:0
sleep 0.3
# Shift goes down while the other client has the focus, and up after the application has it back
focus "$foreign"
K 150 50:1
focus "$win"
sleep 0.3
K 150 50:0
sleep 0.3
K 150 24:1 24:0

for _ in $(seq 600); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
exit $status
