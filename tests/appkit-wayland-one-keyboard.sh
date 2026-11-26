#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# A process has one wl_keyboard: every time the seat gains the keyboard capability the process makes one
# get_keyboard request, on one wl_seat object, however many frameworks of the process read keys. Runs
# appkit-keyboard-cgevents-wayland.sh (every wtype run makes the seat lose and regain the capability) with
# libwayland's client debug output (WAYLAND_DEBUG=1 in the guest, which the command has to set) and counts
# the requests. Usage:
#   WAYLAND_DEBUG=1 is set by the caller's command, e.g. A4_ENV=WAYLAND_DEBUG=1 run1.sh wayland 60 <appkit-keyboard-cgevents>
#   appkit-wayland-one-keyboard.sh <command that runs appkit-keyboard-cgevents>
# Needs python3, swaymsg and wtype.
set -u
here=$(cd "$(dirname "$0")" && pwd)
log=$(mktemp)
trap 'rm -f "$log"' EXIT
bash "$here/appkit-keyboard-cgevents-wayland.sh" "$@" > "$log" 2>&1
python3 -I - "$log" <<'PY'
import re, sys, collections
requests = collections.Counter()
gains = collections.Counter()
have = {}
for line in open(sys.argv[1], errors="replace"):
    m = re.search(r"wl_seat#(\d+)\.get_keyboard\(", line)
    if m:
        requests[m.group(1)] += 1
    m = re.search(r"wl_seat#(\d+)\.capabilities\((\d+)\)", line)
    if m:
        seat, caps = m.group(1), int(m.group(2))
        if caps & 2 and not have.get(seat, False):
            gains[seat] += 1
        have[seat] = bool(caps & 2)
total = sum(requests.values())
print("get_keyboard requests: %d on %d seat object(s) %s; the keyboard capability appeared %d time(s) on them"
      % (total, len(requests), sorted(requests), sum(gains[s] for s in requests)))
ok = total > 0 and len(requests) == 1
print(("PASS" if ok else "FAIL") + " the process requests its keyboard on one wl_seat object")
ok2 = ok and requests[next(iter(requests))] == gains[next(iter(requests))]
print(("PASS" if ok2 else "FAIL") + " one get_keyboard request each time the capability appeared")
sys.exit(0 if ok and ok2 else 1)
PY
