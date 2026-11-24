#!/usr/bin/env python3
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Host side of the portal file chooser test: a private session bus with a fake
# portal (fake-portal.c) and the guest program ../appkit-portal-file-chooser.m
# in each of its modes.
#
#   run.py GUEST-BINARY
#
# Needs a display: an X server with a window manager (DISPLAY, default :99), or
# a Wayland compositor when WAYLAND_DISPLAY is set (passed on to the guest with
# XDG_RUNTIME_DIR), plus dbus-daemon,
# a C compiler with the libdbus-1 headers, and `darling` on PATH (DPREFIX as
# for any darling command).
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


binary = os.path.abspath(sys.argv[1])
here = os.path.dirname(os.path.abspath(__file__))
work = tempfile.mkdtemp(prefix="appkit-portal.", dir=os.environ.get("TMPDIR"))
display = os.environ.get("DISPLAY", ":99")
flags = subprocess.run(["pkg-config", "--cflags", "--libs", "dbus-1"], stdout=subprocess.PIPE,
                       text=True, check=True).stdout.split()
fake = os.path.join(work, "fake-portal")
subprocess.run(["cc", "-o", fake, os.path.join(here, "fake-portal.c")] + flags, check=True)


# A bus of our own with no service directories, so that nothing on the host
# (such as a real xdg-desktop-portal) can be started on it by activation. The
# listen element is required; --address replaces it.
bus_config = os.path.join(work, "bus.conf")
with open(bus_config, "w") as f:
    f.write("""<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
""")

start_dir = os.path.join(work, "start")
os.mkdir(start_dir)


def read(path):
    try:
        return open(path).read()
    except FileNotFoundError:
        return ""


class Scenario:
    def __init__(self, name, portal_args=None, address=None):
        self.name = name
        self.log = os.path.join(work, name + ".log")
        self.address = address or "unix:abstract=darling-portal-test-%d-%s" % (os.getpid(), name)
        self.bus = None
        self.portal = None
        if address is None:
            out = subprocess.run(["dbus-daemon", "--config-file=" + bus_config, "--address=" + self.address,
                                  "--print-pid", "--fork"], stdout=subprocess.PIPE, text=True, check=True)
            self.bus = int(out.stdout.split()[0])
            if portal_args is not None:
                env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS=self.address)
                self.portal = subprocess.Popen([fake] + self.portal_cmd(portal_args), env=env)
                end = time.time() + 10
                while time.time() < end and "READY" not in read(self.log):
                    time.sleep(0.1)

    def portal_cmd(self, args):
        # args: options of fake-portal ("--..."), then CODE and URIs
        options = [a for a in args if a.startswith("--")]
        rest = [a for a in args if not a.startswith("--")]
        return options + [self.log, "120"] + rest

    def run(self, mode, *extra):
        out = os.path.join(work, self.name + ".out")
        env = ["DBUS_SESSION_BUS_ADDRESS=" + self.address, "PORTAL_TEST_DIR=" + start_dir]
        if os.environ.get("WAYLAND_DISPLAY"):
            env += ["DARLING_APPKIT_BACKEND=wayland", "WAYLAND_DISPLAY=" + os.environ["WAYLAND_DISPLAY"],
                    "XDG_RUNTIME_DIR=" + os.environ.get("XDG_RUNTIME_DIR", "")]
        else:
            env += ["DISPLAY=" + display]
        # One run at a time, bounded in time and in memory.
        with open(out, "w") as f:
            subprocess.run(["timeout", "-s", "KILL", "60", "darling", "shell", "sh", "-c",
                            "ulimit -v 4000000; exec \"$0\" \"$@\"", "env"] + env +
                           ["/Volumes/SystemRoot" + binary, mode] + list(extra),
                           stdin=subprocess.DEVNULL, stdout=f, stderr=subprocess.STDOUT)
        return read(out)

    def calls(self):
        return read(self.log)

    def close(self):
        for p in (self.portal,):
            if p is not None:
                p.terminate()
        if self.bus:
            try:
                os.kill(self.bus, 15)
            except ProcessLookupError:
                pass


def result(out):
    m = re.search(r"^RESULT (-?\d+) ?(.*)$", out, re.M)
    return (int(m.group(1)), m.group(2).split("|") if m.group(2) else []) if m else None


URIS = ["0", "file:///tmp/a%20b.txt", "file:///home/x/c.txt"]

# Several files, modal, with the options of the panel.
s = Scenario("open", URIS)
out = s.run("open")
log = s.calls()
check("CALL OpenFile" in log, "runModal on an open panel calls FileChooser.OpenFile")
check("s'multiple':<true>" in log and "s'directory':<false>" in log and "s'modal':<true>" in log,
      "multiple, directory and modal options")
