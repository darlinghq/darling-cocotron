#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of appkit-x11-xim-composed-text: runs a private fcitx5 (its own D-Bus session, configuration and
# runtime directories) as the X input method on $DISPLAY, which must have a window manager, and types with XTest
# (xdotool) into the window "xim-composed". The command that runs the program must give it XMODIFIERS=@im=fcitx
# (and a locale with compose tables, LANG=en_US.UTF-8) in its environment, and gets the caller's HOME, session
# bus and runtime directory. Usage:
#   appkit-x11-xim-composed-text.sh <command that runs appkit-x11-xim-composed-text>
# Needs fcitx5, dbus-run-session and xdotool; exits 77 (skipped) when one is missing.
set -u
for tool in fcitx5 dbus-run-session xdotool; do
    command -v "$tool" > /dev/null || { echo "SKIP: $tool is not installed"; exit 77; }
done
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/config/fcitx5" "$work/data" "$work/cache" "$work/runtime" "$work/home"
chmod 700 "$work/runtime"
cat > "$work/config/fcitx5/profile" <<PROFILE
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=keyboard-us

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[GroupOrder]
0=Default
PROFILE

cat > "$work/session.sh" <<'SESSION'
#!/usr/bin/env bash
# $1: scratch directory, the rest: the command that runs the program. Runs inside the D-Bus session.
set -u
work=$1; shift
fcitx5 -D --disable all --enable xcb,xim,dbus,dbusfrontend,keyboard,imselector > "$work/fcitx5.log" 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null || true' EXIT
for _ in $(seq 300); do grep -q 'Service name change' "$work/fcitx5.log" && break; sleep 0.1; done
grep -q 'Service name change' "$work/fcitx5.log" || { echo "FAIL: the private fcitx5 did not start"; cat "$work/fcitx5.log"; exit 1; }
sleep 1
# The program is the caller's: it gets the caller's session bus and runtime directory back
restore=(env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_CACHE_HOME "HOME=$ORIG_HOME")
if [ -n "${ORIG_DBUS-}" ]; then restore+=("DBUS_SESSION_BUS_ADDRESS=$ORIG_DBUS"); else restore=("${restore[@]:0:1}" -u DBUS_SESSION_BUS_ADDRESS "${restore[@]:1}"); fi
if [ -n "${ORIG_XDG-}" ]; then restore+=("XDG_RUNTIME_DIR=$ORIG_XDG"); else restore=("${restore[@]:0:1}" -u XDG_RUNTIME_DIR "${restore[@]:1}"); fi
"${restore[@]}" "$@" > "$work/out" 2>&1 < /dev/null &
pid=$!
for _ in $(seq 600); do grep -q '^READY' "$work/out" && break; sleep 0.1; done
grep -q '^READY' "$work/out" || { echo "FAIL: the test never became ready"; cat "$work/out"; exit 1; }
sleep 1.5
win=$(xdotool search --name '^xim-composed$' | head -1)
[ -n "$win" ] || { echo "FAIL: no window"; cat "$work/out"; exit 1; }
xdotool windowactivate --sync "$win" 2>/dev/null
xdotool windowfocus --sync "$win" 2>/dev/null
sleep 0.5
xdotool key dead_acute
sleep 0.4
xdotool key space
sleep 0.5
xdotool key b
sleep 0.4
xdotool key q
for _ in $(seq 300); do grep -q -E '^(ALL PASSED|FAILED)' "$work/out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$work/out"
exit $status
SESSION
chmod +x "$work/session.sh"

ORIG_DBUS=${DBUS_SESSION_BUS_ADDRESS-} ORIG_XDG=${XDG_RUNTIME_DIR-} ORIG_HOME=$HOME \
env -u DBUS_SESSION_BUS_ADDRESS -u WAYLAND_DISPLAY -u WAYLAND_SOCKET -u XDG_SESSION_TYPE \
    HOME="$work/home" XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data" XDG_CACHE_HOME="$work/cache" \
    XDG_RUNTIME_DIR="$work/runtime" XMODIFIERS=@im=fcitx LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    dbus-run-session -- "$work/session.sh" "$work" "$@"
