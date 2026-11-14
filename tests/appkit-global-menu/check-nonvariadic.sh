#!/bin/sh
# Copyright (C) 2026 Lubos Dolezel
#
# Fails if the X11 backend imports a variadic libdbus function. libdbus is a
# host library called without translating the calling convention, so
# variadic calls (dbus_message_append_args, dbus_message_get_args and the
# like) read their arguments from the wrong places on arm64.
#
# usage: check-nonvariadic.sh <X11 backend Mach-O file>
set -eu
bin=$1
rc=0
for sym in dbus_message_append_args dbus_message_get_args dbus_message_get_args_valist \
           dbus_message_append_args_valist dbus_set_error dbus_message_new_error_printf; do
	if llvm-nm "$bin" 2>/dev/null | grep -q "_${sym}\$"; then
		echo "FAIL: backend imports variadic $sym"
		rc=1
	fi
done
[ $rc -eq 0 ] && echo "PASS"
exit $rc
