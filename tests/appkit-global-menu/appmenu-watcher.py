#!/usr/bin/env python3
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Prints what KWin knows about the application menus of its windows, the way
# Plasma's Global Menu applet learns it: through the
# org_kde_plasma_window_management protocol, whose org_kde_plasma_window
# objects send application_menu(service_name, object_path) for a window that
# set the address of its menu (with org_kde_kwin_appmenu on Wayland, or the
# _KDE_NET_WM_APPMENU_* properties on X11). The protocol is described in
# https://invent.kde.org/libraries/plasma-wayland-protocols
# (src/protocols/plasma-window-management.xml).
#
# The compositor must let the client use the protocol: start KWin with
# KWIN_WAYLAND_NO_PERMISSION_CHECKS=1. It speaks the wire protocol directly
# (https://wayland.freedesktop.org/docs/html/ch04.html), so it needs nothing
# but Python. One line per event, flushed:
#
#   window <id> app_id <app id>
#   window <id> pid <pid>
#   window <id> title <title>
#   window <id> menu <service name> <object path>
#   window <id> unmapped
#
#   appmenu-watcher.py SECONDS   (WAYLAND_DISPLAY and XDG_RUNTIME_DIR as for any client)
import os
import socket
import struct
import sys
import time

DISPLAY_ID = 1
REGISTRY_ID = 2

# Opcodes are the positions of the requests and events in the protocol XML.
WL_DISPLAY_GET_REGISTRY = 1
WL_DISPLAY_EV_ERROR = 0
WL_REGISTRY_BIND = 0
WL_REGISTRY_EV_GLOBAL = 0
MANAGER_GET_WINDOW_BY_UUID = 2      # since 12
MANAGER_EV_WINDOW_WITH_UUID = 4     # since 13
WINDOW_EV_TITLE_CHANGED = 0
WINDOW_EV_APP_ID_CHANGED = 1
WINDOW_EV_UNMAPPED = 5
WINDOW_EV_PID_CHANGED = 10
WINDOW_EV_APPLICATION_MENU = 13     # since 10
MANAGER_VERSION = 16


def string_arg(value):
    data = value.encode() + b"\0"
    return struct.pack("<I", len(data)) + data + b"\0" * (-len(data) % 4)


class Reader:
    def __init__(self, data):
        self.data = data
        self.pos = 0

    def uint(self):
        value = struct.unpack_from("<I", self.data, self.pos)[0]
        self.pos += 4
        return value

    def string(self):
        length = self.uint()
        value = self.data[self.pos:self.pos + length - 1].decode(errors="replace")
        self.pos += length + (-length % 4)
        return value


def main():
    seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 60
    name = os.environ.get("WAYLAND_DISPLAY", "wayland-0")
    path = name if name.startswith("/") else os.path.join(os.environ["XDG_RUNTIME_DIR"], name)
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(path)
    next_id = [3]

    def send(obj, opcode, payload=b""):
        sock.sendall(struct.pack("<II", obj, ((8 + len(payload)) << 16) | opcode) + payload)

    def new_id():
        next_id[0] += 1
        return next_id[0] - 1

    send(DISPLAY_ID, WL_DISPLAY_GET_REGISTRY, struct.pack("<I", REGISTRY_ID))
    manager = None
    windows = {}
    buffer = b""
    end = time.time() + seconds
    sock.settimeout(0.2)

    while time.time() < end:
        try:
            chunk = sock.recv(65536)
        except socket.timeout:
            continue
        if not chunk:
            print("disconnected", flush=True)
            return 1
        buffer += chunk
        while len(buffer) >= 8:
            obj, word = struct.unpack_from("<II", buffer)
            size, opcode = word >> 16, word & 0xffff
            if len(buffer) < size:
                break
            args = Reader(buffer[8:size])
            buffer = buffer[size:]

            if obj == DISPLAY_ID and opcode == WL_DISPLAY_EV_ERROR:
                args.uint()
                code = args.uint()
                print("error %d %s" % (code, args.string()), flush=True)
                return 1
            if obj == REGISTRY_ID and opcode == WL_REGISTRY_EV_GLOBAL:
                global_name = args.uint()
                interface = args.string()
                version = args.uint()
                if interface == "org_kde_plasma_window_management" and manager is None:
                    if version < 13:
                        print("window management version %d is too old" % version, flush=True)
                        return 1
                    manager = new_id()
                    send(REGISTRY_ID, WL_REGISTRY_BIND,
                         struct.pack("<I", global_name) + string_arg(interface) +
                         struct.pack("<II", min(version, MANAGER_VERSION), manager))
                    print("bound window management", flush=True)
            elif obj == manager and opcode == MANAGER_EV_WINDOW_WITH_UUID:
                args.uint()
                uuid = args.string()
                window = new_id()
                windows[window] = uuid
                send(manager, MANAGER_GET_WINDOW_BY_UUID, struct.pack("<I", window) + string_arg(uuid))
            elif obj in windows:
                label = "window %s" % windows[obj]
                if opcode == WINDOW_EV_TITLE_CHANGED:
                    print("%s title %s" % (label, args.string()), flush=True)
                elif opcode == WINDOW_EV_APP_ID_CHANGED:
                    print("%s app_id %s" % (label, args.string()), flush=True)
                elif opcode == WINDOW_EV_PID_CHANGED:
                    print("%s pid %d" % (label, args.uint()), flush=True)
                elif opcode == WINDOW_EV_APPLICATION_MENU:
                    service = args.string()
                    print("%s menu %s %s" % (label, service, args.string()), flush=True)
                elif opcode == WINDOW_EV_UNMAPPED:
                    print("%s unmapped" % label, flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
