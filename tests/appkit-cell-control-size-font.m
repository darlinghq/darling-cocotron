// Copyright (C) 2026 Lubos Dolezel
//
// Changing the control size of a cell, or of a control through its cell or
// through -[NSControl setControlSize:], leaves the font alone: the font of
// every cell class keeps its size at every control size, and a font that was
// set stays. Black-box observation on macOS 10.14.4 and 26.7.3.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void checkCell(const char *name, NSCell *cell) {
    NSFont *initial = [[[cell font] retain] autorelease];
    NSControlSize sizes[] = { NSControlSizeSmall, NSControlSizeMini, NSControlSizeRegular };

    for (int i = 0; i < 3; i++) {
        [cell setControlSize: sizes[i]];
        if ([cell controlSize] != sizes[i]) {
            fprintf(stderr, "FAIL %s: controlSize %ld after setting %ld\n", name, (long) [cell controlSize],
                    (long) sizes[i]);
            failures++;
        }
        if ([[cell font] pointSize] != [initial pointSize]) {
            fprintf(stderr, "FAIL %s: font %g at control size %ld, was %g\n", name, [[cell font] pointSize],
                    (long) sizes[i], [initial pointSize]);
            failures++;
        }
    }
    [cell setFont: [NSFont systemFontOfSize: 20]];
    [cell setControlSize: NSControlSizeSmall];
    if ([[cell font] pointSize] != 20) {
        fprintf(stderr, "FAIL %s: a 20 point font became %g at the small control size\n", name,
                [[cell font] pointSize]);
        failures++;
    }
}

static void checkControl(const char *name, NSControl *control) {
    CGFloat initial = [[control font] pointSize];

    [control setControlSize: NSControlSizeMini];
    if ([[control font] pointSize] != initial) {
        fprintf(stderr, "FAIL %s: font %g after setControlSize: mini, was %g\n", name, [[control font] pointSize],
                initial);
        failures++;
    }
    [[control cell] setControlSize: NSControlSizeSmall];
    if ([[control font] pointSize] != initial) {
        fprintf(stderr, "FAIL %s: font %g after the cell's setControlSize: small, was %g\n", name,
                [[control font] pointSize], initial);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        checkCell("NSCell", [[[NSCell alloc] initTextCell: @"x"] autorelease]);
        checkCell("NSActionCell", [[[NSActionCell alloc] initTextCell: @"x"] autorelease]);
        checkCell("NSTextFieldCell", [[[NSTextFieldCell alloc] initTextCell: @"x"] autorelease]);
        checkCell("NSSecureTextFieldCell", [[[NSSecureTextFieldCell alloc] initTextCell: @"x"] autorelease]);
        checkCell("NSSearchFieldCell", [[[NSSearchFieldCell alloc] initTextCell: @"x"] autorelease]);
        checkCell("NSComboBoxCell", [[[NSComboBoxCell alloc] initTextCell: @"x"] autorelease]);
        checkCell("NSTokenFieldCell", [[[NSTokenFieldCell alloc] initTextCell: @"x"] autorelease]);
        checkCell("NSTableHeaderCell", [[[NSTableHeaderCell alloc] initTextCell: @"x"] autorelease]);
        checkCell("NSButtonCell", [[[NSButtonCell alloc] initTextCell: @"x"] autorelease]);
        checkCell("NSPopUpButtonCell", [[[NSPopUpButtonCell alloc] initTextCell: @"x" pullsDown: NO] autorelease]);
        checkCell("NSMenuItemCell", [[[NSMenuItemCell alloc] initTextCell: @"x"] autorelease]);
        checkCell("NSBrowserCell", [[[NSBrowserCell alloc] initTextCell: @"x"] autorelease]);
        checkCell("NSPathCell", [[[NSPathCell alloc] initTextCell: @"x"] autorelease]);
        checkCell("NSDatePickerCell", [[[NSDatePickerCell alloc] initTextCell: @"x"] autorelease]);

        NSButton *button = [[[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 80, 30)] autorelease];
        [button setBezelStyle: NSBezelStyleRounded];
        checkControl("NSButton", button);
        checkControl("NSTextField", [[[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 80, 22)] autorelease]);
        checkControl("NSPopUpButton", [[[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 80, 22)
                                                                  pullsDown: NO] autorelease]);
    }
    if (failures) {
        printf("FAIL (%d)\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
