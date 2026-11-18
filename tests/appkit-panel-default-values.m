// Copyright (C) 2026 Lubos Dolezel
//
// The default values of the standard panels, as read from new ones on macOS 10.14.4 (black-box): an open
// panel is titled "Open" with a hidden title, prompt "Open", an empty message and style mask 0x8109; a save
// panel is titled "Save" with a visible title, prompt "Save", an empty message and style mask 0x1. The panel's
// title is the one of its window, so setting it changes -title, hidden or not. With a number of seconds as the
// argument the open panel is also shown for that long, so that a host script can read the title the window
// manager has for it (tests/appkit-panel-window-title.sh). Needs a display.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSOpenPanel *open = [NSOpenPanel openPanel];
        CHECK([[open title] isEqualToString: @"Open"]);
        CHECK([[open prompt] isEqualToString: @"Open"]);
        CHECK([[open message] isEqualToString: @""]);
        CHECK([open styleMask] == 0x8109);
        CHECK([open titleVisibility] == NSWindowTitleHidden);

        NSSavePanel *save = [NSSavePanel savePanel];
        CHECK([[save title] isEqualToString: @"Save"]);
        CHECK([[save prompt] isEqualToString: @"Save"]);
        CHECK([[save message] isEqualToString: @""]);
        CHECK([save styleMask] == 0x1);
        CHECK([save titleVisibility] == NSWindowTitleVisible);

        // the title is the window's, whatever its visibility
        [open setTitle: @"Choose"];
        CHECK([[open title] isEqualToString: @"Choose"]);
        CHECK([open titleVisibility] == NSWindowTitleHidden);
        [save setTitle: @"Export"];
        CHECK([[save title] isEqualToString: @"Export"]);

        if (argc > 1) {
            [open setTitle: @"Panel title test"];
            [open beginWithCompletionHandler: ^(NSModalResponse r) {}];
            [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: atof(argv[1])]];
            [open cancel: nil];
        }
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
