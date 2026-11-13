#!/usr/bin/env python3
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Host side of the menu bar test: with no application menu registrar on the
# session bus (and then with no session bus at all) the active application
# shows its own menu bar along the top of the screen.
#
#   run-bar.py GUEST-BINARY
#
# Needs Xvfb :99 with a window manager (xfwm4), xdotool, xprop, xwininfo,
# xmessage, gdbus and dbus-daemon.
import os
import re
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

DISPLAY = ":99"
binary = os.path.abspath(sys.argv[1])
work = tempfile.mkdtemp(prefix="appkit-global-menu.")


def x(*cmd):
    return subprocess.run(list(cmd), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
                          env=dict(os.environ, DISPLAY=DISPLAY)).stdout


def top_level(cls):
    """The X windows of the program: (id, type, x, y, width, mapped)."""
    result = []
    for line in x("xwininfo", "-root", "-tree").splitlines():
        m = re.match(r"\s+(0x[0-9a-f]+) (?:\"[^\"]*\"|\(has no name\)): \(\"%s\"" % re.escape(cls), line)
        if not m:
            continue
        ident = m.group(1)
        info = x("xwininfo", "-id", ident)
        prop = x("xprop", "-id", ident, "_NET_WM_WINDOW_TYPE")
        g = lambda name: int(re.search(name + r":\s+(-?\d+)", info).group(1))
        result.append((ident, prop.split("=")[-1].strip(), g("Absolute upper-left X"),
                       g("Absolute upper-left Y"), g("Width"), "IsViewable" in info))
    return result


def bars(cls):
    return [w for w in top_level(cls) if "_NET_WM_WINDOW_TYPE_DOCK" in w[1]]


def wait_until(condition, seconds=15):
    end = time.time() + seconds
    while time.time() < end:
        value = condition()
        if value:
            return value
        time.sleep(0.3)
    return None


def screen_width():
    return int(re.search(r"Width: (\d+)", x("xwininfo", "-root")).group(1))


# Case 1: a session bus without a registrar.
bus = Bus(work)
log = os.path.join(work, "bar.log")
guest = start_guest(bus, work, binary, log, "panel")
other = None
try:
    check(wait_for(log, "READY", 60), "the application is running")
    wait_for(log, "bar frame", 10)
    cls = "appkit-global-menu"
    found = wait_until(lambda: bars(cls), 10)
    check(bool(found), "a dock window appears while the application is active")
    ident, kind, bx, by, bw, mapped = found[0]
    check(by == 0 and bx == 0, "the bar is at the top left of the screen")
    check(bw == screen_width(), "the bar spans the screen width")
    check(mapped, "the bar is mapped")
    strut = x("xprop", "-id", ident, "_NET_WM_STRUT_PARTIAL")
    check(re.search(r"= 0, 0, \d+, 0", strut) is not None, "the bar reserves a strip at the top with a strut")
    workarea = x("xprop", "-root", "_NET_WORKAREA")
    check(re.search(r"= 0, [1-9]\d*, ", workarea) is not None, "the window manager keeps windows below the bar")

    # The bar lists the application name first, then File; open File and choose New_Doc.
    items = {int(m.group(1)): (int(m.group(2)), int(m.group(3)))
             for m in re.finditer(r"bar item (\d+) x=(\d+) y=(\d+)", read(log))}
    check(0 in items and 1 in items, "the bar draws both menus")
    if 1 in items:
        fx, fy = items[1]
        before = {w[0] for w in top_level(cls)}
        env = dict(os.environ, DISPLAY=DISPLAY)
        # Press on File, drag down to the first item of its menu and release there.
        subprocess.run(["xdotool", "mousemove", str(fx), str(fy)], env=env)
        time.sleep(0.4)
        subprocess.run(["xdotool", "mousedown", "1"], env=env)
        menu = wait_until(lambda: [w for w in top_level(cls) if w[0] not in before], 8)
        check(bool(menu), "File opens its menu below the bar")
        if menu:
            mid, mkind, mx, my, mw, mm = menu[0]
            check(my >= by and my < 60, "the menu opens right under the bar")
            subprocess.run(["xdotool", "mousemove", str(mx + 20), str(my + 6)], env=env)
            time.sleep(0.3)
            subprocess.run(["xdotool", "mousemove", str(mx + 22), str(my + 13)], env=env)
            time.sleep(0.6)
        subprocess.run(["xdotool", "mouseup", "1"], env=env)
        check(wait_for(log, "action newDoc mainthread=1", 8), "choosing an item performs its action")

    # Another application takes the focus: the bar goes away; the focus
    # returning brings it back.
    other = subprocess.Popen(["xmessage", "-display", DISPLAY, "another application"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    gone = wait_until(lambda: not [w for w in bars(cls) if w[5]], 10)
    check(bool(gone), "the bar is hidden while the application is not active")
    panel = [w for w in top_level(cls) if "_NET_WM_WINDOW_TYPE_DOCK" not in w[1] and w[5]]
    if panel:
        subprocess.run(["xdotool", "windowactivate", panel[0][0]], env=dict(os.environ, DISPLAY=DISPLAY))
        check(bool(wait_until(lambda: [w for w in bars(cls) if w[5]], 10)),
              "the bar is shown again when the application is active again")
    else:
        check(False, "the application's panel is visible")

    # Quit through the exported menu, which also works without a registrar.
    reg = bus.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus.ListNames")
    names = re.findall(r"':(\d+\.\d+)'", reg or "")
    for n in names:
        layout = bus.call(":" + n, "/MenuBar", "com.canonical.dbusmenu.GetLayout", 0, -1, "[]")
        if layout:
            items_by_id = flatten(parse_variant(layout)[1])
            quit_id = find_item(items_by_id, "Quit Test")
            bus.call(":" + n, "/MenuBar", "com.canonical.dbusmenu.Event", quit_id, "clicked", "<0>", 0)
            break
    try:
        guest.wait(15)
    except subprocess.TimeoutExpired:
        pass
finally:
    if other is not None:
        other.kill()
    if guest.poll() is None:
        guest.kill()
    bus.close()

# Case 2: no session bus at all.
nobus = type("NoBus", (), {"address": "unix:path=/nonexistent/bus"})()
log2 = os.path.join(work, "nobus.log")
guest2 = start_guest(nobus, work, binary, log2, "panel", lifetime=25)
try:
    check(wait_for(log2, "READY", 60), "the application starts without a session bus")
    check(bool(wait_until(lambda: bars("appkit-global-menu"), 10)), "the bar is shown without a session bus")
    try:
        guest2.wait(40)
    except subprocess.TimeoutExpired:
        pass
finally:
    if guest2.poll() is None:
        guest2.kill()
print("logs in", work)
sys.exit(finish())
