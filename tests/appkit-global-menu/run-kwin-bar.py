#!/usr/bin/env python3
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# The application's menu bar under KWin (wlr-layer-shell, no global menu) on
# Wayland. A private virtual KWin with its own session bus; the pointer is a
# libei device of KWin's (kwin-pointer.c); KWin's window list comes from a
# KWin script (kwin-windows.js).
#
#   run-kwin-bar.py GUEST_PROGRAM
#
# GUEST_PROGRAM is ../appkit-global-menu.m built for the guest. DARLING names
# the darling launcher (default: darling). Needs kwin_wayland, libei and its
# headers, python3-dbus, gdbus, dbus-monitor, and a C compiler.
#
# Cases:
#   - no global menu, a borderless window: the bar is one layer surface along
#     the top of the output that stays mapped (it is not recreated), the
#     window has no strip, and with the pointer a click on a title opens its
#     menu right below the bar and a click on an item runs its action;
#   - no global menu and no window at all: the same bar; with a titled window the
#     window has the strip and there is no bar;
#   - windows ordered out and in, a key window change and windows closing: the\n#     bar stays the same surface and is shown at the end;\n#   - no session bus reachable: the bar is shown;\n#   - a global menu (fake-registrar.c) from the start: no bar;
#   - a global menu that appears or goes away while the application runs:
#     the bar goes away and comes back.
import argparse
import os
import re
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Bus, build_registrar, check, finish, read, require_no_lockscreen, wait_for  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SOCKET = "darling-menu-bar-test"
WIDTH, HEIGHT = 1280, 800


def build_pointer(work):
    exe = os.path.join(work, "kwin-pointer")
    flags = subprocess.run(["pkg-config", "--cflags", "--libs", "libei-1.0"], stdout=subprocess.PIPE,
                           text=True, check=True).stdout.split()
    subprocess.run(["cc", "-o", exe, os.path.join(HERE, "kwin-pointer.c")] + flags, check=True)
    return exe


