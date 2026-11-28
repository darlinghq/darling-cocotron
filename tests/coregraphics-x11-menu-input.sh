#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of coregraphics-x11-menu-input: asks the X server on $DISPLAY (which must have a window manager that handles docks)
# whether another client can grab the pointer and the keyboard while the program, which sees only CoreGraphics, shows the
# window of a menu that holds the input for it, and whether the window carries the address of its application menu.
# Usage: coregraphics-x11-menu-input.sh <command that runs coregraphics-x11-menu-input>
# (the command gets the directory the program watches as its last argument, with $GUEST_PATH_PREFIX in front of it when the
# program sees the host's files under a prefix; in a Darling guest: /Volumes/SystemRoot). Needs xdotool, xprop and a C compiler with the
# Xlib headers.
set -u
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
out=$(mktemp)
dir=$(mktemp -d)
cc -Wall "$here/x11-grab-probe.c" -lX11 -o "$dir/probe" || { echo "FAIL: no probe"; exit 1; }
"$@" "${GUEST_PATH_PREFIX:-}$dir" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$out" "$dir"' EXIT
for _ in $(seq 400); do grep -q '^\(READY\|SKIP\)' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { cat "$out"; grep -q '^SKIP' "$out" && exit 0; echo "FAIL: the program never became ready"; exit 1; }
status=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; status=1; }
advance() { touch "$dir/go$1"; for _ in $(seq 100); do grep -q "^STAGE $1\$" "$out" && break; sleep 0.1; done; sleep 0.3; }
win=$(xdotool search --name '^menu-window$' | head -1)
[ -n "$win" ] || { cat "$out"; echo "FAIL: no window"; exit 1; }
grep -q '^FLAGS places=1' "$out" && ok "the window manager places the menu bar" || bad "$(grep '^FLAGS' "$out")"
xprop -id "$win" _KDE_NET_WM_APPMENU_SERVICE_NAME | grep -q '"org.example.menu"' && ok "the window carries the service name of its menu" || bad "service: $(xprop -id "$win" _KDE_NET_WM_APPMENU_SERVICE_NAME)"
xprop -id "$win" _KDE_NET_WM_APPMENU_OBJECT_PATH | grep -q '"/MenuBar"' && ok "the window carries the object path of its menu" || bad "path: $(xprop -id "$win" _KDE_NET_WM_APPMENU_OBJECT_PATH)"
[ "$("$dir/probe")" = "pointer=0 keyboard=0" ] && ok "nothing is held while no menu is shown" || bad "grabs before a menu: $("$dir/probe")"

advance 1
[ "$("$dir/probe")" = "pointer=1 keyboard=1" ] && ok "the pointer and the keyboard are held for a menu that is shown" || bad "grabs with a menu: $("$dir/probe")"
advance 2
[ "$("$dir/probe")" = "pointer=1 keyboard=1" ] && ok "they are still held while a menu is shown after another one went" || bad "grabs after a second menu: $("$dir/probe")"
advance 3
[ "$("$dir/probe")" = "pointer=0 keyboard=0" ] && ok "they are let go when the last menu is hidden" || bad "grabs after the menus: $("$dir/probe")"
advance 4
xprop -id "$win" _KDE_NET_WM_APPMENU_SERVICE_NAME | grep -q 'not found' && ok "a withdrawn address is gone from the window" || bad "service remains: $(xprop -id "$win" _KDE_NET_WM_APPMENU_SERVICE_NAME)"

touch "$dir/go5"
wait $pid 2>/dev/null
grep '^\(PASS\|FAIL\)' "$out"
grep -q '^FAIL' "$out" && status=1
grep -q '^RESULT failures=0' "$out" || status=1
[ $status = 0 ] && echo "RESULT failures=0" || echo "RESULT failures=1"
exit $status
