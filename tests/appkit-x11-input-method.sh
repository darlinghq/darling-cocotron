#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of appkit-x11-input-method: runs the test input method x11-test-xim-server.c on $DISPLAY, which must have
# a window manager, and types into the window "xim-input-method" with XTest (xdotool). The command that runs the
# program must give it XMODIFIERS=@im=testxim and a UTF-8 locale (LANG=en_US.UTF-8) in its environment. Usage:
#   appkit-x11-input-method.sh <command that runs appkit-x11-input-method>
# Checks the log of the input method as well: it was given the spot the program printed as EXPECT SPOT. Needs
# xdotool and a C compiler with the Xlib, XTest and xcb-imdkit headers (the key injector and the input method).
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
sleep 1.5
win=$(xdotool search --name '^xim-input-method$' | head -1)
[ -n "$win" ] || { echo "FAIL: no window"; cat "$out"; exit 1; }
xdotool windowactivate --sync "$win" 2>/dev/null
xdotool windowfocus --sync "$win" 2>/dev/null
sleep 0.5

# X key codes (evdev): a 38, b 56, c 54, 1 10, BackSpace 22, Return 36, Escape 9
P=0.4
t() { K 120 "$1:1" "$1:0"; sleep $P; }
t 38; t 56            # a b
t 22                  # BackSpace
t 56; t 36            # b Return
t 54; t 9             # c Escape
t 11; t 9             # 2 Escape
t 12; t 9             # 3 Escape
t 13                  # 4
t 10                  # 1

for _ in $(seq 300); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
echo "input method log:"; sed 's/^/  /' "$work/xim.log"
expected=$(sed -n 's/^EXPECT SPOT //p' "$out" | head -1)
if [ -n "$expected" ] && grep -q "^SPOT $expected\$" "$work/xim.log"; then
    echo "PASS the input method was told the spot of the client's caret ($expected)"
else
    echo "FAIL the input method was not told the spot $expected"; status=1
fi
if grep -q '^STYLE onthespot' "$work/xim.log"; then echo "PASS the window used the on-the-spot style"; else echo "FAIL the window did not use the on-the-spot style"; status=1; fi
exit $status
