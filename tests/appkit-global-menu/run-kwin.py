#!/usr/bin/env python3
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# The main menu under KWin, on Wayland and on X11 (KWin's Xwayland), with and
# without a global menu on the session bus. Everything is private: a virtual
# KWin (kwin_wayland --virtual) with its own runtime directory, and its own
# session bus. KWin's view of the windows is read with appmenu-watcher.py, the
# way Plasma's Global Menu applet reads it.
#
#   run-kwin.py [--registrar fake|kded] GUEST_PROGRAM
#
# GUEST_PROGRAM is ../appkit-global-menu.m built for the guest. The global menu
# is either fake-registrar.c (fake, the default), or Plasma's own: kded6 with
# only its appmenu module, which owns com.canonical.AppMenu.Registrar while
# something owns org.kde.kappmenuview (the name the Global Menu applet and
# KWin's title bar button take); the script takes that name itself (kded).
# DARLING names the darling launcher (default: darling).
#
# Cases, each checked on Wayland and on X11:
#   - a global menu exists: the menu is exported (GetLayout has the items),
#     KWin reports its address for the window, and the window has no strip;
#   - none exists: Wayland shows the menu bar as a layer surface (see
#     run-kwin-bar.py) and no strip in the window; X11 shows its own menu bar
#     along the top of the screen.
import argparse
import glob
import os
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Bus, build_registrar, check, finish, flatten, parse_variant, read, wait_for  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SOCKET = "darling-menu-test"
REGISTRAR = "com.canonical.AppMenu.Registrar"


def has_owner(bus, name):
    return bus.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus.NameHasOwner",
                    "'%s'" % name) == "(true,)"


def wait_owner(bus, name, present, seconds=15):
    end = time.time() + seconds
    while time.time() < end:
        if has_owner(bus, name) == present:
            return True
        time.sleep(0.3)
    return False


def kded_config(config):
    """kded6rc that autoloads only the appmenu module."""
    os.makedirs(config, exist_ok=True)
    modules = set()
    for d in glob.glob("/usr/lib*/qt6/plugins/kf6/kded") + glob.glob("/usr/lib/*/qt6/plugins/kf6/kded"):
        modules.update(os.path.splitext(os.path.basename(f))[0] for f in glob.glob(d + "/*.so"))
    with open(os.path.join(config, "kded6rc"), "w") as f:
        for m in sorted(modules):
            f.write("[Module-%s]\nautoload=%s\n\n" % (m, "true" if m == "appmenu" else "false"))


class GlobalMenu:
    """Something that shows application menus, which can be turned on and off."""

    def __init__(self, kind, bus, work, env):
        self.kind, self.bus, self.work, self.env = kind, bus, work, env
        self.process = None
        self.daemon = None
        if kind == "fake":
            self.exe = build_registrar(work)
        else:
            self.daemon = subprocess.Popen(["kded6"], env=env, stdout=open(os.path.join(work, "kded.out"), "w"),
                                           stderr=subprocess.STDOUT)
            wait_owner(bus, "org.kde.kded6", True)

    def on(self):
        if self.kind == "fake":
            self.process = subprocess.Popen([self.exe, os.path.join(self.work, "registrar.log"), "600"],
                                            env=self.bus.env)
        else:
            # Takes the name a global menu view takes, and holds it.
            self.process = subprocess.Popen(
                [sys.executable, "-c",
                 "import dbus, time; b = dbus.SessionBus(); "
                 "b.request_name('org.kde.kappmenuview', dbus.bus.NAME_FLAG_DO_NOT_QUEUE); time.sleep(600)"],
                env=self.bus.env)
        return wait_owner(self.bus, REGISTRAR, True)

    def off(self):
        if self.process is not None:
            self.process.kill()
            self.process.wait()
            self.process = None
        return wait_owner(self.bus, REGISTRAR, False)

    def close(self):
        self.off()
        if self.daemon is not None:
            self.daemon.kill()
            self.daemon.wait()


def run_guest(args, work, env, tag, backend):
    """Runs the guest program in window mode until it has logged READY and
    returns (log text, process). The process exits by itself."""
    log = os.path.join(work, tag + ".log")
    open(log, "w").close()
    darling = os.environ.get("DARLING", "darling")
    command = ["timeout", "-s", "KILL", "120", darling, "shell", "env"] + env + [
        "DARLING_APPKIT_BACKEND=" + backend,
        "/Volumes/SystemRoot" + os.path.abspath(args.program), "/Volumes/SystemRoot" + log, "window", "12"]
    process = subprocess.Popen(command, stdin=subprocess.DEVNULL,
                               stdout=open(os.path.join(work, tag + ".out"), "w"), stderr=subprocess.STDOUT)
    wait_for(log, "READY", 90)
    # The bar report follows READY after a second; it ends with "bar frame" or is "bar none".
    end = time.time() + 10
    while time.time() < end and "bar frame" not in read(log) and "bar none" not in read(log):
        time.sleep(0.2)
    return read(log), process


