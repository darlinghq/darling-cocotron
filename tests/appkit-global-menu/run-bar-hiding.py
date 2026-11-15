#!/usr/bin/env python3
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Host side of the test that the application's own menu bar hides when the
# application asks for it: while its key window has the full screen style, and
# while its presentation options hide the menu bar (NSApplication
# presentationOptions, NSApplicationPresentationHideMenuBar and
# NSApplicationPresentationAutoHideMenuBar). Everywhere else it is shown.
#
#   run-bar-hiding.py GUEST-BINARY
#
# Needs Xvfb :99 with a window manager (xfwm4), xwininfo and xprop.
import os
import re
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

DISPLAY = ":99"
CLASS = "appkit-global-menu"
binary = os.path.abspath(sys.argv[1])
work = tempfile.mkdtemp(prefix="appkit-global-menu.")


def x(*cmd):
    return subprocess.run(list(cmd), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
                          env=dict(os.environ, DISPLAY=DISPLAY)).stdout


def bar_visible():
    """Whether a dock window of the program is mapped."""
    for line in x("xwininfo", "-root", "-tree").splitlines():
        m = re.match(r"\s+(0x[0-9a-f]+) (?:\"[^\"]*\"|\(has no name\)): \(\"%s\"" % re.escape(CLASS), line)
        if not m:
            continue
        if "_NET_WM_WINDOW_TYPE_DOCK" in x("xprop", "-id", m.group(1), "_NET_WM_WINDOW_TYPE") and \
                "IsViewable" in x("xwininfo", "-id", m.group(1)):
            return True
    return False


def wait_bar(visible, seconds=2.5):
    end = time.time() + seconds
    while time.time() < end:
        if bar_visible() == visible:
            return True
        time.sleep(0.2)
    return False


# (state logged by the guest, whether the menu bar is shown in it)
STATES = [
    ("windowed", True),
    ("full-screen-style", False),
    ("windowed-again", True),
    ("hide-menu-bar", False),
    ("default-options", True),
    ("auto-hide-menu-bar", False),
    ("default-options-again", True),
]

bus = type("NoBus", (), {"address": "unix:path=/nonexistent/bus"})()
log = os.path.join(work, "hiding.log")
guest = start_guest(bus, work, binary, log, "hiding", lifetime=0)
try:
    check(wait_for(log, "READY", 60), "the application is running")
    for name, shown in STATES:
        if not wait_for(log, "STEP %s " % name, 20):
            check(False, "the guest reached the state %s" % name)
            break
        check(wait_bar(shown), "the menu bar is %s in the state %s" % ("shown" if shown else "hidden", name))
    check(wait_for(log, "done", 20), "the guest finished")
finally:
    if guest.poll() is None:
        guest.kill()
print("logs in", work)
sys.exit(finish())
