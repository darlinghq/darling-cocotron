#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs coregraphics-wayland-toplevel-ordering (order, parents, keyboard focus, miniaturizing and fullscreen of toplevel
# windows through CoreGraphics alone) on the Wayland compositor $WAYLAND_DISPLAY (with DARLING_APPKIT_BACKEND=wayland).
# Usage: coregraphics-wayland-toplevel-ordering.sh <command that runs coregraphics-wayland-toplevel-ordering>
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
