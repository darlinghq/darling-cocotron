#!/usr/bin/env python3
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Tracking of the menus of the application's own menu bar (the screen menu bar,
# a layer surface on Wayland and a dock window on X11): pointer and keyboard.
#
#   run-bar-tracking.py [--cases focused,owner,nowindow,parent,startup,policy,noext] kwin|sway|x11 GUEST_PROGRAM [DISPLAY]
#
# GUEST_PROGRAM is ../appkit-global-menu.m built for the guest. "kwin" runs a
# private virtual KWin (the pointer and keyboard are a libei device of KWin's),
# "sway" a headless sway (wl-input.c, a virtual pointer and keyboard) and "x11" an
# Xvfb DISPLAY (default :99) with a window manager that places docks, driven
# with xdotool. DARLING names the darling launcher (default: darling). Needs the
# tools of run-kwin-bar.py, sway or xdotool for the backend.
#
# Cases "policy" and "noext" cover the recognition of an application bundle by its contents rather than
# a .app extension (NSRunningApplication's policy and bundle URL for six layouts of a program, and an
# application in a bundle directory without .app that never sets a policy: it owns and shows the bar).
#
# Three applications are tested: one that has the keyboard focus (a borderless
# window and the bar), the menu bar owner that does not (a regular application
# with a main menu and an offscreen window, and an LSUIElement helper whose
# window has the focus) and one that is active and owns the bar with no window
# at all while no client has the focus. In each:
#   - the pointer moves in small steps from a title of the bar straight down
#     into its submenu: the menu stays open and its first item is highlighted
#     (the titles cover the whole height of the bar, with no strip below them);
#   - the pointer over the empty part of the bar does not close the open menu;
#   - a menu opened by a click, closed by a click outside, opened again: the
#     keyboard works in it (Down and Return run the first item's action, Escape
#     closes the submenu and then the menu).
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import Bus, check, finish, helper_bundle, plain_bundle, read, wait_for  # noqa: E402

DARLING = os.environ.get("DARLING", "darling")
KEY_CODES = {"Escape": 1, "Return": 28, "Down": 108}


def wait_until(condition, seconds=15):
    end = time.time() + seconds
    while time.time() < end:
        value = condition()
        if value:
            return value
        time.sleep(0.2)
    return None


class Backend:
    """A display server with a pointer and a keyboard to drive, and the way the guest finds it."""

    width = 1280
    height = 800

    def move(self, x, y):
        raise NotImplementedError

    def click(self):
        raise NotImplementedError

    def down(self):
        raise NotImplementedError

    def up(self):
        raise NotImplementedError

    def key(self, name):
        raise NotImplementedError

    def focus_application(self, program):
        """Gives the input focus to the program's window, where the display server does not."""

    def guest_env(self):
        raise NotImplementedError

    def close(self):
        pass


