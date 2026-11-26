#!/bin/bash
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# A process has one connection to the window system: CoreGraphics opens it and AppKit's backend uses
# the same one. Starts the guest test coregraphics-native-connection in its "hold" mode (the process
# stays up with the window system connected) and counts, from the host, the sockets of that process that
# are connected to the X server or to the Wayland compositor (the server's end of each, in ss(8)).
#
# Usage: coregraphics-native-connection-count.sh <x11|wayland> <server socket name> <expected count> <guest test command>
#   server socket name: the basename of the server's socket (X0, X91, wayland-1)
# The command is run with "hold" or "hold-appkit" appended (the test then prints READY and waits).
# Needs ss(8). Exit status 0 when the process held the expected number of connections in both modes.
set -u
backend=$1 server=$2 expected=$3
shift 3
work=$(mktemp -d)
pid=
cleanup() {
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT INT TERM
command -v ss >/dev/null || { echo "need ss" >&2; exit 2; }

# The number of sockets of the process <pid> whose peer is a socket bound to the server's name.
count_connections() {
    local target=$1 inodes
    inodes=$(for fd in /proc/"$target"/fd/*; do
        link=$(readlink "$fd" 2>/dev/null) || continue
        case $link in socket:\[*) link=${link#socket:[}; echo "${link%]}";; esac
    done)
    [ -n "$inodes" ] || { echo 0; return; }
    # The client's socket has no address; the server's end carries the server's socket name. Columns:
    # netid state recv-q send-q local-address local-inode peer-address peer-inode. A connection is the
    # server-side socket whose peer is one of the process' sockets.
    ss -xnH 2>/dev/null | awk -v server="$server" -v inodes="$inodes" '
        BEGIN { n = split(inodes, a, "\n"); for (i = 1; i <= n; i++) mine[a[i]] = 1 }
        { local = $5; sub(/^@/, "", local); m = split(local, parts, "/");
          if (($8 in mine) && parts[m] == server) count++ }
        END { print count + 0 }'
}

fail=0
for mode in hold hold-appkit; do
    "$@" "$mode" > "$work/log" 2>&1 &
    runner=$!
    for _ in $(seq 150); do grep -q '^READY' "$work/log" && break; sleep 0.2; done
    grep -q '^READY' "$work/log" || { echo "FAIL ($mode): the test did not get ready"; cat "$work/log"; kill "$runner" 2>/dev/null; fail=1; continue; }
    # The guest process is the host process whose command line names the test and the mode.
    pid=$(pgrep -f "coregraphics-native-connection[a-z-]* $mode\$" | tail -n 1)
    if [ -z "$pid" ]; then
        echo "FAIL ($mode): cannot find the process"
        fail=1
    else
        n=$(count_connections "$pid")
        if [ "$n" = "$expected" ]; then
            echo "ok ($backend, $mode): $n connection(s) to $server"
        else
            echo "FAIL ($backend, $mode): $n connection(s) to $server, expected $expected"
            fail=1
        fi
    fi
    kill "$pid" 2>/dev/null
    wait "$runner" 2>/dev/null
    pid=
done
[ $fail = 0 ] && echo PASS || { echo FAIL; exit 1; }
