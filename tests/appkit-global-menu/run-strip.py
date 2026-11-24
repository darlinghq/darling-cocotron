#!/usr/bin/env python3
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# The in-window menu strip is on by default when there is no global menu. The
# DarlingMenuBarStyle preference (global domain, or the org.darlinghq.AppKit
# domain) chooses "window", "screen" or "auto", and the older boolean
# DarlingInWindowMenuBar means "window". Each case runs the guest program once,
# because the setting is read once per process.
#
#   run-strip.py GUEST-BINARY [DISPLAY]
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

binary = os.path.abspath(sys.argv[1])
display = sys.argv[2] if len(sys.argv) > 2 else ":99"
work = tempfile.mkdtemp(prefix="appkit-global-menu.")
DOMAIN = "org.darlinghq.AppKit"


def guest(*args):
    return subprocess.run(["timeout", "-s", "KILL", "60", "darling", "shell"] + list(args),
                          stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def strip_line(case):
    log = os.path.join(work, case + ".log")
    guest("env", "DISPLAY=" + display, "/Volumes/SystemRoot" + binary, "/Volumes/SystemRoot" + log, "strip")
    m = re.search(r"strip window=(\d) panel=(\d) extraFrameHeight=(\d+)", read(log))
    return tuple(int(v) for v in m.groups()) if m else None


def with_default(args, case):
    """The strip line with the preference written, and the preference deleted again."""
    try:
        guest("defaults", "write", *args)
        return strip_line(case)
    finally:
        guest("defaults", "delete", *args[:2])


def stripped(line):
    return line is not None and line[0] == 1 and line[1] == 0


def unstripped(line):
    return line is not None and line[0] == 0 and line[1] == 0


default = strip_line("default")
check(stripped(default), "by default (no global menu) a titled window has the strip and a panel has none")

screen = with_default((DOMAIN, "DarlingMenuBarStyle", "screen"), "screen")
check(unstripped(screen), "DarlingMenuBarStyle screen: no strip")
check(screen is not None and default is not None and default[2] > screen[2], "the strip takes room in the window frame")
check(stripped(with_default((DOMAIN, "DarlingMenuBarStyle", "window"), "window")),
      "DarlingMenuBarStyle window: the strip")
check(stripped(with_default((DOMAIN, "DarlingMenuBarStyle", "auto"), "auto")), "DarlingMenuBarStyle auto: as the default")
check(stripped(with_default((DOMAIN, "DarlingMenuBarStyle", "Window"), "case")), "the value is not case sensitive")
check(stripped(with_default((DOMAIN, "DarlingMenuBarStyle", "nonsense"), "nonsense")),
      "an unknown value is taken as auto")
check(unstripped(with_default(("-g", "DarlingMenuBarStyle", "screen"), "global-screen")),
      "DarlingMenuBarStyle in the global domain")
check(stripped(with_default((DOMAIN, "DarlingInWindowMenuBar", "-bool", "YES"), "legacy-yes")),
      "the older DarlingInWindowMenuBar YES: the strip")
check(stripped(with_default(("-g", "DarlingInWindowMenuBar", "-bool", "YES"), "legacy-global")),
      "the older DarlingInWindowMenuBar in the global domain")
check(stripped(with_default((DOMAIN, "DarlingInWindowMenuBar", "-bool", "NO"), "legacy-no")),
      "DarlingInWindowMenuBar NO is the default")
try:
    guest("defaults", "write", DOMAIN, "DarlingInWindowMenuBar", "-bool", "YES")
    check(unstripped(with_default((DOMAIN, "DarlingMenuBarStyle", "screen"), "style-over-legacy")),
          "DarlingMenuBarStyle takes precedence over DarlingInWindowMenuBar")
finally:
    guest("defaults", "delete", DOMAIN, "DarlingInWindowMenuBar")

again = strip_line("again")
check(stripped(again), "deleting the preferences gives the default again")
print("logs in", work)
sys.exit(finish())
