// Copyright (C) 2026 Lubos Dolezel
//
// NSColorWell colorWellStyle. The documentation (macOS 13) lists it as a settable property whose
// type is an enumeration of three styles named default, minimal and expanded. It gives neither a
// starting value for the property nor numbers for the styles. Everything marked GUESS pins this implementation's choice, not a
// documented or measured value: the property starts as the default style, the cases are 0, 1 and 2
// in that order (the test does not rely on the numbers), and the value is independent of the well's
// color, border and active state.
// Build: clang -fobjc-arc -framework AppKit appkit-colorwell-color-well-style.m
// Needs the Darling guest with a display: creating a color well reaches the shared color panel.
// Not covered: any effect of the style on how the well looks or reacts (the value is only stored).
// On master the enumeration, the selectors and the constants do not exist: the test does not
// compile against master's header (with or without ARC), and could not run.
#import <AppKit/AppKit.h>
#include <stdio.h>

// the property is macOS 13 API; the guest has it whatever the build's deployment target is
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

static int failures;
#define CHECK(c) do { if (!(c)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// An application subclass whose setter wraps the superclass one (the failing receiver in a real
// application was a subclass).
@interface MyColorWell : NSColorWell
- (void)setColorWellStyle:(NSColorWellStyle)style;
@end
@implementation MyColorWell
- (void)setColorWellStyle:(NSColorWellStyle)style {
    (void)[self colorWellStyle];
    [super setColorWellStyle:style];
}
@end

static void checkWell(NSColorWell *well) {
    CHECK([well colorWellStyle] == NSColorWellStyleDefault);      // GUESS: the default

    NSColorWellStyle cases[] = { NSColorWellStyleMinimal, NSColorWellStyleExpanded,
        NSColorWellStyleDefault, NSColorWellStyleExpanded, NSColorWellStyleMinimal };
    for (int i = 0; i < 5; i++) {
        [well setColorWellStyle:cases[i]];
        CHECK([well colorWellStyle] == cases[i]);
    }

    // the value and the well's other state do not overwrite one another
    NSColor *color = [NSColor redColor];
    [well setColorWellStyle:NSColorWellStyleExpanded];
    [well setColor:color];
    [well setBordered:NO];
    CHECK([well colorWellStyle] == NSColorWellStyleExpanded);     // GUESS: not reset by the others
    [well setColorWellStyle:NSColorWellStyleMinimal];
    CHECK([well color] == color);
    CHECK(![well isBordered]);
    [well setBordered:YES];
    CHECK([well colorWellStyle] == NSColorWellStyleMinimal);
}

int main(void) {
    @autoreleasepool {
        // creating a color well reaches the shared color panel, which needs the display
        [NSApplication sharedApplication];
        CHECK([NSColorWell instancesRespondToSelector:@selector(colorWellStyle)]);
        CHECK([NSColorWell instancesRespondToSelector:@selector(setColorWellStyle:)]);

        // three distinct cases
        CHECK(NSColorWellStyleDefault != NSColorWellStyleMinimal);
        CHECK(NSColorWellStyleDefault != NSColorWellStyleExpanded);
        CHECK(NSColorWellStyleMinimal != NSColorWellStyleExpanded);

        NSColorWell *plain = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 23)];
        checkWell(plain);
        MyColorWell *mine = [[MyColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 23)];
        checkWell(mine);

        // wells do not share the value
        NSColorWell *first = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 23)];
        NSColorWell *second = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 23)];
        [first setColorWellStyle:NSColorWellStyleExpanded];
        CHECK([second colorWellStyle] == NSColorWellStyleDefault);
        [second setColorWellStyle:NSColorWellStyleMinimal];
        CHECK([first colorWellStyle] == NSColorWellStyleExpanded);
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
