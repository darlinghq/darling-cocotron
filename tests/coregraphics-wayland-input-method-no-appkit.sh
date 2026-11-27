#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of coregraphics-wayland-input-method-no-appkit: runs the fake input method of wayland-input-method/ (see its
# README.md) on the compositor named by $WAYLAND_DISPLAY and $XDG_RUNTIME_DIR, which must be a wlroots compositor such
# as a headless sway (darling-skills' wayland.sh), then the program, which sees only CoreGraphics, and checks what the
# input method was told of the window's text and kind of text.
# Usage: coregraphics-wayland-input-method-no-appkit.sh <fake-input-method> <command that runs the program>
# (the program has to get DARLING_APPKIT_BACKEND=wayland, WAYLAND_DISPLAY and XDG_RUNTIME_DIR in its environment, and
# DARLING_TEST_INPUT_METHOD=1 for a failure instead of a SKIP when there is no input method). Prints what the program
# prints, then the driver's checks.
set -u
fim=$1; shift
work=$(mktemp -d)
"$fim" > "$work/fim" 2>&1 < /dev/null &
fimpid=$!
trap 'kill $fimpid 2>/dev/null; rm -rf "$work"' EXIT
for _ in $(seq 50); do grep -q '^ready' "$work/fim" && break; sleep 0.1; done
grep -q '^ready' "$work/fim" || { echo "SKIP: the compositor has no input method protocol"; cat "$work/fim"; exit 0; }

"$@" > "$work/out" 2>&1 < /dev/null
rc=$?
cat "$work/out"
grep -q '^SKIP' "$work/out" && exit 0
sleep 1
failures=0
check() {
    if grep -qxF -- "$2" "$work/fim"; then echo "PASS: $1"; else echo "FAIL: $1"; failures=$((failures + 1)); fi
}
# The fake input method prints what it hears: the text around the caret (bytes of UTF-8: "xy", the 4 bytes of
# U+20BB7, "z"; the caret after "y" is byte 2) and the content type (spellcheck 2 and multiline 0x200; email 6).
check "the input method heard the surrounding text with the caret in bytes of UTF-8" 'surrounding "xy𠮷z" 2 2'
check "and the content type" 'content_type 514 6'
[ "$rc" -eq 0 ] || failures=$((failures + 1))
[ "$failures" -eq 0 ] && echo "DRIVER PASSED" || echo "DRIVER FAILED $failures"
exit $((failures != 0))
