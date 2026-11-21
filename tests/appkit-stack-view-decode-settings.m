// Copyright (C) 2026 Lubos Dolezel
// A stack view decoded from a keyed archive (as from a nib) keeps the settings archived with
// it: orientation, alignment, distribution, spacing, edge insets, hidden view detaching,
// hugging and clipping resistance priorities. The archive is written with the keys macOS
// 26.7.3 and 10.14.4 use for NSStackView. Then a decoded vertical stack view filling a
// window's content view stacks the views added to it from the top.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

// Writes what macOS writes for a stack view, and is decoded as an NSStackView.
@interface ArchivedStackView : NSObject <NSCoding> {
@public
    BOOL _defaults;
}
@end

@implementation ArchivedStackView

- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeInt32: 256 forKey: @"NSvFlags"];
    [coder encodeObject: @"{200, 300}" forKey: @"NSFrameSize"];
    if (_defaults) {
        [coder encodeInteger: 0 forKey: @"NSStackViewOrientation"];
        [coder encodeInteger: 10 forKey: @"NSStackViewAlignment"];
        [coder encodeFloat: 1000 forKey: @"NSStackViewVerticalClippingResistance"];
        [coder encodeFloat: 1000 forKey: @"NSStackViewHorizontalClippingResistance"];
        [coder encodeFloat: 250 forKey: @"NSStackViewVerticalHugging"];
        [coder encodeFloat: 250 forKey: @"NSStackViewHorizontalHugging"];
        [coder encodeFloat: 8 forKey: @"NSStackViewSpacing"];
        [coder encodeBool: NO forKey: @"NSStackViewHasEqualSpacing"];
        [coder encodeFloat: 0 forKey: @"NSStackViewEdgeInsets.top"];
        [coder encodeFloat: 0 forKey: @"NSStackViewEdgeInsets.left"];
        [coder encodeFloat: 0 forKey: @"NSStackViewEdgeInsets.right"];
        [coder encodeFloat: 0 forKey: @"NSStackViewEdgeInsets.bottom"];
        [coder encodeBool: YES forKey: @"NSStackViewDetachesHiddenViews"];
    } else {
        [coder encodeInteger: NSUserInterfaceLayoutOrientationVertical forKey: @"NSStackViewOrientation"];
        [coder encodeInteger: NSLayoutAttributeLeading forKey: @"NSStackViewAlignment"];
        [coder encodeFloat: 740 forKey: @"NSStackViewVerticalClippingResistance"];
        [coder encodeFloat: 760 forKey: @"NSStackViewHorizontalClippingResistance"];
        [coder encodeFloat: 249.5 forKey: @"NSStackViewVerticalHugging"];
        [coder encodeFloat: 251.5 forKey: @"NSStackViewHorizontalHugging"];
        [coder encodeFloat: 0 forKey: @"NSStackViewSpacing"];
        [coder encodeInteger: NSStackViewDistributionFill forKey: @"NSStackViewdistribution"];
        [coder encodeFloat: 1 forKey: @"NSStackViewEdgeInsets.top"];
        [coder encodeFloat: 2 forKey: @"NSStackViewEdgeInsets.left"];
        [coder encodeFloat: 4 forKey: @"NSStackViewEdgeInsets.right"];
        [coder encodeFloat: 3 forKey: @"NSStackViewEdgeInsets.bottom"];
        [coder encodeBool: NO forKey: @"NSStackViewDetachesHiddenViews"];
    }
    [coder encodeBool: YES forKey: @"NSStackViewHasFlatViewHierarchy"];
}

- (instancetype) initWithCoder: (NSCoder *) coder {
    return [super init];
}

@end

static NSStackView *decode(BOOL defaults) {
    ArchivedStackView *archived = [[ArchivedStackView alloc] init];
    archived->_defaults = defaults;

    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData: data];
    [archiver setClassName: @"NSStackView" forClass: [ArchivedStackView class]];
    [archiver encodeObject: archived forKey: @"root"];
    [archiver finishEncoding];

    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData: data];
    id object = [unarchiver decodeObjectForKey: @"root"];
    [unarchiver finishDecoding];
    return object;
}

