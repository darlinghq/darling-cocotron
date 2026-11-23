#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/appkit-menu-bar-without-windows.m with a private session bus. The test expects no desktop global menu;
# on a desktop session whose bus has a global-menu registrar the application exports its menu there and draws no
# bar, so the test must not see that bus. Usage:
#   appkit-menu-bar-without-windows.sh x11|wayland <command that runs the guest binary, such as
#   "darling shell env DBUS_SESSION_BUS_ADDRESS=@BUS@ DISPLAY=:99 /path/appkit-menu-bar-without-windows">
# The word @BUS@ in the command is replaced by the address of the private bus, and the backend name is appended to
# the command (the launcher passes only the variables named after env into the guest). Needs dbus-daemon.
set -u
backend=$1; shift
work=$(mktemp -d)
dbus-daemon --session --address="unix:path=$work/bus" --nofork > /dev/null 2>&1 &
bus=$!
trap 'kill $bus 2>/dev/null; rm -rf "$work"' EXIT
for _ in $(seq 50); do [ -S "$work/bus" ] && break; sleep 0.1; done
args=()
for word in "$@"; do args+=("${word//@BUS@/unix:path=$work/bus}"); done
"${args[@]}" "$backend" < /dev/null
