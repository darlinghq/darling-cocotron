// Copyright (C) 2026 Lubos Dolezel
//
// CGDisplayGammaTableCapacity returns the number of entries of the display's gamma table (macOS 26.7.3
// returns 256 for the main display, as does macOS 10.14.4), and CGDisplayIsInMirrorSet is false for a
// display that is not mirrored, which is what CGDisplayMirrorsDisplay reports for it (kCGNullDirectDisplay).
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

static int failures;

static void expect(int ok, const char *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", what);
    failures += !ok;
}

int main(void)
{
    CGDirectDisplayID main = CGMainDisplayID();
    expect(CGDisplayGammaTableCapacity(main) == 256, "the main display's gamma table has 256 entries");
    expect(CGDisplayGammaTableCapacity(main) > 0, "the capacity is not 0");
    expect(CGDisplayMirrorsDisplay(main) == kCGNullDirectDisplay, "the main display mirrors nothing");
    expect(!CGDisplayIsInMirrorSet(main), "the main display is not in a mirror set");
    printf(failures ? "FAILED\n" : "PASS\n");
    return failures != 0;
}
