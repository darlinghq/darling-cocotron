#!/usr/bin/env bash
# Copyright (C) 2026 Lubos Dolezel
# Runs driver.m on the shared Xvfb :99 with xfwm4 (start both first, see the guest-testing notes),
# which starts two helper processes and moves the window manager's focus between them with
# SetFrontProcess(), checking after each call that the process asked for is the active application
# and the other one is not.
#   DRIVER=<driver in the guest> HELPER=<helper in the guest> run-x11.sh
# Exit status 0 when the driver passes.
set -euo pipefail
temp=$(mktemp -d); trap 'rm -rf "$temp"' EXIT
export DISPLAY=:99
DARLING_APPKIT_BACKEND=x11 timeout -s KILL 120 darling shell "${DRIVER:?driver in the guest}" "${HELPER:?helper in the guest}" x11 \
    </dev/null >"$temp/guest.log" 2>&1 || { echo "FAIL: driver failed"; cat "$temp/guest.log"; exit 1; }
cat "$temp/guest.log"
grep -q '^PASS$' "$temp/guest.log"
