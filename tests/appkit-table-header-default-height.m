// Copyright (C) 2026 Lubos Dolezel
//
// The header of a table made in code is 25 points high for a program built with the 10.11 SDK or later (17 for
// older ones), as is a header view made with -init; a header view made with an explicit frame keeps its frame.
// Pins the QUIRK in NSTableHeaderView. Reference: macOS 10.14.4. Run twice, with the SDK version recorded as new and
// old, passing "old" for the second:
//   guest-cc.sh -t 10.13 -o t-new t.m -framework AppKit -Wl,-sdk_version,10.14
//   guest-cc.sh -t 10.13 -o t-old t.m -framework AppKit -Wl,-sdk_version,10.10
#import <AppKit/AppKit.h>
#include <mach-o/dyld_priv.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        BOOL old = argc > 1 && strcmp(argv[1], "old") == 0;
        uint32_t sdk = dyld_get_program_sdk_version();
        if (old != (sdk < 0x000a0b00)) {
            printf("SKIP: the program's SDK version is 0x%08x, not an %s program\n", sdk, old ? "old" : "new");
            return 0;
        }
        CGFloat standard = old ? 17 : 25;
        NSTableView *table = [[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier: @"a"];
        [column setTitle: @"Name"];
        [table addTableColumn: column];
        CHECK([[table headerView] frame].size.height == standard);

        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)];
        [scroll setDocumentView: table];
        [scroll setHasVerticalScroller: YES];
        [scroll tile];
        CHECK([[table headerView] frame].size.height == standard);

        NSTableHeaderView *header = [[NSTableHeaderView alloc] init];
        CHECK(header.frame.size.height == standard);
        NSTableHeaderView *sized = [[NSTableHeaderView alloc] initWithFrame: NSMakeRect(0, 0, 90, 17)];
        CHECK(sized.frame.size.height == 17 && sized.frame.size.width == 90);

        [table setHeaderView: nil];
        CHECK([table headerView] == nil);
        [table setHeaderView: sized];
        CHECK([[table headerView] frame].size.height == 17);
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