check("arg1 s'Choose notes'" in log, "the panel's message is the dialog title")
check("s'current_folder':<[%s,00]>" % ",".join("%02x" % c for c in start_dir.encode()) in log, "the directory is a NUL-terminated host path")
check("s'handle_token':<s'" in log, "a handle token is sent")
check("s'filters':<[(s'Supported Files',[(0,s'*.[tT][xX][tT]')])]>" in log, "the allowed type becomes a filter")
check("s'current_filter':<(s'Supported Files',[(0,s'*.[tT][xX][tT]')])>" in log, "and the current filter")
check(result(out) == (1, ["/Volumes/SystemRoot/tmp/a b.txt", "/Volumes/SystemRoot/home/x/c.txt"]),
      "the URIs become guest paths: %r" % (result(out),))
s.close()

# A folder panel.
s = Scenario("folder", ["0", "file:///home/x/dir"])
out = s.run("folder")
check("s'directory':<true>" in s.calls(), "a folder-only panel sets the directory option")
check(result(out) == (1, ["/Volumes/SystemRoot/home/x/dir"]), "the folder is returned")
s.close()

# Save: name, label, and the first allowed extension added to the result.
s = Scenario("save", ["0", "file:///tmp/out"])
out = s.run("save")
log = s.calls()
check("CALL SaveFile" in log, "runModal on a save panel calls FileChooser.SaveFile")
check("s'current_name':<s'Report'>" in log and "s'accept_label':<s'Export'>" in log,
      "name and prompt are sent")
check(result(out) == (1, ["/Volumes/SystemRoot/tmp/out.txt"]), "the save result gets the allowed extension: %r" % (result(out),))
s.close()

# Sheet: on X11 the parent window is the sheet's window as x11:<id>; Wayland has
# no handle to give yet. The call returns at once.
s = Scenario("sheet", URIS)
out = s.run("sheet")
if os.environ.get("WAYLAND_DISPLAY"):
    check("arg0 s''" in s.calls(), "Wayland: no parent window handle")
else:
    check(re.search(r"arg0 s'x11:[0-9a-f]+'", s.calls()) is not None, "the sheet's window is the parent, as x11:<id>")
check(out.find("RETURNED") >= 0 and out.find("RETURNED") < out.find("RESULT"),
      "the sheet call returns before the dialog is closed")
check(result(out) is not None and result(out)[0] == 1 and len(result(out)[1]) == 2,
      "the completion handler gets OK and the files")
s.close()

# Modeless begin.
s = Scenario("begin", URIS)
out = s.run("begin")
check(out.find("RETURNED") >= 0 and out.find("RETURNED") < out.find("RESULT"), "begin returns at once")
check(result(out) is not None and result(out)[0] == 1, "the completion handler runs")
s.close()

# Cancelled and failed dialogs.
for code in ("1", "2"):
    s = Scenario("cancel" + code, [code])
    out = s.run("open")
    check(result(out) == (0, []), "response code %s is a cancel with no files" % code)
    s.close()

s = Scenario("badurl", ["0", "http://example.com/a"])
out = s.run("open")
check(result(out) == (0, []), "a response that is not file URIs is a cancel")
s.close()

s = Scenario("early", ["--respond-first", "0", "file:///tmp/a.txt"])
out = s.run("open")
check(result(out) == (1, ["/Volumes/SystemRoot/tmp/a.txt"]), "a Response that arrives before the method reply is used")
s.close()

# Panels the portal cannot show use the built-in panel.
for mode, why in (("accessory", "an accessory view without controls"),
                  ("accessory-text", "an accessory view with a text field"),
                  ("delegate", "a filtering delegate")):
    s = Scenario(mode, URIS)
    out = s.run(mode)
    check("CALL" not in s.calls(), "%s: the portal is not called" % why)
    check(result(out) == (0, []) and "DONE" in out, "%s: the built-in panel ran and was cancelled" % why)
    s.close()

# An accessory view of pop-up buttons and check boxes goes to the portal as "choices", and the answers are put back
# into the controls (the action of a control that changed is sent: here the pop-up's changes the allowed file type).
s = Scenario("choices", ["--choice=c0=2", "--choice=c1=true", "0", "file:///tmp/a.txt"])
out = s.run("choices", "domain")
log = s.calls()
check("CALL OpenFile" in log, "an accessory view of a pop-up and a check box: the portal is called")
check("s'choices':<[(s'c0',s'Plain Text Encoding',[(s'0',s'Automatic'),(s'1',s'Unicode (UTF-8)'),"
      "(s'2',s'Western (ISO Latin 1)')],s'0'),(s'c1',s'Ignore rich text commands',[],s'false')]>" in log,
      "the pop-up (with its label, colon removed) and the check box are the choices: %r" %
      ([l for l in log.splitlines() if "choices" in l],))
