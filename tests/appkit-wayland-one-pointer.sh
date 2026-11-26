#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# A process has one wl_pointer: every time the seat gains the pointer capability the process makes one get_pointer
# request, on one wl_seat object, however many frameworks of the process read the pointer (AppKit's windows,
# cursors and locks use the wl_pointer CoreGraphics decodes). Runs appkit-pointer-cgevents-wayland (whose own checks
# do not matter here) with libwayland's client debug output (WAYLAND_DEBUG=1 in the guest, which the command has to
# set), takes the virtual pointer away and brings another (the seat loses and regains the capability), and counts
# the requests. Usage:
#   WAYLAND_DEBUG=1 is set by the caller's command, e.g. A4_ENV=WAYLAND_DEBUG=1 run1.sh wayland 60 <appkit-pointer-cgevents-wayland>
#   appkit-wayland-one-pointer.sh <command that runs appkit-pointer-cgevents-wayland>
# $VIRTUAL_POINTER, $WAYLAND_DISPLAY, $XDG_RUNTIME_DIR and $SWAYSOCK as for appkit-pointer-cgevents-wayland.sh.
# Needs python3 and swaymsg.
set -u
pointer=${VIRTUAL_POINTER:?path of the built wayland-virtual-pointer helper}
work=$(mktemp -d)
log=$work/log
mkfifo "$work/fifo1" "$work/fifo2"
"$pointer" < "$work/fifo1" > "$work/vp1" 2>&1 &
vp1=$!
exec 3> "$work/fifo1"
"$@" > "$log" 2>&1 < /dev/null &
pid=$!
vp2=
trap 'exec 3>&- 4>&-; kill $pid $vp1 $vp2 2>/dev/null; rm -rf "$work"' EXIT
for _ in $(seq 50); do grep -q '^READY' "$work/vp1" && break; sleep 0.1; done
for _ in $(seq 600); do grep -q '^READY' "$log" && break; sleep 0.1; done
grep -q '^READY' "$log" || { echo "FAIL: the test never became ready"; head -50 "$log"; exit 1; }
sleep 2
swaymsg -q '[title="ptr-cgevents-wayland"] move position 200 200, focus'
echo "abs 400 400" >&3
sleep 1
# The pointer goes away and another comes
exec 3>&-
kill $vp1; wait $vp1 2>/dev/null
sleep 1.5
"$pointer" < "$work/fifo2" > "$work/vp2" 2>&1 &
vp2=$!
exec 4> "$work/fifo2"
for _ in $(seq 50); do grep -q '^READY' "$work/vp2" && break; sleep 0.1; done
echo "abs 420 420" >&4
sleep 1.5
exec 4>&-
kill $vp2 2>/dev/null; wait $vp2 2>/dev/null
kill $pid 2>/dev/null; wait $pid 2>/dev/null
python3 -I - "$log" <<'PY'
import re, sys, collections
requests = collections.Counter()
gains = collections.Counter()
have = {}
for line in open(sys.argv[1], errors="replace"):
    m = re.search(r"wl_seat#(\d+)\.get_pointer\(", line)
    if m:
        requests[m.group(1)] += 1
    m = re.search(r"wl_seat#(\d+)\.capabilities\((\d+)\)", line)
    if m:
        seat, caps = m.group(1), int(m.group(2))
        if caps & 1 and not have.get(seat, False):
            gains[seat] += 1
        have[seat] = bool(caps & 1)
total = sum(requests.values())
print("get_pointer requests: %d on %d seat object(s) %s; the pointer capability appeared %d time(s) on them"
      % (total, len(requests), sorted(requests), sum(gains[s] for s in requests)))
ok = total > 0 and len(requests) == 1
print(("PASS" if ok else "FAIL") + " the process requests its pointer on one wl_seat object")
ok2 = ok and gains[next(iter(requests))] >= 2 and requests[next(iter(requests))] == gains[next(iter(requests))]
print(("PASS" if ok2 else "FAIL") + " one get_pointer request each time the capability appeared (it appeared again after the pointer was replaced)")
sys.exit(0 if ok and ok2 else 1)
PY
