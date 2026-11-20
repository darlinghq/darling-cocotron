#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/appkit-open-panel-presentation.m on $DISPLAY (a window manager must be running) and checks, for an open
# panel run as a sheet, modally and modelessly:
#  - the panel is a dialog window related to the document window (WM_TRANSIENT_FOR);
#  - a sheet is drawn over the document window (the fixture checks the frame), a panel run modally has the window
#    manager's frame;
#  - once the panel is dismissed the document window is drawn again where the panel was (no stale panel contents):
#    the fixture's window is one colour, and the root window must show it there.
# Usage: appkit-open-panel-presentation-x11.sh <command that runs "appkit-open-panel-presentation <kind> <seconds>">
# Needs xdotool, xprop, ImageMagick's import and python3.
set -u
status=0
here=$(dirname "$0")
for kind in sheet modal modeless; do
    out=$(mktemp); shot=$(mktemp -u).png
    "$@" $kind 5 > "$out" 2>&1 < /dev/null &
    pid=$!
    for _ in $(seq 400); do grep -q '^READY' "$out" && break; sleep 0.1; done
    grep -q '^READY' "$out" || { echo "FAIL: $kind: the fixture never became ready"; cat "$out"; status=1; kill $pid 2>/dev/null; continue; }
    sleep 1
    doc=$(xdotool search --name '^opp-doc$' | head -1)
    id=$(xdotool search --name '^Open$' | head -1)
    transient=$(xprop -id "$id" WM_TRANSIENT_FOR | sed -n 's/.*window id # //p')
    if [ -n "$transient" ] && [ "$(printf '0x%x' "$doc")" = "$transient" ]; then echo "PASS: $kind panel is transient for the document window"
    else echo "FAIL: $kind panel is not transient for the document window ($transient)"; status=1; fi
    for _ in $(seq 400); do grep -q '^DISMISSED' "$out" && break; sleep 0.1; done
    sleep 0.5
    import -window root PNG24:"$shot"
    read -r _ _ dx dy dw dh <<< "$(grep '^WIN doc' "$out")"
    read -r _ sh <<< "$(grep '^SCREEN' "$out" | awk '{print $1, $3}')"
    top=$((sh - dy - dh))
    # the lower part of the document window's content, where the panel was
    frac=$(python3 -I - "$shot" $((dx + 20)) $((top + 80)) $((dw - 40)) $((dh - 120)) <<'PY'
import sys, struct, zlib
p = sys.argv[1]; x0, y0, rw, rh = map(int, sys.argv[2:6])
d = open(p, 'rb').read(); pos = 8; idat = b''
while pos < len(d):
    n, = struct.unpack('>I', d[pos:pos+4]); t = d[pos+4:pos+8]; b = d[pos+8:pos+8+n]; pos += 12 + n
    if t == b'IHDR': w, h, bd, ct = struct.unpack('>IIBB', b[:10])
    if t == b'IDAT': idat += b
raw = zlib.decompress(idat); bpp = {2: 3, 6: 4}[ct]; stride = w * bpp; prev = bytearray(stride); i = 0; rows = []
for y in range(h):
    f = raw[i]; line = bytearray(raw[i+1:i+1+stride]); i += 1 + stride
    for x in range(stride):
        a = line[x-bpp] if x >= bpp else 0; b = prev[x]; c = prev[x-bpp] if x >= bpp else 0
        if f == 1: line[x] = (line[x] + a) & 255
        elif f == 2: line[x] = (line[x] + b) & 255
        elif f == 3: line[x] = (line[x] + ((a + b) >> 1)) & 255
        elif f == 4:
            pp = a + b - c; pa = abs(pp-a); pb = abs(pp-b); pc = abs(pp-c)
            line[x] = (line[x] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
    rows.append(line); prev = line
n = g = 0
for y in range(y0, y0 + rh):
    for x in range(x0, x0 + rw):
        r, gg, b = rows[y][x*bpp:x*bpp+3]; n += 1
        if abs(r - 26) < 14 and abs(gg - 153) < 14 and abs(b - 51) < 14: g += 1
print("%.3f" % (g / n))
PY
)
    if python3 -I -c "import sys; sys.exit(0 if float('$frac') > 0.98 else 1)"; then echo "PASS: $kind: the document window is drawn again after the panel closed ($frac)"
    else echo "FAIL: $kind: stale contents after the panel closed (only $frac of the area shows the window)"; status=1; fi
    wait $pid
    grep -q '^PASS' "$out" || { echo "FAIL: $kind: the fixture's own checks failed"; grep '^FAIL' "$out"; status=1; }
    rm -f "$out" "$shot"
done
exit $status
