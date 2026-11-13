#!/usr/bin/env python3
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Host side of the "click, then click an item" menu test. A menu opened by a
# click that is released at once stays open until an item is chosen or the
# user clicks outside, and the application stays active while it is open.
#
#   run-sticky.py GUEST-BINARY [MODE...]
#
# MODE is bar, strip, popup or context (default: all four). Needs Xvfb :99 with
# xfwm4, xdotool, xwininfo and dbus-daemon.
import os
import re
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

DISPLAY = ":99"
ENV = dict(os.environ, DISPLAY=DISPLAY)
binary = os.path.abspath(sys.argv[1])
modes = sys.argv[2:] or ["bar", "strip", "popup", "context"]
work = tempfile.mkdtemp(prefix="appkit-menu-sticky.")
CLASS = "appkit-menu-sticky-click"


def x(*cmd):
    return subprocess.run(list(cmd), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
                          env=ENV).stdout


def xdo(*args):
    subprocess.run(["xdotool"] + list(args), env=ENV)


def windows():
    """Mapped X windows of the program: {id: (x, y, width, height)}."""
    result = {}
    for line in x("xwininfo", "-root", "-tree").splitlines():
        m = re.match(r"\s+(0x[0-9a-f]+) (?:\"[^\"]*\"|\(has no name\)): \(\"%s\"" % re.escape(CLASS), line)
        if not m:
            continue
        info = x("xwininfo", "-id", m.group(1))
        if "IsViewable" not in info:
            continue
        g = lambda name: int(re.search(name + r":\s+(-?\d+)", info).group(1))
        result[m.group(1)] = (g("Absolute upper-left X"), g("Absolute upper-left Y"), g("Width"), g("Height"))
    return result


def wait_until(condition, seconds=10):
    end = time.time() + seconds
    while time.time() < end:
        value = condition()
        if value:
            return value
        time.sleep(0.25)
    return None


def new_window(before):
    """The newly mapped window after `before`, if any (the menu)."""
    found = wait_until(lambda: {k: v for k, v in windows().items() if k not in before}, 6)
    if not found:
        return None
    return sorted(found.values(), key=lambda w: w[2] * w[3])[0]


def click(px, py):
    xdo("mousemove", str(px), str(py))
    time.sleep(0.3)
    xdo("mousedown", "1")
    time.sleep(0.08)
    xdo("mouseup", "1")


def right_click(px, py):
    xdo("mousemove", str(px), str(py))
    time.sleep(0.3)
    xdo("mousedown", "3")
    time.sleep(0.08)
    xdo("mouseup", "3")


def stop_guests():
    """Kills the guest programs: killing the darling shell that started one
    does not end it."""
    target = ("/Volumes/SystemRoot" + binary).encode()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            argv = open("/proc/%s/cmdline" % pid, "rb").read().split(b"\0")
        except OSError:
            continue
        if argv and argv[0] == target:
            try:
                os.kill(int(pid), 9)
            except ProcessLookupError:
                pass


def guest_defaults(*args):
    subprocess.run(["timeout", "-s", "KILL", "60", "darling", "shell", "defaults"] + list(args),
                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def run_mode(mode):
    if mode == "strip":
        guest_defaults("write", "org.darlinghq.AppKit", "DarlingInWindowMenuBar", "-bool", "YES")
    try:
        run_mode_body(mode)
    finally:
        if mode == "strip":
            guest_defaults("delete", "org.darlinghq.AppKit", "DarlingInWindowMenuBar")


def run_mode_body(mode):
    bus = Bus(work)
    log = os.path.join(work, mode + ".log")
    guest = start_guest(bus, work, binary, log, mode, lifetime=0)
    opener = right_click if mode == "context" else click
    try:
        check(wait_for(log, "READY", 60), "%s: the application is running" % mode)
        m = None
        end = time.time() + 15
        while time.time() < end and m is None:
            m = re.search(r"trigger (\d+) (\d+)", read(log))
            time.sleep(0.3)
        check(m is not None, "%s: the position of the menu's title is known" % mode)
        if m is None:
            return
        tx, ty = int(m.group(1)), int(m.group(2))
        time.sleep(1)

        # A click opens the menu and a second click on an item chooses it.
        before = set(windows())
        opener(tx, ty)
        menu = new_window(before)
        check(menu is not None, "%s: a click opens the menu" % mode)
        if menu:
            time.sleep(1.0)
            check(bool(set(windows()) - before), "%s: the menu stays open after the click is released" % mode)
            mx, my, mw, mh = menu
            ids = [k for k, v in windows().items() if v == menu]
            kind = x("xprop", "-id", ids[0], "_NET_WM_WINDOW_TYPE") if ids else ""
            check("DROPDOWN_MENU" in kind or "POPUP_MENU" in kind,
                  "%s: the menu window has a menu type of its own" % mode)
            attrs = x("xwininfo", "-id", ids[0], "-all") if ids else ""
            check("Override Redirect State: yes" in attrs,
                  "%s: the menu window is not managed by the window manager" % mode)
            click(mx + mw // 2, my + mh // 2)
            check(wait_for(log, "chose Beta", 6), "%s: the second click chooses the item under it" % mode)
            gone = wait_until(lambda: not (set(windows()) - before), 5)
            check(bool(gone), "%s: the menu closes after the choice" % mode)
        check("resigned" not in read(log), "%s: the application stayed active" % mode)

        # A click outside the menu closes it without choosing anything.
        time.sleep(1)
        size = len(read(log))
        before = set(windows())
        opener(tx, ty)
        menu = new_window(before)
        check(menu is not None, "%s: the menu opens again" % mode)
        if menu:
            time.sleep(1.0)
            click(1700, 950)
            gone = wait_until(lambda: not (set(windows()) - before), 5)
            check(bool(gone), "%s: a click outside closes the menu" % mode)
            check("chose" not in read(log)[size:], "%s: nothing is chosen by the click outside" % mode)

        # Keys go to the open menu (the arrow keys are not tested: the X11 backend
        # gives them no function key characters).
        time.sleep(1)
        before = set(windows())
        opener(tx, ty)
        menu = new_window(before)
        check(menu is not None, "%s: the menu opens a third time" % mode)
        if menu:
            time.sleep(1.0)
            xdo("key", "Escape")
            gone = wait_until(lambda: not (set(windows()) - before), 5)
            check(bool(gone), "%s: Escape closes the menu" % mode)
            time.sleep(0.5)
            size = len(read(log))
            before = set(windows())
            opener(tx, ty)
            menu = new_window(before)
            if menu:
                time.sleep(1.0)
                # The keys typed while the menu is open reach it: with the
                # pointer on an item, Return chooses it.
                mx, my, mw, mh = menu
                xdo("mousemove", str(mx + mw // 2), str(my + mh // 2))
                time.sleep(0.6)
                xdo("key", "Return")
                check(wait_for(log, "chose", 6) and "chose Beta" in read(log)[size:],
                      "%s: Return chooses the item under the pointer of the open menu" % mode)
        check("resigned" not in read(log), "%s: the application stayed active throughout" % mode)
    finally:
        if guest.poll() is None:
            guest.kill()
        bus.close()
        stop_guests()


for mode in modes:
    run_mode(mode)
print("logs in", work)
sys.exit(finish())
