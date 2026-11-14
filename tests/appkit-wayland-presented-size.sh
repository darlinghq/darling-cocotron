#!/bin/bash
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# The size a Wayland compositor shows a window at is its logical size, whatever the scale the
# window is drawn at. Runs a guest command that opens the 301x203 point window of
# appkit-wayland-backing-scale and holds it, asks sway for the window's rectangle and checks it
# is 301 wide (a borderless window; sway must have no borders of its own and float windows).
# Usage: appkit-wayland-presented-size.sh <command that runs "appkit-wayland-backing-scale <scale> 6">
# Needs swaymsg and jq-free text matching, SWAYSOCK and WAYLAND_DISPLAY set for the headless sway.
set -u
"$@" &
pid=$!
width=
for i in $(seq 30); do
    sleep 0.5
    width=$(swaymsg -t get_tree | grep -A8 '"shell": "xdg_shell"' | grep -m1 '"width"' | tr -dc '0-9')
    [ -n "$width" ] && [ "$width" != 0 ] && break
done
wait "$pid"
if [ "$width" = 301 ]; then echo PASS; else echo "FAIL: the compositor shows the window at width '$width', expected 301"; exit 1; fi
