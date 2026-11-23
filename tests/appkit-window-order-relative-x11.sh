#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/appkit-window-order-relative.m on $DISPLAY (with a window manager) and fails when the program
# fails or logs an X protocol error. Usage:
#   appkit-window-order-relative-x11.sh <command that runs "appkit-window-order-relative">
set -u
out=$(mktemp)
trap 'rm -f "$out"' EXIT
"$@" > "$out" 2>&1 < /dev/null
status=$?
if grep -q 'X11 ERROR' "$out"; then
    echo "FAIL: the X server reported an error"
    status=1
fi
cat "$out"
exit $status
