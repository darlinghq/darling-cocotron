#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs coregraphics-x11-toplevel-ordering (ordering, levels, keyboard focus, miniaturizing and fullscreen of toplevel
# windows through CoreGraphics alone) on the X server $DISPLAY, which needs a window manager that supports EWMH.
# Usage: coregraphics-x11-toplevel-ordering.sh <command that runs coregraphics-x11-toplevel-ordering>
set -u
out=$(mktemp)
trap 'rm -f "$out"' EXIT
"$@" > "$out" 2>&1 < /dev/null
status=$?
grep '^\(PASS\|FAIL\|SKIP\)' "$out"
grep -q '^FAIL' "$out" && status=1
grep -q '^SKIP' "$out" && exit 0
grep -q '^RESULT failures=0' "$out" || status=1
[ $status = 0 ] && echo "RESULT failures=0" || echo "RESULT failures=1"
exit $status
