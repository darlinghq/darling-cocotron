#!/usr/bin/env bash
# Fail if an @implementation declares instance variables in a "{ ... }" block.
# Darling builds its frameworks fat, and the i386 slice uses the fragile
# Objective-C ABI, which rejects ivars in @implementation ("inconsistent number
# of instance variables"). Declare them in the @interface instead.
# Limit: preprocessor directives are not parsed, so an #if 0 block can mislead it.
# Usage: check-implementation-ivars.sh [file...]   (default: every tracked .m/.mm)
set -euo pipefail
export LC_ALL=C  # some files are not valid UTF-8; BSD awk aborts on those otherwise

cd "$(dirname "$0")/.."
if [ "$#" -gt 0 ]; then
	files=("$@")
else
	files=()
	while IFS= read -r f; do files+=("$f"); done < <(git ls-files '*.m' '*.mm')
fi
[ "${#files[@]}" -gt 0 ] || exit 0

${AWK:-awk} '
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
' "${files[@]}" || { echo "error: ivars declared in @implementation (breaks the i386 fragile-ABI slice); move them to the @interface" >&2; exit 1; }
