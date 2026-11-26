#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of coregraphics-x11-toplevel-events: moves and sizes the program's window, has the X server ask for part of
# it to be painted again and asks it to close, while the program, which sees only CoreGraphics, records what the
# window system reports of the window.
# Usage: coregraphics-x11-toplevel-events.sh <command that runs coregraphics-x11-toplevel-events>
# (the command gets the directory the program watches as its last argument, with $GUEST_PATH_PREFIX in front of it
# when the program sees the host's files under a prefix; in a Darling guest: /Volumes/SystemRoot).
# $DISPLAY must have a window manager. Needs xdotool and a C compiler with the Xlib headers.
set -u
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
out=$(mktemp)
dir=$(mktemp -d)
probe=$dir/probe
cc -Wall "$here/coregraphics-x11-toplevel-events-probe.c" -lX11 -o "$probe" || { echo "FAIL: no probe"; exit 1; }
"$@" "${GUEST_PATH_PREFIX:-}$dir" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$out" "$dir"' EXIT
for _ in $(seq 400); do grep -q '^\(READY\|SKIP\|RESULT\)' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { cat "$out"; grep -q '^SKIP' "$out" && exit 0; echo "FAIL: the program never became ready"; exit 1; }
window=
for _ in $(seq 50); do
    window=$(xdotool search --name '^tl-events$' | head -1)
    [ -n "$window" ] && break
    sleep 0.1
done
[ -n "$window" ] || { echo "FAIL: no window named tl-events"; echo "RESULT failures=1"; exit 1; }
advance() { touch "$dir/go$1"; for _ in $(seq 100); do grep -q "^STAGE $1\$" "$out" && break; sleep 0.1; done; }

xdotool windowmove "$window" 500 350
advance 1
xdotool windowsize "$window" 400 300
advance 2
"$probe" expose "$window" 10 20 50 40
advance 3
"$probe" close "$window"
advance 4
# The program has taken its handler away: asking again tells it nothing.
"$probe" close "$window"
advance 5
wait $pid 2>/dev/null
status=$?
grep '^\(PASS\|FAIL\)' "$out"
grep -q '^FAIL' "$out" && status=1
grep -q '^RESULT failures=0' "$out" || status=1
[ $status = 0 ] && echo "RESULT failures=0" || echo "RESULT failures=1"
exit $status
