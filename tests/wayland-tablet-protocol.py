#!/usr/bin/env python3
"""Wayland tablet protocol wiring, without a compositor (darlinghq/darling#2591).

The decoder is driven by opcode numbers, so a stale number after an XML change would send tablet
events to the wrong handler. This test reads the protocol XML, the enum and the opcode-check table
the backend uses, and the scanner's generated interface tables, and verifies that they agree. It
runs on a host with wayland-scanner and needs no Wayland display or tablet.

Usage: python3 tests/wayland-tablet-protocol.py
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
XML = "/usr/share/wayland-protocols/unstable/tablet/tablet-unstable-v2.xml"
HEADER = os.path.join(ROOT, "CoreGraphics/WaylandSupport/WaylandProtocol.h")
LIBRARY = os.path.join(ROOT, "CoreGraphics/WaylandSupport/WaylandLibrary.m")
CMAKE = os.path.join(ROOT, "CoreGraphics/WaylandSupport/WaylandProtocols.cmake")
PRIVATE = os.path.join(ROOT, "CoreGraphics/include/CoreGraphics/CoreGraphicsPrivate.h")
CGEVENT = os.path.join(ROOT, "CoreGraphics/CGEventObjC.m")

failures = 0


def check(condition, what):
    global failures
    print(("PASS " if condition else "FAIL ") + what)
    if not condition:
        failures += 1


def main():
    check(os.path.exists(XML), "the tablet protocol XML is installed")
    if not os.path.exists(XML):
        return 1
    root = ET.parse(XML).getroot()
    header = open(HEADER, encoding="utf-8").read()
    library = open(LIBRARY, encoding="utf-8").read()
    cmake = open(CMAKE, encoding="utf-8").read()
    private = open(PRIVATE, encoding="utf-8").read()
    cgevent = open(CGEVENT, encoding="utf-8").read()

    check("tablet-unstable-v2.xml" in cmake, "the tablet XML is in WAYLAND_PROTOCOL_FILES")

    # Mouse-only window fields do not exist on tablet CGEvents: the backend and AppKit use these
    # common fields instead. They must be inside the common-field range of the CGEvent class mask.
    common = {
        "kCGSTabletPointerID": 202,
        "kCGSTabletSystemTabletID": 203,
        "kCGSTabletCapabilityMask": 204,
        "kCGSTabletVendorPointerType": 205,
        "kCGSTabletPointerType": 206,
        "kCGSTabletVendorPointerSerialNumber": 207,
        "kCGSTabletWindowNumber": 208,
        "kCGSTabletWindowNumberThatCanHandleThisEvent": 209,
    }
    for name, value in common.items():
        check(re.search(r"\b%s\s*=\s*%d\b" % (name, value), private) is not None,
              "%s is %d" % (name, value))
    check("{180, 209}" in cgevent, "the tablet common fields are in CGEvent's common range")
    check(re.search(r"\bZWP_TABLET_PAD_EV_REMOVED\s*=\s*7\b", header) is not None,
          "the pad removed opcode used by cleanup is 7")

    # Pads are not decoded: their proxies are only kept so the seat can release them.
    decoded = {"zwp_tablet_manager_v2", "zwp_tablet_seat_v2", "zwp_tablet_v2", "zwp_tablet_tool_v2"}
    interfaces = {}
    for interface in root.findall("interface"):
        name = interface.get("name")
        if not name.startswith("zwp_tablet_"):
            continue
        interfaces[name] = interface
        if name in decoded or name == "zwp_tablet_pad_v2":
            check("extern const struct wl_interface %s_interface;" % name in header,
                  "%s is declared to the backend" % name)
        if name not in decoded:
            continue
        requests = [child for child in interface if child.tag == "request"]
        events = [child for child in interface if child.tag == "event"]
        for opcode, request in enumerate(requests):
            symbol = {
                "zwp_tablet_manager_v2": "ZWP_TABLET_MANAGER",
                "zwp_tablet_seat_v2": "ZWP_TABLET_SEAT",
                "zwp_tablet_v2": "ZWP_TABLET",
                "zwp_tablet_tool_v2": "ZWP_TABLET_TOOL",
                "zwp_tablet_pad_v2": "ZWP_TABLET_PAD",
            }[name] + "_" + request.get("name").upper().replace("-", "_")
            check(re.search(r"\b%s\s*=\s*%d\b" % (symbol, opcode), header) is not None,
                  "%s request %s is opcode %d" % (name, request.get("name"), opcode))
            check("%s_interface, false, %s, \"%s\"" % (name, symbol, request.get("name")) in library,
                  "%s request %s is opcode-checked" % (name, request.get("name")))
        for opcode, event in enumerate(events):
            symbol = {
                "zwp_tablet_manager_v2": "ZWP_TABLET_MANAGER",
                "zwp_tablet_seat_v2": "ZWP_TABLET_SEAT",
                "zwp_tablet_v2": "ZWP_TABLET",
                "zwp_tablet_tool_v2": "ZWP_TABLET_TOOL",
                "zwp_tablet_pad_v2": "ZWP_TABLET_PAD",
            }[name] + "_EV_" + event.get("name").upper().replace("-", "_")
            check(re.search(r"\b%s\s*=\s*%d\b" % (symbol, opcode), header) is not None,
                  "%s event %s is opcode %d" % (name, event.get("name"), opcode))
            check("%s_interface, true, %s, \"%s\"" % (name, symbol, event.get("name")) in library,
                  "%s event %s is opcode-checked" % (name, event.get("name")))

    tool = interfaces.get("zwp_tablet_tool_v2")
    if tool is not None:
        for enum in tool.findall("enum"):
            for entry in enum.findall("entry"):
                symbol = "ZWP_TABLET_TOOL_%s_%s" % (
                    enum.get("name").upper(), entry.get("name").upper())
                value = int(entry.get("value"), 0)
                match = re.search(r"\b%s\s*=\s*(0x[0-9a-fA-F]+|[0-9]+)\b" % symbol, header)
                check(match is not None and int(match.group(1), 0) == value,
                      "%s is %d" % (symbol, value))

    scanner = shutil.which("wayland-scanner")
    check(scanner is not None, "wayland-scanner is available")
    if scanner is not None:
        with tempfile.TemporaryDirectory(prefix="darling-tablet-protocol-") as directory:
            generated = os.path.join(directory, "tablet-unstable-v2-protocol.m")
            result = subprocess.run([scanner, "private-code", XML, generated],
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            check(result.returncode == 0, "the tablet XML generates a protocol table")
            if result.returncode == 0:
                text = open(generated, encoding="utf-8").read()
                for name in interfaces:
                    check("wl_interface %s_interface" % name in text,
                          "the generated table defines %s" % name)

    print("%d failure(s)" % failures)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
