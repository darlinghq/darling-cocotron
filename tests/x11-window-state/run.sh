#!/usr/bin/env bash
# Copyright (C) 2026 Lubos Dolezel
# Runs a guest test of this directory on the shared Xvfb :99 with xfwm4 (start
# both first, see the guest-testing notes) and checks, with a host helper, what
# the X server holds for each window the test names.
#   run.sh hidden      GUEST_BIN=<cross-compiled hidden-window in the guest>
#   run.sh decorations GUEST_BIN=<cross-compiled decorations in the guest>
#   run.sh invisible   GUEST_BIN=<cross-compiled invisible-window in the guest>
#   run.sh key-window <mode>  GUEST_BIN=<cross-compiled key-window in the guest>; mode is one of
#                      orderfront makekey makefront modal nokey click (see key-window.m); needs xdotool
# Exit status 0 when every window is as expected.
#
# Expectations come from the documented AppKit contract: -orderOut: and
# -makeKeyWindow do not show a window (only the -orderFront family does), and
# NSWindowStyleMaskTitled is the style bit for a title bar. On macOS 26.7.3
# a window whose mask lacks Titled has no title bar (frame and content height
# are equal), while a titled window keeps its 32 point title bar when
# titlebarAppearsTransparent is YES and titleVisibility is hidden. A mask with
# Resizable but without Titled has no title bar on 26.7.3 but a 22 point one on
# macOS 10.14.4; we follow 10.14.4, so under X11 it gets the full window
# manager frame like a titled window. Closable alone and Borderless have none.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mode=${1:?hidden or decorations}
temp=$(mktemp -d); trap 'rm -rf "$temp"' EXIT
cc -Wall "$here/probe.c" -lX11 -lXext -o "$temp/probe"
export DISPLAY=:99
[ "$mode" = key-window ] && guestargs=("${2:?orderfront, makekey, makefront, modal, nokey or click}" 14) || guestargs=()
DARLING_APPKIT_BACKEND=x11 timeout -s KILL 90 darling shell "${GUEST_BIN:?path of the cross-compiled test in the guest}" "${guestargs[@]}" \
    </dev/null >"$temp/guest.log" 2>&1 &
guest=$!
for _ in $(seq 1 300); do
    grep -q READY "$temp/guest.log" && break
    sleep 0.2
done
grep -q READY "$temp/guest.log" || { echo "FAIL: guest never printed READY"; cat "$temp/guest.log"; exit 1; }

fail=0
check() { # title expected-regex
    got=$("$temp/probe" "$1" || true)
    if [[ "$got" =~ $2 ]]; then echo "PASS $1: $got"; else echo "FAIL $1: got '$got', want /$2/"; fail=1; fi
}
case $mode in
hidden)
    check restack-visible "mapped=1"
    check restack-ordered-in "mapped=1"
    for t in restack-hidden-above restack-hidden-below restack-hidden-key restack-ordered-out; do
        check "$t" "mapped=0"
    done
    ;;
decorations)
    framed="motif=none"
    frameless="motif=flags:2 functions:0 decorations:0( |$)"
    # Resizable without Titled gets the full frame too (follows Mac OS X 10.14)
    check deco-titled "$framed"
    check deco-borderless "$frameless"
    check deco-untitled "$framed"
    check deco-untitled-fixed "$frameless"
    check deco-borderless-resizable "$framed"
    check deco-titled-to-untitled "$framed"
    check deco-untitled-to-fixed "$frameless"
    check deco-untitled-to-titled "$framed"
    check deco-titled-transparent "$framed"
    ;;
invisible)
    # Windows with alpha 0 and no compositor: frameless, empty shape, still mapped. Only meaningful
    # on a display without a compositing manager (xfwm4 --compositor=off on :99).
    check inv-alpha0-titled "mapped=1 motif=flags:2 functions:0 decorations:0 shape=0 frameshape=0 compositor=0"
    check inv-alpha0-borderless "mapped=1 motif=flags:2 functions:0 decorations:0 shape=0 frameshape=0 compositor=0"
    check inv-alpha1-titled "mapped=1 motif=none shape=1 frameshape=[1-9][0-9]* compositor=0"
    check inv-restored-titled "mapped=1 motif=none shape=1 frameshape=[1-9][0-9]* compositor=0"
    check inv-partial-titled "mapped=1 motif=none shape=1 frameshape=[1-9][0-9]* compositor=0"
    ;;
key-window)
    # What the host does while the guest waits: nothing (makekey, makefront, modal, nokey), types
    # with the window manager's focus on the visible window (orderfront) or clicks into it (click).
    geometry() { timeout 20 xdotool search --sync --name '^kw-b$' | head -1 | xargs -I{} xdotool getwindowgeometry --shell {}; }
    case ${2} in
    orderfront)
        sleep 1
        xdotool type --delay 100 abc
        ;;
    click)
        eval "$(geometry)"
        xdotool mousemove $((X + WIDTH / 2)) $((Y + HEIGHT / 2)) click 1
        ;;
    esac
    xdotool keyup super Super_L shift Shift_L ctrl Control_L alt Alt_L
    for _ in $(seq 1 200); do
        grep -q -E '^(DONE|FAILED)' "$temp/guest.log" && break
        sleep 0.2
    done
    grep -q '^DONE' "$temp/guest.log" || fail=1
    ;;
*) echo "unknown mode $mode"; exit 2 ;;
esac
wait $guest || { echo "FAIL: guest exited with an error"; fail=1; }
cat "$temp/guest.log"
exit $fail
