#!/usr/bin/env python3
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Host side of the status item test: a private session bus (dbus-run-session)
# with a small StatusNotifierWatcher, the guest program with two status items,
# and the calls and signals of a desktop's tray.
#
#   run-notifier.py GUEST-BINARY [--display :99] [--env NAME=VALUE]...
#
# Needs dbus-run-session and python3 with dbus-python and PyGObject (GLib).
# The --env options go to the guest program, for instance
# DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY=... to run it on Wayland.
import os
import subprocess
import sys
import tempfile
import time

if os.environ.get("APPKIT_STATUS_ITEM_INNER") != "1":
    env = dict(os.environ, APPKIT_STATUS_ITEM_INNER="1")
    os.execvpe("dbus-run-session",
               ["dbus-run-session", "--", sys.executable, os.path.abspath(__file__)] + sys.argv[1:], env)

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

PROPERTIES = "org.freedesktop.DBus.Properties"
ITEM = "org.kde.StatusNotifierItem"
WATCHER = "org.kde.StatusNotifierWatcher"
MENU = "com.canonical.dbusmenu"

failures = 0


def check(ok, what):
    global failures
    print(("PASS: " if ok else "FAIL: ") + what, flush=True)
    if not ok:
        failures += 1


def pump(condition, seconds):
    """Runs the main loop until the condition holds; returns whether it did."""
    end = time.time() + seconds
    ctx = GLib.MainContext.default()
    while time.time() < end:
        if condition():
            return True
        ctx.iteration(False)
        time.sleep(0.02)
    return condition()


def read(path):
    try:
        return open(path).read()
    except FileNotFoundError:
        return ""


