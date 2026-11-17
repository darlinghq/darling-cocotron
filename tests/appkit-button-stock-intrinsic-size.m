// Copyright (C) 2026 Lubos Dolezel
//
// The intrinsic size of rounded push buttons, checkboxes and radio buttons: the width is the title width
// plus a fixed amount per control size, rounded up; push buttons have a fixed height per control size.
// This is a QUIRK (test_quirk_stock_button_widths) with Mojave metrics, observed on macOS 10.14.4; see
// vd-upstream mac-probes/ua6-button-widths.m for the table of values. The test states the formula, so it
// holds with the fonts of any platform. It passes on 10.14.4 and fails on 26.7.3, whose metrics differ and
// are not followed.
//
// Build: clang -fobjc-arc -framework AppKit appkit-button-stock-intrinsic-size.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSButton *makeButton(NSString *title, int kind, NSControlSize size) {
    NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    [b setTitle:title];
    if (kind == 0) [b setBezelStyle:NSBezelStyleRounded];
    else [b setButtonType:kind == 1 ? NSButtonTypeSwitch : NSButtonTypeRadio];
    [[b cell] setControlSize:size];
    [b setFont:[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:size]]];
    return b;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSControlSize sizes[3] = {NSControlSizeRegular, NSControlSizeSmall, NSControlSizeMini};
        const double pad[3][3] = {{28, 16, 22}, {18, 17, 16}, {19, 19, 17}};
        const double pushHeight[3] = {21, 18, 15};
        NSArray *titles = @[@"", @"A", @"Stop", @"Apply to All", @"Show the advanced options now"];
        for (int kind = 0; kind < 3; kind++) {
            for (int k = 0; k < 3; k++) {
                for (NSString *title in titles) {
                    NSButton *b = makeButton(title, kind, sizes[k]);
                    NSFont *font = [b font];
                    double text = [title sizeWithAttributes:@{NSFontAttributeName: font}].width;
                    NSSize s = [b intrinsicContentSize];
                    if (s.width != ceil(text + pad[kind][k]))
                        fprintf(stderr, "kind %d size %d '%s': width %g, expected %g\n", kind, k, [title UTF8String], s.width, ceil(text + pad[kind][k]));
                    CHECK(s.width == ceil(text + pad[kind][k]));
                    if (kind == 0) CHECK(s.height == pushHeight[k]);
                }
            }
        }
        // A pull-down or pop-up button is not a push button (it has its own sizing).
        NSPopUpButton *popUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 100, 20) pullsDown:NO];
        [popUp addItemWithTitle:@"A"];
        CHECK([popUp intrinsicContentSize].width != ceil([@"A" sizeWithAttributes:@{NSFontAttributeName: [popUp font]}].width + 28));
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
