#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/appkit-window-manager-hints.m on $DISPLAY (a window manager must be running) and checks
# what the X11 backend told the window manager about each window, and where each window is:
#  - the main window, the window that draws its own chrome and the borderless window that cannot become main
#    (all windows of a regular application, which the Dock lists) are application windows: type NORMAL,
#    no SKIP_TASKBAR, no WM_TRANSIENT_FOR;
#  - every other window is not listed in a task bar (SKIP_TASKBAR and SKIP_PAGER) and belongs to the
#    main window (WM_TRANSIENT_FOR), with the type its kind gives (utility for the panel, pop-up menu
#    for pop-ups, tool tip for the tool tip);
#  - every managed window positions itself (WM_NORMAL_HINTS USPosition and PPosition), and every
#    window is where it was asked to be;
#  - a window that cannot become key says so (WM_HINTS input False).
# If KWIN_QUERY is set to a command that prints one "KWINWIN <caption> k=v ..." line per window (see
# the impl note), the window manager's own view is checked too: no task-bar entry for any window
# but the application windows, and the key window is the only active one.
# Usage: appkit-window-manager-hints-x11.sh <command that runs "appkit-window-manager-hints <seconds>">
# Needs xdotool and xprop.
set -u
out=$(mktemp)
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$out"' EXIT
for _ in $(seq 400); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 1
status=0
fail() { echo "FAIL: $*"; status=1; }
pass() { echo "PASS: $*"; }

screen_h=$(sed -n 's/^SCREEN [0-9]* //p' "$out")
managed_list=$(xprop -root _NET_CLIENT_LIST)
main_id=$(xdotool search --name '^wmh-main$' | head -1)

# name x y w h (Cocoa, as requested), kind: application | popup | popup-oor | aux | panel | tooltip
while read -r name x y w h kind; do
    id=$(xdotool search --name "^$name\$" | head -1)
    if [ -z "$id" ]; then fail "$name: no window"; continue; fi
    props=$(xprop -id "$id" _NET_WM_WINDOW_TYPE _NET_WM_STATE WM_TRANSIENT_FOR WM_NORMAL_HINTS WM_HINTS 2>&1)
    hex=$(printf '0x%x' "$id")
    managed=0; grep -q "$hex" <<< "$managed_list" && managed=1
    got=()
    type=$(sed -n 's/^_NET_WM_WINDOW_TYPE(ATOM) = _NET_WM_WINDOW_TYPE_//p' <<< "$props")
    skip=no; grep -q '_NET_WM_STATE_SKIP_TASKBAR' <<< "$props" && grep -q '_NET_WM_STATE_SKIP_PAGER' <<< "$props" && skip=yes
    transient=none
    if grep -q '^WM_TRANSIENT_FOR(WINDOW)' <<< "$props"; then
        t=$(sed -n 's/^WM_TRANSIENT_FOR(WINDOW): window id # //p' <<< "$props"); [ "$t" = "$(printf '0x%x' "$main_id")" ] && transient=main || transient=$t
    fi
    posHints=no; grep -q 'user specified location' <<< "$props" && grep -q 'program specified location' <<< "$props" && posHints=yes
    input=unset
    grep -q 'Client accepts input or input focus: False' <<< "$props" && input=no
    grep -q 'Client accepts input or input focus: True' <<< "$props" && input=yes
    eval "$(xdotool getwindowgeometry --shell "$id")"
    wantX=$x wantY=$((screen_h - y - h))
    case $kind in
        application) wantType=NORMAL wantSkip=no wantTransient=none;;
        popup)       wantType=POPUP_MENU wantSkip=yes wantTransient=main;;
        aux)         wantType=NORMAL wantSkip=yes wantTransient=main;;
        panel)       wantType=UTILITY wantSkip=yes wantTransient=main;;
        tooltip)     wantType=TOOLTIP wantSkip=yes wantTransient=main;;
    esac
    # Pop-ups that cannot become key are not managed (the window manager neither lists nor places them); the
    # rest must tell the window manager that they place themselves.
    wantPos=yes; [ "$managed" = 0 ] && wantPos=any
    wantInput=yes; [ "$name" = wmh-tooltip ] || [ "$name" = wmh-child ] && wantInput=no
    line="$name: type $type skip $skip transient $transient positioned-by-app $posHints input $input at $X,$Y"
    ok=1
    [ "$type" = "$wantType" ] || ok=0
    [ "$skip" = "$wantSkip" ] || ok=0
    [ "$transient" = "$wantTransient" ] || ok=0
    [ "$wantPos" = any ] || [ "$posHints" = "$wantPos" ] || ok=0
    [ "$input" = "$wantInput" ] || ok=0
    [ "$X,$Y" = "$wantX,$wantY" ] || ok=0
    if [ $ok = 1 ]; then pass "$line"; else fail "$line; expected type $wantType skip $wantSkip transient $wantTransient positioned-by-app $wantPos input $wantInput at $wantX,$wantY"; fi
done <<EOF
wmh-main 100 500 500 350 application
wmh-chrome 1400 400 210 140 application
wmh-popup 820 560 160 120 popup
wmh-popup-level 1100 640 200 150 popup
wmh-loose 1400 700 170 110 application
wmh-child 700 300 150 100 popup
wmh-panel 1000 300 180 130 panel
wmh-tooltip 300 200 120 40 tooltip
EOF

if [ -n "${KWIN_QUERY:-}" ]; then
    kw=$($KWIN_QUERY)
    for n in wmh-main wmh-chrome wmh-loose; do
        l=$(grep "^KWINWIN $n " <<< "$kw")
        if grep -q 'skipTaskbar=false' <<< "$l"; then pass "KWin lists $n in the task bar"; else fail "KWin does not list $n: $l"; fi
    done
    for n in wmh-popup wmh-popup-level wmh-child wmh-panel wmh-tooltip; do
        l=$(grep "^KWINWIN $n " <<< "$kw")
        if [ -z "$l" ] || grep -q 'skipTaskbar=true' <<< "$l"; then pass "KWin keeps $n out of the task bar"; else fail "KWin lists $n in the task bar: $l"; fi
    done
    key=$(sed -n 's/^KEY //p' "$out")
    active=$(grep 'active=true' <<< "$kw" | sed 's/^KWINWIN \([^ ]*\) .*/\1/' | tr '\n' ' ')
    if [ "$active" = "$key " ]; then pass "only the key window ($key) is active"; else fail "active windows: '$active', the key window is $key"; fi
fi
kill $pid 2>/dev/null; wait $pid 2>/dev/null
grep '^FAIL ' "$out"
[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
exit $status
