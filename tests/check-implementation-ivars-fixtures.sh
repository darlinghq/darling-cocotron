#!/usr/bin/env bash
# Checks that check-implementation-ivars.sh reports what it should, from any
# directory, and tells a scan that failed from a file that has ivars.
set -euo pipefail

checker="$(cd "$(dirname "$0")" && pwd)/check-implementation-ivars.sh"
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
failures=0

expect() { # name, expected exit status, command...
	local name=$1 want=$2 got=0
	shift 2
	"$@" >/dev/null 2>&1 || got=$?
	if [ "$got" -ne "$want" ]; then
		echo "FAIL $name: exit $got, expected $want"
		failures=$((failures + 1))
	fi
}

printf '@implementation A\n- (void)f {}\n@end\n' > "$dir/ok.m"
printf '@implementation B {\n    int x;\n}\n@end\n' > "$dir/brace-same-line.m"
printf '@implementation C\n#if 1\n{\n    int x;\n}\n#endif\n@end\n' > "$dir/directive-between.m"
printf '@implementation D
#if __OBJC2__
{
    int x;
}
#endif
@end
' > "$dir/objc2-only.m"

expect "file without ivars" 0 "$checker" "$dir/ok.m"
expect "ivars, brace on the @implementation line" 1 "$checker" "$dir/brace-same-line.m"
expect "ivars, #if 1 before the brace" 1 "$checker" "$dir/directive-between.m"
expect "ivars guarded by #if __OBJC2__" 0 "$checker" "$dir/objc2-only.m"
expect "relative path from another directory" 0 bash -c 'cd "$1" && "$2" ok.m' _ "$dir" "$checker"
expect "relative path with ivars" 1 bash -c 'cd "$1" && "$2" brace-same-line.m' _ "$dir" "$checker"
expect "missing file is a scan failure, not ivars" 2 "$checker" "$dir/missing.m"
expect "missing awk is a scan failure, not ivars" 2 env AWK=/nonexistent-awk "$checker" "$dir/ok.m"

[ "$failures" -eq 0 ] && echo "PASS check-implementation-ivars fixtures"
exit "$failures"