class Session:
    def __init__(self, work, program):
        self.work = work
        self.program = program
        self.runtime = os.path.join(work, "run")
        os.mkdir(self.runtime, 0o700)
        self.bus = Bus(work)
        self.env = dict(self.bus.env, XDG_RUNTIME_DIR=self.runtime, KWIN_WAYLAND_NO_PERMISSION_CHECKS="1",
                        XDG_CONFIG_HOME=os.path.join(work, "config"), XDG_CACHE_HOME=os.path.join(work, "cache"),
                        XDG_DATA_HOME=os.path.join(work, "data"), QT_QPA_PLATFORM="offscreen",
                        WAYLAND_DISPLAY=SOCKET)
        self.env.pop("DISPLAY", None)
        self.kwin = subprocess.Popen(["kwin_wayland", "--virtual", "--no-lockscreen", "--socket", SOCKET, "--width", str(WIDTH),
                                      "--height", str(HEIGHT), "sleep", "1000"],
                                     env=self.env, stdout=open(os.path.join(work, "kwin.out"), "w"),
                                     stderr=subprocess.STDOUT)
        end = time.time() + 30
        while time.time() < end and not os.path.exists(os.path.join(self.runtime, SOCKET)):
            time.sleep(0.2)
        require_no_lockscreen(self.kwin)
        # The pointer: KWin hands out a libei connection over D-Bus.
        import dbus
        self.connection = dbus.bus.BusConnection(self.bus.address)
        end = time.time() + 30
        while True:
            try:
                remote = self.connection.get_object("org.kde.KWin", "/org/kde/KWin/EIS/RemoteDesktop")
                fd, self.cookie = dbus.Interface(remote, "org.kde.KWin.EIS.RemoteDesktop").connectToEIS(7)
                break
            except dbus.DBusException:
                if time.time() > end:
                    raise
                time.sleep(0.5)
        number = fd.take()
        self.pointer = subprocess.Popen([build_pointer(work), str(number)], stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, text=True, pass_fds=[number])
        os.close(number)
        self.pointer_ready = False

    def close(self):
        for p in (getattr(self, "pointer", None), self.kwin):
            if p is not None:
                p.kill()
                p.wait()
        self.bus.close()

    def gdbus(self, dest, path, method, *args):
        r = subprocess.run(["gdbus", "call", "--session", "--dest", dest, "--object-path", path, "--method",
                            method] + [str(a) for a in args], env=self.env, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, text=True, timeout=30)
        return r.stdout.strip()

    def windows(self):
        """KWin's windows as dicts, read with kwin-windows.js."""
        monitor = subprocess.Popen(["dbus-monitor", "--session", "interface=org.darlinghq.test"], env=self.env,
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        time.sleep(0.5)
        reply = self.gdbus("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadScript",
                           os.path.join(HERE, "kwin-windows.js"), "darling-windows")
        number = re.search(r"\d+", reply).group(0)
        self.gdbus("org.kde.KWin", "/Scripting/Script" + number, "org.kde.kwin.Script.run")
        windows = []
        end = time.time() + 10
        while time.time() < end:
            line = monitor.stdout.readline()
            m = re.search(r'string "((?:WIN|END)[^"]*)"', line)
            if m:
                if m.group(1) == "END":
                    break
                fields = dict(kv.split("=") for kv in m.group(1).split()[1:])
                window = {k: (int(v) if v.lstrip("-").isdigit() else v) for k, v in fields.items()}
                window["text"] = m.group(1)
                windows.append(window)
        monitor.kill()
        monitor.wait()
        self.gdbus("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.unloadScript", "darling-windows")
        return windows

    def bars(self):
        return [w for w in self.windows() if w["x"] == 0 and w["y"] == 0 and w["w"] == WIDTH and w["h"] < 100]

    def point(self, command):
        if not self.pointer_ready:
            self.pointer_ready = self.pointer.stdout.readline().strip() == "READY"
        self.pointer.stdin.write(command + "\n")
        self.pointer.stdin.flush()
        self.pointer.stdout.readline()
        time.sleep(0.3)

    def guest(self, mode, tag, seconds=60, extra_env=(), extra_args=()):
        log = os.path.join(self.work, tag + ".log")
        open(log, "w").close()
        darling = os.environ.get("DARLING", "darling")
        env = ["DBUS_SESSION_BUS_ADDRESS=" + self.bus.address,
               "WAYLAND_DISPLAY=" + os.path.join(self.runtime, SOCKET), "DARLING_APPKIT_BACKEND=wayland"] + list(extra_env)
        process = subprocess.Popen(["timeout", "-s", "KILL", "120", darling, "shell", "env"] + env +
                                   ["/Volumes/SystemRoot" + os.path.abspath(self.program),
                                    "/Volumes/SystemRoot" + log, mode, str(seconds)] + list(extra_args),
                                   stdin=subprocess.DEVNULL, stdout=open(os.path.join(self.work, tag + ".out"), "w"),
                                   stderr=subprocess.STDOUT)
        wait_for(log, "READY", 90)
        # The bar report follows READY after a second.
        wait_for(log, "bar frame", 10) or wait_for(log, "bar none", 3)
        return log, process


def wait_until(condition, seconds=15):
    end = time.time() + seconds
    while time.time() < end:
        value = condition()
        if value:
            return value
        time.sleep(0.4)
    return None


def items(log):
    return {int(m.group(1)): (int(m.group(2)), int(m.group(3)))
            for m in re.finditer(r"bar item (\d+) x=(\d+) y=(\d+)", read(log))}


def stop(process):
    # Killing the launcher leaves the application running in the container, with its bar: shut the
    # container down, so that the next case starts alone.
    process.kill()
    process.wait()
    subprocess.run([os.environ.get("DARLING", "darling"), "shutdown"], stdin=subprocess.DEVNULL,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
    time.sleep(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("program")
    args = parser.parse_args()
    work = tempfile.mkdtemp(prefix="kwin-bar-", dir=os.environ.get("TMPDIR"))
    session = Session(work, args.program)
    registrar = None
    try:
        registrar_exe = build_registrar(work)

        def registrar_on():
            nonlocal registrar
            registrar = subprocess.Popen([registrar_exe, os.path.join(work, "registrar.log"), "600"],
                                         env=session.bus.env)
            time.sleep(1.5)

        def registrar_off():
            nonlocal registrar
            registrar.kill()
            registrar.wait()
            registrar = None
            time.sleep(1.5)

        # A borderless window, no global menu.
        log, process = session.guest("borderless", "borderless")
        check("strip window=0" in read(log), "borderless window: no strip in the window")
        bars = wait_until(session.bars, 10)
        check(bool(bars) and len(bars) == 1, "borderless window: one bar along the top of the output (%s)" % bars)
        if bars:
            check(bars[0]["skipTaskbar"] == 1, "the bar has no task bar entry")
            ident = bars[0]["id"]
            time.sleep(4)
            check([b["id"] for b in session.bars()] == [ident],
                  "the bar stays the same layer surface (it is not recreated again and again)")
            known = {w["id"] for w in session.windows()}
            positions = items(log)
            check(1 in positions, "the bar draws its titles")
            if 1 in positions:
                x, y = positions[1]
                session.point("move %d %d" % (x, y))
                session.point("click")
                check(wait_for(log, "tracking begin", 10), "a click on a title opens its menu")
                popups = wait_until(lambda: [w for w in session.windows() if w["id"] not in known], 5)
                check(bool(popups), "the menu is a window of its own")
                if popups:
                    p = popups[0]
                    check(p["y"] == bars[0]["h"] and abs(p["x"] - x) < 100,
                          "the menu opens right below the bar, at its title (%s)" % p["text"])
                    session.point("move %d %d" % (p["x"] + 20, p["y"] + 12))
                    session.point("click")
                    check(wait_for(log, "action newDoc mainthread=1", 10),
                          "a click on an item runs its action on the main thread")
        stop(process)

        # No window at all: the bar. A titled window carries the menu strip instead (run-kwin-menu-style.py
        # covers when the bar and the strips come and go).
        log, process = session.guest("nowindow", "nowindow")
        check(len(wait_until(session.bars, 10) or []) == 1, "nowindow: the bar is shown")
        check("strip window=0" in read(log), "nowindow: no strip in the window")
        stop(process)
        log, process = session.guest("window", "window")
        time.sleep(3)
        check("strip window=1" in read(log), "window: the strip in the window")
        check(session.bars() == [], "window: no bar")
        stop(process)

        # Windows come and go (ordered out and in, the key window changes, one closes, one replaces
        # another): the bar is not hidden and shown again for each, and it is there at the end.
        # WAYLAND_DEBUG shows the layer surfaces the application creates.
        log, process = session.guest("churn", "churn", extra_env=["WAYLAND_DEBUG=client"])
        wait_for(log, "churn done", 20)
        time.sleep(1)
        final = session.bars()
        check(len(final) == 1, "after the windows came and went the bar is shown")
        check("churn done active=1 barVisible=1" in read(log), "the application sees its bar ordered in at the end")
        created = read(os.path.join(work, "churn.out")).count("get_layer_surface(")
        check(created == 1, "the bar was not hidden and shown again while the windows came and went (%d surfaces)" % created)
        stop(process)

        # No session bus at all (the application cannot reach any registrar): the bar is shown.
        log, process = session.guest("borderless", "nobus", extra_env=["DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent/bus"])
        check(len(wait_until(session.bars, 10) or []) == 1, "without a session bus: the bar is shown")
        stop(process)

        # A global menu from the start.
        registrar_on()
        log, process = session.guest("borderless", "global")
        time.sleep(3)
        check(session.bars() == [], "with a global menu from the start: no bar")
        # ... that goes away, and comes back, while the application runs.
        registrar_off()
        check(bool(wait_until(session.bars, 10)), "the global menu goes away: the bar appears")
        registrar_on()
        check(wait_until(lambda: not session.bars(), 10) is not None,
              "the global menu appears: the bar goes away")
        registrar_off()
        check(bool(wait_until(session.bars, 10)), "the global menu goes away again: the bar is back")
        stop(process)
    finally:
        if registrar is not None:
            registrar.kill()
        session.close()
        print("work directory: " + work)
    return finish()


if __name__ == "__main__":
    sys.exit(main())
