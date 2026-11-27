#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# The Wayland counterpart of appkit-collection-view-drag-x11.sh: drags the selected items 1 and 4 of "cv-source"
# (tests/appkit-collection-view-drag-live.m) onto item 2 of "cv-target" and into the gap before its item 1, with a
# virtual pointer (tests/wayland-virtual-pointer.c, in $VIRTUAL_POINTER), and checks the source's session callbacks,
# what the target accepted where, and that the drop target shows no longer once the drag is over.
# $WAYLAND_DISPLAY, $XDG_RUNTIME_DIR and $SWAYSOCK must name a headless sway (darling-skills' wayland.sh) whose
# windows float. Usage:
#   appkit-collection-view-drag-wayland.sh <command that runs "appkit-collection-view-drag-live <seconds>">
# Needs swaymsg and python3.
set -u
pointer=${VIRTUAL_POINTER:?path of the built wayland-virtual-pointer helper}
work=$(mktemp -d)
out=$work/out vpout=$work/pointer
mkfifo "$work/fifo"
"$pointer" < "$work/fifo" > "$vpout" 2>&1 &
vp=$!
exec 3> "$work/fifo"
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'exec 3>&-; kill $pid $vp 2>/dev/null; rm -rf "$work"' EXIT
for _ in $(seq 50); do grep -q '^READY' "$vpout" && break; sleep 0.1; done
grep -q '^READY' "$vpout" || { echo "FAIL: no virtual pointer"; cat "$vpout"; exit 1; }

for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 2
swaymsg -q '[title="cv-source"] move position 100 100, focus'
swaymsg -q '[title="cv-target"] move position 600 100'
sleep 0.5

origin() { # print "x y" of the top left corner of the content of the window with this title, in layout coordinates
    set -- "$1" $(awk '$1 == "CONTENT" { print $2, $3; exit }' "$out")
    swaymsg -t get_tree | python3 -I -c '
import json, sys
def walk(n):
    if n.get("name") == sys.argv[1] and n.get("shell") == "xdg_shell":
        r = n["rect"]
        # Whatever the window shows above its content is at the top
        print(r["x"] + r["width"] - int(sys.argv[2]), r["y"] + r["height"] - int(sys.argv[3]))
        return True
    return any(walk(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
walk(json.load(sys.stdin))' "$@"
}
offset() { # offset <AT|GAP> <window> <item>: "x y" in the window, as the test printed it
    awk -v k="$1" -v w="$2" -v i="$3" '$1 == k && $2 == w && $3 == i { print $4, $5; exit }' "$out"
}
point() { # point <AT|GAP> <window> <item>: "x y" in layout coordinates
    local o d
    o=$(origin "$2") && d=$(offset "$1" "$2" "$3") && [ -n "$o" ] && [ -n "$d" ] || return 1
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
    dragged=$(grep -c '^DRAGGED' "$vpout")
    echo "drag $sx $sy $((tx - sx)) $((ty - sy))" >&3
    for _ in $(seq 100); do [ "$(grep -c '^DRAGGED' "$vpout")" -gt "$dragged" ] && break; sleep 0.1; done
    sleep 1.5
    lines=$(tail -n +$((start + 1)) "$out")
    check "$name: source" "$(echo "$lines" | grep '^SOURCE' | tr '\n' ' ')" "SOURCE willBegin items=1,4 SOURCE ended op=1 "
    check "$name: drop" "$(echo "$lines" | grep '^TARGET accept')" \
        "TARGET accept $want urls=/private/var/tmp/cv-item-1,/private/var/tmp/cv-item-4"
    check "$name: after" "$(echo "$lines" | grep '^TARGET after')" "TARGET after highlight=0 gap=0"
done

kill $pid 2>/dev/null
wait $pid 2>/dev/null
[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
exit $status