class KWinBackend(Backend):
    def __init__(self, work):
        import importlib.util
        spec = importlib.util.spec_from_file_location("run_kwin_bar", os.path.join(HERE, "run-kwin-bar.py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.module = module
        self.session = module.Session(work, "")
        self.session.point("move 1 1")
        self.bus = self.session.bus

    def move(self, x, y):
        s = self.session
        if not s.pointer_ready:
            s.pointer_ready = s.pointer.stdout.readline().strip() == "READY"
        s.pointer.stdin.write("move %d %d\n" % (x, y))
        s.pointer.stdin.flush()
        s.pointer.stdout.readline()

    def click(self):
        self.session.point("click")

    def down(self):
        self.session.point("down")

    def up(self):
        self.session.point("up")

    def key(self, name):
        self.session.point("key %d" % KEY_CODES[name])

    def guest_env(self):
        s = self.session
        return ["DBUS_SESSION_BUS_ADDRESS=" + s.bus.address, "WAYLAND_DISPLAY=" + os.path.join(s.runtime, self.module.SOCKET),
                "DARLING_APPKIT_BACKEND=wayland"]

    def close(self):
        self.session.close()


class SwayBackend(Backend):
    def __init__(self, work):
        self.runtime = os.path.join(work, "run")
        os.mkdir(self.runtime, 0o700)
        self.bus = Bus(work)
        cfg = os.path.join(work, "sway.cfg")
        with open(cfg, "w") as f:
            f.write("output HEADLESS-1 resolution %dx%d\nfocus_follows_mouse no\ndefault_border none\n" %
                    (self.width, self.height))
        self.env = dict(self.bus.env, XDG_RUNTIME_DIR=self.runtime, WLR_BACKENDS="headless",
                        WLR_LIBINPUT_NO_DEVICES="1", WLR_RENDERER="pixman")
        self.env.pop("DISPLAY", None)
        self.env.pop("WAYLAND_DISPLAY", None)
        self.sway = subprocess.Popen(["sway", "-c", cfg], env=self.env,
                                     stdout=open(os.path.join(work, "sway.out"), "w"), stderr=subprocess.STDOUT)
        wait_until(lambda: os.path.exists(os.path.join(self.runtime, "wayland-1")) and
                   any(n.startswith("sway-ipc") for n in os.listdir(self.runtime)), 30)
        self.sock = os.path.join(self.runtime, [n for n in os.listdir(self.runtime) if n.startswith("sway-ipc")][0])
        self.env["WAYLAND_DISPLAY"] = os.path.join(self.runtime, "wayland-1")
        self.start_input(work)

    def start_input(self, work):
        """The virtual pointer and keyboard (wl-input.c)."""
        exe = os.path.join(work, "wl-input")
        subprocess.run(["wayland-scanner", "client-header", os.path.join(HERE, "wl-input.xml"),
                        os.path.join(work, "wl-input-client.h")], check=True)
        subprocess.run(["wayland-scanner", "private-code", os.path.join(HERE, "wl-input.xml"),
                        os.path.join(work, "wl-input-protocol.c")], check=True)
        flags = subprocess.run(["pkg-config", "--cflags", "--libs", "wayland-client", "xkbcommon"],
                               stdout=subprocess.PIPE, text=True, check=True).stdout.split()
        subprocess.run(["cc", "-I" + work, "-o", exe, os.path.join(HERE, "wl-input.c"),
                        os.path.join(work, "wl-input-protocol.c")] + flags, check=True)
        self.input = subprocess.Popen([exe, str(self.width), str(self.height)], env=self.env, stdin=subprocess.PIPE,
                                      stdout=subprocess.PIPE, text=True)
        self.input.stdout.readline()

    def command(self, text):
        self.input.stdin.write(text + "\n")
        self.input.stdin.flush()
        self.input.stdout.readline()

    def msg(self, *args):
        return subprocess.run(["swaymsg", "-s", self.sock] + list(args), env=self.env, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, text=True, timeout=30).stdout

    def move(self, x, y):
        self.command("move %d %d" % (x, y))

    def click(self):
        self.command("click")

    def down(self):
        self.command("down")

    def up(self):
        self.command("up")

    def key(self, name):
        self.command("key %d" % KEY_CODES[name])

    def guest_env(self):
        return ["DBUS_SESSION_BUS_ADDRESS=" + self.bus.address, "WAYLAND_DISPLAY=" + self.env["WAYLAND_DISPLAY"],
                "DARLING_APPKIT_BACKEND=wayland"]

    def close(self):
        self.input.kill()
        self.sway.kill()
        self.sway.wait()
        self.bus.close()


class X11Backend(Backend):
    def __init__(self, work, display):
        self.display = display
        self.xenv = dict(os.environ, DISPLAY=display)
        self.bus = Bus(work)

    def x(self, *cmd):
        subprocess.run(list(cmd), env=self.xenv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)

    def focus_application(self, program):
        # The window class of a program is its name; the bar is a dock window of the same class.
        for ident in subprocess.run(["xdotool", "search", "--onlyvisible", "--class", os.path.basename(program)],
                                    env=self.xenv, stdout=subprocess.PIPE, text=True).stdout.split():
            kind = subprocess.run(["xprop", "-id", ident, "_NET_WM_WINDOW_TYPE"], env=self.xenv,
                                  stdout=subprocess.PIPE, text=True).stdout
            if "_NET_WM_WINDOW_TYPE_DOCK" not in kind:
                self.x("xdotool", "windowfocus", ident)
                return

    def move(self, x, y):
        self.x("xdotool", "mousemove", str(x), str(y))

    def click(self):
        self.x("xdotool", "click", "1")

    def down(self):
        self.x("xdotool", "mousedown", "1")

    def up(self):
        self.x("xdotool", "mouseup", "1")

    def key(self, name):
        self.x("xdotool", "key", name)

    def guest_env(self):
        return ["DISPLAY=" + self.display, "DBUS_SESSION_BUS_ADDRESS=" + self.bus.address,
                "DARLING_APPKIT_BACKEND=x11"]

    def close(self):
        self.bus.close()


def main():
    argv = sys.argv[1:]
    cases = ["focused", "owner", "nowindow", "parent", "startup", "policy", "noext"]
    if argv[:1] == ["--cases"] and len(argv) > 1:
        cases = argv[1].split(",")
        argv = argv[2:]
    if len(argv) < 2:
        print(__doc__)
        return 2
    kind = argv[0]
    program = os.path.abspath(argv[1])
    work = tempfile.mkdtemp(prefix="bar-tracking-", dir=os.environ.get("TMPDIR"))
    if kind == "kwin":
        be = KWinBackend(work)
    elif kind == "sway":
        be = SwayBackend(work)
    else:
        be = X11Backend(work, argv[2] if len(argv) > 2 else ":99")

    def guest(mode, tag, extra_args=(), exe=None):
        log = os.path.join(work, tag + ".log")
        # Right after "darling shutdown" the launcher can fail with "the container exited, try again".
        for attempt in range(3):
            open(log, "w").close()
            process = subprocess.Popen(
                ["timeout", "-s", "KILL", "150", DARLING, "shell", "env"] + be.guest_env() +
                [exe or "/Volumes/SystemRoot" + program, "/Volumes/SystemRoot" + log, mode, "100"] + list(extra_args),
                stdin=subprocess.DEVNULL, stdout=open(os.path.join(work, tag + ".out"), "w"),
                stderr=subprocess.STDOUT)
            end = time.time() + 90
            while time.time() < end and process.poll() is None and "READY" not in read(log):
                time.sleep(0.3)
            if "READY" in read(log):
                break
            process.kill()
            process.wait()
            subprocess.run([DARLING, "shutdown"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=60)
            time.sleep(4)
        wait_for(log, "bar frame", 10) or wait_for(log, "bar none", 3)
        return log, process

    def stop(process):
        process.kill()
        process.wait()
        subprocess.run([DARLING, "shutdown"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=60)
        time.sleep(4)

    def run_case(tag, mode, extra_args=(), keyboard=True, focused=False, exe=None):
        log, process = guest(mode, tag, extra_args, exe)
        try:
            case(tag, log, keyboard, focused)
        finally:
            stop(process)

    def count(log, text):
        return read(log).count(text)

    def case(tag, log, keyboard, focused):
        m = re.search(r"bar frame x=(\d+) y=(\d+) width=(\d+) height=(\d+)", read(log))
        if focused:
            be.focus_application(program)
        positions = {int(a): (int(b), int(c)) for a, b, c in re.findall(r"bar item (\d+) x=(\d+) y=(\d+)", read(log))}
        check(bool(m) and 1 in positions, tag + ": the bar draws its titles")
        if not m or 1 not in positions:
            return
        bar_height = int(m.group(4))
        fx, fy = positions[1]
        empty_x = fx + 500

        def settle(seconds=1.0):
            time.sleep(seconds)

        def open_file_menu():
            before = count(log, "willOpen File")
            be.move(fx, fy)
            settle(0.4)
            be.click()
            return wait_until(lambda: count(log, "willOpen File") > before, 10) is not None

        def close_by_title_click():
            before = count(log, "didClose File")
            be.move(fx, fy)
            settle(0.4)
            be.click()
            return wait_until(lambda: count(log, "didClose File") > before, 8) is not None

        def tracking_ended(before):
            return wait_until(lambda: count(log, "tracking end") > before, 8) is not None

        # Titles and the submenu: straight down in small steps.
        check(open_file_menu(), tag + ": a click on the File title opens its menu")
        settle(1.0)
        closed = count(log, "didClose File")
        for y in range(fy, bar_height + 20, 2):
            be.move(fx, y)
            time.sleep(0.03)
        settle(1.0)
        check(count(log, "didClose File") == closed,
              tag + ": the menu stays open while the pointer moves down from the title into it")
        check("highlight File New_Doc" in read(log),
              tag + ": and the first item of the submenu is highlighted (%s)" % re.findall(r"highlight File .*", read(log))[-1:])

        # The empty part of the bar.
        be.move(empty_x, fy)
        settle(1.0)
        check(count(log, "didClose File") == closed, tag + ": the pointer over the empty part of the bar keeps the open menu")
        be.move(fx, fy)
        settle(0.6)
        check(count(log, "didClose File") == closed, tag + ": and back on the title as well")
        end = count(log, "tracking end")
        check(close_by_title_click(), tag + ": a second click on the title closes the menu")
        check(tracking_ended(end), tag + ": and ends the tracking")

        # Keyboard in a menu opened by a click; again after the first menu was closed.
        for round_ in (1, 2):
            if not keyboard:
                break
            actions = count(log, "action newDoc")
            end = count(log, "tracking end")
            check(open_file_menu(), tag + ": the menu opens by a click (%d)" % round_)
            settle(1.0)
            be.key("Down")
            settle(0.4)
            be.key("Return")
            check(wait_until(lambda: count(log, "action newDoc") > actions, 8) is not None,
                  tag + ": Down and Return run the first item's action (%d)" % round_)
            check(tracking_ended(end), tag + ": the menu is closed by the choice (%d)" % round_)

        if not keyboard:
            return
        end = count(log, "tracking end")
        closed = count(log, "didClose File")
        check(open_file_menu(), tag + ": the menu opens by a click (Escape)")
        settle(1.0)
        be.key("Escape")
        check(wait_until(lambda: count(log, "didClose File") > closed, 8) is not None,
              tag + ": Escape closes the menu")
        ended = tracking_ended(end)
        check(ended, tag + ": and ends the tracking")
        if not ended:
            close_by_title_click()

    def last(log, prefix):
        lines = [l for l in read(log).splitlines() if l.startswith(prefix)]
        return lines[-1] if lines else ""

    def run_parent(delay):
        """A regular application with a bar and a windowless process outside any bundle that it starts
        DELAY ms after the bar was ordered in, and that activates itself over and over. The process is
        prohibited (as on macOS): it neither becomes the front application nor the menu bar owner, so
        the application keeps its bar, its ownership and its activation."""
        tag = "parent-%dms" % delay
        log, process = guest("parent", tag, ["%d" % delay])
        child = log + ".child"
        try:
            check(wait_for(log, "STEP child launched", 30), tag + ": the windowless process is started")
            check(wait_for(child, "POLICY 2", 60), tag + ": it is prohibited (not in an application bundle)")
            time.sleep(4)
            check("owner=0" in last(child, "OWNER"), tag + ": it does not own the menu bar (%s)" % last(child, "OWNER"))
            check("owner=1" in last(log, "OWNER"), tag + ": the application still owns the menu bar (%s)" % last(log, "OWNER"))
            check("RESIGN" not in read(log), tag + ": the application did not resign")
            check("bar=1" in last(log, "STATE"), tag + ": its bar is still shown (%s)" % last(log, "STATE"))
            case(tag, log, True, True)
        finally:
            stop(process)

    def run_startup(delay):
        """The window the application showed at startup is closed DELAY ms after the bar was ordered
        in: the application stays active, owns the menu bar and keeps its bar."""
        tag = "startup-%dms" % delay
        log, process = guest("startup", tag, ["%d" % delay])
        try:
            check(wait_for(log, "STEP window closed", 30), tag + ": the startup window is closed")
            time.sleep(3)
            check("RESIGN" not in read(log), tag + ": the application did not resign")
            check("owner=1" in last(log, "OWNER"), tag + ": it still owns the menu bar (%s)" % last(log, "OWNER"))
            check("bar=1" in last(log, "STATE"), tag + ": its bar is still shown (%s)" % last(log, "STATE"))
        finally:
            stop(process)

    def run_policy():
        """The policy and the bundle URL that NSRunningApplication gives a program, by where it lies: an
        application bundle is recognised by its contents (the executable in Contents/MacOS next to an
        Info.plist whose package type is APPL or absent), not by a .app extension."""
        layouts = [
            ("app", plain_bundle(work, program, "Policy.app"), 0, True),
            ("no extension", plain_bundle(work, program, "Policy.AppBundle/Inner"), 0, True),
            ("no extension, no package type", plain_bundle(work, program, "Policy2.AppBundle/Inner", None), 0, True),
            ("no extension, LSUIElement", plain_bundle(work, program, "Policy3.AppBundle/Inner", ui_element=True), 1, True),
            ("another package type", plain_bundle(work, program, "Policy4.AppBundle/Inner", "BNDL"), 2, False),
            ("no Info.plist", plain_bundle(work, program, "Policy5.AppBundle/Inner", plist=False), 2, False),
        ]
        os.makedirs(os.path.join(work, "bare"))
        bare = os.path.join(work, "bare", os.path.basename(program))
        subprocess.run(["cp", program, bare], check=True)
        layouts.append(("bare executable", ("/Volumes/SystemRoot" + bare, None), 2, False))
        for name, (exe, bundle), policy, has_url in layouts:
            tag = "policy-" + re.sub(r"\W+", "-", name)
            log = os.path.join(work, tag + ".log")
            open(log, "w").close()
            for attempt in range(3):
                subprocess.run(["timeout", "-s", "KILL", "100", DARLING, "shell", "env"] + be.guest_env() +
                               [exe, "/Volumes/SystemRoot" + log, "policy"],
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if "NSAPP" in read(log):
                    break
                time.sleep(4)
            text = read(log)
            check("RUNNING policy=%d " % policy in text, "%s: NSRunningApplication's policy is %d (%s)" %
                  (name, policy, re.findall(r"RUNNING.*", text)[:1]))
            check("NSAPP policy=%d" % policy in text, "%s: and NSApplication's too" % name)
            if has_url:
                url = re.search(r"url=(\S+)", text)
                check(bool(url) and url.group(1).rstrip("/").endswith(os.path.relpath(bundle, work)),
                      "%s: the bundle URL is the bundle directory (%s)" % (name, url and url.group(1)))
            else:
                check("url=(none)" in text, "%s: there is no bundle URL" % name)
        subprocess.run([DARLING, "shutdown"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=60)
        time.sleep(4)

    try:
        if "policy" in cases:
            run_policy()
        if "noext" in cases:
            # An application that never sets a policy, in a bundle directory with no .app extension: it is a
            # regular application, owns the menu bar and shows it.
            exe, _ = plain_bundle(work, program, "Outer.AppBundle/Probe")
            log, process = guest("bundled", "noext", exe=exe)
            try:
                check("POLICY 0" in read(log), "noext: the application's policy is regular (%s)" % last(log, "POLICY"))
                check("owner=1" in last(log, "OWNER"), "noext: it owns the menu bar (%s)" % last(log, "OWNER"))
                check("bar=1" in last(log, "STATE"), "noext: its bar is shown (%s)" % last(log, "STATE"))
                case("noext", log, True, True)
            finally:
                stop(process)
        if "parent" in cases:
            for delay in (0, 300):
                run_parent(delay)
        if "startup" in cases:
            for delay in (0, 30, 100, 400):
                run_startup(delay)
        if "focused" in cases:
            run_case("focused", "borderless", focused=True)
        if "owner" in cases:
            helper = helper_bundle(work, program)
            # sway gives a popup of a layer surface without keyboard interactivity no keyboard focus
            # while another client has it, so the keyboard checks of the owner case are not made there.
            run_case("owner-uielement", "owner", [helper, "helper"], keyboard=(kind != "sway"))
        if "nowindow" in cases:
            run_case("nowindow", "nowindow", keyboard=(kind != "sway"))
    finally:
        be.close()
        print("work directory: " + work)
    return finish()


if __name__ == "__main__":
    sys.exit(main())
