#!/usr/bin/env python3
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# The in-window menu strip is off by default and comes back with the
# DarlingInWindowMenuBar preference (global domain, or the org.darlinghq.AppKit
# domain). Each case runs the guest program once, because the setting is read
# once per process.
#
#   run-strip.py GUEST-BINARY
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

binary = os.path.abspath(sys.argv[1])
work = tempfile.mkdtemp(prefix="appkit-global-menu.")


def guest(*args):
    return subprocess.run(["timeout", "-s", "KILL", "60", "darling", "shell"] + list(args),
                          stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def strip_line(case):
    log = os.path.join(work, case + ".log")
    guest("env", "DISPLAY=:99", "/Volumes/SystemRoot" + binary, "/Volumes/SystemRoot" + log, "strip")
    m = re.search(r"strip window=(\d) panel=(\d) extraFrameHeight=(\d+)", read(log))
    return tuple(int(v) for v in m.groups()) if m else None


default = strip_line("default")
check(default is not None and default[0] == 0 and default[1] == 0,
      "by default a titled window has no in-window menu strip")
try:
    guest("defaults", "write", "-g", "DarlingInWindowMenuBar", "-bool", "YES")
    glob = strip_line("global")
    check(glob is not None and glob[0] == 1 and glob[1] == 0,
          "with the preference in the global domain a titled window has the strip and a panel has none")
    check(glob is not None and default is not None and glob[2] > default[2],
          "the strip takes room in the window frame")
finally:
    guest("defaults", "delete", "-g", "DarlingInWindowMenuBar")

try:
    guest("defaults", "write", "org.darlinghq.AppKit", "DarlingInWindowMenuBar", "-bool", "YES")
    domain = strip_line("domain")
    check(domain is not None and domain[0] == 1, "the org.darlinghq.AppKit domain also turns the strip on")
finally:
    guest("defaults", "delete", "org.darlinghq.AppKit", "DarlingInWindowMenuBar")

again = strip_line("again")
check(again is not None and again[0] == 0, "deleting the preference turns the strip off again")
print("logs in", work)
sys.exit(finish())
