#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of coregraphics-x11-input-method-no-appkit: runs the test input method x11-test-xim-server.c on $DISPLAY,
# which must have a window manager, gives the program's X window the keyboard focus and types into it with XTest
# (xdotool). The command that runs the program must give it XMODIFIERS=@im=testxim and a UTF-8 locale
# (LANG=en_US.UTF-8) in its environment. Usage:
#   coregraphics-x11-input-method-no-appkit.sh <command that runs coregraphics-x11-input-method-no-appkit>
# Checks the log of the input method as well: it was given the spot the program set (10,36: the bottom left
# corner of the cursor rectangle 10,20 2x16) and then the one it moved to (50,76). Needs xdotool and a C
# compiler with the Xlib, XTest and xcb-imdkit headers (the key injector and the input method).
set -u
work=$(mktemp -d)
out=$work/out
here=$(cd "$(dirname "$0")" && pwd)
cc -o "$work/xkeys" "$here/x11-xtest-keys.c" -lX11 -lXtst || { echo "FAIL: cannot build the key injector"; exit 1; }
cc -o "$work/xim" "$here/x11-test-xim-server.c" -lxcb -lxcb-imdkit -lxcb-keysyms || { echo "FAIL: cannot build the input method"; exit 1; }
K() { "$work/xkeys" "$@"; }
"$work/xim" testxim "$work/xim.log" &
xim=$!
for _ in $(seq 100); do grep -q '^READY' "$work/xim.log" 2>/dev/null && break; sleep 0.1; done
grep -q '^READY' "$work/xim.log" || { echo "FAIL: the input method did not start"; kill $xim 2>/dev/null; rm -rf "$work"; exit 1; }
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid $xim 2>/dev/null; rm -rf "$work"' EXIT

for _ in $(seq 600); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
win=$(sed -n 's/^READY //p' "$out" | head -1)
sleep 1
xdotool windowactivate --sync "$win" 2>/dev/null
xdotool windowfocus "$win" 2>/dev/null
sleep 0.5

# X key codes (evdev): 2 11, 3 12, 4 13, a 38, b 56, c 54, d 40, 1 10, BackSpace 22, Return 36, Escape 9, Tab 23, F2 68
P=0.4
t() { K 120 "$1:1" "$1:0"; sleep $P; }
t 38; t 56            # a b
t 22                  # BackSpace
t 56; t 36            # b Return
t 54; t 9             # c Escape
t 11; t 9             # 2 Escape
t 12; t 9             # 3 Escape
t 13                  # 4
t 23                  # Tab
t 68                  # F2
t 40                  # d
t 10                  # 1

for _ in $(seq 300); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
echo "input method log:"; sed 's/^/  /' "$work/xim.log"
check() { if grep -q "$2" "$work/xim.log"; then echo "PASS $1"; else echo "FAIL $1"; status=1; fi; }
check "the input method offered the on-the-spot style and the window used it" '^STYLE onthespot'
check "the input method was given the keyboard focus of the window" '^FOCUS'
check "the input method was told the spot (the bottom left of the cursor rectangle)" '^SPOT 10 36$'
check "and the spot the rectangle was moved to" '^SPOT 50 76$'
exit $status
