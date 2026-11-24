#!/usr/bin/env python3
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Where the main menu is shown by default on X11, and how it follows the
# application's activation. The same cases as run-kwin-menu-style.py, against
# an Xvfb with a window manager that places docks (xfwm4):
#
#   run-menu-style-x11.py GUEST_PROGRAM [DISPLAY [focus]]
#
# DISPLAY defaults to :99; "focus" runs only the cases of another application taking the focus. Needs xdotool, xprop, xmessage, gdbus and dbus-daemon.
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import Bus, build_registrar, check, finish, read, wait_for  # noqa: E402

DARLING = os.environ.get("DARLING", "darling")
program = os.path.abspath(sys.argv[1])
DISPLAY = sys.argv[2] if len(sys.argv) > 2 else ":99"
# The window class of the program is its name.
CLASS = os.path.basename(program)
work = tempfile.mkdtemp(prefix="menu-style-x11-", dir=os.environ.get("TMPDIR"))
XENV = dict(os.environ, DISPLAY=DISPLAY)


def x(*cmd):
    return subprocess.run(list(cmd), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, env=XENV).stdout


def windows(want_dock):
    """Viewable top-level windows of the program, docks or not: (id, width)."""
    result = []
    for ident in x("xdotool", "search", "--onlyvisible", "--class", CLASS).split():
        dock = "_NET_WM_WINDOW_TYPE_DOCK" in x("xprop", "-id", ident, "_NET_WM_WINDOW_TYPE")
        geometry = x("xdotool", "getwindowgeometry", "--shell", ident)
        m = re.search(r"WIDTH=(\d+)", geometry)
        if dock == want_dock and m:
            result.append((ident, int(m.group(1))))
    return result


def bars():
    return windows(True)


def wait_until(condition, seconds=15):
    end = time.time() + seconds
    while time.time() < end:
        value = condition()
        if value:
            return value
        time.sleep(0.3)
    return None


def defaults(*args):
    subprocess.run([DARLING, "shell", "defaults"] + list(args), stdin=subprocess.DEVNULL,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)


def exported_menu(bus, seconds=10):
    """Whether some client on the bus exports a dbusmenu with the program's File menu (waits for it)."""
    end = time.time() + seconds
    while time.time() < end:
        if exported_menu_now(bus):
            return True
        time.sleep(1)
    return False


def exported_menu_now(bus):
    reg = bus.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus.ListNames")
    for n in re.findall(r"':(\d+\.\d+)'", reg or ""):
        layout = bus.call(":" + n, "/MenuBar", "com.canonical.dbusmenu.GetLayout", 0, -1, "[]")
        if layout and "About Test" in layout:
            return True
    return False


def guest(bus, mode, tag, seconds=100):
    log = os.path.join(work, tag + ".log")
    open(log, "w").close()
    process = subprocess.Popen(
        ["timeout", "-s", "KILL", "150", DARLING, "shell", "env", "DISPLAY=" + DISPLAY,
         "DBUS_SESSION_BUS_ADDRESS=" + bus.address, "DARLING_APPKIT_BACKEND=x11",
         "/Volumes/SystemRoot" + program, "/Volumes/SystemRoot" + log, mode, str(seconds)],
        stdin=subprocess.DEVNULL, stdout=open(os.path.join(work, tag + ".out"), "w"), stderr=subprocess.STDOUT)
    wait_for(log, "READY", 90)
    wait_for(log, "bar frame", 10) or wait_for(log, "bar none", 3)
    return log, process


