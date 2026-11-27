#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of coregraphics-wayland-activation: reads the Wayland protocol log the program writes (it has to run with
# WAYLAND_DEBUG=client, and DARLING_APPKIT_BACKEND=wayland, WAYLAND_DISPLAY and XDG_RUNTIME_DIR in its environment) and checks
# that the request for the process' activation became an xdg-activation request: a token was asked for and committed, and
# when the compositor sent it, xdg_activation_v1.activate named the surface of the window.
# Usage: coregraphics-wayland-activation.sh <command that runs coregraphics-wayland-activation>
set -u
out=$(mktemp)
trap 'rm -f "$out"' EXIT
"$@" > "$out" 2>&1 < /dev/null
status=0
grep '^\(PASS\|FAIL\|SKIP\)' "$out"
grep -q '^SKIP' "$out" && exit 0
grep -q '^DONE' "$out" || { echo "FAIL: the program did not finish"; status=1; }
# The log is the whole of the output: take what follows the program's READY.
log=$(sed -n '/^READY/,$p' "$out")
get=$(echo "$log" | grep -n 'xdg_activation_v1#[0-9]*\.get_activation_token(new id xdg_activation_token_v1#' | head -1 | cut -d: -f1)
commit=$(echo "$log" | grep -n 'xdg_activation_token_v1#[0-9]*\.commit()' | head -1 | cut -d: -f1)
activate=$(echo "$log" | grep -n 'xdg_activation_v1#[0-9]*\.activate(' | head -1 | cut -d: -f1)
if [ -n "$get" ] && [ -n "$commit" ] && [ -n "$activate" ] && [ "$get" -lt "$commit" ] && [ "$commit" -lt "$activate" ]; then
    echo "PASS: a token was asked for and committed, then the window was activated with it"
else
    echo "FAIL: the activation request was not made (token $get, commit $commit, activate $activate)"; status=1
fi
surface=$(echo "$log" | grep 'xdg_activation_v1#[0-9]*\.activate(' | head -1 | sed -n 's/.*wl_surface#\([0-9]*\)).*/\1/p')
if [ -n "$surface" ] && grep -q "get_xdg_surface(new id xdg_surface#[0-9]*, wl_surface#$surface)" "$out"; then
    echo "PASS: the surface that was activated is a window's surface"
else
    echo "FAIL: the activated surface $surface is not a window's"; status=1
fi
[ $status = 0 ] && echo "RESULT failures=0" || echo "RESULT failures=1"
exit $status
