#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# The KWin counterpart of coregraphics-wayland-toplevel-decorations.sh: the same program on a private KWin
# (--no-lockscreen) whose pointer is a libei device (appkit-global-menu/kwin-pointer.c) and whose windows are read with a
# KWin script. The window "wdeco-client" (the one whose frame is 312x240 points) draws a frame of its own; a press on its
# title bar must move it, one on its bottom right corner resize it, one on the close button must be reported as a close
# request, and one on the content must be a mouse event of the content.
#
#   coregraphics-wayland-toplevel-decorations-kwin.py GUEST_PROGRAM
#
# DARLING names the darling launcher (default: darling). Needs kwin_wayland, libei and its headers, python3-dbus, gdbus,
# dbus-monitor and a C compiler.
import importlib.util
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "appkit-global-menu"))
spec = importlib.util.spec_from_file_location("kwinbar", os.path.join(HERE, "appkit-global-menu", "run-kwin-bar.py"))
kwinbar = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kwinbar)
from common import check, finish, read, wait_for  # noqa: E402


def client_window(session):
    for window in session.windows():
        if window.get("w") == 312 and window.get("h") == 240:
            return window
    return None


def drag(session, x, y, dx, dy):
    session.point("move %d %d" % (x, y))
    session.point("down")
    for i in range(1, 9):
        session.point("move %d %d" % (x + dx * i // 8, y + dy * i // 8))
    session.point("up")
    time.sleep(1)


def main():
    program = sys.argv[1]
    work = tempfile.mkdtemp(prefix="kwin-deco-", dir=os.environ.get("TMPDIR"))
    session = kwinbar.Session(work, program)
    log = os.path.join(work, "out.txt")
    darling = os.environ.get("DARLING", "darling")
    guest_dir = os.path.join(work, "go")
    os.mkdir(guest_dir)
    try:
        env = ["WAYLAND_DISPLAY=" + os.path.join(session.runtime, kwinbar.SOCKET), "DARLING_APPKIT_BACKEND=wayland",
               "XDG_RUNTIME_DIR=" + session.runtime]
        process = subprocess.Popen(["timeout", "-s", "KILL", "150", darling, "shell", "env"] + env +
                                   ["/Volumes/SystemRoot" + os.path.abspath(program), "/Volumes/SystemRoot" + guest_dir],
                                   stdin=subprocess.DEVNULL, stdout=open(log, "w"), stderr=subprocess.STDOUT)
        check(wait_for(log, "READY", 90), "the program is ready")
        time.sleep(1)
        window = client_window(session)
        check(window is not None, "KWin has the window that draws its own frame, as big as that frame")
        if window is None:
            print(read(log))
            return finish()
        x0, y0, w0, h0 = window["x"], window["y"], window["w"], window["h"]
        mice = read(log).count("MOUSE")

        # The title bar, away from the buttons, moves the window.
        drag(session, x0 + 200, y0 + 20, 80, 60)
        moved = client_window(session)
        check(moved is not None and abs(moved["x"] - x0 - 80) <= 1 and abs(moved["y"] - y0 - 60) <= 1,
              "the title bar moves the window (%s)" % str(moved and (moved["x"] - x0, moved["y"] - y0)))
        check(read(log).count("MOUSE") == mice, "the program gets no mouse event for the title bar")
        x0, y0 = moved["x"], moved["y"]

        # The bottom right corner starts an interactive resize: the compositor configures the window at the sizes the pointer
        # makes (KWin goes back to the old size when the program does not keep the new one, so the sizes it asked for are what
        # is looked at).
        drag(session, x0 + w0 - 3, y0 + h0 - 3, 40, 30)
        sizes = [tuple(int(v) for v in line.split()[1:3]) for line in read(log).splitlines() if line.startswith("CONFIGURE ")]
        check(any(w >= w0 + 35 and h >= h0 + 25 for w, h in sizes),
              "the bottom right corner makes the compositor resize the window (%s)" % str(max(sizes) if sizes else None))

        # The close button asks for the window to close.
        session.point("move %d %d" % (x0 + 6 + 10 + 9, y0 + 6 + 14))
        session.point("click")
        check(wait_for(log, "CLOSE 1", 5), "the close button is reported as a close request")
        check(read(log).count("MOUSE") == mice, "the close button is not a mouse event of the content")

        # The content gets its press.
        session.point("move %d %d" % (x0 + 150, y0 + 120))
        session.point("click")
        check(wait_for(log, "MOUSE down", 5), "a press on the content is a mouse event")
        again = [w for w in session.windows() if w["x"] == x0 and w["y"] == y0]
        check(len(again) >= 1, "the press on the content did not move the window")

        open(os.path.join(guest_dir, "go1"), "w").close()
        open(os.path.join(guest_dir, "go2"), "w").close()
        wait_for(log, "RESULT", 20)
        text = read(log)
        for line in text.splitlines():
            if line.startswith("FAIL"):
                check(False, "program: " + line)
        check("RESULT failures=0" in text, "the program's own checks pass")
        print("--- program output:")
        print("\n".join(l for l in text.splitlines() if not l.startswith("PASS")))
        kwinbar.stop(process)
    finally:
        session.close()
    return finish()


if __name__ == "__main__":
    sys.exit(main())
