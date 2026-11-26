#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of coregraphics-x11-toplevel-window: gives the program its stages and asks the X server on $DISPLAY (which
# must have a window manager) what became of the windows: their title, class, owner, protocols, size limits, opacity,
# whether the window manager leaves them alone, and the depth of the window made translucent.
# Usage: coregraphics-x11-toplevel-window.sh <command that runs coregraphics-x11-toplevel-window>
# (the command gets the directory the program watches as its last argument, with $GUEST_PATH_PREFIX in front of it
# when the program sees the host's files under a prefix; in a Darling guest: /Volumes/SystemRoot).
# Needs xdotool, xprop and a C compiler with the Xlib headers.
set -u
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
out=$(mktemp)
dir=$(mktemp -d)
probe=$dir/probe
cc -Wall "$here/coregraphics-x11-toplevel-window-probe.c" -lX11 -o "$probe" || { echo "FAIL: no probe"; exit 1; }
"$@" "${GUEST_PATH_PREFIX:-}$dir" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$out" "$dir"' EXIT
for _ in $(seq 400); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the program never became ready"; cat "$out"; exit 1; }
grep '^SKIP' "$out" && exit 0
status=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; status=1; }
find_window() { xdotool search --name "^$1\$" | head -1; }
property() { xprop -id "$1" "$2" 2>/dev/null; }
size() { sed -n "s/.*program specified $1 size: \\([0-9]*\\) by \\([0-9]*\\).*/\\1x\\2/p" <<< "$2"; }
advance() { touch "$dir/go$1"; for _ in $(seq 100); do grep -q "^STAGE $1\$" "$out" && break; sleep 0.1; done; sleep 0.5; }

unmanaged=$(find_window tl-unmanaged)
managed=$(find_window tl-managed)
[ -n "$unmanaged" ] && ok "the unmanaged window has its title as its name" || bad "no window named tl-unmanaged"
[ -n "$managed" ] && ok "the managed window has its title as its name" || bad "no window named tl-managed"
[ -n "$managed" ] && [ -n "$unmanaged" ] || { echo "RESULT failures=1"; exit 1; }

property "$managed" _NET_WM_NAME | grep -q '"tl-managed"' && ok "_NET_WM_NAME is set" || bad "_NET_WM_NAME is missing"
property "$managed" WM_NAME | grep -q '"tl-managed"' && ok "WM_NAME is set" || bad "WM_NAME is missing"
property "$managed" WM_PROTOCOLS | grep -q WM_DELETE_WINDOW && ok "the window takes part in the close protocol" || bad "WM_DELETE_WINDOW is missing"
property "$managed" WM_CLASS | grep -q 'coregraphics-x11-toplevel-window' && ok "the class names the program" || bad "WM_CLASS does not name the program"
property "$managed" _NET_WM_PID | grep -q '= [0-9]' && ok "the owner is published" || bad "_NET_WM_PID is missing"
hints=$(property "$managed" WM_NORMAL_HINTS)
[ "$(size minimum "$hints")" = 200x150 ] && [ "$(size maximum "$hints")" = 800x600 ] && ok "the size limits are hinted" || bad "size hints: $hints"
grep -q 'user specified location\|program specified location' <<< "$hints" && ok "a managed window positions itself" || bad "no position hint: $hints"
property "$managed" _NET_WM_WINDOW_OPACITY | grep -q '= 2147483647' && ok "alpha 0.5 is the opacity property" || bad "opacity: $(property "$managed" _NET_WM_WINDOW_OPACITY)"
"$probe" "$managed" | grep -q 'override=0' && ok "the window manager manages it" || bad "the managed window is override-redirect"
"$probe" "$unmanaged" | grep -q 'override=1' && ok "an unmanaged window is override-redirect" || bad "the unmanaged window is managed"
"$probe" "$managed" | grep -q 'map=2' && ok "the shown window is mapped" || bad "the shown window is not mapped"

advance 1
property "$managed" _NET_WM_WINDOW_OPACITY | grep -q 'not found' && ok "alpha 1 removes the opacity property" || bad "opacity stays: $(property "$managed" _NET_WM_WINDOW_OPACITY)"
hints=$(property "$managed" WM_NORMAL_HINTS)
[ -z "$(size minimum "$hints")" ] && [ -z "$(size maximum "$hints")" ] && ok "no limits leave no size hints" || bad "size hints remain: $hints"

advance 2
again=$(find_window tl-managed)
[ -n "$again" ] && [ "$again" != "$managed" ] && ok "the recreated window is another X window" || bad "the recreated window is not new"
"$probe" "$again" | grep -q 'depth=32' && ok "the recreated window has the 32-bit visual" || bad "depth: $("$probe" "$again")"
[ -z "$(xdotool search --onlyvisible --name '^tl-managed$' | grep -x "$managed")" ] && ok "the old window is gone" || bad "the old window is still shown"

advance 3
[ -z "$(find_window tl-unmanaged)$(find_window tl-managed)" ] && ok "released windows are gone" || bad "released windows remain"
wait $pid 2>/dev/null
grep '^\(PASS\|FAIL\)' "$out" | sed 's/^/program: /'
grep -q '^FAIL' "$out" && status=1
[ $status = 0 ] && echo "RESULT failures=0" || echo "RESULT failures=1"
exit $status