class Watcher(dbus.service.Object):
    """The service a desktop's tray provides."""

    def __init__(self, bus):
        super().__init__(bus, "/StatusNotifierWatcher")
        self.bus = bus
        self.registered = []

    def own(self):
        self.bus.request_name(WATCHER)

    def release(self):
        self.bus.release_name(WATCHER)

    @dbus.service.method(WATCHER, in_signature="s", sender_keyword="sender")
    def RegisterStatusNotifierItem(self, service, sender=None):
        self.registered.append(str(service))

    @dbus.service.method(PROPERTIES, in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        return {"IsStatusNotifierHostRegistered": dbus.Boolean(True),
                "ProtocolVersion": dbus.Int32(0),
                "RegisteredStatusNotifierItems": dbus.Array(self.registered, signature="s")}[str(name)]

    @dbus.service.method(PROPERTIES, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return {"IsStatusNotifierHostRegistered": dbus.Boolean(True)}


def guest_command(binary, log, mode, address, display, extra):
    env = ["DISPLAY=" + display, "DBUS_SESSION_BUS_ADDRESS=" + address] + extra
    return (["timeout", "-s", "KILL", "150", "darling", "shell", "env"] + env +
            ["/Volumes/SystemRoot" + binary, "/Volumes/SystemRoot" + log, mode])


def start_guest(binary, work, name, mode, address, display, extra):
    log = os.path.join(work, name + ".log")
    out = open(os.path.join(work, name + ".out"), "w")
    proc = subprocess.Popen(guest_command(binary, log, mode, address, display, extra),
                            stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT)
    return proc, log


def step(log, n):
    open("%s.step%d" % (log, n), "w").close()
    return pump(lambda: "STEP %d\n" % n in read(log), 30)


def parse_args():
    args = sys.argv[1:]
    binary = os.path.abspath(args.pop(0))
    display = os.environ.get("DISPLAY", ":99")
    extra = []
    while args:
        a = args.pop(0)
        if a == "--display":
            display = args.pop(0)
        elif a == "--env":
            extra.append(args.pop(0))
    return binary, display, extra


def pixels(pixmap):
    width, height, data = int(pixmap[0]), int(pixmap[1]), bytes(bytearray(pixmap[2]))
    return width, height, data


def pixel(pixmap, x, y):
    width, height, data = pixels(pixmap)
    i = (y * width + x) * 4
    return tuple(data[i:i + 4])  # A, R, G, B


def labels(node):
    ident, props, children = node
    found = [str(props.get("label"))] if "label" in props else []
    for c in children:
        found += labels(c)
    return found


def find_id(node, label):
    ident, props, children = node
    if props.get("label") == label:
        return int(ident)
    for c in children:
        r = find_id(c, label)
        if r is not None:
            return r
    return None


def main():
    binary, display, extra = parse_args()
    address = os.environ["DBUS_SESSION_BUS_ADDRESS"]
    work = tempfile.mkdtemp(prefix="appkit-status-item.")
    bus = dbus.SessionBus()
    signals = []

    def on_signal(*args, **kw):
        signals.append((str(kw["interface"]), str(kw["member"]), str(kw["path"]), args))

    bus.add_signal_receiver(on_signal, interface_keyword="interface", member_keyword="member",
                            path_keyword="path")

    def seen(member, path=None, since=0):
        return any(m == member and (path is None or p == path) for _, m, p, _ in signals[since:])

    guest = None
    guest_log = None

    def with_tray():
        nonlocal guest, guest_log
        # A tray that is not there yet.
        watcher = Watcher(bus)
        guest, log = start_guest(binary, work, "guest", "tray", address, display, extra)
        guest_log = log
        check(pump(lambda: "READY" in read(log), 90), "the guest application is running")
        print("guest backend: " + ([l for l in read(log).splitlines() if l.startswith("backend ")] or ["unknown"])[0][8:])

        def items():
            found = {}
            for name in bus.list_names():
                if str(name).startswith("org.kde.StatusNotifierItem-"):
                    try:
                        obj = bus.get_object(name, "/StatusNotifierItem")
                        ident = str(dbus.Interface(obj, PROPERTIES).Get(ITEM, "Id"))
                        found[ident.split("-", 1)[1]] = (str(name), obj)
                    except dbus.DBusException:
                        pass
            return found

        check(pump(lambda: len(items()) == 2, 10), "each status item serves a StatusNotifierItem on the bus")
        found = items()
        check(sorted(found) == ["probe-action", "probe-menu"], "an item's Id has its autosave name")
        if sorted(found) != ["probe-action", "probe-menu"]:
            return
        menu_name, menu_obj = found["probe-menu"]
        action_name, action_obj = found["probe-action"]
        mp = dbus.Interface(menu_obj, PROPERTIES)
        ap = dbus.Interface(action_obj, PROPERTIES)

        check(watcher.registered == [], "no watcher: nothing is registered, the items exist")
        check(str(mp.Get(ITEM, "Status")) == "Active", "properties can be read without a watcher")

        # The watcher appears later.
        watcher.own()
        check(pump(lambda: len(watcher.registered) == 2, 10), "both items register when the watcher appears")
        check(sorted(watcher.registered) == sorted([menu_name, action_name]),
              "an item registers with its bus name")

        # Properties.
        check(str(mp.Get(ITEM, "Title")) == "Probe", "Title is the item's title")
        check(str(mp.Get(ITEM, "Category")) == "ApplicationStatus", "Category is ApplicationStatus")
        check(str(mp.Get(ITEM, "Status")) == "Active", "Status is Active for a visible item with content")
        check(str(mp.Get(ITEM, "Menu")) == "/StatusNotifierItem/Menu", "Menu is the object path of the menu")
        check(bool(mp.Get(ITEM, "ItemIsMenu")), "an item with a menu is a menu")
        check(not bool(ap.Get(ITEM, "ItemIsMenu")), "an item without a menu is not a menu")
        check(str(ap.Get(ITEM, "Menu")) == "/", "an item without a menu has the root path as its menu")
        tip = mp.Get(ITEM, "ToolTip")
        check(str(tip[2]) == "Tip", "ToolTip has the tool tip as its title")
        pm = mp.Get(ITEM, "IconPixmap")
        sizes = [(int(p[0]), int(p[1])) for p in pm]
        check(sizes == [(22, 22), (44, 44)], "IconPixmap has square pixmaps at 1x and 2x (%s)" % (sizes,))
        if sizes == [(22, 22), (44, 44)]:
            a, r, g, b = pixel(pm[0], 11, 11)
            check(a == 255 and r > 200 and g < 60 and b < 60, "the pixmap holds the image (red, opaque centre)")
            check(pixel(pm[0], 0, 0)[0] == 0, "the margin around a 16 point image is transparent")
        apm = ap.Get(ITEM, "IconPixmap")
        check(len(apm) == 2 and int(apm[0][1]) == 22 and int(apm[0][0]) > 22,
              "an item with only a title gets a pixmap of its text, wider than tall")
        if len(apm) == 2:
            check(any(pixel(apm[0], x, y)[0] > 0 for x in range(int(apm[0][0])) for y in range(22)),
                  "the title text is drawn")

        # Clicks.
        ai = dbus.Interface(action_obj, ITEM)
        ai.Activate(0, 0)
        check(pump(lambda: "action item 1 mainthread=1" in read(log), 10), "Activate sends the action on the main thread")
        ai.SecondaryActivate(0, 0)
        time.sleep(1)
        check("action item 2" not in read(log), "SecondaryActivate does not send an action sent on left clicks only")
        dbus.Interface(menu_obj, ITEM).Activate(0, 0)

        # The menu.
        mo = bus.get_object(menu_name, "/StatusNotifierItem/Menu")
        dm = dbus.Interface(mo, MENU)
        rev, layout = dm.GetLayout(0, -1, dbus.Array([], signature="s"))
        check(labels(layout) == ["Alpha", "Beta"] or labels(layout)[:2] == ["Alpha", "Beta"],
              "the menu is exported with the items of the NSMenu (%s)" % labels(layout))
        check(any(c[1].get("type") == "separator" for c in layout[2]), "the separator is exported")
        alpha = find_id(layout, "Alpha")
        dm.Event(alpha, "clicked", dbus.Int32(0, variant_level=1), dbus.UInt32(0))
        check(pump(lambda: "action menu Alpha" in read(log), 10), "choosing a menu item sends its action")

        # Updates.
        mark = len(signals)
        check(step(log, 1), "step 1")
        check(pump(lambda: seen("NewTitle", "/StatusNotifierItem", mark), 10), "a new title is announced")
        check(pump(lambda: seen("NewToolTip", "/StatusNotifierItem", mark), 10), "a new tool tip is announced")
        check(str(mp.Get(ITEM, "Title")) == "Changed", "Title follows the item")
        check(str(mp.Get(ITEM, "ToolTip")[2]) == "Tip2", "ToolTip follows the item")

        mark = len(signals)
        check(step(log, 2), "step 2")
        check(pump(lambda: seen("NewIcon", "/StatusNotifierItem", mark), 10), "a new image is announced")
        pm = mp.Get(ITEM, "IconPixmap")
        a, r, g, b = pixel(pm[0], 11, 11)
        check(a == 255 and 200 < r < 255 and abs(r - g) < 4 and abs(g - b) < 4,
              "a template image is drawn in a light grey (%d,%d,%d)" % (r, g, b))

        mark = len(signals)
        check(step(log, 3), "step 3")
        check(pump(lambda: seen("LayoutUpdated", "/StatusNotifierItem/Menu", mark), 10),
              "a change of the menu is announced with LayoutUpdated")
        rev, layout = dm.GetLayout(0, -1, dbus.Array([], signature="s"))
        check("Gamma" in labels(layout), "the new menu item is in the layout")

        mark = len(signals)
        check(step(log, 4), "step 4")
        check(pump(lambda: seen("NewStatus", "/StatusNotifierItem", mark), 10), "hiding is announced")
        check(str(mp.Get(ITEM, "Status")) == "Passive", "a hidden item is Passive")
        mark = len(signals)
        check(step(log, 5), "step 5")
        check(pump(lambda: seen("NewStatus", "/StatusNotifierItem", mark), 10), "showing is announced")
        check(str(mp.Get(ITEM, "Status")) == "Active", "a shown item is Active")

        check(step(log, 6), "step 6")
        ai.SecondaryActivate(0, 0)
        check(pump(lambda: "action item 2" in read(log), 10), "SecondaryActivate sends an action sent on right clicks")

        # The tray goes away and comes back.
        before = len(watcher.registered)
        watcher.release()
        time.sleep(0.5)
        watcher.own()
        check(pump(lambda: len(watcher.registered) >= before + 2, 10), "the items register again with a new watcher")

        # Removal.
        gone = []
        bus.add_signal_receiver(lambda n, old, new: gone.append((str(n), str(new))),
                                signal_name="NameOwnerChanged", dbus_interface="org.freedesktop.DBus")
        check(step(log, 7), "step 7")
        check(pump(lambda: (menu_name, "") in gone, 10), "a removed item leaves the bus")
        check(menu_name not in [str(n) for n in bus.list_names()], "its name is gone")
        check(action_name in [str(n) for n in bus.list_names()], "the other item stays")
        check(step(log, 8), "step 8")
        check(pump(lambda: (action_name, "") in gone, 10), "the second removed item leaves the bus")
        check("DONE" in read(log), "the guest finished")
        check(guest.wait(timeout=30) == 0, "the guest exited cleanly")

    try:
        with_tray()

        # Items without a session bus.
        nolog = os.path.join(work, "nobus.log")
        proc, nolog = start_guest(binary, work, "nobus", "tray", "unix:path=/nonexistent/bus", display, extra)
        check(pump(lambda: "READY" in read(nolog), 90), "with no session bus the application runs and the items exist")
        for n in range(1, 9):
            if not step(nolog, n):
                break
        check("DONE" in read(nolog), "with no session bus every change goes through without trouble")
        proc.wait(timeout=30)

        # The NSStatusItem contract, which needs no tray.
        proc, apilog = start_guest(binary, work, "api", "api", "unix:path=/nonexistent/bus", display, extra)
        proc.wait(timeout=120)
        text = read(apilog)
        for line in text.splitlines():
            if line.startswith("FAIL:"):
                check(False, "api: " + line[6:])
        check(text.rstrip().endswith("PASS"), "the NSStatusItem contract checks pass")
    finally:
        if guest is not None and guest.poll() is None:
            # Lets a guest that is still waiting for steps run to its end.
            for n in range(1, 9):
                open("%s.step%d" % (guest_log, n), "w").close()
            try:
                guest.wait(timeout=20)
            except subprocess.TimeoutExpired:
                guest.kill()
    print("%d failure(s)" % failures)
    return 1 if failures else 0


sys.exit(main())
