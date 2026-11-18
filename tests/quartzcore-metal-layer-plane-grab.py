#!/usr/bin/env python3
# Copyright (C) 2026 Lubos Dolezel
#
# Host side of quartzcore-metal-layer-plane.m: reads pixels of a window from the
# screen. Usage: quartzcore-metal-layer-plane-grab.py <window title> (<label> <x> <y>)...
# with x and y in window pixels, top-left origin. Prints "pixel <label> RRGGBB"
# for each point. On X11 (DISPLAY) it also prints "x11-subwindows <n>", the
# number of windows inside the window. With SWAYSOCK set it reads a sway
# output with grim and finds the window through swaymsg instead.
#
# The guest test runs it as a host program, e.g. with
#   PLANE_GRAB="/Volumes/SystemRoot/usr/bin/python3 -I /<host path>/quartzcore-metal-layer-plane-grab.py"
import ctypes
import json
import os
import subprocess
import sys


def points(argv):
    triples = argv[2:]
    return [(triples[i], int(triples[i + 1]), int(triples[i + 2])) for i in range(0, len(triples) - 2, 3)]


def sway(title, wanted):
    tree = json.loads(subprocess.run(["swaymsg", "-t", "get_tree", "-r"], capture_output=True, check=True).stdout)
    stack = [tree]
    rect = None
    while stack:
        node = stack.pop()
        if node.get("name") == title and node.get("type") in ("con", "floating_con"):
            rect = node["rect"]
            break
        stack.extend(node.get("nodes", []) + node.get("floating_nodes", []))
    if rect is None:
        print("window not found")
        return
    for label, x, y in wanted:
        ppm = subprocess.run(["grim", "-g", "%d,%d 1x1" % (rect["x"] + x, rect["y"] + y), "-t", "ppm", "-"],
                             capture_output=True, check=True).stdout
        r, g, b = ppm[-3:]
        print("pixel %s %02X%02X%02X" % (label, r, g, b))


class XImage(ctypes.Structure):
    pass


def x11(title, wanted):
    x = ctypes.CDLL("libX11.so.6")
    x.XOpenDisplay.restype = ctypes.c_void_p
    x.XDefaultRootWindow.restype = ctypes.c_ulong
    x.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
    x.XQueryTree.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_ulong),
                             ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.POINTER(ctypes.c_ulong)),
                             ctypes.POINTER(ctypes.c_uint)]
    x.XFetchName.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_char_p)]
    x.XTranslateCoordinates.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_int, ctypes.c_int,
                                        ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
                                        ctypes.POINTER(ctypes.c_ulong)]
    x.XGetImage.restype = ctypes.c_void_p
    x.XGetImage.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int, ctypes.c_uint, ctypes.c_uint,
                            ctypes.c_ulong, ctypes.c_int]
    x.XGetPixel.restype = ctypes.c_ulong
    x.XGetPixel.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
    x.XFree.argtypes = [ctypes.c_void_p]

    display = x.XOpenDisplay(None)
    if not display:
        print("cannot open display")
        return
    root = x.XDefaultRootWindow(display)

    def children(window):
        r, p, n = ctypes.c_ulong(), ctypes.c_ulong(), ctypes.c_uint()
        kids = ctypes.POINTER(ctypes.c_ulong)()
        if not x.XQueryTree(display, window, ctypes.byref(r), ctypes.byref(p), ctypes.byref(kids), ctypes.byref(n)):
            return []
        result = [kids[i] for i in range(n.value)]
        if kids:
            x.XFree(kids)
        return result

    def name(window):
        value = ctypes.c_char_p()
        if x.XFetchName(display, window, ctypes.byref(value)) and value.value is not None:
            return value.value.decode(errors="replace")
        return None

    def find(window):
        for child in children(window):
            if name(child) == title:
                return child
            found = find(child)
            if found:
                return found
        return None

    def count(window):
        return sum(1 + count(child) for child in children(window))

    window = find(root)
    if not window:
        print("window not found")
        return
    ox, oy, child = ctypes.c_int(), ctypes.c_int(), ctypes.c_ulong()
    x.XTranslateCoordinates(display, window, root, 0, 0, ctypes.byref(ox), ctypes.byref(oy), ctypes.byref(child))
    print("x11-subwindows %d" % count(window))
    all_planes = (1 << 64) - 1 if ctypes.sizeof(ctypes.c_ulong) == 8 else (1 << 32) - 1
    for label, px, py in wanted:
        image = x.XGetImage(display, root, ox.value + px, oy.value + py, 1, 1, all_planes, 2)  # ZPixmap
        value = x.XGetPixel(image, 0, 0) & 0xFFFFFF
        print("pixel %s %06X" % (label, value))
        # XDestroyImage is a macro; the image is freed with the process


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: %s <window title> (<label> <x> <y>)..." % sys.argv[0])
    wanted = points(sys.argv)
    if os.environ.get("SWAYSOCK"):
        sway(sys.argv[1], wanted)
    else:
        x11(sys.argv[1], wanted)
    sys.stdout.flush()


main()
