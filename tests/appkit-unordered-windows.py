#!/usr/bin/env python3
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Host side of appkit-unordered-windows: windows that were created but never
# ordered in have no mapped X window, whether or not they are deferred, and the
# window that was ordered in is mapped.
#
#   appkit-unordered-windows.py GUEST-BINARY [Fixture.nib]
#
# Needs Xvfb :99 with a window manager (xfwm4) and xwininfo.
import os
import re
import subprocess
import sys
import tempfile
import time

DISPLAY = ":99"
binary = os.path.abspath(sys.argv[1])
nib = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else None
CLASS = os.path.basename(binary)
failures = 0


def check(ok, what):
    global failures
    print(("PASS: " if ok else "FAIL: ") + what)
    if not ok:
        failures += 1


def x(*cmd):
    return subprocess.run(list(cmd), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
                          env=dict(os.environ, DISPLAY=DISPLAY)).stdout


def windows():
    """{title: mapped} for the X windows of the program."""
    result = {}
    for line in x("xwininfo", "-root", "-tree").splitlines():
        m = re.match(r"\s+(0x[0-9a-f]+) (?:\"([^\"]*)\"|\(has no name\)): \(\"%s\"" % re.escape(CLASS), line)
        if m:
            result.setdefault(m.group(2) or "", []).append("IsViewable" in x("xwininfo", "-id", m.group(1)))
    return result


work = tempfile.mkdtemp(prefix="appkit-unordered.")
log = os.path.join(work, "log")
cmd = ["timeout", "-s", "KILL", "90", "darling", "shell", "env", "DISPLAY=" + DISPLAY,
       "/Volumes/SystemRoot" + binary, "/Volumes/SystemRoot" + log]
if nib:
    cmd.append("/Volumes/SystemRoot" + nib)
guest = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    end = time.time() + 60
    while time.time() < end and "READY" not in (open(log).read() if os.path.exists(log) else ""):
        time.sleep(0.3)
    text = open(log).read() if os.path.exists(log) else ""
    check("READY" in text, "the application is running")
    time.sleep(2)
    seen = windows()
    nibvisible = "nib window visible=1" in text
    allowed = {"visible"} | ({"Fixture Window"} if nibvisible else set())
    check(any(seen.get("visible", [])), "the window that was ordered in is mapped")
    mapped = sorted(t for t, flags in seen.items() if any(flags) and t not in allowed)
    check(not mapped, "no window that was not ordered in is mapped (mapped: %s)" % ", ".join(mapped or ["none"]))
    # Whatever windows were ordered out later must stay unmapped, too: give the
    # application time to act on its own.
    time.sleep(3)
    mapped = sorted(t for t, flags in windows().items() if any(flags) and t not in allowed)
    check(not mapped, "they stay unmapped (mapped: %s)" % ", ".join(mapped or ["none"]))
    check("deferred number=-1" in text, "a deferred window has the window number -1 until it is ordered in")
    if nib:
        check("nib loaded=1" in text, "the nib loads")
        # A nib window that is visible at launch is ordered in by the loader, the
        # others are not.
        check(any(seen.get("Fixture Window", [])) == nibvisible,
              "the window of the nib is mapped exactly when the nib made it visible")
finally:
    guest.kill()
    target = ("/Volumes/SystemRoot" + binary).encode()
    for pid in os.listdir("/proc"):
        if pid.isdigit():
            try:
                argv = open("/proc/%s/cmdline" % pid, "rb").read().split(b"\0")
            except OSError:
                continue
            if argv and argv[0] == target:
                os.kill(int(pid), 9)
print("%d failure(s)" % failures)
sys.exit(1 if failures else 0)