check(result(out) == (1, ["/Volumes/SystemRoot/tmp/a.txt"]), "the file is returned: %r" % (result(out),))
check("CONTROLS popup=2 check=1 popupActions=1 checkActions=1" in out,
      "the portal's answers are in the controls, once each action: %r" % ([l for l in out.splitlines() if "CONTROLS" in l],))
s.close()

# No answers for the choices (a portal that ignores them): the controls keep their values.
s = Scenario("choices-ignored", ["0", "file:///tmp/a.txt"])
out = s.run("choices", "domain")
check("CONTROLS popup=0 check=0 popupActions=0 checkActions=0" in out,
      "without answers the controls are unchanged: %r" % ([l for l in out.splitlines() if "CONTROLS" in l],))
s.close()

# A cancelled dialog leaves the controls as they were, whatever the portal says.
s = Scenario("choices-cancel", ["--choice=c0=1", "1"])
out = s.run("choices", "domain")
check(result(out) == (0, []) and "CONTROLS popup=0 check=0 popupActions=0 checkActions=0" in out,
      "a cancelled dialog does not change the controls: %r" % ([l for l in out.splitlines() if "CONTROLS" in l],))
s.close()

# Answers that are not an option of the choice are ignored.
s = Scenario("choices-bad", ["--choice=c0=7", "--choice=c1=maybe", "--choice=zzz=1", "0", "file:///tmp/a.txt"])
out = s.run("choices", "domain")
check("CONTROLS popup=0 check=0 popupActions=0 checkActions=0" in out,
      "answers that are not an option of their choice are ignored: %r" % ([l for l in out.splitlines() if "CONTROLS" in l],))
s.close()

# A save panel: the pop-up's action runs before the name gets its extension.
s = Scenario("choices-save", ["--choice=c0=1", "0", "file:///tmp/out"])
out = s.run("choices-save", "domain")
log = s.calls()
check("CALL SaveFile" in log and "s'File Format',[(s'0',s'Plain text'),(s'1',s'Rich text')],s'0')" in log,
      "a save panel's pop-up is a choice of SaveFile")
check(result(out) == (1, ["/Volumes/SystemRoot/tmp/out.rtf"]),
      "the choice made in the dialog decides the extension: %r" % (result(out),))
s.close()

s = Scenario("off", URIS)
out = s.run("plain", "off")
check("CALL" not in s.calls(), "preference unset: the portal is not called")
check(result(out) == (0, []) and "DONE" in out, "preference unset: the built-in panel is used")
s.close()

s = Scenario("app", ["0", "file:///tmp/a.txt"])
out = s.run("single", "app")
check("CALL OpenFile" in s.calls(), "the application's own value turns it on")
check(result(out) == (1, ["/Volumes/SystemRoot/tmp/a.txt"]), "the application's own value: one file %r" % (result(out),))
s.close()

s = Scenario("appoff", URIS)
out = s.run("plain", "app-off")
check("CALL" not in s.calls(), "the application's NO wins over the domain's YES: the portal is not called")
check(result(out) == (0, []) and "DONE" in out, "the application's NO: the built-in panel is used")
s.close()

# Answers that are not to be believed or cannot come.
s = Scenario("toomany", URIS)
out = s.run("single")
check(result(out) == (0, []), "several files for a single-selection panel are a cancel: %r" % (result(out),))
s.close()

s = Scenario("splituri", ["0", "file:///tmp/a.txt\nfile:///tmp/b.txt", "#comment"])
out = s.run("open")
check(result(out) == (0, []), "a URI with a line break is refused, not split: %r" % (result(out),))
s.close()

s = Scenario("impostor", ["--impostor", "0", "file:///tmp/a.txt"])
out = s.run("single")
check(result(out) == (1, ["/Volumes/SystemRoot/tmp/a.txt"]),
      "a Response from another bus client is ignored: %r" % (result(out),))
s.close()

s = Scenario("vanish", ["--vanish", "0", "file:///tmp/a.txt"])
out = s.run("single")
check("VANISH" in s.calls() and result(out) == (0, []) and "DONE" in out,
      "the portal leaving the bus without a Response is a cancel: %r" % (result(out),))
s.close()

# The portal is not on the bus, or there is no bus.
s = Scenario("noportal", None)
out = s.run("plain")
check(result(out) == (0, []) and "DONE" in out, "no portal on the bus: the built-in panel is used")
s.close()
s = Scenario("nobus", None, address="unix:path=/nonexistent/bus")
out = s.run("plain")
check(result(out) == (0, []) and "DONE" in out, "no session bus: the built-in panel is used")
s.close()

print("%d failure(s)" % failures)
sys.exit(1 if failures else 0)
