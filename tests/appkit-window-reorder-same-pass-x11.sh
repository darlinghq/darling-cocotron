#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/appkit-window-reorder-same-pass.m with the X11 backend and watches the root window
# (xev -root -event substructure) while it runs: windows ordered out and in again within one pass of the
# run loop must not be unmapped and mapped (no UnmapNotify or MapNotify in the LOOP section), a window
# ordered out for good must be unmapped (an UnmapNotify in the HIDE section) and mapped again when it is
# ordered in (a MapNotify in the SHOW section). With a reparenting window manager the root sees the
# window manager's frames, which are unmapped and mapped along with the client windows.
# Usage: appkit-window-reorder-same-pass-x11.sh <command that runs the fixture with DISPLAY and
#        DARLING_APPKIT_BACKEND=x11 in its environment>; DISPLAY must be set for this script too.
# Needs python3 and xev.
set -u
[ -n "${DISPLAY:-}" ] || { echo "FAIL: DISPLAY is not set"; exit 1; }
command -v xev > /dev/null || { echo "FAIL: xev is not installed"; exit 1; }
exec python3 -I - "$@" << 'PYEOF'
import subprocess, sys, time, threading, re

events, fixture = [], []   # (time, line)
xev = subprocess.Popen(["xev", "-root", "-event", "substructure"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
def pump(proc, sink):
    for line in proc.stdout:
        sink.append((time.time(), line.rstrip("\n")))
threading.Thread(target=pump, args=(xev, events), daemon=True).start()
time.sleep(1)
app = subprocess.Popen(sys.argv[1:], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, text=True)
threading.Thread(target=pump, args=(app, fixture), daemon=True).start()
deadline = time.time() + 60
while time.time() < deadline and app.poll() is None:
    time.sleep(0.2)
time.sleep(0.5)
app.kill()
xev.kill()

marks = {}
for t, line in fixture:
    m = re.match(r"^(READY|LOOP-BEGIN|LOOP-END|HIDE-BEGIN|HIDE-END|SHOW-BEGIN|SHOW-END|DONE)\b", line)
    if m:
        marks[m.group(1)] = t
status = 0
def fail(msg):
    global status
    status = 1
    print("FAIL: " + msg)
for t, line in fixture:
    if line.startswith("FAIL"):
        status = 1
        print(line)
if "DONE" not in marks:
    print("FAIL: the fixture did not finish")
    for t, line in fixture[:20]:
        print(line)
    sys.exit(1)

def count(kind, begin, end):
    return sum(1 for t, line in events if marks[begin] <= t <= marks[end] and line.startswith(kind))

if not any(line.startswith("MapNotify") for t, line in events):
    fail("no X11 events seen on the root window")
unmaps, maps = count("UnmapNotify", "LOOP-BEGIN", "LOOP-END"), count("MapNotify", "LOOP-BEGIN", "LOOP-END")
if unmaps == 0 and maps == 0:
    print("PASS: re-ordering windows out and in within one pass unmapped and mapped nothing")
else:
    fail("re-ordering windows out and in within one pass caused %d unmaps and %d maps (want 0 and 0)" % (unmaps, maps))
unmaps = count("UnmapNotify", "HIDE-BEGIN", "HIDE-END")
if unmaps >= 1:
    print("PASS: a window ordered out for good was unmapped")
else:
    fail("a window ordered out for good was not unmapped")
maps = count("MapNotify", "SHOW-BEGIN", "SHOW-END")
if maps >= 1:
    print("PASS: a window ordered in again was mapped")
else:
    fail("a window ordered in again was not mapped")
if any(line.startswith("PASS") for t, line in fixture):
    print("PASS: the application stayed active while its windows were re-ordered")
else:
    fail("the fixture reported a failure")
print("FAIL" if status else "PASS")
sys.exit(status)
PYEOF
