#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of coregraphics-x11-drag-no-appkit: presses the left button in the program's source window, moves the
# pointer over its destination window and releases it there, again passing over the destination and releasing outside
# it, and once more for the local drag, with XTest on $DISPLAY. The source window is at (100, 100), 300x200, the
# destination window at (500, 100), 300x200, in root coordinates. Usage:
#   coregraphics-x11-drag-no-appkit.sh <command that runs coregraphics-x11-drag-no-appkit>
# Needs a C compiler with the Xlib and XTest headers (the injector).
set -u
work=$(mktemp -d)
out=$work/out
here=$(cd "$(dirname "$0")" && pwd)
cc -o "$work/xptr" "$here/x11-xtest-pointer.c" -lX11 -lXtst || { echo "FAIL: cannot build the pointer injector"; exit 1; }
X() { "$work/xptr" "$@"; }
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$work"' EXIT

waitfor() { for _ in $(seq 600); do grep -q "^$1" "$out" && return 0; sleep 0.1; done; return 1; }
waitfor READY || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 1

status=0
for n in 1 2 3; do
    waitfor "ARMED $n" || { echo "FAIL: drag $n was never armed"; status=1; break; }
    X 80 m:250:200 b:1:1
    case $n in
    2) X 120 m:350:200 m:450:200 m:550:200 m:650:200 m:650:260 m:650:500 m:650:700 b:1:0 ;;
    *) X 120 m:350:200 m:450:200 m:550:200 m:600:200 m:650:200 m:652:202 m:655:205 b:1:0 ;;
    esac
    waitfor "DONE $n" || { echo "FAIL: drag $n never finished"; status=1; break; }
    X 100 m:900:700
done

for _ in $(seq 100); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
rc=$?
cat "$out"
[ $rc -eq 0 ] || status=1
exit $status
