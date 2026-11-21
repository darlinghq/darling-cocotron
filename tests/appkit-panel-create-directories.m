// Copyright (C) 2026 Lubos Dolezel
//
// canCreateDirectories of the standard panels, as read on macOS 10.14.4 and 26.7.3 (black-box): a new
// save panel allows making folders, a new open panel does not, and the setter changes the value. A
// panel created after one was changed has the default again. Needs a display.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSSavePanel *save = [NSSavePanel savePanel];
        CHECK([save canCreateDirectories]);
        [save setCanCreateDirectories: NO];
        CHECK(![save canCreateDirectories]);
        [save setCanCreateDirectories: YES];
        CHECK([save canCreateDirectories]);
        [save setCanCreateDirectories: NO];

        NSOpenPanel *open = [NSOpenPanel openPanel];
        CHECK(![open canCreateDirectories]);
        [open setCanCreateDirectories: YES];
        CHECK([open canCreateDirectories]);

        CHECK([[NSSavePanel savePanel] canCreateDirectories]);
        CHECK(![[NSOpenPanel openPanel] canCreateDirectories]);
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
