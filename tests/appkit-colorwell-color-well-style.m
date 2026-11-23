// Copyright (C) 2026 Lubos Dolezel
//
// NSColorWell colorWellStyle. The documentation (macOS 13) lists it as a settable property whose
// type is an enumeration of three styles named default, minimal and expanded. It gives neither a
// starting value for the property nor numbers for the styles; the public header gives 0, 1 and 2 in that order.
// Observed on macOS 26.7.3 (mac-probes/cristim/batch12a/p770.m): the property starts as the default style,
// any value is stored (a number that is not a case too), the value is independent of the well's color and
// border, and an archive carries it under the key NSColorWellStyle (only when it is not the default).
// Build: clang -fobjc-arc -framework AppKit appkit-colorwell-color-well-style.m
// Needs the Darling guest with a display: creating a color well reaches the shared color panel.
// Not covered: any effect of the style on how the well looks or reacts (the value is only stored).
// On master the enumeration, the selectors and the constants do not exist: the test does not
// compile against master's header (with or without ARC), and could not run.
#import <AppKit/AppKit.h>
#include <stdio.h>

// Stands in for the object in a keyed archive: it writes only the one key (as an archive of a program that
// does not know the property would not have it, and as macOS writes it), and is decoded as the class under test.
static NSString *standInKey;
static NSInteger standInValue;
@interface ArchivedStandIn : NSObject <NSCoding>
@end
@implementation ArchivedStandIn
- (void)encodeWithCoder:(NSCoder *)coder {
    if (standInKey != nil)
        [coder encodeInteger:standInValue forKey:standInKey];
}
- (id)initWithCoder:(NSCoder *)coder { return [super init]; }
@end

static id decodedAs(Class cls, NSString *key, NSInteger value) {
    standInKey = key;
    standInValue = value;
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver encodeObject:[ArchivedStandIn new] forKey:@"root"];
    [archiver finishEncoding];
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    [unarchiver setClass:cls forClassName:@"ArchivedStandIn"];
    return [unarchiver decodeObjectForKey:@"root"];
}

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
    CHECK([well colorWellStyle] == NSColorWellStyleDefault);      // the default

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
    CHECK([well colorWellStyle] == NSColorWellStyleExpanded);     // not reset by the others
    [well setColorWellStyle:NSColorWellStyleMinimal];
    CHECK([well color] == color);
    CHECK(![well isBordered]);
    [well setBordered:YES];
    CHECK([well colorWellStyle] == NSColorWellStyleMinimal);
}

int main(void) {
    @autoreleasepool {
        // the public header's numbers
        CHECK(NSColorWellStyleDefault == 0 && NSColorWellStyleMinimal == 1 && NSColorWellStyleExpanded == 2);
        // the archive key, absent for the default style
        CHECK([(NSColorWell *)decodedAs([NSColorWell class], nil, 0) colorWellStyle] == NSColorWellStyleDefault);
        CHECK([(NSColorWell *)decodedAs([NSColorWell class], @"NSColorWellStyle", 1) colorWellStyle] == NSColorWellStyleMinimal);
        CHECK([(NSColorWell *)decodedAs([NSColorWell class], @"NSColorWellStyle", 2) colorWellStyle] == NSColorWellStyleExpanded);

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
