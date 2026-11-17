#!/usr/bin/env bash
# Copyright (C) 2026 Lubos Dolezel
#
# The general pasteboard and the host's X11 clipboard show the same contents, whichever process copies:
#  1. a Darling process copies, another Darling process pastes (through the pasteboard service);
#  2. a Darling process copies, a host program reads the clipboard;
#  3. a host program copies, a Darling process pastes (also one that was already running);
#  4. pbcopy (no window system connection) copies while a Darling window system process runs: the host reads it;
#     pbpaste prints what the host copied.
# Needs an X server (DISPLAY) with a Darling container using it, xclip (or a stand-in that takes the same
# -selection clipboard -i/-o arguments) on the host, and the test binary built with guest-cc.sh:
#   appkit-pasteboard-host-clipboard.sh /path/to/binary
# Prints one PASS/FAIL line per check.
BIN=$1
DARLING=${DARLING:-darling}
status=0
HOSTBIN=/Volumes/SystemRoot$BIN

check() { if [ "$2" = 0 ]; then echo "PASS: $1"; else echo "FAIL: $1"; status=1; fi; }
TMP=$(mktemp -d /tmp/pbhost.XXXXXX)
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$TMP"' EXIT

# 1
$DARLING shell env DISPLAY="$DISPLAY" "$HOSTBIN" copy "darling-to-darling-$$" 8 </dev/null >"$TMP/c1" 2>&1 &
sleep 2
timeout -s KILL 30 $DARLING shell env DISPLAY="$DISPLAY" "$HOSTBIN" paste 5 "darling-to-darling-$$" </dev/null >"$TMP/p1" 2>&1
check "a Darling process pastes what another one copied" $?
wait

# 2
$DARLING shell env DISPLAY="$DISPLAY" "$HOSTBIN" copy "darling-to-host-$$" 10 </dev/null >"$TMP/c2" 2>&1 &
sleep 3
[ "$(xclip -selection clipboard -o 2>/dev/null)" = "darling-to-host-$$" ]
check "the host reads what a Darling process copied" $?
wait

# 3
printf 'host-to-darling-%s' "$$" | xclip -selection clipboard -i
sleep 1
timeout -s KILL 30 $DARLING shell env DISPLAY="$DISPLAY" "$HOSTBIN" paste 5 "host-to-darling-$$" </dev/null >"$TMP/p3" 2>&1
check "a Darling process pastes what the host copied" $?

# a process that is already running notices the next host copy
$DARLING shell env DISPLAY="$DISPLAY" "$HOSTBIN" paste 12 "host-later-$$" </dev/null >"$TMP/p3b" 2>&1 &
sleep 3
printf 'host-later-%s' "$$" | xclip -selection clipboard -i
wait $!
check "a running Darling process notices a host copy" $?

# 4
$DARLING shell env DISPLAY="$DISPLAY" "$HOSTBIN" hold 12 </dev/null >"$TMP/h" 2>&1 &
sleep 3
printf 'pbcopy-%s' "$$" | $DARLING shell /usr/bin/pbcopy >"$TMP/pb" 2>&1
sleep 2
[ "$(xclip -selection clipboard -o 2>/dev/null)" = "pbcopy-$$" ]
check "the host reads what pbcopy copied while a window system process runs" $?
printf 'host-for-pbpaste-%s' "$$" | xclip -selection clipboard -i
sleep 2
$DARLING shell /usr/bin/pbpaste >"$TMP/pp" 2>&1 </dev/null
[ "$(cat "$TMP/pp")" = "host-for-pbpaste-$$" ]
check "pbpaste prints what the host copied while a window system process runs" $?
wait
exit $status
