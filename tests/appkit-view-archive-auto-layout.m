// Copyright (C) 2026 Lubos Dolezel
// The Auto Layout state of a view survives keyed archiving, which is how nibs carry it: the
// "do not translate the autoresizing mask" flag, the constraints set up in Interface Builder
// (the ones marked to be archived), and the content hugging and compression resistance
// priorities. A text field that the decoded constraints only center takes the width of its
// text instead of the width in its archived frame.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int g_failures;
#define CHECK(cond) do { \
        if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } \
    } while (0)

static NSView *roundtrip(NSView *view)
{
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData: data];
    [archiver setRequiresSecureCoding: NO];
    [archiver encodeObject: view forKey: @"root"];
    [archiver finishEncoding];
    [archiver release];

    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData: data];
    [unarchiver setRequiresSecureCoding: NO];
    NSView *result = [[unarchiver decodeObjectForKey: @"root"] retain];
    [unarchiver finishDecoding];
    [unarchiver release];
    return [result autorelease];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        // 1. The state itself.
        NSView *container = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 370, 415)] autorelease];
        NSTextField *field = [[[NSTextField alloc] initWithFrame: NSMakeRect(105, 241, 160, 32)] autorelease];
        [field setBezeled: NO];
        [field setDrawsBackground: NO];
        [field setEditable: NO];
        [field setSelectable: NO];
        [field setFont: [NSFont systemFontOfSize: 27]];
        [field setLineBreakMode: NSLineBreakByClipping];
        [field setStringValue: @"The Unarchiver"];
        [field setTranslatesAutoresizingMaskIntoConstraints: NO];
        [field setContentHuggingPriority: 251 forOrientation: NSLayoutConstraintOrientationHorizontal];
        [field setContentCompressionResistancePriority: 749 forOrientation: NSLayoutConstraintOrientationVertical];
        [container addSubview: field];
        NSLayoutConstraint *centerX = [NSLayoutConstraint constraintWithItem: field
                                                                   attribute: NSLayoutAttributeCenterX
                                                                   relatedBy: NSLayoutRelationEqual
                                                                      toItem: container
                                                                   attribute: NSLayoutAttributeCenterX
                                                                  multiplier: 1
                                                                    constant: 7];
        NSLayoutConstraint *top = [NSLayoutConstraint constraintWithItem: field
                                                               attribute: NSLayoutAttributeTop
                                                               relatedBy: NSLayoutRelationEqual
                                                                  toItem: container
                                                               attribute: NSLayoutAttributeTop
                                                              multiplier: 1
                                                                constant: 140];
        // Only the constraints marked to be archived are written (those of Interface Builder).
        [centerX setShouldBeArchived: YES];
        [top setShouldBeArchived: YES];
        NSLayoutConstraint *notArchived = [NSLayoutConstraint constraintWithItem: field
                                                                       attribute: NSLayoutAttributeHeight
                                                                       relatedBy: NSLayoutRelationEqual
                                                                          toItem: nil
                                                                       attribute: NSLayoutAttributeNotAnAttribute
                                                                      multiplier: 1
                                                                        constant: 33];
        [container addConstraints: [NSArray arrayWithObjects: centerX, top, notArchived, nil]];

        NSView *decoded = roundtrip(container);
        CHECK(decoded != nil);
        CHECK([[decoded subviews] count] == 1);
        NSTextField *decodedField = [[decoded subviews] firstObject];
        CHECK([decodedField isKindOfClass: [NSTextField class]]);
        CHECK(![decodedField translatesAutoresizingMaskIntoConstraints]);
        CHECK([decoded translatesAutoresizingMaskIntoConstraints]);
        CHECK([decodedField contentHuggingPriorityForOrientation: NSLayoutConstraintOrientationHorizontal] == 251);
        CHECK([decodedField contentCompressionResistancePriorityForOrientation: NSLayoutConstraintOrientationVertical] == 749);

        NSArray *constraints = [decoded constraints];
        CHECK([constraints count] == 2);
        BOOL sawCenterX = NO, sawTop = NO;
        for (NSLayoutConstraint *constraint in constraints) {
            CHECK([constraint firstItem] == decodedField);
            CHECK([constraint secondItem] == decoded);
            if ([constraint firstAttribute] == NSLayoutAttributeCenterX && [constraint constant] == 7)
                sawCenterX = YES;
            if ([constraint firstAttribute] == NSLayoutAttributeTop && [constraint constant] == 140)
                sawTop = YES;
        }
        CHECK(sawCenterX);
        CHECK(sawTop);

        // A view that translates its mask archives no flag and no constraints.
        NSView *plain = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease];
        NSView *plainDecoded = roundtrip(plain);
        CHECK([plainDecoded translatesAutoresizingMaskIntoConstraints]);
        CHECK([[plainDecoded constraints] count] == 0);
        CHECK([plainDecoded contentHuggingPriorityForOrientation: NSLayoutConstraintOrientationHorizontal] == NSLayoutPriorityDefaultLow);
        CHECK([plainDecoded contentCompressionResistancePriorityForOrientation: NSLayoutConstraintOrientationHorizontal] == NSLayoutPriorityDefaultHigh);

        // 2. The layout of the decoded view: the width comes from the text, the position from
        // the constraints.
        NSWindow *window = [[[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 370, 415)
                                                        styleMask: NSWindowStyleMaskTitled
                                                          backing: NSBackingStoreBuffered
                                                            defer: NO] autorelease];
        [window setContentView: decoded];
        [decoded layoutSubtreeIfNeeded];
        NSRect frame = [decodedField frame];
        CHECK(frame.size.width != 160);
        CHECK(frame.size.width >= [decodedField intrinsicContentSize].width);
        CHECK(frame.size.width > 175);
        CHECK(fabs(NSMidX(frame) - (NSMidX([decoded bounds]) + 7)) <= 1);
        CHECK(fabs((NSHeight([decoded bounds]) - NSMaxY(frame)) - 140) <= 1);
    }
    if (g_failures == 0)
        printf("PASS\n");
    return g_failures != 0;
}
