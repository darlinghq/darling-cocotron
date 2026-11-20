// Copyright (C) 2026 Lubos Dolezel
//
// A button (and a bare button cell) archived with NSKeyedArchiver and
// unarchived again keeps its bezel style, border, transparency, button type
// masks, image position and scaling, title, alternate title, key equivalent,
// control size, alignment and tag, as on macOS 10.14.4 and 26.7.3 (black-box
// observation).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

#define SAME(what, getter) do { \
    long a_ = (long) [before getter], b_ = (long) [after getter]; \
    if (a_ != b_) { \
        fprintf(stderr, "FAIL %s: %s %ld after the round trip, was %ld\n", what, #getter, b_, a_); \
        failures++; \
    } } while (0)

#define SAME_OBJECT(what, getter) do { \
    id a_ = [before getter], b_ = [after getter]; \
    if (!(a_ == b_ || [a_ isEqual: b_])) { \
        fprintf(stderr, "FAIL %s: %s '%s' after the round trip, was '%s'\n", what, #getter, \
                [[b_ description] UTF8String], [[a_ description] UTF8String]); \
        failures++; \
    } } while (0)

static void compare(const char *what, NSButtonCell *before, NSButtonCell *after) {
    if (![after isKindOfClass: [NSButtonCell class]]) {
        fprintf(stderr, "FAIL %s: unarchived %s\n", what, [NSStringFromClass([after class]) UTF8String]);
        failures++;
        return;
    }
    SAME(what, bezelStyle);
    SAME(what, isBordered);
    SAME(what, isTransparent);
    SAME(what, highlightsBy);
    SAME(what, showsStateBy);
    SAME(what, imageScaling);
    SAME(what, showsBorderOnlyWhileMouseInside);
    SAME(what, controlSize);
    SAME(what, alignment);
    SAME(what, keyEquivalentModifierMask);
    SAME(what, tag);
    SAME_OBJECT(what, title);
    SAME_OBJECT(what, alternateTitle);
    SAME_OBJECT(what, keyEquivalent);
    // macOS 10.14 archives the leading and trailing positions (7 and 8, which
    // switches and radio buttons use there) as left and right
    if ([before imagePosition] < 7)
        SAME(what, imagePosition);
}

static NSButton *button(NSButtonType type, NSBezelStyle bezel, NSControlSize size) {
    NSButton *b = [[[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 100, 40)] autorelease];
    [b setButtonType: type];
    [b setBezelStyle: bezel];
    [b setTitle: @"Hello"];
    [[b cell] setControlSize: size];
    return b;
}

static void roundTrip(const char *what, NSButton *b) {
    NSButton *copy = [NSKeyedUnarchiver unarchiveObjectWithData: [NSKeyedArchiver archivedDataWithRootObject: b]];
    if (![copy isKindOfClass: [NSButton class]]) {
        fprintf(stderr, "FAIL %s: unarchived %s\n", what, [NSStringFromClass([copy class]) UTF8String]);
        failures++;
        return;
    }
    compare(what, [b cell], [copy cell]);
    NSButtonCell *cell = [NSKeyedUnarchiver unarchiveObjectWithData:
                                                    [NSKeyedArchiver archivedDataWithRootObject: [b cell]]];
    compare([[NSString stringWithFormat: @"%s (cell)", what] UTF8String], [b cell], cell);
}

static void test_bezel_styles(void) {
    for (NSBezelStyle bezel = 1; bezel <= 15; bezel++) {
        if (bezel == 3 || bezel == 4)
            continue;   // not defined
        char what[32];
        snprintf(what, sizeof what, "bezel %ld", (long) bezel);
        roundTrip(what, button(NSButtonTypeMomentaryPushIn, bezel, NSControlSizeRegular));
    }
}

static void test_button_types(void) {
    roundTrip("rounded push", button(NSButtonTypeMomentaryPushIn, NSBezelStyleRounded, NSControlSizeRegular));
    roundTrip("small square, small", button(NSButtonTypeMomentaryPushIn, NSBezelStyleSmallSquare, NSControlSizeSmall));
    roundTrip("textured toggle, mini", button(NSButtonTypeToggle, NSBezelStyleTexturedRounded, NSControlSizeMini));
    roundTrip("recessed push on push off", button(NSButtonTypePushOnPushOff, NSBezelStyleRecessed, NSControlSizeRegular));
    roundTrip("switch", button(NSButtonTypeSwitch, NSBezelStyleRegularSquare, NSControlSizeRegular));
    roundTrip("radio", button(NSButtonTypeRadio, NSBezelStyleRegularSquare, NSControlSizeSmall));

    NSButton *b = button(NSButtonTypeMomentaryChange, NSBezelStyleRegularSquare, NSControlSizeRegular);
    [b setBordered: NO];
    roundTrip("borderless momentary change", b);

    b = button(NSButtonTypeMomentaryPushIn, NSBezelStyleShadowlessSquare, NSControlSizeRegular);
    [b setTransparent: YES];
    roundTrip("transparent", b);

    b = button(NSButtonTypeToggle, NSBezelStyleTexturedRounded, NSControlSizeRegular);
    [b setAlternateTitle: @"Alt"];
    [b setKeyEquivalent: @"k"];
    [b setKeyEquivalentModifierMask: NSEventModifierFlagCommand | NSEventModifierFlagShift];
    [b setImagePosition: NSImageRight];
    [b setImageScaling: NSImageScaleProportionallyUpOrDown];
    [[b cell] setShowsBorderOnlyWhileMouseInside: YES];
    [b setAlignment: NSTextAlignmentRight];
    [b setTag: 42];
    roundTrip("toggle with settings", b);
}

// The archived contents of a button cell are its title.
static void test_contents_is_title(void) {
    NSButtonCell *cell = [[[NSButtonCell alloc] initTextCell: @"Title"] autorelease];
    [cell setBezelStyle: NSBezelStyleRounded];
    [cell setState: NSControlStateValueOn];
    NSButtonCell *after = [NSKeyedUnarchiver unarchiveObjectWithData: [NSKeyedArchiver archivedDataWithRootObject: cell]];
    if (![[after title] isKindOfClass: [NSString class]] || ![[after title] isEqualToString: @"Title"]) {
        fprintf(stderr, "FAIL title after the round trip: %s\n", [[[after title] description] UTF8String]);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_bezel_styles();
        test_button_types();
        test_contents_is_title();
    }
    if (failures) {
        printf("FAIL (%d)\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
