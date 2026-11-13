# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Helpers of the host side of the global menu tests: a private session bus,
# the fake registrar, gdbus calls and a parser for the text gdbus prints.
import os
import re
import subprocess
import sys
import tempfile
import time

failures = 0


def check(ok, what):
    global failures
    print(("PASS: " if ok else "FAIL: ") + what)
    if not ok:
        failures += 1


def finish():
    print("%d failure(s)" % failures)
    return 1 if failures else 0


def gvariant(value):
    # gdbus takes an argument that starts with a minus for an option.
    if isinstance(value, int) and value < 0:
        return "int32 %d" % value
    return str(value)


class Bus:
    """A private session bus daemon and the environment that points at it."""

    def __init__(self, work):
        self.address = "unix:abstract=darling-global-menu-%d" % os.getpid()
        out = subprocess.run(
            ["dbus-daemon", "--session", "--address=" + self.address, "--print-pid", "--fork"],
            stdout=subprocess.PIPE, text=True, check=True)
        self.pid = int(out.stdout.split()[0])
        self.env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS=self.address)
        self.work = work

    def close(self):
        try:
            os.kill(self.pid, 15)
        except ProcessLookupError:
            pass

    def call(self, dest, path, method, *args):
        """gdbus call; returns the text of the reply, or None on an error."""
        r = subprocess.run(["gdbus", "call", "--session", "--dest", dest, "--object-path", path,
                            "--method", method] + [gvariant(a) for a in args],
                           env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                           timeout=30)
        return r.stdout.strip() if r.returncode == 0 else None


def build_registrar(work):
    exe = os.path.join(work, "fake-registrar")
    here = os.path.dirname(os.path.abspath(__file__))
    flags = subprocess.run(["pkg-config", "--cflags", "--libs", "dbus-1"], stdout=subprocess.PIPE,
                           text=True, check=True).stdout.split()
    subprocess.run(["cc", "-o", exe, os.path.join(here, "fake-registrar.c")] + flags, check=True)
    return exe


def wait_for(path, text, seconds):
    """Waits until the file contains the text."""
    end = time.time() + seconds
    while time.time() < end:
        try:
            if text in open(path).read():
                return True
        except FileNotFoundError:
            pass
        time.sleep(0.2)
    return False


def read(path):
    try:
        return open(path).read()
    except FileNotFoundError:
        return ""


def start_guest(bus, work, binary, log, mode, lifetime=100):
    """Runs the guest program in the background; returns the process. The bus
    only has an address, which may be one nobody listens on. A lifetime in
    seconds makes the program exit by itself."""
    env = ["DISPLAY=:99", "DBUS_SESSION_BUS_ADDRESS=" + bus.address]
    out = open(os.path.join(work, "guest.out"), "w")
    return subprocess.Popen(
        ["timeout", "-s", "KILL", "150", "darling", "shell", "env"] + env +
        ["/Volumes/SystemRoot" + binary, "/Volumes/SystemRoot" + log, mode] +
        ([str(lifetime)] if lifetime else []),
        stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT)


# A parser for the GVariant text format that gdbus prints: tuples, arrays,
# dictionaries, variants, strings, numbers and booleans.
def parse_variant(text):
    tokens = re.findall(r"'(?:[^'\\]|\\.)*'|[()\[\]{}<>,:]|[^\s()\[\]{}<>,:]+", text)
    pos = [0]

    def peek():
        return tokens[pos[0]] if pos[0] < len(tokens) else None

    def take():
        pos[0] += 1
        return tokens[pos[0] - 1]

    def value():
        t = take()
        if t == "(":
            items = []
            while peek() != ")":
                items.append(value())
                if peek() == ",":
                    take()
            take()
            return tuple(items)
        if t == "[":
            items = []
            while peek() != "]":
                items.append(value())
                if peek() == ",":
                    take()
            take()
            return items
        if t == "{":
            d = {}
            while peek() != "}":
                k = value()
                take()  # ':'
                d[k] = value()
                if peek() == ",":
                    take()
            take()
            return d
        if t == "<":
            v = value()
            take()
            return v
        if t.startswith("'"):
            return t[1:-1].replace("\\'", "'").replace("\\\\", "\\")
        if t in ("true", "false"):
            return t == "true"
        if re.fullmatch(r"-?\d+", t):
            return int(t)
        if t.startswith("@"):
            return value()  # a type annotation before an empty array
        if re.fullmatch(r"(u?int\d+|byte|double|handle)", t):
            return value()  # a type annotation before the number
        return t

    return value()


def flatten(layout):
    """Maps item id -> (props, [child ids]) from the (ia{sv}av) layout."""
    items = {}

    def walk(node):
        ident, props, children = node
        items[ident] = (props, [c[0] for c in children])
        for c in children:
            walk(c)

    walk(layout)
    return items


def find_item(items, label, parent=None):
    for ident, (props, children) in items.items():
        if props.get("label") == label:
            return ident
    return None
