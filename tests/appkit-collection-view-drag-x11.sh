#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drags between the collection views of tests/appkit-collection-view-drag-live.m with XTest (xdotool) on $DISPLAY,
# which must have a window manager: the selected items 1 and 4 of "cv-source" onto item 2 of "cv-target" and into
# the gap before its item 1, then a text/uri-list from an X client (tests/appkit-x11-xdnd/xdnd-source-driver.c) onto
# its item 5. Checks the source's session callbacks, what the target accepted where, and that the drop target shows
# no longer once the drag is over. Usage:
#   appkit-collection-view-drag-x11.sh <command that runs "appkit-collection-view-drag-live <seconds>">
# for example: appkit-collection-view-drag-x11.sh darling shell /path/appkit-collection-view-drag-live 40
# Needs xdotool and a C compiler with the X11 headers.
set -u
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
out=$work/out
cc -Wall "$here/appkit-x11-xdnd/xdnd-source-driver.c" -lX11 -o "$work/driver" || exit 1
host_file=$work/cv-host-file
: > "$host_file"
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$work"' EXIT

for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 1

origin() { # print "x y" of the top left corner of the content of the window with this title
    local id
    id=$(xdotool search --name "^$1\$" | head -1)
    [ -n "$id" ] || return 1
    eval "$(xdotool getwindowgeometry --shell "$id")"
    echo $X $Y
}
offset() { # offset <AT|GAP> <window> <item>: "x y" in the window, as the test printed it
    awk -v k="$1" -v w="$2" -v i="$3" '$1 == k && $2 == w && $3 == i { print $4, $5; exit }' "$out"
}
point() { # point <AT|GAP> <window> <item>: "x y" on the screen
    local o d
    o=$(origin "$2") && d=$(offset "$1" "$2" "$3") || return 1
    set -- $o $d
    echo $(($1 + $3)) $(($2 + $4))
}

status=0
check() { # check <name> <got> <want>
    if [ "$2" = "$3" ]; then echo "PASS: $1: $2"; else echo "FAIL: $1: '$2'; expected '$3'"; status=1; fi
}

# name, where to drop (kind and item of cv-target), what the target should accept
for spec in "on-item AT 2 item=2 op=on" "in-gap GAP 1 item=1 op=before"; do
    set -- $spec
    name=$1 kind=$2 item=$3 want="$4 $5"
    from=$(point AT cv-source 1) && to=$(point $kind cv-target $item) || { echo "FAIL: $name: no windows"; status=1; continue; }
    set -- $from; sx=$1 sy=$2
    set -- $to; tx=$1 ty=$2
    start=$(wc -l < "$out")
    xdotool mousemove $sx $sy
    sleep 0.3
    xdotool mousedown 1
    sleep 0.3
    for i in 1 2 3 4 5 6 7 8 9 10; do
        xdotool mousemove $((sx + (tx - sx) * i / 10)) $((sy + (ty - sy) * i / 10))
        sleep 0.1
    done
    sleep 0.3
    xdotool mouseup 1
    sleep 1.5
    lines=$(tail -n +$((start + 1)) "$out")
    check "$name: source" "$(echo "$lines" | grep '^SOURCE' | tr '\n' ' ')" "SOURCE willBegin items=1,4 SOURCE ended op=1 "
    check "$name: drop" "$(echo "$lines" | grep '^TARGET accept')" \
        "TARGET accept $want urls=/private/var/tmp/cv-item-1,/private/var/tmp/cv-item-4"
    check "$name: after" "$(echo "$lines" | grep '^TARGET after')" "TARGET after highlight=0 gap=0"
done

# A drop from another X client
start=$(wc -l < "$out")
at=$(offset AT cv-target 5)
XDND_TARGET=cv-target XDND_AT="${at/ /,}" XDND_URIS="file://$host_file"$'\r\n' "$work/driver" > "$work/driver.out" 2>&1
check "host: driver" "$(cat "$work/driver.out")" "OK"
sleep 1
lines=$(tail -n +$((start + 1)) "$out")
check "host: drop" "$(echo "$lines" | grep '^TARGET accept')" "TARGET accept item=5 op=on urls=/Volumes/SystemRoot$host_file"
check "host: string" "$(echo "$lines" | grep '^TARGET string')" "TARGET string file:///Volumes/SystemRoot$host_file"
check "host: source" "$(echo "$lines" | grep -c '^SOURCE')" "0"

kill $pid 2>/dev/null
wait $pid 2>/dev/null
[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
exit $status
