#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of appkit-wayland-relative-mouse: moves a virtual pointer (tests/wayland-virtual-pointer.c, in
# $VIRTUAL_POINTER) over the window "relative-mouse-wayland" when the program says STEP n, and checks the cursor
# requests (wl_pointer.set_cursor, libwayland's client debug output: the command has to set WAYLAND_DEBUG=1 in the
# guest) between the MARK lines the program prints after each hide and show call. $WAYLAND_DISPLAY, $XDG_RUNTIME_DIR and
# $SWAYSOCK must name a headless sway whose windows float. Usage:
#   WAYLAND_DEBUG=1 is set by the caller's command, e.g. A4_ENV=WAYLAND_DEBUG=1 run1.sh wayland 120 <appkit-wayland-relative-mouse>
#   appkit-wayland-relative-mouse.sh <command that runs appkit-wayland-relative-mouse>
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
for _ in $(seq 600); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 2
swaymsg -q '[title="relative-mouse-wayland"] move position 200 200, focus'
sleep 0.5
center=$(swaymsg -t get_tree | python3 -I -c '
import json, sys
def walk(n):
    if n.get("name") == "relative-mouse-wayland" and n.get("shell") == "xdg_shell":
        r = n["rect"]
        print(r["x"] + r["width"] // 2, r["y"] + r["height"] // 2)
        return True
    return any(walk(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
walk(json.load(sys.stdin))')
[ -n "$center" ] || { echo "FAIL: the window is not on screen"; cat "$out"; exit 1; }
PX=${center% *} PY=${center#* }

n=0
V() {
    echo "$*" >&3
    n=$((n + 1))
    for _ in $(seq 300); do [ "$(wc -l < "$vpout")" -gt "$n" ] && return; sleep 0.02; done
}
waitstep() { for _ in $(seq 600); do grep -q "^STEP $1\$" "$out" && return 0; sleep 0.1; done; echo "FAIL: no STEP $1"; return 1; }
V "abs $PX $PY"
sleep 1
waitstep 1; sleep 0.3; V "rel 10 5"; sleep 0.3; V "rel 12 -4"; sleep 0.3; V "rel -6 8"
waitstep 2; sleep 0.8; V "rel 7 4"; sleep 0.3; V "rel -3 2"; sleep 0.3; V "rel 5 -6"
waitstep 3; sleep 0.8; V "rel 2 2"
waitstep 4; sleep 0.3; V "rel 20 0"; sleep 0.3; V "rel 0 20"
waitstep 5; sleep 0.3; V "rel 5 5"
for _ in $(seq 300); do grep -q '^MARK end$' "$out" && break; sleep 0.1; done
wtype -s 300 q
for _ in $(seq 300); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cp "$out" "$work/final"
python3 -I - "$work/final" <<'PY'
import re, sys
lines = open(sys.argv[1], errors="replace").read().splitlines()
segments = {}
current = []
for l in lines:
    m = re.match(r"^MARK (\w+)$", l)
    if m:
        segments[m.group(1)] = current
        current = []
        continue
    if re.search(r"wl_pointer[@#]\d+\.set_cursor\(", l):
        current.append("nil" if re.search(r"set_cursor\(\d+, nil,", l) else "image")
    elif l.startswith("STEP "):
        current = []
failed = 0
def check(name, ok, what):
    global failed
    print(("PASS " if ok else "FAIL ") + what)
    if not ok:
        failed += 1
nil = lambda k: segments.get(k, []).count("nil")
img = lambda k: segments.get(k, []).count("image")
check("hide1", nil("hide1") >= 1, "the first hide gives the pointer no cursor image")
check("hide2", nil("hide2") == 0 and img("hide2") == 0, "a second hide asks the compositor for nothing (hidden twice)")
check("show1", nil("show1") == 0 and img("show1") == 0, "one show of two hides leaves the cursor hidden")
check("show2", nil("show2") == 0 and img("show2") >= 1, "the second show brings the cursor image back")
check("show3", nil("show3") == 0 and img("show3") == 0, "a show with nothing hidden does nothing")
check("nshide", nil("nshide") >= 1, "+[NSCursor hide] hides the cursor")
check("nsunhide", nil("nsunhide") == 0 and img("nsunhide") >= 1, "+[NSCursor unhide] shows it again")
check("hideuntil", nil("hideuntil") >= 1, "+[NSCursor setHiddenUntilMouseMoves:YES] hides the cursor")
check("end", nil("end") == 0 and img("end") >= 1, "the cursor comes back when the mouse moves")
sys.stdout.flush()
sys.exit(1 if failed else 0)
PY
pystatus=$?
grep -v -E "^\[|wl_|^MARK|^STEP|^READY" "$work/final" | grep -v "^  \(tap\|ns\)" ; grep "^  \(tap\|ns\)" "$work/final"
[ $status -eq 0 ] && [ $pystatus -eq 0 ] || { echo "FAILED (program $status, cursor requests $pystatus)"; exit 1; }
echo "ALL PASSED"
