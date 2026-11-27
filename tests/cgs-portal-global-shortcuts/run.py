#!/usr/bin/env python3
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Host side of the GlobalShortcuts Carbon hot key test: a private session bus
# with a fake portal (fake-portal.c) and the guest program
# ../carbon-hotkeys-portal.m. The guest must receive a Carbon press and release
# while no window of its own has the keyboard focus.
#
#   run.py GUEST-BINARY
#
# Needs a Wayland compositor (WAYLAND_DISPLAY, with XDG_RUNTIME_DIR), dbus-daemon,
# a C compiler with libdbus-1 headers, and `darling` on PATH (DPREFIX as usual).
import os
import re
import subprocess
import sys
import tempfile
import time

failures = 0


def check(ok, what):
    global failures
    print(("PASS: " if ok else "FAIL: ") + what)
    if not ok:
        failures += 1


if "WAYLAND_DISPLAY" not in os.environ:
    print("SKIP: a Wayland compositor is needed for the CoreGraphics backend")
    sys.exit(0)

binary = os.path.abspath(sys.argv[1])
here = os.path.dirname(os.path.abspath(__file__))
work = tempfile.mkdtemp(prefix="cgs-global-shortcuts.", dir=os.environ.get("TMPDIR"))
flags = subprocess.run(["pkg-config", "--cflags", "--libs", "dbus-1"], stdout=subprocess.PIPE,
                       text=True, check=True).stdout.split()
fake = os.path.join(work, "fake-portal")
subprocess.run(["cc", "-o", fake, os.path.join(here, "fake-portal.c")] + flags, check=True)

bus_config = os.path.join(work, "bus.conf")
with open(bus_config, "w") as f:
    f.write("""<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
""")

address = "unix:abstract=darling-global-shortcuts-%d" % os.getpid()
started = subprocess.run(["dbus-daemon", "--config-file=" + bus_config, "--address=" + address,
                          "--print-pid", "--fork"], stdout=subprocess.PIPE, text=True, check=True)
bus_pid = int(started.stdout.split()[0])
log = os.path.join(work, "portal.log")
env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS=address)
portal = subprocess.Popen([fake, log, "60"], env=env)
end = time.time() + 10
while time.time() < end:
    try:
        if "READY" in open(log).read():
            break
    except FileNotFoundError:
        pass
    time.sleep(0.1)

out = os.path.join(work, "guest.out")
guest_env = [
    "DBUS_SESSION_BUS_ADDRESS=" + address,
    "DARLING_APPKIT_BACKEND=wayland",
    "WAYLAND_DISPLAY=" + os.environ["WAYLAND_DISPLAY"],
    "XDG_RUNTIME_DIR=" + os.environ.get("XDG_RUNTIME_DIR", ""),
]
with open(out, "w") as f:
    subprocess.run(["timeout", "-s", "KILL", "60", "darling", "shell", "env"] + guest_env +
                   ["/Volumes/SystemRoot" + binary],
                   stdin=subprocess.DEVNULL, stdout=f, stderr=subprocess.STDOUT)

portal.terminate()
try:
    os.kill(bus_pid, 15)
except ProcessLookupError:
    pass

calls = open(log).read() if os.path.exists(log) else ""
result = open(out).read() if os.path.exists(out) else ""

check("CALL Register" in calls, "the portal client associates the process with an app id")
check("CALL CreateSession" in calls, "a GlobalShortcuts session is created")
check("CALL BindShortcuts session=/org/freedesktop/portal/desktop/session/" in calls,
      "the bound shortcuts use the session the portal returned")
control_trigger = re.search(r"SHORTCUT darling-1\n(?:  .*\n)*?  preferred_trigger=(CTRL\+[A-Za-z0-9_]+)\n", calls)
shift_trigger = re.search(r"SHORTCUT darling-2\n(?:  .*\n)*?  preferred_trigger=(CTRL\+SHIFT\+[A-Za-z0-9_]+)\n", calls)
check("SHORTCUT darling-1" in calls and control_trigger is not None,
      "Control+A is offered with a well-formed XDG trigger: %r" %
      (control_trigger.group(1) if control_trigger else None))
check("SHORTCUT darling-2" in calls and shift_trigger is not None,
      "Control+Shift+A is offered with a well-formed XDG trigger: %r" %
      (shift_trigger.group(1) if shift_trigger else None))
check("SIGNAL Activated darling-1" in calls and "SIGNAL Deactivated darling-1" in calls,
      "the fake portal sent activation and deactivation")

check("READY" in result, "the guest registered its hot keys")
check("seen: P1 R1" in result, "only the bound shortcut reaches Carbon, once per activation: %r" %
      ([line for line in result.splitlines() if line.startswith("seen:")],))
check("ALL PASSED" in result and "FAIL" not in result, "the guest's Carbon contract checks passed: %r" %
      ([line for line in result.splitlines() if line.startswith(("ALL", "FAILED", "FAIL"))],))

print("FAILED %d" % failures if failures else "ALL PASSED")
sys.exit(1 if failures else 0)
