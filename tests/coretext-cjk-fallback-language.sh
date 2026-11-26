#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/coretext-cjk-fallback-language.c in Darling with a fontconfig configuration that
# gives Chinese, Japanese and Korean faces of their own (coretext-cjk-fallback-language.conf,
# which needs the Noto Sans CJK fonts on the host). Usage:
#   coretext-cjk-fallback-language.sh <command that runs coretext-cjk-fallback-language>
# fontconfig runs on the host side of the process, so FONTCONFIG_FILE is a host path.
set -u
export FONTCONFIG_FILE="$(cd "$(dirname "$0")" && pwd)/coretext-cjk-fallback-language.conf"
out=$("$@" 2>&1)
status=$?
echo "$out"
if echo "$out" | grep -q '^SKIP'; then
	echo "FAIL: the configuration gave no language-specific faces (are the Noto Sans CJK fonts installed?)"
	exit 1
fi
exit $status
