#!/usr/bin/env python3
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Where the main menu is shown by default, under a private virtual KWin (Wayland,
# with its own session bus), and how it follows the application's activation:
#
#   run-kwin-menu-style.py GUEST_PROGRAM
#
# GUEST_PROGRAM is ../appkit-global-menu.m built for the guest (x86_64 or i386).
# Needs what run-kwin-bar.py needs, and kcalc (a native Wayland client that
# stands for another application; QT_QPA_PLATFORM=wayland).
#
# Cases:
#   - no global menu, a titled window: the window draws the menu strip, there is
#     no menu bar surface;
#   - no window at all: the menu bar surface is there;
#   - a titled window appears in an application without one: the menu bar
#     surface goes away; the window closes: it comes back;
#   - a global menu (fake registrar): the menu is exported, no strip, no bar;
#   - DarlingMenuBarStyle "screen": no strip, the bar (or the global menu);
#     "window": the strip even with a global menu, which gets no export;
#     the older DarlingInWindowMenuBar still means "window";
#   - another application (a native client) takes the focus: the application
#     resigns and its bar goes away; the focus coming back brings the bar back;
#   - the menu bar owner: an application with a menu and no visible window
#     starts a helper (an LSUIElement bundle, then a program that switches to
#     the accessory policy) that opens a window with the focus: the helper does
#     not take the menu bar over, so the application stays
#     NSWorkspace.menuBarOwningApplication and keeps its bar although it
#     resigned; a native client taking the focus from the helper ends the bar,
#     the focus returning to the helper brings it back; when the helper quits
#     the owner is active again.
#
# A second argument limits the run: "focus" runs the focus cases only, "owner"
# the menu bar owner cases only.
import importlib.machinery
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
loader = importlib.machinery.SourceFileLoader("run_kwin_bar", os.path.join(HERE, "run-kwin-bar.py"))
spec = importlib.util.spec_from_loader("run_kwin_bar", loader)
rkb = importlib.util.module_from_spec(spec)
loader.exec_module(rkb)
from common import build_registrar, check, finish, owner_flavors, read, wait_for  # noqa: E402

DARLING = os.environ.get("DARLING", "darling")


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
    """Whether some client on the bus exports a dbusmenu with the program's File menu."""
    reg = bus.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus.ListNames")
    for n in re.findall(r"':(\d+\.\d+)'", reg or ""):
        layout = bus.call(":" + n, "/MenuBar", "com.canonical.dbusmenu.GetLayout", 0, -1, "[]")
        if layout and "About Test" in layout:
            return True
    return False


def main():
    program = sys.argv[1]
    work = tempfile.mkdtemp(prefix="kwin-menu-style-", dir=os.environ.get("TMPDIR"))
    session = rkb.Session(work, program)
    registrar = None
    foreign = None
    try:
        registrar_exe = build_registrar(work)
        wait = rkb.wait_until
        no_bars = lambda: wait(lambda: not session.bars(), 10) is not None

        only = sys.argv[2] if len(sys.argv) > 2 else None
        if only is None:
            # The default, with no global menu.
            log, process = session.guest("window", "window")
            check("strip window=1" in read(log), "a titled window carries the menu strip by default")
            check(no_bars(), "with a strip in a window there is no menu bar surface")
            time.sleep(3)
            check(not session.bars(), "the menu bar surface does not appear later either")
            check("windows=1" in read(log), "the application counts the window that carries the strip")
            rkb.stop(process)

            log, process = session.guest("borderless", "borderless")
            check("strip window=0" in read(log), "a borderless window carries no strip")
            check(len(wait(session.bars, 10) or []) == 1, "with only a borderless window the menu bar surface is shown")
            rkb.stop(process)

            log, process = session.guest("nowindow", "nowindow")
            check(len(wait(session.bars, 10) or []) == 1, "with no window the menu bar surface is shown")
            rkb.stop(process)

            # A window that can carry the strip appears, and goes away.
            log, process = session.guest("swap", "swap", seconds=100)
            check(len(wait(session.bars, 10) or []) == 1, "swap: no window at first: the menu bar surface is shown")
            check(wait_for(log, "STEP window opened strip=1", 20), "swap: the window opened and carries the strip")
            check(no_bars(), "swap: the menu bar surface goes away when the window appears")
            check(wait_for(log, "STEP window closed", 20), "swap: the window closed")
            check(len(wait(session.bars, 10) or []) == 1, "swap: the menu bar surface comes back when the window is gone")
            rkb.stop(process)

            # A global menu: exported, no strip, no bar.
            registrar = subprocess.Popen([registrar_exe, os.path.join(work, "registrar.log"), "900"],
                                         env=session.bus.env)
            time.sleep(1.5)
            log, process = session.guest("window", "global")
            time.sleep(3)
            check("strip window=0" in read(log), "with a global menu a titled window has no strip")
            check(session.bars() == [], "with a global menu there is no menu bar surface")
            check(exported_menu(session.bus), "with a global menu the menu is exported on the session bus")
            rkb.stop(process)

            # Preferences.
            defaults("write", "org.darlinghq.AppKit", "DarlingMenuBarStyle", "window")
            try:
                log, process = session.guest("window", "style-window-global")
                time.sleep(3)
                check("strip window=1" in read(log), "DarlingMenuBarStyle window: the strip, even with a global menu")
                check(session.bars() == [], "DarlingMenuBarStyle window: no bar over a window with the strip")
                check(not exported_menu(session.bus), "DarlingMenuBarStyle window: the menu is not exported")
                rkb.stop(process)
            finally:
                defaults("delete", "org.darlinghq.AppKit", "DarlingMenuBarStyle")
            registrar.kill()
            registrar.wait()
            registrar = None
            time.sleep(1.5)

            defaults("write", "org.darlinghq.AppKit", "DarlingMenuBarStyle", "screen")
            try:
                log, process = session.guest("window", "style-screen")
                check("strip window=0" in read(log), "DarlingMenuBarStyle screen: a titled window has no strip")
                check(len(wait(session.bars, 10) or []) == 1, "DarlingMenuBarStyle screen: the menu bar surface is shown")
                rkb.stop(process)
            finally:
                defaults("delete", "org.darlinghq.AppKit", "DarlingMenuBarStyle")

            defaults("write", "org.darlinghq.AppKit", "DarlingInWindowMenuBar", "-bool", "YES")
            try:
                log, process = session.guest("window", "legacy-yes")
                time.sleep(3)
                check("strip window=1" in read(log) and not session.bars(),
                      "DarlingInWindowMenuBar YES still gives the strip and no bar")
                rkb.stop(process)
                defaults("write", "org.darlinghq.AppKit", "DarlingMenuBarStyle", "screen")
                log, process = session.guest("window", "style-over-legacy")
                check("strip window=0" in read(log),
                      "DarlingMenuBarStyle takes precedence over DarlingInWindowMenuBar")
                rkb.stop(process)
            finally:
                defaults("delete", "org.darlinghq.AppKit", "DarlingMenuBarStyle")
                defaults("delete", "org.darlinghq.AppKit", "DarlingInWindowMenuBar")

        # Another application takes the focus, and gives it back.
        cenv = dict(session.env, QT_QPA_PLATFORM="wayland", WAYLAND_DISPLAY=rkb.SOCKET)
        foreign = subprocess.Popen(["kcalc"], env=cenv, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)

        def activate(window):
            script = os.path.join(work, "activate.js")
            with open(script, "w") as f:
                f.write(read(os.path.join(HERE, "kwin-activate.js")).replace("@TARGET@", window["id"]))
            reply = session.gdbus("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadScript",
                                  script, "darling-activate")
            number = re.search(r"\d+", reply).group(0)
            session.gdbus("org.kde.KWin", "/Scripting/Script" + number, "org.kde.kwin.Script.run")
            session.gdbus("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.unloadScript", "darling-activate")

        def windows_of(pid_filter):
            # The full-screen window with no task bar entry is KWin's own (its placeholder session program).
            return [w for w in session.windows()
                    if pid_filter(w) and w["h"] > 100 and not w["popup"] and not w["skipTaskbar"]]

        theirs = wait(lambda: windows_of(lambda w: w["pid"] == foreign.pid), 30)
        check(bool(theirs), "the other application has a window")
        for mode, tag in (("borderless", "focus-borderless"), ("window", "focus-window")):
            if only == "owner":
                break
            log, process = session.guest(mode, tag)
            ours = wait(lambda: windows_of(lambda w: w["pid"] != foreign.pid), 10)
            check(bool(ours), tag + ": the application has a window")
            if not (ours and theirs):
                rkb.stop(process)
                continue
            activate(theirs[0])
            check(wait_for(log, "RESIGN", 15), tag + ": the application resigns when another application has the focus")
            check(wait_for(log, "STATE active=0 bar=0", 10), tag + ": it has no menu bar window then (after a moment)")
            check(no_bars(), tag + ": the menu bar surface is gone while the other application is active")
            time.sleep(2)
            check(not session.bars(), tag + ": and stays gone")
            activate(ours[0])
            check(wait(lambda: read(log).rfind("ACTIVE") > read(log).rfind("RESIGN"), 15) is not None,
                  tag + ": the application is active again when its window has the focus")
            if mode == "borderless":
                check(len(wait(session.bars, 10) or []) == 1,
                      tag + ": the menu bar surface comes back with the focus")
            else:
                time.sleep(1)
                check(not session.bars(), tag + ": a window with the strip: still no menu bar surface")
            rkb.stop(process)

        # The menu bar owner and a helper that is not a regular application.
        for name, helper, helper_mode in owner_flavors(work, program):
            if only == "focus":
                break
            tag = "owner-" + name
            log, process = session.guest("owner", tag, seconds=100, extra_args=[helper, helper_mode])
            helper_log = log + ".helper"

            def last_owner():
                lines = [l for l in read(log).splitlines() if l.startswith("OWNER")]
                return lines[-1] if lines else ""

            check(len(wait(session.bars, 10) or []) == 1, tag + ": before the helper the application's bar is shown")
            check(wait_for(log, "OWNER owner=1 front=self", 10), tag + ": the application owns the menu bar and is in front")
            check(wait_for(helper_log, "HELPER policy=1", 60), tag + ": the helper does not have the regular policy")
            check(wait_for(log, "RESIGN", 30), tag + ": the application resigns when the helper has the focus")
            time.sleep(2.5)
            check(len(session.bars()) == 1, tag + ": the bar stays while the helper has the focus")
            check("owner=1 front=other" in last_owner(), tag + ": the application is still the menu bar owner, the helper is in front")
            check(wait_for(log, "STATE active=0 bar=1", 3), tag + ": the application is not active and shows its bar")

            check(bool(theirs), tag + ": the native client has a window")
            activate(theirs[0])
            check(no_bars(), tag + ": the bar goes away when a native client takes the focus from the helper")
            check(wait(lambda: "owner=0" in last_owner(), 10) is not None,
                  tag + ": nobody owns the menu bar then")
            mine = wait(lambda: windows_of(lambda w: w["pid"] != foreign.pid), 10)
            check(bool(mine), tag + ": the helper's window is known to the compositor")
            if mine:
                activate(mine[0])
                check(len(wait(session.bars, 10) or []) == 1, tag + ": the bar comes back when the helper has the focus again")
                check(wait(lambda: "owner=1 front=other" in last_owner(), 10) is not None,
                      tag + ": the application owns the menu bar again")

            open(helper_log + ".quit", "w").close()
            check(wait_for(helper_log, "helper quits", 20), tag + ": the helper quits")
            check(wait(lambda: read(log).rfind("ACTIVE") > read(log).rfind("RESIGN"), 20) is not None,
                  tag + ": the application is active again when the helper is gone")
            check(wait(lambda: "owner=1 front=self" in last_owner(), 10) is not None,
                  tag + ": and is in front and owns the menu bar")
            check(len(wait(session.bars, 10) or []) == 1, tag + ": and shows its bar")
            rkb.stop(process)
    finally:
        for p in (registrar, foreign):
            if p is not None:
                p.kill()
        session.close()
        print("work directory: " + work)
    return finish()


if __name__ == "__main__":
    sys.exit(main())
