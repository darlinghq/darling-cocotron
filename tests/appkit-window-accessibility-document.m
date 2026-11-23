// Copyright (C) 2026 Lubos Dolezel
//
// accessibilityDocument of the NSAccessibility protocol (macOS 10.10), on NSWindow. The
// documentation declares it as a copy property of type NSString, nullable, "the URL for
// the file that the accessibility element represents" (the setter: "sets the URL for the
// file"); it states no default and no further semantics. NSWindow conforms to the protocol,
// so it has the accessors; so do the other conformers that share this implementation.
// Everything marked GUESS pins this implementation's choice, not a documented or measured
// value: the default is nil, nil is accepted and reads back as nil, and the string is not
// parsed or checked as a URL.
// Build: clang -fobjc-arc -framework AppKit appkit-window-accessibility-document.m
// Not covered: any effect on the accessibility tree (the value is only stored), the copy
// semantics of the property, and the attribute-based reading
// (accessibilityAttributeValue:) of the document attribute. On master the selectors do not
// exist: with ARC the test does not compile against master's header, without ARC the first call
// raises an unrecognized selector.
#import <AppKit/AppKit.h>
#include <stdio.h>

// the property is macOS 10.10 API; the guest has it whatever the build's deployment target is
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

static int failures;
#define CHECK(c) do { if (!(c)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// An application subclass whose setter wraps the superclass one (the failing receiver in a
// real application was a subclass).
@interface MyWindow : NSWindow
- (void)setAccessibilityDocument:(NSString *)document;
@end
@implementation MyWindow
- (void)setAccessibilityDocument:(NSString *)document {
    (void)[self accessibilityDocument];
    [super setAccessibilityDocument:document];
}
@end

static BOOL same(NSString *a, NSString *b) { return a == b || [a isEqualToString:b]; }

static void checkDocument(id<NSAccessibility> element) {
    CHECK([element accessibilityDocument] == nil);   // GUESS: the default

    NSString *url = @"file:///Users/someone/Documents/Report.txt";
    [element setAccessibilityDocument:url];
    CHECK(same([element accessibilityDocument], url));

    // another value replaces it; the string is not interpreted (GUESS)
    [element setAccessibilityDocument:@"not a url"];
    CHECK(same([element accessibilityDocument], @"not a url"));
    [element setAccessibilityDocument:@""];
    CHECK([element accessibilityDocument] != nil);
    CHECK([[element accessibilityDocument] length] == 0);

    // nil is allowed by the declaration and clears it (GUESS: reads back as nil)
    [element setAccessibilityDocument:url];
    [element setAccessibilityDocument:nil];
    CHECK([element accessibilityDocument] == nil);
}

// the value and the element's other accessibility state do not overwrite one another
static void checkIndependence(id<NSAccessibility> element) {
    [element setAccessibilityDocument:@"file:///a"];
    [element setAccessibilityIdentifier:@"id"];
    [element setAccessibilityHelp:@"help"];
    [element setAccessibilityPlaceholderValue:@"placeholder"];
    CHECK(same([element accessibilityDocument], @"file:///a"));
    CHECK(same([element accessibilityIdentifier], @"id"));
    CHECK(same([element accessibilityHelp], @"help"));
    CHECK(same([element accessibilityPlaceholderValue], @"placeholder"));
    [element setAccessibilityDocument:@"file:///b"];
    CHECK(same([element accessibilityIdentifier], @"id"));
    CHECK(same([element accessibilityHelp], @"help"));
    CHECK(same([element accessibilityPlaceholderValue], @"placeholder"));
    [element setAccessibilityHelp:@"other"];
    CHECK(same([element accessibilityDocument], @"file:///b"));
}

static NSWindow *newWindow(Class cls) {
    return [[cls alloc] initWithContentRect:NSMakeRect(100, 100, 300, 200)
                                  styleMask:NSWindowStyleMaskTitled
                                    backing:NSBackingStoreBuffered
                                      defer:YES];
}

int main(void) {
    @autoreleasepool {
        CHECK([NSWindow instancesRespondToSelector:@selector(accessibilityDocument)]);
        CHECK([NSWindow instancesRespondToSelector:@selector(setAccessibilityDocument:)]);
        CHECK([NSWindow conformsToProtocol:@protocol(NSAccessibility)]);

        NSWindow *window = newWindow([NSWindow class]);
        checkDocument(window);
        checkIndependence(window);

        MyWindow *mine = (MyWindow *)newWindow([MyWindow class]);
        checkDocument(mine);
        checkIndependence(mine);

        // windows do not share the value, and the title does not stand in for it
        NSWindow *first = newWindow([NSWindow class]);
        NSWindow *second = newWindow([NSWindow class]);
        [first setTitle:@"First"];
        [first setAccessibilityDocument:@"file:///first"];
        CHECK([second accessibilityDocument] == nil);
        [second setAccessibilityDocument:@"file:///second"];
        CHECK(same([first accessibilityDocument], @"file:///first"));
        CHECK(same([first title], @"First"));
        CHECK(same([first accessibilityTitle], @"First"));

        // the other conformers that share the implementation
        NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        checkDocument(view);
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Item" action:NULL keyEquivalent:@""];
        checkDocument(item);
        NSAccessibilityElement *element =
            [NSAccessibilityElement accessibilityElementWithRole:NSAccessibilityGroupRole
                                                           frame:NSMakeRect(0, 0, 10, 10)
                                                           label:@"E"
                                                          parent:view];
        checkDocument(element);
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
