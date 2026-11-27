#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of coregraphics-wayland-toplevel-decorations on a headless sway: looks at the compositor's tree while the program,
# which sees only CoreGraphics, shows windows with each kind of title bar, and presses a virtual pointer on the frame the
# program's "wdeco-client" window draws for itself. The title bar must move the window, an edge must resize it, the close
# button must be reported as a close request and the content must get its mouse events, none of which the frame may.
# Usage: coregraphics-wayland-toplevel-decorations.sh <command that runs coregraphics-wayland-toplevel-decorations>
# (the command gets the directory the program watches as its last argument, with $GUEST_PATH_PREFIX in front of it when the
# program sees the host's files under a prefix; in a Darling guest: /Volumes/SystemRoot). The program has to get
# DARLING_APPKIT_BACKEND=wayland, WAYLAND_DISPLAY and XDG_RUNTIME_DIR in its environment. $SWAYSOCK names a headless sway
# (darling-skills' wayland.sh) whose windows float; VIRTUAL_POINTER is the path of a built tests/wayland-virtual-pointer.c.
# Needs swaymsg and python3.
set -u
pointer=${VIRTUAL_POINTER:?path of the built wayland-virtual-pointer helper}
out=$(mktemp)
dir=$(mktemp -d)
mkfifo "$dir/fifo"
"$pointer" < "$dir/fifo" > "$dir/pointer" 2>&1 &
vp=$!
exec 3> "$dir/fifo"
swaymsg -q default_floating_border normal
swaymsg -q default_border normal
"$@" "${GUEST_PATH_PREFIX:-}$dir" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'exec 3>&-; kill $pid $vp 2>/dev/null; rm -rf "$out" "$dir"' EXIT
for _ in $(seq 50); do grep -q '^READY' "$dir/pointer" && break; sleep 0.1; done
grep -q '^READY' "$dir/pointer" || { echo "FAIL: no virtual pointer"; cat "$dir/pointer"; exit 1; }
for _ in $(seq 400); do grep -q '^\(READY\|SKIP\|RESULT\)' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { cat "$out"; grep -q '^SKIP' "$out" && exit 0; echo "FAIL: the program never became ready"; exit 1; }
status=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; status=1; }
node() { # print "<border> <x> <y> <width> <height>" of the window with this title (rect: the surface)
    swaymsg -t get_tree | python3 -I -c '
import json, sys
def walk(n):
    if n.get("name") == sys.argv[1] and n.get("shell") == "xdg_shell":
        r, w = n["rect"], n["window_rect"]
        print(n.get("border"), r["x"] + w["x"], r["y"] + w["y"], w["width"], w["height"])
        return True
    return any(walk(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
walk(json.load(sys.stdin))' "$1"
}
mouse_lines() { grep -c '^MOUSE' "$out"; }
sleep 1
set -- $(node wdeco-server); [ "${1:-}" = normal ] && ok "a standard title bar is the compositor's frame" || bad "wdeco-server border: ${1:-no window}"
set -- $(node wdeco-hidden); [ "${1:-}" = csd ] && ok "a title bar the application does not show leaves the frame to the client" || bad "wdeco-hidden border: ${1:-no window}"
set -- $(node wdeco-client); [ "${1:-}" = csd ] && ok "a window that prefers a frame of its own declares client-side decorations" || bad "wdeco-client border: ${1:-no window}"
[ "${4:-}" = 312 ] && [ "${5:-}" = 240 ] && ok "the surface is as big as the frame the window draws" || bad "wdeco-client surface: ${4:-?}x${5:-?}"

swaymsg -q '[title="wdeco-server"] move position 20 20'
swaymsg -q '[title="wdeco-hidden"] move position 400 20'
swaymsg -q '[title="wdeco-client"] move position 800 300'
sleep 0.5
set -- $(node wdeco-client); x0=$2 y0=$3 w0=$4 h0=$5
[ -n "${x0:-}" ] || { cat "$out"; echo "FAIL: no client window"; exit 1; }
pointer_cmd() { echo "$*" >&3; }
wait_for_pointer() { for _ in $(seq 100); do grep -q "^$1" "$dir/pointer" && return 0; sleep 0.1; done; return 1; }
count_pointer() { grep -c "^$1" "$dir/pointer"; }

# A press on the title bar, away from the buttons, moves the window and is not a mouse event of the content.
before=$(mouse_lines); n=$(count_pointer DRAGGED)
pointer_cmd "drag $((x0 + 200)) $((y0 + 20)) 80 60"
for _ in $(seq 100); do [ "$(count_pointer DRAGGED)" -gt "$n" ] && break; sleep 0.1; done
sleep 1
set -- $(node wdeco-client); mx=$(($2 - x0)) my=$(($3 - y0))
if [ $((mx - 80)) -ge -1 ] && [ $((mx - 80)) -le 1 ] && [ $((my - 60)) -ge -1 ] && [ $((my - 60)) -le 1 ]; then ok "the title bar moves the window ($mx,$my)"; else bad "the title bar moved the window by $mx,$my, not 80,60"; fi
[ "$(mouse_lines)" = "$before" ] && ok "the program gets no mouse event for the title bar" || bad "the title bar press reached the content: $(grep '^MOUSE' "$out" | tail -2 | tr '\n' ' ')"
x0=$2 y0=$3

# The close button is reported as a close request; the miniaturize button, which sway cannot honour, does nothing.
n=$(count_pointer CLICKED)
pointer_cmd "$((x0 + 6 + 10 + 9)) $((y0 + 6 + 14))"
for _ in $(seq 50); do grep -q '^CLOSE 1' "$out" && break; sleep 0.1; done
grep -q '^CLOSE 1' "$out" && ok "the close button asks for the window to close" || bad "no close request"
[ "$(mouse_lines)" = "$before" ] && ok "the close button is not a mouse event of the content" || bad "the close button press reached the content"

# The bottom right corner resizes it.
n=$(count_pointer DRAGGED)
pointer_cmd "drag $((x0 + w0 - 3)) $((y0 + h0 - 3)) 40 30"
for _ in $(seq 100); do [ "$(count_pointer DRAGGED)" -gt "$n" ] && break; sleep 0.1; done
sleep 1
set -- $(node wdeco-client); dw=$(($4 - w0)) dh=$(($5 - h0))
if [ $((dw - 40)) -ge -2 ] && [ $((dw - 40)) -le 2 ] && [ $((dh - 30)) -ge -2 ] && [ $((dh - 30)) -le 2 ]; then ok "the corner resizes the window ($dw,$dh)"; else bad "the corner resized the window by $dw,$dh, not 40,30"; fi
w1=$4 h1=$5

# A press on the content is the content's, and does not move the window.
set -- $(node wdeco-client); x0=$2 y0=$3
pointer_cmd "$((x0 + 150)) $((y0 + 120))"
for _ in $(seq 50); do [ "$(mouse_lines)" -gt "$before" ] && break; sleep 0.1; done
grep -q '^MOUSE down' "$out" && ok "a press on the content is a mouse event" || bad "the content got no mouse event"
set -- $(node wdeco-client)
[ "$2" = "$x0" ] && [ "$3" = "$y0" ] && ok "the press on the content did not move the window" || bad "the window moved to $2,$3"

touch "$dir/go1"
for _ in $(seq 100); do grep -q '^STAGE 1' "$out" && break; sleep 0.1; done
touch "$dir/go2"
wait $pid 2>/dev/null
grep '^\(PASS\|FAIL\)' "$out"
grep -q '^FAIL' "$out" && status=1
grep -q '^RESULT failures=0' "$out" || status=1
[ $status = 0 ] && echo "RESULT failures=0" || echo "RESULT failures=1"
exit $status
