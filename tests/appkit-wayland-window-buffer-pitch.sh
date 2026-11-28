#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# A dma-buf the Wayland backend shares a window's pixels in has rows that start at a multiple of 256 bytes. A compositor
# that samples the buffer with its GPU needs that of a linear buffer; with rows of the tight 4 * width bytes a window of
# an unaligned width is shown sheared. Runs appkit-wayland-window-buffer-pitch (width 661 pixels) with libwayland's client
# debug output and checks the zwp_linux_buffer_params_v1.add stride of every buffer the window got. Prints SKIP when the
# compositor offers no linux-dmabuf (the window then uses wl_shm and there is nothing to check). Usage:
#   appkit-wayland-window-buffer-pitch.sh <command that runs appkit-wayland-window-buffer-pitch with WAYLAND_DEBUG=client>
# $WAYLAND_DISPLAY and $XDG_RUNTIME_DIR name the compositor. Needs python3.
set -u
out=$(mktemp)
trap 'rm -f "$out"' EXIT
"$@" > "$out" 2>&1 < /dev/null
grep -q '^SKIP' "$out" && { grep '^SKIP' "$out"; exit 0; }
grep -q '^PASS' "$out" || { echo "FAIL: the fixture failed"; head -40 "$out"; exit 1; }
python3 -I -c '
import re, sys
# libwayland prints the request arguments: add(fd N, plane, offset, stride, modifier hi, modifier lo) and
# create_immed(new id wl_buffer#N, width, height, format, flags)
strides = []; sizes = []
for line in sys.stdin:
    m = re.search(r"zwp_linux_buffer_params_v1#\d+\.add\(fd \d+, \d+, \d+, (\d+), \d+, \d+\)", line)
    if m: strides.append(int(m.group(1)))
    m = re.search(r"zwp_linux_buffer_params_v1#\d+\.create_immed\(new id wl_buffer#\d+, (\d+), (\d+),", line)
    if m: sizes.append((int(m.group(1)), int(m.group(2))))
if not strides:
    print("SKIP: no linux-dmabuf buffers (the compositor offers none the window can use)"); sys.exit(0)
bad = [s for s in strides if s % 256 != 0]
window = [s for s in sizes if s[0] in (661,)]
if not window:
    print("FAIL: no dma-buf of the 661 pixel wide window (sizes seen: %s)" % sizes); sys.exit(1)
if bad:
    print("FAIL: dma-buf strides that are not a multiple of 256: %s" % bad); sys.exit(1)
print("PASS: the dma-bufs of the window have strides %s" % sorted(set(strides)))
' < "$out"
