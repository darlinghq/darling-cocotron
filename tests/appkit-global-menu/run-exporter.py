#!/usr/bin/env python3
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Host side of the exporter test: a private session bus with a fake registrar,
# the guest program with a menu, and calls that a desktop's global menu makes.
#
#   run-exporter.py GUEST-BINARY
#
# Needs Xvfb :99 with a window manager, gdbus, dbus-daemon, xprop and a C
# compiler with the libdbus-1 headers.
import os
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

binary = os.path.abspath(sys.argv[1])
work = tempfile.mkdtemp(prefix="appkit-global-menu.")
bus = Bus(work)
registrar_log = os.path.join(work, "registrar.log")
stop = os.path.join(work, "stop-registrar")
guest_log = os.path.join(work, "guest.log")
monitor_out = open(os.path.join(work, "monitor.txt"), "w")
registrar = monitor = guest = None
try:
    registrar = subprocess.Popen([build_registrar(work), registrar_log, "170", stop], env=bus.env)
    check(wait_for(registrar_log, "READY", 10), "the fake registrar owns its name")
    monitor = subprocess.Popen(
        ["dbus-monitor", "--address", bus.address,
         "type='signal',interface='com.canonical.dbusmenu',member='LayoutUpdated'"],
        stdout=monitor_out, stderr=subprocess.STDOUT)
    time.sleep(1)

    guest = start_guest(bus, work, binary, guest_log, "panel")
    check(wait_for(guest_log, "READY", 60), "the guest application is running")
    check(wait_for(registrar_log, "RegisterWindow", 20), "the registrar is told about a window")

    reg = [l.split() for l in read(registrar_log).splitlines() if l.startswith("RegisterWindow")]
    sender, window, path = reg[0][1], int(reg[0][2]), reg[0][3]
    check(path == "/MenuBar", "the window is registered with the menu's object path")
    check(window != 0, "the registered window id is an X window")

    x = subprocess.run(["xprop", "-display", ":99", "-id", str(window),
                        "_KDE_NET_WM_APPMENU_SERVICE_NAME", "_KDE_NET_WM_APPMENU_OBJECT_PATH"],
                       stdout=subprocess.PIPE, text=True).stdout
    check('"%s"' % sender in x, "the window carries the service name KDE reads")
    check('"/MenuBar"' in x, "the window carries the object path KDE reads")

    def call(method, *args):
        return bus.call(sender, "/MenuBar", "com.canonical.dbusmenu." + method, *args)

    version = bus.call(sender, "/MenuBar", "org.freedesktop.DBus.Properties.Get",
                       "com.canonical.dbusmenu", "Version")
    check(version is not None and "3" in version, "Version property is 3")

    def layout(parent=0, depth=-1):
        text = call("GetLayout", parent, depth, "[]")
        return flatten(parse_variant(text)[1]) if text else {}

    items = layout()
    root_children = items.get(0, ({}, []))[1]
    check(len(root_children) == 2, "the root has the application menu and File")
    first = items.get(root_children[0], ({}, []))[0] if root_children else {}
    check(first.get("label") == os.path.basename(binary),
          "the first menu is titled with the application name, not the item's title")
    file_id = find_item(items, "File")
    check(file_id is not None, "File menu exported")
    props = lambda label: items[find_item(items, label)][0]
    new_doc = find_item(items, "New__Doc")
    check(new_doc is not None, "underscores in a title are doubled")
    check(props("New__Doc").get("shortcut") == [["Control", "N"]], "Command+N shown as a shortcut")
    check(props("Save").get("shortcut") == [["Control", "Shift", "S"]], "Command+Shift+S shown as a shortcut")
    check(any(p.get("type") == "separator" for p, _ in items.values()), "separators exported")
    check(props("Hidden").get("visible") is False, "a hidden item is exported as not visible")
    check(props("Checked").get("toggle-type") == "checkmark" and props("Checked").get("toggle-state") == 1,
          "item state is exported as a check mark")
    check(props("Dynamic").get("children-display") == "submenu", "submenus are exported")
    check(props("New__Doc").get("enabled") is True, "an enabled item is enabled")

    shallow = layout(0, 1)
    check(all(not c for _, c in [shallow[k] for k in root_children]) if root_children and
          all(k in shallow for k in root_children) else False,
          "recursionDepth limits the layout")
    group = call("GetGroupProperties", "[%d]" % new_doc, "['label']")
    check(group is not None and "New__Doc" in group and "shortcut" not in group,
          "GetGroupProperties filters properties")
    prop = call("GetProperty", new_doc, "label")
    check(prop is not None and "New__Doc" in prop, "GetProperty")

    # AboutToShow: updates the menu (the delegate's menuNeedsUpdate: and
    # validation) before the desktop reads it.
    dynamic = find_item(items, "Dynamic")
    check(call("AboutToShow", file_id) is not None, "AboutToShow is answered")
    check("needsUpdate Dynamic" in read(guest_log), "AboutToShow runs menuNeedsUpdate: of the menu")
    check("validate disabledAction" in read(guest_log), "AboutToShow validates the items")
    items = layout()
    check(find_item(items, "Dynamic 1") is not None, "the items the delegate added are exported")
    call("Event", dynamic, "opened", "<0>", 0)
    check("willOpen Dynamic" in read(guest_log), "the opened event calls menuWillOpen:")
    call("Event", dynamic, "closed", "<0>", 0)
    check("didClose Dynamic" in read(guest_log), "the closed event calls menuDidClose:")
    current = layout()
    check(current[find_item(current, "Disabled")][0].get("enabled") is False,
          "validation disables an item for which the target answers NO")

    # clicked performs the action, on the main thread.
    call("Event", new_doc, "clicked", "<0>", 0)
    time.sleep(0.5)
    check("action newDoc mainthread=1" in read(guest_log), "a clicked event performs the action on the main thread")
    call("Event", find_item(layout(), "Disabled"), "clicked", "<0>", 0)
    time.sleep(0.5)
    check("action disabledAction" not in read(guest_log), "a disabled item does not perform its action")

    # A change made by the application is announced.
    before = read(monitor_out.name).count("LayoutUpdated")
    call("Event", find_item(layout(), "Add Item"), "clicked", "<0>", 0)
    check(wait_for(guest_log, "action addItem", 5), "Add Item performed")
    deadline = time.time() + 5
    while time.time() < deadline and read(monitor_out.name).count("LayoutUpdated") <= before:
        time.sleep(0.2)
    check(read(monitor_out.name).count("LayoutUpdated") > before, "a change of the menu sends LayoutUpdated")
    check(find_item(layout(), "Added item") is not None, "the new item is in the layout")

    call("Event", find_item(layout(), "Quit Test"), "clicked", "<0>", 0)
    check(wait_for(guest_log, "action quit", 5), "the application menu item works")
    try:
        guest.wait(15)
    except subprocess.TimeoutExpired:
        pass
    check(guest.poll() is not None, "the application exits")
finally:
    open(stop, "w").close()
    for p in (guest, monitor, registrar):
        if p is not None and p.poll() is None:
            p.kill()
    bus.close()
    print("logs in", work)
sys.exit(finish())
