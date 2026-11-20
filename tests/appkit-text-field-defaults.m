// Copyright (C) 2026 Lubos Dolezel
//
// The defaults of a new NSTextField and NSTextFieldCell, and the size
// -[NSTextFieldCell cellSize] adds to the text for each border style. The
// expected values were observed on macOS 10.14.4 (black-box; 26.7.3 agrees on
// the defaults).
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;

static void expectTrue(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL %s\n", what);
        failures++;
    }
}

static void checkField(const char *name, NSTextField *field, BOOL drawsBackground, NSColor *background) {
    char what[128];
    snprintf(what, sizeof what, "%s drawsBackground %d", name, drawsBackground);
    expectTrue([field drawsBackground] == drawsBackground, what);
    snprintf(what, sizeof what, "%s backgroundColor %s", name, [[background description] UTF8String]);
    expectTrue([[field backgroundColor] isEqual: background], what);
}

// QUIRK: a new field draws its background. See -[NSTextField initWithFrame:].
static void test_quirk_field_defaults(void) {
    NSTextField *fields[] = { [[[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 100, 22)] autorelease],
                              [[[NSTextField alloc] init] autorelease] };
    for (int i = 0; i < 2; i++) {
        NSTextField *field = fields[i];
        const char *name = i ? "init" : "initWithFrame:";
        checkField(name, field, YES, [NSColor textBackgroundColor]);
        expectTrue([[field textColor] isEqual: [NSColor controlTextColor]], "a new field's text colour is controlTextColor");
        expectTrue([field isBezeled] && ![field isBordered], "a new field is bezeled and has no line border");
        expectTrue([field isEditable] && [field isSelectable], "a new field is editable and selectable");
        expectTrue([field bezelStyle] == NSTextFieldSquareBezel, "a new field has the square bezel");
    }
    NSTextField *field = fields[0];
    [field setBezeled: NO];
    checkField("unbezeled", field, YES, [NSColor textBackgroundColor]);

    checkField("NSSearchField", [[[NSSearchField alloc] initWithFrame: NSMakeRect(0, 0, 100, 22)] autorelease], NO,
               [NSColor textBackgroundColor]);
    checkField("NSSecureTextField", [[[NSSecureTextField alloc] initWithFrame: NSMakeRect(0, 0, 100, 22)] autorelease],
               YES, [NSColor controlBackgroundColor]);
    checkField("NSComboBox", [[[NSComboBox alloc] initWithFrame: NSMakeRect(0, 0, 100, 22)] autorelease], YES,
               [NSColor textBackgroundColor]);
    if ([NSTextField respondsToSelector: @selector(labelWithString:)]) {
        expectTrue(![[NSTextField labelWithString: @"x"] drawsBackground], "a label draws no background");
        expectTrue(![[NSTextField wrappingLabelWithString: @"x"] drawsBackground], "a wrapping label draws no background");
        expectTrue([[NSTextField textFieldWithString: @"x"] drawsBackground], "textFieldWithString: draws its background");
    }
}

// QUIRK: a new cell has textBackgroundColor but draws no background. See
// -[NSTextFieldCell initTextCell:].
static void test_quirk_cell_defaults(void) {
    NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell: @"x"] autorelease];
    expectTrue(![cell drawsBackground], "a new cell draws no background");
    expectTrue([[cell backgroundColor] isEqual: [NSColor textBackgroundColor]], "a new cell's background is textBackgroundColor");
    expectTrue(![cell isBezeled] && ![cell isBordered] && ![cell isEditable], "a new cell is plain and not editable");
}

static void expectSize(const char *what, NSSize size, NSSize expected) {
    if (fabs(size.width - expected.width) > 0.01 || fabs(size.height - expected.height) > 0.01) {
        fprintf(stderr, "FAIL %s: {%g,%g}, expected {%g,%g}\n", what, size.width, size.height, expected.width,
                expected.height);
        failures++;
    }
}

// QUIRK: the space cellSize adds for each border style. See
// -[NSTextFieldCell _textInsetSize].
static void test_quirk_cell_size(void) {
    static const struct { CGFloat font; NSControlSize size; CGFloat roundedInset, roundedHeight; } cases[] = {
        { 13, NSControlSizeRegular, 21, 22 }, { 11, NSControlSizeSmall, 20, 19 }, { 20, NSControlSizeRegular, 21, 22 },
    };
    for (unsigned i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell: @"Hello"] autorelease];
        [cell setFont: [NSFont systemFontOfSize: cases[i].font]];
        [cell setControlSize: cases[i].size];
        NSSize text = [[cell attributedStringValue] size];
        char what[96];

        snprintf(what, sizeof what, "%g pt plain", cases[i].font);
        expectSize(what, [cell cellSize], NSMakeSize(text.width + 4, text.height));
        [cell setBordered: YES];
        snprintf(what, sizeof what, "%g pt line border", cases[i].font);
        expectSize(what, [cell cellSize], NSMakeSize(text.width + 8, text.height + 4));
        [cell setBezeled: YES];
        snprintf(what, sizeof what, "%g pt square bezel", cases[i].font);
        expectSize(what, [cell cellSize], NSMakeSize(ceil(text.width + 8), ceil(text.height + 5)));
        [cell setBezelStyle: NSTextFieldRoundedBezel];
        snprintf(what, sizeof what, "%g pt rounded bezel", cases[i].font);
        expectSize(what, [cell cellSize], NSMakeSize(ceil(text.width + cases[i].roundedInset), cases[i].roundedHeight));
    }
    NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell: @"Hello"] autorelease];
    [cell setFont: [NSFont systemFontOfSize: 9]];
    [cell setControlSize: NSControlSizeMini];
    [cell setBezeled: YES];
    [cell setBezelStyle: NSTextFieldRoundedBezel];
    NSSize text = [[cell attributedStringValue] size];
    expectSize("9 pt mini rounded bezel", [cell cellSize], NSMakeSize(ceil(text.width + 19), 17));

    // sizeToFit gives a bezeled field its cell size
    NSTextField *field = [[[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 100, 40)] autorelease];
    [field setStringValue: @"Hello"];
    [field setFont: [NSFont systemFontOfSize: 13]];
    NSSize size = [[field cell] cellSize];
    [field sizeToFit];
    expectSize("sizeToFit of a bezeled field", [field frame].size, size);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_quirk_field_defaults();
        test_quirk_cell_defaults();
        test_quirk_cell_size();
    }
    if (failures) {
        printf("FAIL (%d)\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