def stop(process):
    process.kill()
    process.wait()
    subprocess.run([DARLING, "shutdown"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, timeout=60)
    time.sleep(1)


def main():
    bus = Bus(work)
    registrar = None
    other = None
    try:
        registrar_exe = build_registrar(work)
        no_bars = lambda: wait_until(lambda: not bars(), 10) is not None
        only_focus = len(sys.argv) > 3 and sys.argv[3] == "focus"

        if not only_focus:
            log, process = guest(bus, "window", "window")
            check("strip window=1" in read(log), "a titled window carries the menu strip by default")
            check(no_bars(), "with a strip in a window there is no menu bar window")
            time.sleep(3)
            check(not bars(), "the menu bar window does not appear later either")
            stop(process)

            log, process = guest(bus, "borderless", "borderless")
            check("strip window=0" in read(log), "a borderless window carries no strip")
            check(len(wait_until(bars, 10) or []) == 1, "with only a borderless window the menu bar window is shown")
            stop(process)

            log, process = guest(bus, "nowindow", "nowindow")
            check(len(wait_until(bars, 10) or []) == 1, "with no window the menu bar window is shown")
            stop(process)

            log, process = guest(bus, "swap", "swap")
            check(len(wait_until(bars, 10) or []) == 1, "swap: no window at first: the menu bar window is shown")
            check(wait_for(log, "STEP window opened strip=1", 20), "swap: the window opened and carries the strip")
            check(no_bars(), "swap: the menu bar window goes away when the window appears")
            check(wait_for(log, "STEP window closed", 20), "swap: the window closed")
            check(len(wait_until(bars, 10) or []) == 1, "swap: the menu bar window comes back when the window is gone")
            stop(process)

            registrar = subprocess.Popen([registrar_exe, os.path.join(work, "registrar.log"), "900"], env=bus.env)
            time.sleep(1.5)
            log, process = guest(bus, "window", "global")
            time.sleep(3)
            check("strip window=0" in read(log), "with a global menu a titled window has no strip")
            check(not bars(), "with a global menu there is no menu bar window")
            check(exported_menu(bus), "with a global menu the menu is exported on the session bus")
            stop(process)

            defaults("write", "org.darlinghq.AppKit", "DarlingMenuBarStyle", "window")
            try:
                log, process = guest(bus, "window", "style-window-global")
                time.sleep(3)
                check("strip window=1" in read(log), "DarlingMenuBarStyle window: the strip, even with a global menu")
                check(not bars(), "DarlingMenuBarStyle window: no bar over a window with the strip")
                check(not exported_menu(bus), "DarlingMenuBarStyle window: the menu is not exported")
                stop(process)
            finally:
                defaults("delete", "org.darlinghq.AppKit", "DarlingMenuBarStyle")
            registrar.kill()
            registrar.wait()
            registrar = None
            time.sleep(1.5)

            defaults("write", "org.darlinghq.AppKit", "DarlingMenuBarStyle", "screen")
            try:
                log, process = guest(bus, "window", "style-screen")
                check("strip window=0" in read(log), "DarlingMenuBarStyle screen: a titled window has no strip")
                check(len(wait_until(bars, 10) or []) == 1, "DarlingMenuBarStyle screen: the menu bar window is shown")
                stop(process)
            finally:
                defaults("delete", "org.darlinghq.AppKit", "DarlingMenuBarStyle")

            defaults("write", "org.darlinghq.AppKit", "DarlingInWindowMenuBar", "-bool", "YES")
            try:
                log, process = guest(bus, "window", "legacy-yes")
                time.sleep(3)
                check("strip window=1" in read(log) and not bars(),
                      "DarlingInWindowMenuBar YES still gives the strip and no bar")
                stop(process)
            finally:
                defaults("delete", "org.darlinghq.AppKit", "DarlingInWindowMenuBar")

        # Another application takes the focus, and gives it back. The other application starts after
        # the program, so that the window manager activates its window then. A utility panel is a window
        # the window manager manages, which cannot carry the strip (a borderless window is not managed).
        for mode, tag in (("panel", "focus-panel"), ("window", "focus-window"), ("nowindow", "focus-none")):
            log, process = guest(bus, mode, tag)
            ours = windows(False)
            if mode != "nowindow":
                check(bool(ours), tag + ": the application has a window")
            other = subprocess.Popen(["xmessage", "-display", DISPLAY, "another application"],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            theirs = wait_until(lambda: x("xdotool", "search", "--onlyvisible", "--class", "[Xx]message").split(), 10)
            check(bool(theirs), tag + ": the other application has a window")
            if theirs:
                subprocess.run(["xdotool", "windowactivate", theirs[0]], env=XENV)
            check(wait_for(log, "RESIGN", 15), tag + ": the application resigns when another application has the focus")
            check(wait_for(log, "STATE active=0 bar=0", 10), tag + ": it has no menu bar window then (after a moment)")
            check(no_bars(), tag + ": the menu bar window is gone while the other application is active")
            time.sleep(2)
            check(not bars(), tag + ": and stays gone")
            if mode != "nowindow":
                # With no window of the application there is none to take the focus back: the focus
                # coming back to a window is what activates the application.
                subprocess.run(["xdotool", "windowactivate", ours[0][0]], env=XENV)
                check(wait_until(lambda: read(log).rfind("ACTIVE") > read(log).rfind("RESIGN"), 15) is not None,
                      tag + ": the application is active again when its window has the focus")
                if mode == "panel":
                    check(len(wait_until(bars, 10) or []) == 1, tag + ": the menu bar window comes back with the focus")
                else:
                    time.sleep(1)
                    check(not bars(), tag + ": a window with the strip: still no menu bar window")
            other.kill()
            other.wait()
            other = None
            stop(process)
    finally:
        for p in (registrar, other):
            if p is not None:
                p.kill()
        bus.close()
        print("work directory: " + work)
    return finish()


if __name__ == "__main__":
    sys.exit(main())
