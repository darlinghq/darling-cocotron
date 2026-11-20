// Copyright (C) 2026 Lubos Dolezel
//
// The cell size and the alignment insets of check boxes and radio buttons are those of macOS 10.14: the cell is
// 18 points high at every control size, as wide as the intrinsic width plus the horizontal insets, and the
// intrinsic size is the cell size without the insets. Expected values were read through the public API on macOS
// 10.14.4 (black-box observation, see vd-upstream/mac-probes/aqua-leftovers-metrics.m); 26.7.3 differs and is not
// followed. test_quirk_toggle_metrics pins the QUIRK-tagged behaviour of the same name in NSButtonCell. The
// widths state the formula, so they hold with the fonts of any platform. Passes on macOS 10.14.4.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL %s line %d: %s\n", __func__, __LINE__, #c); failures++; } } while (0)

static NSButton *toggle(BOOL radio, NSString *title, NSControlSize size) {
    NSButton *b = [[[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 100, 30)] autorelease];
    [b setButtonType: radio ? NSButtonTypeRadio : NSButtonTypeSwitch];
    [b setTitle: title];
    [[b cell] setControlSize: size];
    [b setFont: [NSFont systemFontOfSize: [NSFont systemFontSizeForControlSize: size]]];
    return b;
}

static void test_quirk_toggle_metrics(void) {
    NSControlSize sizes[3] = {NSControlSizeRegular, NSControlSizeSmall, NSControlSizeMini};
    // insets {top, left, bottom, right}
    const double insets[2][3][4] = {{{2, 2, 2, 2}, {3, 3, 3, 2}, {5, 4, 3, 2}}, {{1, 1, 1, 2}, {2, 2, 2, 1}, {4, 4, 4, 1}}};
    const double pad[2][3] = {{18, 17, 16}, {19, 19, 17}};
    NSString *titles[3] = {@"", @"Wi", @"Check box title"};
    for (int radio = 0; radio < 2; radio++)
        for (int z = 0; z < 3; z++)
            for (int t = 0; t < 3; t++) {
                NSButton *b = toggle(radio, titles[t], sizes[z]);
                double text = [titles[t] sizeWithAttributes: @{NSFontAttributeName: [b font]}].width;
                NSEdgeInsets ai = [b alignmentRectInsets];
                CHECK(ai.top == insets[radio][z][0] && ai.left == insets[radio][z][1] &&
                      ai.bottom == insets[radio][z][2] && ai.right == insets[radio][z][3]);
                NSSize cell = [[b cell] cellSize], intrinsic = [b intrinsicContentSize];
                double width = ceil(text + pad[radio][z]);
                CHECK(cell.height == 18);
                CHECK(intrinsic.width == width && cell.width == width + ai.left + ai.right);
                CHECK(intrinsic.height == 18 - ai.top - ai.bottom);
                CHECK(cell.width == width + ai.left + ai.right);
                // a frame's alignment rectangle is the frame inset by them
                NSRect af = [b alignmentRectForFrame: NSMakeRect(10, 10, 100, 30)];
                CHECK(af.origin.x == 10 + ai.left && af.size.width == 100 - ai.left - ai.right && af.size.height == 30 - ai.top - ai.bottom);
                [b sizeToFit];
                CHECK([b frame].size.height == 18 && [b frame].size.width == cell.width);
            }
    // an empty title is 22 points wide at every size, as macOS 10.14 shows
    for (int radio = 0; radio < 2; radio++)
        for (int z = 0; z < 3; z++)
            CHECK([[toggle(radio, @"", sizes[z]) cell] cellSize].width == 22);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_quirk_toggle_metrics();
    }
    if (failures) { printf("FAIL (%d)\n", failures); return 1; }
    printf("PASS\n");
    return 0;
}
