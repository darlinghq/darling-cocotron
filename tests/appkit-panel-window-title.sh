#!/usr/bin/env bash
# Copyright (C) 2026 Lubos Dolezel
#
# X11 harness: runs tests/appkit-panel-default-values.m (built as $1, in the Darling guest) with the open panel
# shown for a while and checks, with xprop (_NET_WM_NAME of the windows in _NET_CLIENT_LIST) on the display named by DISPLAY, that the window manager has the
# panel's title for it although its title is hidden.
# Usage: appkit-panel-window-title.sh <guest program path inside the guest>
set -euo pipefail
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
names() {
    for id in $(xprop -root _NET_CLIENT_LIST | sed 's/.*# //; s/,//g'); do
        xprop -id "$id" _NET_WM_NAME
    done
}
(sleep 8; names >"$temp/names" 2>&1) &
timeout -s KILL 60 darling shell "$1" 14 </dev/null >"$temp/guest.out" 2>&1
wait
grep -q PASS "$temp/guest.out"
grep -q '"Panel title test"' "$temp/names"
echo PASS
