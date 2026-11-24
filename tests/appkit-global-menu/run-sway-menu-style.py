#!/usr/bin/env python3
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Where the main menu is shown by default under a headless sway (wlr-layer-shell,
# no appmenu protocol, so no global menu), and how it follows the application's
# activation:
#
#   run-sway-menu-style.py GUEST_PROGRAM
#
# GUEST_PROGRAM is ../appkit-global-menu.m built for the guest. The menu bar
# surface is looked for in the guest's own state lines (STATE ... bar=) and in
# the layer surfaces sway lists for its output. Needs sway, swaymsg and kcalc (a
# native Wayland client, QT_QPA_PLATFORM=wayland, that stands for another
# application).
import json
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import Bus, check, finish, read, wait_for  # noqa: E402

DARLING = os.environ.get("DARLING", "darling")
program = os.path.abspath(sys.argv[1])
work = tempfile.mkdtemp(prefix="sway-menu-style-", dir=os.environ.get("TMPDIR"))
runtime = os.path.join(work, "run")
os.mkdir(runtime, 0o700)


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


def main():
    bus = Bus(work)
    cfg = os.path.join(work, "sway.cfg")
    with open(cfg, "w") as f:
        f.write("output HEADLESS-1 resolution 1280x800\nfocus_follows_mouse no\ndefault_border none\n")
    env = dict(bus.env, XDG_RUNTIME_DIR=runtime, WLR_BACKENDS="headless", WLR_LIBINPUT_NO_DEVICES="1",
               WLR_RENDERER="pixman")
    env.pop("DISPLAY", None)
    env.pop("WAYLAND_DISPLAY", None)
    sway = subprocess.Popen(["sway", "-c", cfg], env=env, stdout=open(os.path.join(work, "sway.out"), "w"),
                            stderr=subprocess.STDOUT)
    foreign = None
    try:
        wait_until(lambda: os.path.exists(os.path.join(runtime, "wayland-1")) and
                   any(n.startswith("sway-ipc") for n in os.listdir(runtime)), 30)
        sock = os.path.join(runtime, [n for n in os.listdir(runtime) if n.startswith("sway-ipc")][0])

        def msg(*args):
            r = subprocess.run(["swaymsg", "-s", sock] + list(args), env=env, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, text=True, timeout=30)
            return r.stdout

        def guest(mode, tag, extra_env=()):
            log = os.path.join(work, tag + ".log")
            open(log, "w").close()
            process = subprocess.Popen(
                ["timeout", "-s", "KILL", "150", DARLING, "shell", "env", "DBUS_SESSION_BUS_ADDRESS=" + bus.address,
                 "WAYLAND_DISPLAY=" + os.path.join(runtime, "wayland-1"), "DARLING_APPKIT_BACKEND=wayland"] +
                list(extra_env) + ["/Volumes/SystemRoot" + program, "/Volumes/SystemRoot" + log, mode, "100"],
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

        def bar_state(log, want):
            """Whether the last STATE line of the guest says the bar is (not) there."""
            lines = [l for l in read(log).splitlines() if l.startswith("STATE")]
            return bool(lines) and (" bar=%d " % want) in lines[-1] + " "

        def waits_for_bar(log, want, seconds=10):
            return wait_until(lambda: bar_state(log, want), seconds) is not None

        log, process = guest("window", "window")
        check("strip window=1" in read(log), "a titled window carries the menu strip by default")
        time.sleep(3)
        check(bar_state(log, 0), "with a strip in a window there is no menu bar surface")
        stop(process)

        log, process = guest("borderless", "borderless")
        check("strip window=0" in read(log), "a borderless window carries no strip")
        check(waits_for_bar(log, 1), "with only a borderless window the menu bar surface is shown")
        stop(process)

        log, process = guest("nowindow", "nowindow")
        check(waits_for_bar(log, 1), "with no window the menu bar surface is shown")
        stop(process)

        log, process = guest("swap", "swap")
        check(waits_for_bar(log, 1), "swap: no window at first: the menu bar surface is shown")
        check(wait_for(log, "STEP window opened strip=1", 20), "swap: the window opened and carries the strip")
        check(waits_for_bar(log, 0), "swap: the menu bar surface goes away when the window appears")
        check(wait_for(log, "STEP window closed", 20), "swap: the window closed")
        check(waits_for_bar(log, 1), "swap: the menu bar surface comes back when the window is gone")
        stop(process)

        defaults("write", "org.darlinghq.AppKit", "DarlingMenuBarStyle", "screen")
        try:
            log, process = guest("window", "style-screen")
            check("strip window=0" in read(log), "DarlingMenuBarStyle screen: a titled window has no strip")
            check(waits_for_bar(log, 1), "DarlingMenuBarStyle screen: the menu bar surface is shown")
            stop(process)
        finally:
            defaults("delete", "org.darlinghq.AppKit", "DarlingMenuBarStyle")

        # Another application takes the focus, and gives it back.
        cenv = dict(env, QT_QPA_PLATFORM="wayland", WAYLAND_DISPLAY=os.path.join(runtime, "wayland-1"))
        foreign = subprocess.Popen(["kcalc"], env=cenv, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
        check(wait_until(lambda: "kcalc" in msg("-t", "get_tree", "-r"), 30) is not None,
              "the other application has a window")
        for mode, tag in (("borderless", "focus-borderless"), ("window", "focus-window")):
            log, process = guest(mode, tag)
            msg("[app_id=\"org.kde.kcalc\"] focus")
            check(wait_for(log, "RESIGN", 15), tag + ": the application resigns when another application has the focus")
            check(waits_for_bar(log, 0), tag + ": it has no menu bar surface then (after a moment)")
            time.sleep(2)
            check(bar_state(log, 0), tag + ": and stays without")
            tree = json.loads(msg("-t", "get_tree", "-r"))
            ours = []

            def walk(node):
                if node.get("type") in ("con", "floating_con") and not node.get("nodes") and \
                        node.get("pid") not in (None, foreign.pid) and node.get("rect", {}).get("height", 0) > 100:
                    ours.append(node["id"])
                for child in node.get("nodes", []) + node.get("floating_nodes", []):
                    walk(child)
            walk(tree)
            check(bool(ours), tag + ": the program's window is known to sway")
            if ours:
                msg("[con_id=%d] focus" % ours[0])
            check(wait_until(lambda: read(log).rfind("ACTIVE") > read(log).rfind("RESIGN"), 15) is not None,
                  tag + ": the application is active again when its window has the focus")
            if mode == "borderless":
                check(waits_for_bar(log, 1), tag + ": the menu bar surface comes back with the focus")
            stop(process)
    finally:
        for p in (foreign, sway):
            if p is not None:
                p.kill()
                p.wait()
        bus.close()
        print("work directory: " + work)
    return finish()


if __name__ == "__main__":
    sys.exit(main())
