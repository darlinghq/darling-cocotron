#!/bin/bash
# Copyright (C) 2026 Lubos Dolezel
# Host harness for nsopenglcontext-setview-cgl-current (x11 backend, Xvfb with a
# window manager on $DISPLAY). Usage: harness.sh <host path of compiled test> [ns]
# Runs the test in the guest, grabs the newest window and exits 0 if it is solid red.
set -u
prog=$1; shift
timeout -s KILL 60 darling shell "/Volumes/SystemRoot$prog" "$@" </dev/null > /dev/null 2>&1 &
sleep 10
w=$(xdotool search --class "" | tail -1)
import -window "$w" /dev/shm/svgrab.$$.png
python3 - /dev/shm/svgrab.$$.png <<'PY'
import sys
from PIL import Image
c = Image.open(sys.argv[1]).convert("RGB").getcolors(100000)
ok = len(c) == 1 and c[0][1] == (255, 0, 0)
print("PASS" if ok else "FAIL: colours %r" % c[:3])
sys.exit(0 if ok else 1)
PY
rc=$?
rm -f /dev/shm/svgrab.$$.png
wait
exit $rc
