#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of coregraphics-wayland-toplevel-events: looks at the compositor's tree while the program, which sees only
# CoreGraphics, shows, draws into, hides and shows again a toplevel window of the UI layer, and asks the compositor to
# close the window.
# Usage: coregraphics-wayland-toplevel-events.sh <command that runs coregraphics-wayland-toplevel-events>
# (the command gets the directory the program watches as its last argument, with $GUEST_PATH_PREFIX in front of it
# when the program sees the host's files under a prefix; in a Darling guest: /Volumes/SystemRoot). The program has to
# get DARLING_APPKIT_BACKEND=wayland, WAYLAND_DISPLAY and XDG_RUNTIME_DIR in its environment. $SWAYSOCK names a headless
# sway (darling-skills' wayland.sh) whose windows float. Needs swaymsg and python3.
set -u
out=$(mktemp)
dir=$(mktemp -d)
"$@" "${GUEST_PATH_PREFIX:-}$dir" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$out" "$dir"' EXIT
titles() { swaymsg -t get_tree | python3 -c '
import json, sys
def walk(n):
    yield n
    for c in n.get("nodes", []) + n.get("floating_nodes", []):
        yield from walk(c)
for n in walk(json.load(sys.stdin)):
    if n.get("name"):
        print(n["name"])'; }
present() { titles | grep -qx tl-events-wl; }
for _ in $(seq 400); do grep -q '^\(READY\|SKIP\|RESULT\)' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { cat "$out"; grep -q '^SKIP' "$out" && exit 0; echo "FAIL: the program never became ready"; exit 1; }
failures=0
check() { if "$@"; then echo "PASS: $DESC"; else echo "FAIL: $DESC"; failures=$((failures + 1)); fi; }
DESC="the window is a toplevel of the compositor with the title it was given"; check present
advance() { touch "$dir/go$1"; for _ in $(seq 100); do grep -q "^STAGE $1\$" "$out" && break; sleep 0.1; done; }

swaymsg '[title="tl-events-wl"] kill' > /dev/null
advance 1
advance 2
sleep 0.5
DESC="a hidden window is gone from the compositor"; check eval '! present'
advance 3
sleep 0.5
DESC="a window that is shown again is a toplevel again"; check present
touch "$dir/go4"
wait $pid 2>/dev/null
status=$?
grep '^\(PASS\|FAIL\)' "$out"
grep -q '^FAIL' "$out" && status=1
grep -q '^RESULT failures=0' "$out" || status=1
[ $failures = 0 ] || status=1
[ $status = 0 ] && echo "RESULT failures=0" || echo "RESULT failures=1"
exit $status
