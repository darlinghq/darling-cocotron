#!/usr/bin/env bash
# Copyright (C) 2026 Lubos Dolezel
# Runs a guest test of this directory on the shared Xvfb :99 with xfwm4 (start
# both first, see the guest-testing notes) and checks, with a host helper, what
# the X server holds for each window the test names.
#   run.sh hidden      GUEST_BIN=<cross-compiled hidden-window in the guest>
#   run.sh decorations GUEST_BIN=<cross-compiled decorations in the guest>
# Exit status 0 when every window is as expected.
#
# Expectations come from the documented AppKit contract: -orderOut: and
# -makeKeyWindow do not show a window (only the -orderFront family does), and
# NSWindowStyleMaskTitled is the style bit for a title bar. On macOS 26.7.3
# a window whose mask lacks Titled has no title bar (frame and content height
# are equal), while a titled window keeps its 32 point title bar when
# titlebarAppearsTransparent is YES and titleVisibility is hidden.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mode=${1:?hidden or decorations}
temp=$(mktemp -d); trap 'rm -rf "$temp"' EXIT
cc -Wall "$here/probe.c" -lX11 -o "$temp/probe"
export DISPLAY=:99
DARLING_APPKIT_BACKEND=x11 timeout -s KILL 90 darling shell "${GUEST_BIN:?path of the cross-compiled test in the guest}" \
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
    frameless="motif=flags:2 decorations:0$"
    check deco-titled "$framed"
    check deco-borderless "$frameless"
    check deco-untitled "$frameless"
    check deco-titled-to-untitled "$frameless"
    check deco-untitled-to-titled "$framed"
    check deco-titled-transparent "$framed"
    ;;
*) echo "unknown mode $mode"; exit 2 ;;
esac
wait $guest || { echo "FAIL: guest exited with an error"; fail=1; }
cat "$temp/guest.log"
exit $fail
