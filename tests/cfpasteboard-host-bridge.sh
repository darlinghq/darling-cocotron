#!/usr/bin/env bash
# Copyright (C) 2026 Lubos Dolezel
#
# The general pasteboard shows the host's clipboard in a process that has no AppKit (CoreGraphics connects them), and
# an AppKit process (NSPasteboard) and a process without AppKit see the same data, both through the host clipboard:
#  1. a process without AppKit copies, the host reads text and HTML;
#  2. the host copies text, then HTML, and a process without AppKit pastes it;
#  3. a process without AppKit copies, an AppKit process pastes it (NSPasteboard);
#  4. an AppKit process copies (NSPasteboard), a process without AppKit pastes it.
# BACKEND=x11 (default; DISPLAY names the X server, xclip is the host client) or BACKEND=wayland (WAYLAND_DISPLAY,
# XDG_RUNTIME_DIR name a headless sway, wl-copy and wl-paste are the host clients, wtype types a key into the
# focused window so that the compositor gives the client the keyboard focus and an input serial).
#   cfpasteboard-host-bridge.sh /path/to/cfpasteboard-host-bridge /path/to/appkit-pasteboard-host-clipboard
# Both binaries are guest programs built for the same architecture. Prints one PASS/FAIL line per check.
CGBIN=/Volumes/SystemRoot$1
APPBIN=/Volumes/SystemRoot$2
DARLING=${DARLING:-darling}
BACKEND=${BACKEND:-x11}
status=0

check() { if [ "$2" = 0 ]; then echo "PASS: $BACKEND: $1"; else echo "FAIL: $BACKEND: $1"; status=1; fi; }
TMP=$(mktemp -d /tmp/cfpbhost.XXXXXX)
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$TMP"' EXIT

if [ "$BACKEND" = wayland ]; then
	GENV=(env DARLING_APPKIT_BACKEND=wayland WAYLAND_DISPLAY="$WAYLAND_DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" HOSTCLIP_WINDOW=1)
	host_set() { printf '%s' "$1" | wl-copy ${2:+-t "$2"}; }
	host_get() { timeout 5 wl-paste -n ${1:+-t "$1"} 2>/dev/null; }
	# The seat has no keyboard until wtype makes a virtual one, which the compositor gives the focus window and which
	# is removed when wtype exits: a key gives the client the keyboard focus (and with it the selection) and an input
	# serial to publish with.
	# KWin has no virtual keyboard protocol: with KWIN_KEYS naming the built tests/kwin-keys the key is injected through
	# its fake input protocol instead (a private kwin_wayland --virtual with --no-lockscreen only).
	kick() { if [ -n "${KWIN_KEYS:-}" ]; then "$KWIN_KEYS" 100 44:1 44:0; else wtype -s 300 z; fi; }
else
	GENV=(env DISPLAY="$DISPLAY")
	host_set() { printf '%s' "$1" | xclip -selection clipboard ${2:+-t "$2"} -i; }
	host_get() { timeout 5 xclip -selection clipboard ${1:+-t "$1"} -o 2>/dev/null; }
	kick() { :; }
fi

# Waits until a background program has printed a line starting with the word (the first guest program of a run has
# to bring the container up, which takes a few seconds).
ready() { for _ in $(seq 400); do grep -q "^$2" "$1" 2>/dev/null && return 0; sleep 0.1; done; return 1; }

# 1
$DARLING shell "${GENV[@]}" "$CGBIN" copy "cg-to-host-$$" 14 </dev/null >"$TMP/c1" 2>&1 &
ready "$TMP/c1" copied; sleep 1; kick; sleep 2
[ "$(host_get)" = "cg-to-host-$$" ]
check "the host reads the text a process without AppKit copied" $?
host_get text/html | grep -q "<b>cg-to-host-$$</b>"
check "the host reads the HTML a process without AppKit copied" $?
wait

# 2
host_set "host-to-cg-$$"
sleep 1
$DARLING shell "${GENV[@]}" "$CGBIN" paste 14 "host-to-cg-$$" </dev/null >"$TMP/p2" 2>&1 &
ready "$TMP/p2" ready; sleep 1; kick
wait $!
check "a process without AppKit pastes the text the host copied" $?
host_set "<i>host-html-$$</i>" text/html
sleep 1
$DARLING shell "${GENV[@]}" "$CGBIN" pastehtml 14 "host-html-$$" </dev/null >"$TMP/p2b" 2>&1 &
ready "$TMP/p2b" ready; sleep 1; kick
wait $!
check "a process without AppKit pastes the HTML the host copied" $?

# 3
$DARLING shell "${GENV[@]}" "$CGBIN" copy "cg-to-appkit-$$" 24 </dev/null >"$TMP/c3" 2>&1 &
cpid=$!
ready "$TMP/c3" copied; sleep 1; kick; sleep 1
$DARLING shell "${GENV[@]}" "$APPBIN" paste 10 "cg-to-appkit-$$" </dev/null >"$TMP/p3" 2>&1 &
sleep 6; kick
wait $!
check "NSPasteboard pastes what a process without AppKit copied" $?
kill $cpid 2>/dev/null; wait $cpid 2>/dev/null

# 4
$DARLING shell "${GENV[@]}" "$APPBIN" copy "appkit-to-cg-$$" 20 </dev/null >"$TMP/c4" 2>&1 &
sleep 6; kick; sleep 1
$DARLING shell "${GENV[@]}" "$CGBIN" paste 10 "appkit-to-cg-$$" </dev/null >"$TMP/p4" 2>&1 &
ready "$TMP/p4" ready; sleep 1; kick
wait $!
check "a process without AppKit pastes what NSPasteboard copied" $?
wait
exit $status