def watcher_menus(text):
    return [line.split()[3:5] for line in text.splitlines() if line.split()[2:3] == ["menu"]]


def check_exported(bus, service, what):
    layout = bus.call(service, "/MenuBar", "com.canonical.dbusmenu.GetLayout", 0, -1, "[]")
    items = flatten(parse_variant(layout)[1]) if layout else {}
    labels = {props.get("label") for props, _ in items.values()}
    check({"File", "Save", "Quit Test"} <= labels, what + ": the exported layout has the menu's items")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--registrar", choices=("fake", "kded"), default="fake")
    parser.add_argument("program")
    args = parser.parse_args()

    work = tempfile.mkdtemp(prefix="kwin-menu-", dir=os.environ.get("TMPDIR"))
    runtime = os.path.join(work, "run")
    os.mkdir(runtime, 0o700)
    bus = Bus(work)
    env = dict(bus.env, XDG_RUNTIME_DIR=runtime, XDG_CONFIG_HOME=os.path.join(work, "config"),
               XDG_CACHE_HOME=os.path.join(work, "cache"), XDG_DATA_HOME=os.path.join(work, "data"),
               KWIN_WAYLAND_NO_PERMISSION_CHECKS="1", WAYLAND_DISPLAY=SOCKET)
    env.pop("DISPLAY", None)
    kded_config(env["XDG_CONFIG_HOME"])
    # KWin starts its session program with DISPLAY set to its Xwayland.
    display_file = os.path.join(work, "x-display")
    session = os.path.join(work, "session.sh")
    with open(session, "w") as f:
        f.write('#!/bin/sh\necho "$DISPLAY" > %s\nexec sleep 600\n' % display_file)
    os.chmod(session, 0o755)
    kwin = subprocess.Popen(["kwin_wayland", "--virtual", "--xwayland", "--socket", SOCKET, "--width", "1280",
                             "--height", "800", session],
                            env=env, stdout=open(os.path.join(work, "kwin.out"), "w"), stderr=subprocess.STDOUT)
    watch = os.path.join(work, "watch.txt")
    watcher = None
    menu = None
    try:
        wait_for(display_file, ":", 30)
        x_display = read(display_file).strip()
        watcher = subprocess.Popen([sys.executable, os.path.join(HERE, "appmenu-watcher.py"), "500"], env=env,
                                   stdout=open(watch, "w"), stderr=subprocess.STDOUT)
        check(wait_for(watch, "bound window management", 10), "the watcher sees KWin's windows")
        menu = GlobalMenu(args.registrar, bus, work, env)
        guest_env = ["DBUS_SESSION_BUS_ADDRESS=" + bus.address]
        wayland_env = guest_env + ["WAYLAND_DISPLAY=" + os.path.join(runtime, SOCKET)]
        x11_env = guest_env + ["DISPLAY=" + x_display]

        for backend, benv in (("wayland", wayland_env), ("x11", x11_env)):
            check(menu.on(), backend + ": the registrar is on the bus")
            seen = len(read(watch))
            log, process = run_guest(args, work, benv, backend + "-global", backend)
            time.sleep(2)
            menus = watcher_menus(read(watch)[seen:])
            check("strip window=0" in log, backend + " with a global menu: no strip in the window")
            check(len(menus) > 0 and menus[-1][0].startswith(":") and menus[-1][1] == "/MenuBar",
                  backend + " with a global menu: KWin has the window's menu address (%s)" % menus)
            if menus:
                check_exported(bus, menus[-1][0], backend)
            if backend == "x11":
                check("bar none" in log, "x11 with a global menu: no menu bar window")
            process.wait()

            check(menu.off(), backend + ": the registrar has left the bus")
            seen = len(read(watch))
            log, process = run_guest(args, work, benv, backend + "-none", backend)
            time.sleep(2)
            menus = watcher_menus(read(watch)[seen:])
            if backend == "wayland":
                # KWin offers wlr-layer-shell: the menu bar is a layer surface (run-kwin-bar.py), not a
                # strip in the window. The menu stays exported, for a global menu that appears later.
                check("strip window=0" in log, "wayland without a global menu: no strip in the window")
            else:
                check("strip window=0" in log and "bar frame x=0 y=0 width=1280" in log,
                      "x11 without a global menu: the application's menu bar along the top of the screen")
            process.wait()
    finally:
        if menu is not None:
            menu.close()
        for p in (watcher, kwin):
            if p is not None:
                p.kill()
                p.wait()
        bus.close()
        print("work directory: " + work)
    return finish()


if __name__ == "__main__":
    sys.exit(main())
