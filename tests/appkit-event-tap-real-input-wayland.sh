#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# The Wayland counterpart of appkit-event-tap-real-input-x11.sh: types "a" with a virtual keyboard
# (wtype) and clicks in the middle of the window "tap-real-input" with a virtual pointer
# (tests/wayland-virtual-pointer.c, in $VIRTUAL_POINTER). $WAYLAND_DISPLAY, $XDG_RUNTIME_DIR and
# $SWAYSOCK must name a headless sway (darling-skills' wayland.sh) whose windows float. Usage:
#   appkit-event-tap-real-input-wayland.sh <command that runs appkit-event-tap-real-input>
# Needs swaymsg, wtype and python3.
set -u
pointer=${VIRTUAL_POINTER:?path of the built wayland-virtual-pointer helper}
work=$(mktemp -d)
out=$work/out vpout=$work/pointer
mkfifo "$work/fifo"
"$pointer" < "$work/fifo" > "$vpout" 2>&1 &
vp=$!
exec 3> "$work/fifo"
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'exec 3>&-; kill $pid $vp 2>/dev/null; rm -rf "$work"' EXIT
for _ in $(seq 50); do grep -q '^READY' "$vpout" && break; sleep 0.1; done
grep -q '^READY' "$vpout" || { echo "FAIL: no virtual pointer"; cat "$vpout"; exit 1; }

for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 2
swaymsg -q '[title="tap-real-input"] move position 200 200, focus'
sleep 0.5

# The middle of the window, in layout coordinates
middle=$(swaymsg -t get_tree | python3 -I -c '
import json, sys
def walk(n):
    if n.get("name") == "tap-real-input" and n.get("shell") == "xdg_shell":
        r = n["rect"]
        print(r["x"] + r["width"] // 2, r["y"] + r["height"] // 2)
        return True
    return any(walk(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
walk(json.load(sys.stdin))')
[ -n "$middle" ] || { echo "FAIL: no window"; cat "$out"; exit 1; }

# The click first focuses the window, then the key goes to it
echo "$middle" >&3
for _ in $(seq 50); do grep -q '^CLICKED' "$vpout" && break; sleep 0.1; done
sleep 0.3
# wtype's keyboard is new to the seat: the client binds it during the pause, then gets the key
wtype -s 200 a

# Part two: while the program does not read, move twice, click, and move twice again
for _ in $(seq 100); do grep -q '^PHASE2' "$out" && break; sleep 0.1; done
grep -q '^PHASE2' "$out" || { echo "FAIL: no second part"; cat "$out"; exit 1; }
set -- $middle
{ echo "move $(($1 - 60)) $2"; echo "move $(($1 - 45)) $2"; echo "$(($1 - 30)) $2"
  echo "move $(($1 + 30)) $2"; echo "move $(($1 + 60)) $2"; } >&3

for _ in $(seq 150); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
exit $status
