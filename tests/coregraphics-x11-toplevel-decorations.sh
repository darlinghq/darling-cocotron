#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of coregraphics-x11-toplevel-decorations: asks the X server on $DISPLAY (which must have a window manager) what
# became of the windows of the program, which sees only CoreGraphics: which of them the window manager frames (the Motif
# hints), which have their corners cut (a window that shows no title bar of its own), that the frames follow a change of the
# kind of a shown window, and that the window manager moves a window when the program asks for it from a left button press.
# Usage: coregraphics-x11-toplevel-decorations.sh <command that runs coregraphics-x11-toplevel-decorations>
# (the command gets the directory the program watches as its last argument, with $GUEST_PATH_PREFIX in front of it when the
# program sees the host's files under a prefix; in a Darling guest: /Volumes/SystemRoot). Needs xdotool, xprop and a C
# compiler with the Xlib and Xext headers.
set -u
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
out=$(mktemp)
dir=$(mktemp -d)
cc -Wall "$here/x11-chromeless-window-shape.c" -lX11 -lXext -o "$dir/shape" || { echo "FAIL: no shape tool"; exit 1; }
"$@" "${GUEST_PATH_PREFIX:-}$dir" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$out" "$dir"' EXIT
for _ in $(seq 400); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { cat "$out"; grep -q '^SKIP' "$out" && exit 0; echo "FAIL: the program never became ready"; exit 1; }
status=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; status=1; }
find_window() { xdotool search --name "^$1\$" | head -1; }
framed() { xprop -id "$1" _MOTIF_WM_HINTS 2>/dev/null | grep -q 'not found'; } # no hint at all leaves the frame to the manager
unframed() { xprop -id "$1" _MOTIF_WM_HINTS 2>/dev/null | grep -q '= 0x2, 0x0, 0x0, 0x0, 0x0'; }
sleep 1
none=$(find_window tbk-none); standard=$(find_window tbk-standard); hidden=$(find_window tbk-hidden); mover=$(find_window tbk-move)
[ -n "$none" ] && [ -n "$standard" ] && [ -n "$hidden" ] && [ -n "$mover" ] || { cat "$out"; echo "FAIL: windows are missing"; exit 1; }
unframed "$none" && ok "a window with no title bar has no frame" || bad "tbk-none: $(xprop -id "$none" _MOTIF_WM_HINTS)"
framed "$standard" && ok "a window with a standard title bar has the manager's frame" || bad "tbk-standard: $(xprop -id "$standard" _MOTIF_WM_HINTS)"
unframed "$hidden" && ok "a window that shows no title bar of its own has no frame" || bad "tbk-hidden: $(xprop -id "$hidden" _MOTIF_WM_HINTS)"
shapes=$("$dir/shape" | sort)
grep -qx 'tbk-hidden: corners cut' <<< "$shapes" && ok "the corners of a window without a title bar of its own are cut" || bad "tbk-hidden corners: $shapes"
grep -qx 'tbk-none: corners whole' <<< "$shapes" && ok "a window with no title bar keeps its corners" || bad "tbk-none corners: $shapes"
grep -qx 'tbk-standard: corners whole' <<< "$shapes" && ok "a window with a standard title bar keeps its corners" || bad "tbk-standard corners: $shapes"

touch "$dir/go1"
for _ in $(seq 100); do grep -q '^STAGE 1$' "$out" && break; sleep 0.1; done
sleep 0.5
framed "$none" && ok "a window given a title bar is framed" || bad "tbk-none after: $(xprop -id "$none" _MOTIF_WM_HINTS)"
unframed "$standard" && ok "a window that lost its title bar is not framed" || bad "tbk-standard after: $(xprop -id "$standard" _MOTIF_WM_HINTS)"

# The window manager moves the window the program asks it to move from a press.
eval "$(xdotool getwindowgeometry --shell "$mover")"
x0=$X y0=$Y
x=$((x0 + 100)) y=$((y0 + 60))
xdotool mousemove $x $y; sleep 0.3
xdotool mousedown 1; sleep 0.3
for i in 1 2 3 4 5 6 7 8; do xdotool mousemove $((x + 80 * i / 8)) $((y + 60 * i / 8)); sleep 0.05; done
sleep 0.3
xdotool mouseup 1; sleep 1
eval "$(xdotool getwindowgeometry --shell "$mover")"
[ $((X - x0)) = 80 ] && [ $((Y - y0)) = 60 ] && ok "the window manager moved the window by the pointer's movement" || bad "moved by $((X - x0)),$((Y - y0))"
grep -q '^MOVE asked=1 accepted=1' "$out" && ok "the program asked once and the request was accepted" || bad "move requests: $(grep '^MOVE' "$out" | tr '\n' ' ')"

touch "$dir/go2"
wait $pid 2>/dev/null
rc=$?
grep '^\(PASS\|FAIL\)' "$out"
grep -q '^FAIL' "$out" && status=1
grep -q '^RESULT failures=0' "$out" || status=1
[ $status = 0 ] && echo "RESULT failures=0" || echo "RESULT failures=1"
exit $status
