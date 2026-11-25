#!/bin/bash
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# CoreGraphics sits below AppKit, so it must not link, load or look up AppKit. Checks the installed
# CoreGraphics framework and its backends (every architecture slice): no load command for AppKit,
# no reference to an AppKit class or symbol, and no AppKit path or class name that a dlopen() or a
# NSClassFromString() could use.
#
# Usage: coregraphics-no-appkit-dependency.sh <CoreGraphics.framework directory of an installed tree> [otool] [nm]
# For example /opt/darling/libexec/darling/System/Library/Frameworks/CoreGraphics.framework
set -u
fw=${1:?usage: $0 <CoreGraphics.framework> [otool] [nm]}
otool=${2:-otool}
nm=${3:-nm}
status=0
files=$(find -L "$fw" -type f \( -name CoreGraphics -o -path '*/Backends/*.backend/Contents/MacOS/*' \) -exec readlink -f {} + | sort -u)
[ -n "$files" ] || { echo "no binaries under $fw" >&2; exit 2; }
for f in $files; do
    if "$otool" -L "$f" 2>/dev/null | grep -q AppKit; then
        echo "FAIL: $f has a load command for AppKit"; status=1
    fi
    if "$nm" -m "$f" 2>/dev/null | grep -E '(undefined|external).*_(OBJC_CLASS_\$_|OBJC_METACLASS_\$_)?(NS(Display|Screen|Application|Window|View|Event|Cursor)|NSApp)\b' >/dev/null; then
        echo "FAIL: $f refers to an AppKit symbol"; status=1
    fi
    if strings -a "$f" | grep -E 'AppKit\.framework|AppKit/Versions|@"NS(Display|Screen)"|^NS(Display|Screen)$' >/dev/null; then
        echo "FAIL: $f names AppKit or one of its classes:"
        strings -a "$f" | grep -E 'AppKit\.framework|AppKit/Versions|^NS(Display|Screen)$' | head -3
        status=1
    fi
done
[ $status = 0 ] && echo "PASS: no AppKit dependency in $(echo "$files" | wc -l) CoreGraphics binaries"
exit $status
