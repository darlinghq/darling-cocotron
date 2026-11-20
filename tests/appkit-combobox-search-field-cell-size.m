// Copyright (C) 2026 Lubos Dolezel
//
// The size of the content of an NSComboBox and an NSSearchField (cellSize, sizeToFit), per control
// size and text. The expected values were observed on macOS 10.14.4 (black-box; 26.7.3 differs).
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;

static void expectSize(const char *what, NSSize size, NSSize expected) {
    if (fabs(size.width - expected.width) > 0.01 || fabs(size.height - expected.height) > 0.01) {
        fprintf(stderr, "FAIL %s: {%g,%g}, expected {%g,%g}\n", what, size.width, size.height, expected.width,
                expected.height);
        failures++;
    }
}

static const struct {
    NSControlSize size;
    CGFloat font, comboInset, comboHeight, searchInset, searchHeight;
} sizes[] = {
    { NSControlSizeRegular, 13, 28, 26, 42, 22 },
    { NSControlSizeSmall, 11, 26, 22, 41, 19 },
    { NSControlSizeMini, 9, 23, 18, 40, 17 },
};
static NSString *const strings[] = { @"", @"Hello", @"Hello World, long text" };

static void configure(NSControl *control, NSString *string, NSControlSize size, CGFloat font) {
    [control setStringValue: string];
    [[control cell] setControlSize: size];
    [control setFont: [NSFont systemFontOfSize: font]];
}

// QUIRK: a combo box's cellSize is the text plus a fixed width and a fixed height per control
// size. See -[NSComboBoxCell cellSize].
static void test_quirk_combo_box_cell_size(void) {
    for (unsigned i = 0; i < 3; i++)
        for (unsigned j = 0; j < 3; j++) {
            NSComboBox *combo = [[[NSComboBox alloc] initWithFrame: NSMakeRect(0, 0, 100, 40)] autorelease];
            char what[96];

            configure(combo, strings[j], sizes[i].size, sizes[i].font);
            NSSize text = [[[combo cell] attributedStringValue] size];
            NSSize expected = NSMakeSize(ceil(text.width + sizes[i].comboInset),
                                         i == 2 && j == 0 ? 19 : sizes[i].comboHeight);

            snprintf(what, sizeof what, "combo box %g pt \"%s\" cellSize", sizes[i].font, [strings[j] UTF8String]);
            expectSize(what, [[combo cell] cellSize], expected);
            // the cell's size does not follow the control's frame
            [combo setFrame: NSMakeRect(0, 0, 300, 80)];
            snprintf(what, sizeof what, "combo box %g pt \"%s\" cellSize in another frame", sizes[i].font,
                     [strings[j] UTF8String]);
            expectSize(what, [[combo cell] cellSize], expected);
            [combo sizeToFit];
            snprintf(what, sizeof what, "combo box %g pt \"%s\" sizeToFit", sizes[i].font, [strings[j] UTF8String]);
            expectSize(what, [combo frame].size, expected);
            snprintf(what, sizeof what, "combo box %g pt \"%s\" cellSizeForBounds", sizes[i].font,
                     [strings[j] UTF8String]);
            expectSize(what, [[combo cell] cellSizeForBounds: NSMakeRect(0, 0, 400, 100)], expected);
        }
    // a cell on its own, outside a control
    NSComboBoxCell *cell = [[[NSComboBoxCell alloc] initTextCell: @"Hello"] autorelease];
    [cell setFont: [NSFont systemFontOfSize: 13]];
    NSSize text = [[cell attributedStringValue] size];
    expectSize("combo box cell without a control", [cell cellSize], NSMakeSize(ceil(text.width + 28), 26));
}

// QUIRK: a search field's cellSize is the text plus a fixed width and the height of a rounded bezel.
// See -[NSSearchFieldCell cellSize].
static void test_quirk_search_field_cell_size(void) {
    for (unsigned i = 0; i < 3; i++)
        for (unsigned j = 0; j < 3; j++) {
            NSSearchField *field = [[[NSSearchField alloc] initWithFrame: NSMakeRect(0, 0, 100, 40)] autorelease];
            char what[96];

            configure(field, strings[j], sizes[i].size, sizes[i].font);
            NSSize text = [[[field cell] attributedStringValue] size];
            NSSize expected = NSMakeSize(ceil(text.width + sizes[i].searchInset), sizes[i].searchHeight);

            snprintf(what, sizeof what, "search field %g pt \"%s\" cellSize", sizes[i].font, [strings[j] UTF8String]);
            expectSize(what, [[field cell] cellSize], expected);
            [field sizeToFit];
            snprintf(what, sizeof what, "search field %g pt \"%s\" sizeToFit", sizes[i].font, [strings[j] UTF8String]);
            expectSize(what, [field frame].size, expected);
            snprintf(what, sizeof what, "search field %g pt \"%s\" cellSizeForBounds", sizes[i].font,
                     [strings[j] UTF8String]);
            expectSize(what, [[field cell] cellSizeForBounds: NSMakeRect(0, 0, 400, 100)], expected);
        }
}

// QUIRK: combo box and search field cells do not wrap their text. See -[NSComboBoxCell initTextCell:].
static void test_quirk_single_line_defaults(void) {
    NSComboBox *combo = [[[NSComboBox alloc] initWithFrame: NSMakeRect(0, 0, 100, 26)] autorelease];
    NSSearchField *search = [[[NSSearchField alloc] initWithFrame: NSMakeRect(0, 0, 100, 22)] autorelease];

    if ([[combo cell] wraps] || ![[combo cell] isScrollable] || [[combo cell] lineBreakMode] != NSLineBreakByClipping) {
        fprintf(stderr, "FAIL a combo box wraps %d scrollable %d lineBreakMode %d\n", (int) [[combo cell] wraps],
                (int) [[combo cell] isScrollable], (int) [[combo cell] lineBreakMode]);
        failures++;
    }
    if ([[search cell] wraps] || [[search cell] isScrollable] || [[search cell] lineBreakMode] != NSLineBreakByClipping) {
        fprintf(stderr, "FAIL a search field wraps %d scrollable %d lineBreakMode %d\n", (int) [[search cell] wraps],
                (int) [[search cell] isScrollable], (int) [[search cell] lineBreakMode]);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_quirk_combo_box_cell_size();
        test_quirk_search_field_cell_size();
        test_quirk_single_line_defaults();
    }
    if (failures) {
        printf("FAIL (%d)\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
