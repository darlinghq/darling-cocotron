// Copyright (C) 2026 Lubos Dolezel
//
// Contract: Apple AppKit documentation page of NSImage init(symbolName:variableValue:)
// (macOS 13), which documents the Objective-C declaration
// + (instancetype) imageWithSymbolName:(NSString *) name variableValue:(double) value;
// as a symbol image from a symbol name and a variable value between 0 and 1; the value
// matters only for symbols that support variable rendering. Darling has no symbol
// artwork and loads no symbols of an application's own, so the image is the one
// +imageWithSystemSymbolName:variableValue:accessibilityDescription: returns. What is
// checked: a non-empty name gives an image of non-zero size; the value is accepted
// inside and outside 0..1 without an exception.
// Placeholder pins, not documented behaviour (the page states none of them): nil for an
// empty name, and the template flag and size equal to those of the system symbol image,
// as this implementation gives. They would change with real symbol artwork. A nil name
// is not tested: the parameter is nonnull.
// Exit codes: 5 the selector is missing, 1 a check failed (named on stderr), 0 pass.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static BOOL sameSize(NSSize a, NSSize b) {
    return fabs(a.width - b.width) < 0.5 && fabs(a.height - b.height) < 0.5;
}

static void test_named_image(void) {
    NSImage *image = [NSImage imageWithSymbolName: @"star" variableValue: 0.5];
    NSImage *system = [NSImage imageWithSystemSymbolName: @"star" variableValue: 0.5 accessibilityDescription: nil];
    CHECK(image != nil);
    CHECK([image isKindOfClass: [NSImage class]]);
    CHECK([image size].width > 0 && [image size].height > 0);
    CHECK([image isTemplate]);  // placeholder pin: the system symbol image is a template
    CHECK([[image representations] count] > 0);
    CHECK(system != nil && sameSize([image size], [system size]));
    CHECK([image isTemplate] == [system isTemplate]);
    CHECK([image respondsToSelector: @selector(imageWithSymbolConfiguration:)]);
    NSImage *large = [image imageWithSymbolConfiguration:
            [NSImageSymbolConfiguration configurationWithScale: NSImageSymbolScaleLarge]];
    CHECK(large != nil && [large size].width > 0);
}

static void test_empty_name(void) {
    CHECK([NSImage imageWithSymbolName: @"" variableValue: 0.5] == nil);
}

static void test_values(void) {
    const double values[] = {0, 0.5, 1, -1, 2};
    for (unsigned i = 0; i < sizeof(values) / sizeof(values[0]); i++) {
        NSImage *image = nil;
        @try {
            image = [NSImage imageWithSymbolName: @"wifi" variableValue: values[i]];
        } @catch (id e) {
            fprintf(stderr, "FAIL: value %g raised %s\n", values[i], [[e description] UTF8String]);
            failures++;
            continue;
        }
        CHECK(image != nil);
        CHECK([image size].width > 0);
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        if (![NSImage respondsToSelector: @selector(imageWithSymbolName:variableValue:)]) {
            fputs("+[NSImage imageWithSymbolName:variableValue:] is missing\n", stderr);
            return 5;
        }
        test_named_image();
        test_empty_name();
        test_values();
        if (failures == 0)
            puts("PASS appkit-nsimage-symbol-name");
    }
    return failures != 0;
}
