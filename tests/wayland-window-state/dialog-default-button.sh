#!/usr/bin/env bash
# Copyright (C) 2026 Lubos Dolezel
# Runs dialog-default-button.m (cross-compiled, GUEST_BIN is its path in the guest) against a
# headless sway: the dialog is made key while a transparent window is the key window, then Return
# is typed with wtype. Needs sway, swaymsg, wtype and a started compositor: WAYLAND_DISPLAY
# (absolute socket path), XDG_RUNTIME_DIR and SWAYSOCK are in the environment.
# usage: dialog-default-button.sh front|order|modal text|keysym
# Exit status 0 when the dialog became key and Return clicked its default button (mode order: when the
# transparent window stayed key and the button was not clicked).
set -euo pipefail
mode=${1:?front, order or modal}
form=${2:?text or keysym}
temp=$(mktemp -d)
kb=
trap 'kill "$kb" 2>/dev/null || true; rm -rf "$temp"' EXIT
DARLING_APPKIT_BACKEND=wayland timeout -s KILL 120 darling shell "${GUEST_BIN:?guest path of the test}" "$mode" 14 \
    </dev/null >"$temp/guest.log" 2>&1 &
for _ in $(seq 1 300); do
    grep -q READY "$temp/guest.log" && break
    sleep 0.2
done
grep -q READY "$temp/guest.log" || { echo "FAIL: guest never printed READY"; cat "$temp/guest.log"; exit 1; }
swaymsg '[title="dd-dialog"] focus' >/dev/null
# A long-lived virtual keyboard first: a transient one leaves the seat without the keyboard capability.
wtype -k Shift_L -s 9000 -k Shift_L &
kb=$!
sleep 1
if [ "$form" = text ]; then
    wtype -s 100 $'\n'
else
    wtype -k Return
fi
fail=0
for _ in $(seq 1 200); do
    grep -q -E '^(DONE|FAILED)' "$temp/guest.log" && break
    sleep 0.2
done
grep -E '^(KEY|CLICKS|DONE|FAILED)' "$temp/guest.log"
grep -q '^DONE' "$temp/guest.log" || fail=1
exit $fail