static NSView *fixedView(CGFloat height) {
    NSView *view = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 300, height)];
    [view setTranslatesAutoresizingMaskIntoConstraints: NO];
    [view addConstraint: [NSLayoutConstraint constraintWithItem: view attribute: NSLayoutAttributeHeight
                                                      relatedBy: NSLayoutRelationEqual toItem: nil
                                                      attribute: NSLayoutAttributeNotAnAttribute multiplier: 1 constant: height]];
    [view addConstraint: [NSLayoutConstraint constraintWithItem: view attribute: NSLayoutAttributeWidth
                                                      relatedBy: NSLayoutRelationEqual toItem: nil
                                                      attribute: NSLayoutAttributeNotAnAttribute multiplier: 1 constant: 300]];
    return view;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSStackView *plain = decode(YES);
        CHECK([plain isKindOfClass: [NSStackView class]], "decoded an NSStackView");
        CHECK([plain orientation] == NSUserInterfaceLayoutOrientationHorizontal, "default orientation is %ld", (long) [plain orientation]);
        CHECK([plain alignment] == NSLayoutAttributeCenterY, "default alignment is %ld", (long) [plain alignment]);
        CHECK([plain distribution] == NSStackViewDistributionGravityAreas, "without the key the distribution is gravity areas, not %ld", (long) [plain distribution]);
        CHECK([plain spacing] == 8, "default spacing is %g", [plain spacing]);
        CHECK([plain detachesHiddenViews], "detaches hidden views by default");
        CHECK([plain huggingPriorityForOrientation: NSLayoutConstraintOrientationVertical] == 250, "default hugging");
        CHECK([plain clippingResistancePriorityForOrientation: NSLayoutConstraintOrientationHorizontal] == 1000, "default clipping resistance");

        NSStackView *stack = decode(NO);
        CHECK([stack orientation] == NSUserInterfaceLayoutOrientationVertical, "orientation is %ld", (long) [stack orientation]);
        CHECK([stack alignment] == NSLayoutAttributeLeading, "alignment is %ld", (long) [stack alignment]);
        CHECK([stack distribution] == NSStackViewDistributionFill, "distribution is %ld", (long) [stack distribution]);
        CHECK([stack spacing] == 0, "spacing is %g", [stack spacing]);
        NSEdgeInsets insets = [stack edgeInsets];
        CHECK(insets.top == 1 && insets.left == 2 && insets.bottom == 3 && insets.right == 4,
              "edge insets are %g %g %g %g", insets.top, insets.left, insets.bottom, insets.right);
        CHECK(![stack detachesHiddenViews], "detachesHiddenViews is NO");
        CHECK([stack huggingPriorityForOrientation: NSLayoutConstraintOrientationVertical] == 249.5f, "vertical hugging is %g",
              [stack huggingPriorityForOrientation: NSLayoutConstraintOrientationVertical]);
        CHECK([stack huggingPriorityForOrientation: NSLayoutConstraintOrientationHorizontal] == 251.5f, "horizontal hugging");
        CHECK([stack clippingResistancePriorityForOrientation: NSLayoutConstraintOrientationVertical] == 740, "vertical clipping resistance");
        CHECK([stack clippingResistancePriorityForOrientation: NSLayoutConstraintOrientationHorizontal] == 760, "horizontal clipping resistance");

        // The decoded vertical stack view, filling a window's content view, stacks its views downwards.
        [stack setEdgeInsets: NSEdgeInsetsMake(0, 0, 0, 0)];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 400)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        NSView *content = [window contentView];
        [stack setTranslatesAutoresizingMaskIntoConstraints: NO];
        [content addSubview: stack];
        for (NSNumber *attribute in @[@(NSLayoutAttributeTop), @(NSLayoutAttributeBottom), @(NSLayoutAttributeLeading), @(NSLayoutAttributeTrailing)])
            [content addConstraint: [NSLayoutConstraint constraintWithItem: stack attribute: [attribute integerValue]
                                                                 relatedBy: NSLayoutRelationEqual toItem: content
                                                                 attribute: [attribute integerValue] multiplier: 1 constant: 0]];
        NSView *top = fixedView(80), *bottom = fixedView(50);
        [stack addArrangedSubview: top];
        [stack addArrangedSubview: bottom];
        [window orderFront: nil];
        [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]];
        [content layoutSubtreeIfNeeded];

        NSRect topFrame = [top convertRect: [top bounds] toView: nil];
        NSRect bottomFrame = [bottom convertRect: [bottom bounds] toView: nil];
        CHECK(NSMinX(topFrame) == 0 && NSMinX(bottomFrame) == 0, "both views at the leading edge: %s %s",
              [NSStringFromRect(topFrame) UTF8String], [NSStringFromRect(bottomFrame) UTF8String]);
        CHECK(NSMaxY(bottomFrame) == NSMinY(topFrame), "the second view is right below the first: %s %s",
              [NSStringFromRect(topFrame) UTF8String], [NSStringFromRect(bottomFrame) UTF8String]);
        CHECK(NSMaxY(topFrame) == NSHeight([content frame]), "the first view is at the top: %s in %s",
              [NSStringFromRect(topFrame) UTF8String], [NSStringFromRect([content frame]) UTF8String]);
    }
    if (failures) {
        printf("%d failures\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
