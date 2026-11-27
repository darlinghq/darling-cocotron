// Copyright (C) 2026 Lubos Dolezel
//
// -[NSTextField isOpaque] is NO: bezeled or not, drawing its background or not, whatever the background
// colour (white, clear, translucent or nil). A field whose bezel leaves its corners transparent, or whose
// background is clear, would otherwise be treated as covering its whole frame, and the area it does not
// cover would show black or stale pixels. Observed through the public API on macOS 26.7.3. Whether a mouse
// down in a field can move the window (-mouseDownCanMoveWindow) does not follow from it: a label does (YES)
// and a bezeled, editable field does not (NO), which the test pins as well.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    failures += !ok;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSTextField *field = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 100, 22)];
        NSTextFieldCell *cell = [field cell];
        NSTextFieldBezelStyle bezels[] = { NSTextFieldSquareBezel, NSTextFieldRoundedBezel };
        for (int b = 0; b < 2; b++) {
            [field setBezeled: YES];
            [cell setBezelStyle: bezels[b]];
            for (int draws = 0; draws < 2; draws++) {
                [field setDrawsBackground: draws];
                expect(![field isOpaque], [NSString stringWithFormat: @"bezeled (style %d), drawsBackground %d: not opaque", (int) bezels[b], draws]);
            }
        }
        [field setBezeled: NO];
        NSColor *colors[] = { [NSColor whiteColor], [NSColor clearColor], [NSColor colorWithCalibratedWhite: 1 alpha: 0.5], nil };
        const char *names[] = { "white", "clear", "translucent", "nil" };
        for (int draws = 0; draws < 2; draws++)
            for (int c = 0; c < 4; c++) {
                [field setDrawsBackground: draws];
                [field setBackgroundColor: colors[c]];
                expect(![field isOpaque], [NSString stringWithFormat: @"borderless, drawsBackground %d, %s: not opaque", draws, names[c]]);
            }
        [field release];

        NSTextField *label = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 100, 22)];
        [label setBezeled: NO];
        [label setDrawsBackground: NO];
        [label setEditable: NO];
        [label setSelectable: NO];
        expect([label mouseDownCanMoveWindow], @"a label lets a mouse down move the window");
        NSTextField *editable = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 100, 22)];
        [editable setBezeled: YES];
        [editable setDrawsBackground: YES];
        [editable setEditable: YES];
        expect(![editable mouseDownCanMoveWindow], @"a bezeled editable field does not");
        [label release];
        [editable release];
    }
    printf(failures ? "FAILED\n" : "PASS\n");
    return failures != 0;
}
