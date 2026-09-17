#!/usr/bin/env python3
"""Static guard for the protocol/version half of scroll-frame coalescing."""

from pathlib import Path
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
protocol = (root / "WaylandProtocol.h").read_text()
library = (root / "WaylandLibrary.m").read_text()
display = (root / "WaylandDisplay.m").read_text()
wayland_xml = Path("/usr/share/wayland/wayland.xml")
pointer_events = []
if wayland_xml.exists():
    tree = ET.parse(wayland_xml)
    pointer = tree.find(".//interface[@name='wl_pointer']")
    pointer_events = [event.attrib["name"] for event in pointer.findall("event")]

checks = {
    "frame opcode matches wl_pointer v5": "WP_POINTER_EV_FRAME = 5" in protocol,
    "installed protocol defines frame as pointer event 5":
        not pointer_events or pointer_events.index("frame") == 5,
    "runtime opcode table validates frame":
        'WP_POINTER_EV_FRAME, "frame"' in library,
    "seat negotiation retains pointer v5": "version: MIN(version, 5)" in display,
    "axis delivery is accumulated": "_pendingScrollY += delta" in display,
    "frame delivery posts accumulated scroll":
        "case WP_POINTER_EV_FRAME:" in display and "[self postPendingScroll]" in display,
    "pre-v5 delivery remains immediate":
        "WL.wl_proxy_get_version(_pointer) < 5" in display,
}

for description, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'} {description}")
if not all(checks.values()):
    raise SystemExit(1)
print(f"RESULT checks={len(checks)} failures=0")
