#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of coregraphics-cursor-no-appkit on Wayland: moves a virtual pointer (the helper tests/wayland-virtual-pointer.c, in
# $VIRTUAL_POINTER) over the window of the program and checks the cursor requests the program made between the steps it
# announces (wl_pointer.set_cursor, wp_cursor_shape_device_v1.set_shape and the cursor surface's buffer, from libwayland's
# client debug output: the command has to set WAYLAND_DEBUG=client in the guest). $WAYLAND_DISPLAY, $XDG_RUNTIME_DIR and
# $SWAYSOCK must name a headless sway whose windows float, at output scale 1; with KWIN set the window is taken to be
# centered at 640 360 of a KWin. Usage:
#   coregraphics-cursor-no-appkit-wayland.sh <command that runs coregraphics-cursor-no-appkit>
# Needs swaymsg (not with KWin) and python3.
set -u
work=$(mktemp -d)
out=$work/out vpout=$work/pointer
if [ -n "${KWIN:-}" ]; then
    # KWin has no virtual pointer: the input comes from the injector tests/kwin-keys.c (in $KWIN_KEYS, KWin's fake input protocol)
    mkfifo "$work/fifo"
    "${KWIN_KEYS:?path of the built kwin-keys}" 20 < "$work/fifo" > "$vpout" 2>&1 &
else
    pointer=${VIRTUAL_POINTER:?path of the built wayland-virtual-pointer helper}
    mkfifo "$work/fifo"
    "$pointer" < "$work/fifo" > "$vpout" 2>&1 &
fi
vp=$!
exec 3> "$work/fifo"
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'exec 3>&-; kill $pid $vp 2>/dev/null; rm -rf "$work"' EXIT
if [ -z "${KWIN:-}" ]; then
    for _ in $(seq 50); do grep -q '^READY' "$vpout" && break; sleep 0.1; done
    grep -q '^READY' "$vpout" || { echo "FAIL: no virtual pointer"; cat "$vpout"; exit 1; }
fi
for _ in $(seq 600); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; head -20 "$out"; exit 1; }
sleep 2
if [ -n "${KWIN:-}" ]; then
    center="640 360"
else
swaymsg -q 'focus'
center=$(swaymsg -t get_tree | python3 -I -c '
import json, sys
def walk(n):
    if n.get("shell") == "xdg_shell":
        r = n["rect"]
        print(r["x"] + r["width"] // 2, r["y"] + r["height"] // 2)
        return True
    return any(walk(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
walk(json.load(sys.stdin))')
fi
[ -n "$center" ] || { echo "FAIL: the window is not on screen"; head -20 "$out"; exit 1; }
if [ -n "${KWIN:-}" ]; then echo "a${center% *},${center#* }" >&3; else echo "abs ${center% *} ${center#* }" >&3; fi
# The compositor reports the first move into a surface as an enter, which is no motion for the program; the second one is.
sleep 1
if [ -n "${KWIN:-}" ]; then
    # KWin places the window itself: the pointer visits points of the display until the program sees it move.
    for y in 360 200 520 120 650; do
        for x in 640 300 980 150 1130; do
            grep -q '^MOVED' "$out" && break 2
            echo "a$x,$y" >&3; sleep 0.4; echo "a$(( x + 4 )),$(( y + 3 ))" >&3; sleep 0.4
        done
    done
else
    echo "rel 4 3" >&3
fi
for _ in $(seq 400); do grep -q '^DONE' "$out" && break; sleep 0.1; done
grep -q '^DONE' "$out" || { echo "FAIL: the program did not finish"; tail -20 "$out"; exit 1; }
cp "$out" "$work/log"
grep -q '^NOSPI' "$out" && echo "NOTE: the cursor SPI is missing"
python3 -I - "$work/log" <<'PY'
import re, sys

SHAPE_DEFAULT, SHAPE_TEXT = 1, 9
buffers, attached, scales, state = {}, {}, {}, {}
steps = []          # per step: the last cursor request: ('hidden',), ('shape', n), ('image', w, h, hotx, hoty)
requests = []       # the requests since the previous step marker
shapeDevice = False
seen_surface_request = []
for line in open(sys.argv[1], errors='replace'):
    m = re.search(r'create_buffer\(new id wl_buffer#(\d+), \d+, (\d+), (\d+),', line)
    if m: buffers[m[1]] = (int(m[2]), int(m[3]))
    m = re.search(r'wl_surface#(\d+)\.attach\(wl_buffer#(\d+),', line)
    if m: attached[m[1]] = buffers.get(m[2])
    m = re.search(r'wl_surface#(\d+)\.set_buffer_scale\((\d+)\)', line)
    if m: scales[m[1]] = int(m[2])
    m = re.search(r'wl_surface#(\d+)\.commit\(\)', line)
    if m: state[m[1]] = (attached.get(m[1]), scales.get(m[1], 1))
    m = re.search(r'wp_cursor_shape_device_v1#\d+\.set_shape\(\d+, (\d+)\)', line)
    if m: requests.append(('shape', int(m[1])))
    m = re.search(r'wl_pointer#\d+\.set_cursor\(\d+, (nil|wl_surface#(\d+)), (-?\d+), (-?\d+)\)', line)
    if m:
        if m[1] == 'nil':
            requests.append(('hidden',))
        else:
            buf, scale = state.get(m[2], (None, 1))
            if buf is not None:
                requests.append(('image', buf[0] // scale, buf[1] // scale, int(m[3]), int(m[4])))
    if re.match(r'STEP \d+ ', line):
        steps.append(requests)
        requests = []

failures = 0
def check(label, ok, detail):
    global failures
    print(('PASS ' if ok else 'FAIL ') + label + ': ' + detail)
    if not ok: failures += 1

def last(n): return steps[n - 1][-1] if len(steps) >= n and steps[n - 1] else None
def shown(request): return request is not None and request[0] != 'hidden'
def anyShown(n): return any(shown(r) for r in steps[n - 1]) if len(steps) >= n else False

check('all steps ran', len(steps) == 8, '%d steps' % len(steps))
check('1 hide: the pointer gets no cursor', last(1) == ('hidden',), str(last(1)))
check('2 show with no cursor selected: the default cursor is requested again',
      shown(last(2)) and (last(2)[0] != 'shape' or last(2)[1] == SHAPE_DEFAULT), str(last(2)))
check('3 the I-beam shape', last(3) is not None and ((last(3)[0] == 'shape' and last(3)[1] == SHAPE_TEXT) or last(3)[0] == 'image'),
      str(last(3)))
check('4 the image: 16x16 points, hot spot 3,5', last(4) is not None and last(4)[0] == 'image' and last(4)[1:] == (16, 16, 3, 5), str(last(4)))
check('5 hide: the pointer gets no cursor', last(5) == ('hidden',), str(last(5)))
check('6 an image selected while hidden shows nothing', not anyShown(6), str(steps[5] if len(steps) > 5 else None))
check('7 show: the image selected meanwhile, hot spot 4,6', last(7) is not None and last(7)[0] == 'image' and last(7)[1:] == (16, 16, 4, 6), str(last(7)))
check('8 no cursor selected: the default cursor', shown(last(8)) and (last(8)[0] != 'shape' or last(8)[1] == SHAPE_DEFAULT), str(last(8)))
if failures == 0:
    print('ALL PASSED')
    sys.exit(0)
print('FAILED %d' % failures)
sys.exit(1)
PY
