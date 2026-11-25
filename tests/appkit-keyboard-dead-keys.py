#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of appkit-keyboard-dead-keys (the guest program) on the Wayland and on the X11 backend, with
# everything private:
#   appkit-keyboard-dead-keys.py wayland|x11 PROGRAM
# starts a virtual KWin (kwin_wayland --virtual --no-lockscreen --xwayland) with the layout us/intl and the
# Compose key on the right Alt key, runs PROGRAM (appkit-keyboard-dead-keys built for the guest) as a client of
# KWin (Wayland) or of its Xwayland (X11), and types into it with kwin-keys.c (KWin's fake input protocol), so
# both backends get the same keys from the same keymap. DARLING names the darling launcher (default: darling).
# The keys are typed as the header of appkit-keyboard-dead-keys.m lists them. Needs a C compiler, wayland-scanner
# and the Wayland client library on the host. Prints the output of the program; exits with its status.
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "appkit-global-menu"))
from common import read, require_no_lockscreen, wait_for  # noqa: E402

SOCKET = "darling-dead-keys-test"

# evdev key codes of a PC keyboard; X key codes are these plus 8
A_E, A_Q, A_S, A_Z = 18, 16, 31, 44
APOSTROPHE, SPACE, RETURN, RIGHT_ALT = 40, 57, 28, 100
GRAVE, SIX, LEFT_SHIFT = 41, 7, 42


def tap(*codes):
    return ["%d:%d" % (code, state) for code in codes for state in (1, 0)]


def shifted(code):
    return ["%d:1" % LEFT_SHIFT] + tap(code) + ["%d:0" % LEFT_SHIFT]


SEQUENCES = [
    tap(A_E, RETURN),
    tap(APOSTROPHE, A_E, RETURN),
    tap(APOSTROPHE, SPACE, RETURN),
    tap(APOSTROPHE, A_Q, RETURN),
    tap(RIGHT_ALT, A_S, A_S, RETURN),
    tap(RIGHT_ALT, A_Z, A_Q, RETURN),
    shifted(APOSTROPHE) + tap(SPACE, RETURN),
    shifted(APOSTROPHE) + tap(A_E, RETURN),
    tap(GRAVE, SPACE, RETURN),
    shifted(GRAVE) + tap(SPACE, RETURN),
    shifted(SIX) + tap(SPACE, RETURN),
]


def run_guest(program, env, work):
    darling = os.environ.get("DARLING", "darling")
    out = os.path.join(work, "guest.out")
    command = ["timeout", "-s", "KILL", "120", darling, "shell", "env"] + env + [
        "/Volumes/SystemRoot" + os.path.abspath(program)]
    process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=open(out, "w"), stderr=subprocess.STDOUT)
    if not wait_for(out, "READY", 90):
        process.kill()
        print("FAIL: the test never became ready")
        print(read(out))
        return None, out
    return process, out


def finish(process, out):
    deadline = time.time() + 40
    while time.time() < deadline and process.poll() is None:
        time.sleep(0.2)
    if process.poll() is None:
        process.kill()
    process.wait()
    print(read(out), end="")
    return process.returncode


def run(backend, program):
    work = tempfile.mkdtemp(prefix="dead-keys-", dir=os.environ.get("TMPDIR"))
    runtime = os.path.join(work, "run")
    os.mkdir(runtime, 0o700)
    config = os.path.join(work, "config")
    os.makedirs(config)
    with open(os.path.join(config, "kxkbrc"), "w") as f:
        f.write("[Layout]\nUse=true\nLayoutList=us\nVariantList=intl\nResetOldOptions=true\nOptions=compose:ralt\n")

    # The key injector: KWin has no virtual keyboard protocol, only the fake input one. It reaches the windows of
    # Wayland clients and, through KWin's Xwayland, those of X11 clients, with the keymap KWin gives both.
    xml = os.path.join(HERE, "kwin-fake-input.xml")
    subprocess.run(["wayland-scanner", "client-header", xml, os.path.join(work, "fake-input-client-protocol.h")],
                   check=True)
    subprocess.run(["wayland-scanner", "private-code", xml, os.path.join(work, "fake-input-protocol.c")], check=True)
    keys = os.path.join(work, "kwin-keys")
    subprocess.run(["cc", "-I" + work, "-o", keys, os.path.join(HERE, "kwin-keys.c"),
                    os.path.join(work, "fake-input-protocol.c"), "-lwayland-client"], check=True)

    env = dict(os.environ, XDG_RUNTIME_DIR=runtime, XDG_CONFIG_HOME=config,
               XDG_CACHE_HOME=os.path.join(work, "cache"), XDG_DATA_HOME=os.path.join(work, "data"),
               KWIN_WAYLAND_NO_PERMISSION_CHECKS="1", WAYLAND_DISPLAY=SOCKET)
    env.pop("DISPLAY", None)
    # KWin starts its session program with DISPLAY set to its Xwayland.
    display_file = os.path.join(work, "x-display")
    session = os.path.join(work, "session.sh")
    with open(session, "w") as f:
        f.write('#!/bin/sh\necho "$DISPLAY" > %s\nexec sleep 600\n' % display_file)
    os.chmod(session, 0o755)
    kwin = subprocess.Popen(["kwin_wayland", "--virtual", "--no-lockscreen", "--xwayland", "--socket", SOCKET,
                             "--width", "1280", "--height", "800", session],
                            env=env, stdout=open(os.path.join(work, "kwin.out"), "w"), stderr=subprocess.STDOUT)
    status = 1
    try:
        if not wait_for(display_file, ":", 30):
            print("FAIL: KWin did not start")
            return 1
        require_no_lockscreen(kwin)
        if backend == "wayland":
            guest_env = ["WAYLAND_DISPLAY=" + os.path.join(runtime, SOCKET), "DARLING_APPKIT_BACKEND=wayland"]
        else:
            guest_env = ["DISPLAY=" + read(display_file).strip(), "DARLING_APPKIT_BACKEND=x11"]
        process, out = run_guest(program, guest_env, work)
        if process is None:
            return 1
        time.sleep(2)
        for sequence in SEQUENCES:
            subprocess.run([keys, "150"] + sequence, env=env, check=True)
            time.sleep(0.3)
        status = finish(process, out)
    finally:
        kwin.kill()
        kwin.wait()
    return status


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("wayland", "x11"):
        sys.exit("usage: appkit-keyboard-dead-keys.py wayland|x11 PROGRAM")
    sys.exit(run(sys.argv[1], sys.argv[2]))


if __name__ == "__main__":
    main()
