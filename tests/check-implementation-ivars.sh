#!/usr/bin/env bash
# Fail if an @implementation declares instance variables in a "{ ... }" block.
# Darling builds its frameworks fat, and the i386 slice uses the fragile
# Objective-C ABI, which rejects ivars in @implementation ("inconsistent number
# of instance variables"). Declare them in the @interface instead.
# Limit: preprocessor directives are not evaluated, so an #if 0 block can mislead it.
# A "{" after "#if __OBJC2__" is accepted: those ivars are not in the i386 slice.
# Usage: check-implementation-ivars.sh [file...]   (default: every tracked .m/.mm)
set -euo pipefail
export LC_ALL=C  # some files are not valid UTF-8; BSD awk aborts on those otherwise

start=$PWD
cd "$(dirname "$0")/.."
if [ "$#" -gt 0 ]; then
	files=()
	for f in "$@"; do
		case $f in /*) files+=("$f") ;; *) files+=("$start/$f") ;; esac
	done
else
	files=()
	while IFS= read -r f; do files+=("$f"); done < <(git ls-files '*.m' '*.mm')
fi
[ "${#files[@]}" -gt 0 ] || exit 0

awk_command=${AWK:-awk}
if ! command -v "$awk_command" >/dev/null 2>&1; then
	echo "error: $awk_command not found, the files were not checked" >&2
	exit 2
fi

status=0
$awk_command '
FNR == 1 { incomment = 0; pending = 0 }
{
	line = $0
	sub(/\r$/, "", line)
	out = ""
	n = length(line); i = 1
	while (i <= n) {
		ch = substr(line, i, 1); two = substr(line, i, 2)
		if (incomment) { if (two == "*/") { incomment = 0; i += 2 } else i++; continue }
		if (two == "/*") { incomment = 1; i += 2; continue }
		if (two == "//") break
		if (ch == "\"" || ch == "\047") {
			out = out ch ch; i++
			while (i <= n) {
				c2 = substr(line, i, 1)
				if (c2 == "\\") i += 2
				else if (c2 == ch) { i++; break }
				else i++
			}
			continue
		}
		out = out ch; i++
	}
	if (out ~ /^[ \t]*$/) next
	if (pending && out ~ /^[ \t]*#/) {  # a directive between the name and the brace
		if (out ~ /__OBJC2__/) pending = 0  # ivars for the modern ABI only are fine
		next
	}
	if (pending) {
		if (out ~ /^[ \t]*\{/) { print FILENAME ":" pendingline; bad = 1 }
		pending = 0
	}
	if (out ~ /^[ \t]*@implementation[ \t]+[A-Za-z_][A-Za-z0-9_]*([ \t]*:[ \t]*[A-Za-z_][A-Za-z0-9_]*)?[ \t]*(\{|$)/) {
		if (out ~ /\{/) { print FILENAME ":" FNR; bad = 1 }
		else { pending = 1; pendingline = FNR }
	}
}
END { exit bad }
' "${files[@]}" || status=$?
if [ "$status" -eq 1 ]; then
	echo "error: ivars declared in @implementation (breaks the i386 fragile-ABI slice); move them to the @interface" >&2
	exit 1
elif [ "$status" -ne 0 ]; then
	echo "error: the awk scan failed (status $status), the files were not checked" >&2
	exit 2
fi
