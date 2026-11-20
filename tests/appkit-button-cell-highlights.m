// Copyright (C) 2026 Lubos Dolezel
//
// A new button cell highlights and shows its state as on macOS 10.14: highlightsBy and showsStateBy per
// initializer, bezel style and button type, the default periodic delay and interval, and the NSPeriodicDelay and
// NSPeriodicInterval keys of an archived cell. Expected values were read through the public API on macOS 10.14.4
// (black-box observation, see vd-upstream/mac-probes/aqua-leftovers-buttoncell.m);
// test_quirk_button_cell_highlight_defaults pins the QUIRK-tagged behaviour of the same name in NSButtonCell.
// Passes on macOS 10.14.4.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL %s line %d: %s\n", __func__, __LINE__, #c); failures++; } } while (0)

enum { Contents = 1, PushIn = 2, Gray = 4, Background = 8 };

static BOOL repeatIs(NSButtonCell *c, float delay, float interval) {
    float d = -1, i = -1;
    [c getPeriodicDelay: &d interval: &i];
    return fabsf(d - delay) < 1e-4 && fabsf(i - interval) < 1e-4;
}

static void test_quirk_button_cell_highlight_defaults(void) {
    NSButtonCell *cells[] = {[[[NSButtonCell alloc] init] autorelease], [[[NSButtonCell alloc] initTextCell: @"x"] autorelease],
                             [[[NSButtonCell alloc] initImageCell: nil] autorelease],
                             [[[[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 80, 20)] autorelease] cell]};
    for (int i = 0; i < 4; i++) {
        CHECK([cells[i] highlightsBy] == (PushIn | Gray | Background));
        CHECK([cells[i] showsStateBy] == 0);
        CHECK(repeatIs(cells[i], 0.4f, 0.075f));
    }
    // the bezel style does not change them
    NSBezelStyle bezels[] = {NSBezelStyleRounded, NSBezelStyleRegularSquare, NSBezelStyleTexturedSquare, NSBezelStyleRoundRect,
                             NSBezelStyleRecessed, NSBezelStyleInline, NSBezelStyleDisclosure, NSBezelStyleTexturedRounded,
                             NSBezelStyleHelpButton, NSBezelStyleCircular, NSBezelStyleSmallSquare};
    for (unsigned i = 0; i < sizeof bezels / sizeof *bezels; i++) {
        NSButtonCell *c = [[[NSButtonCell alloc] initTextCell: @"x"] autorelease];
        [c setBezelStyle: bezels[i]];
        CHECK([c highlightsBy] == (PushIn | Gray | Background) && [c showsStateBy] == 0);
    }
    struct { NSButtonType type; int highlights, shows; } types[] = {
        {NSButtonTypeMomentaryLight, Gray | Background, 0}, {NSButtonTypeMomentaryPushIn, PushIn | Gray | Background, 0},
        {NSButtonTypeMomentaryChange, Contents, 0}, {NSButtonTypePushOnPushOff, PushIn | Gray | Background, Gray | Background},
        {NSButtonTypeOnOff, Gray | Background, Gray | Background}, {NSButtonTypeToggle, Contents | PushIn, Contents},
        {NSButtonTypeSwitch, Contents, Contents}, {NSButtonTypeRadio, Contents, Contents}};
    for (unsigned i = 0; i < sizeof types / sizeof *types; i++) {
        NSButton *b = [[[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 80, 20)] autorelease];
        [b setButtonType: types[i].type];
        CHECK([[b cell] highlightsBy] == types[i].highlights && [[b cell] showsStateBy] == types[i].shows);
        NSButtonCell *c = [[[NSButtonCell alloc] initTextCell: @"x"] autorelease];
        [c setButtonType: types[i].type];
        CHECK([c highlightsBy] == types[i].highlights && [c showsStateBy] == types[i].shows);
        CHECK(repeatIs(c, 0.4f, 0.075f));
    }
}

static NSDictionary *buttonCellDictionary(NSButtonCell *c) {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject: c];
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData: data options: 0 format: NULL error: NULL];
    for (id o in [plist objectForKey: @"$objects"])
        if ([o isKindOfClass: [NSDictionary class]] && [o objectForKey: @"NSButtonFlags"] != nil)
            return o;
    return nil;
}

static void test_periodic_keys(void) {
    NSButtonCell *c = [[[NSButtonCell alloc] initTextCell: @"x"] autorelease];
    NSDictionary *d = buttonCellDictionary(c);
    CHECK([[d objectForKey: @"NSPeriodicDelay"] intValue] == 400 && [[d objectForKey: @"NSPeriodicInterval"] intValue] == 75);
    [c setPeriodicDelay: 0.5 interval: 0.125];
    [c setHighlightsBy: NSChangeGrayCellMask];
    d = buttonCellDictionary(c);
    CHECK([[d objectForKey: @"NSPeriodicDelay"] intValue] == 500 && [[d objectForKey: @"NSPeriodicInterval"] intValue] == 125);
    NSButtonCell *back = [NSKeyedUnarchiver unarchiveObjectWithData: [NSKeyedArchiver archivedDataWithRootObject: c]];
    CHECK(repeatIs(back, 0.5f, 0.125f) && [back highlightsBy] == Gray);
    NSButtonCell *plain = [NSKeyedUnarchiver unarchiveObjectWithData:
                           [NSKeyedArchiver archivedDataWithRootObject: [[[NSButtonCell alloc] initTextCell: @"y"] autorelease]]];
    CHECK(repeatIs(plain, 0.4f, 0.075f) && [plain highlightsBy] == (PushIn | Gray | Background));
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_quirk_button_cell_highlight_defaults();
        test_periodic_keys();
    }
    if (failures) { printf("FAIL (%d)\n", failures); return 1; }
    printf("PASS\n");
    return 0;
}
