// Copyright (C) 2026 Lubos Dolezel
//
// A nib stores a view of an application's own class as a custom view: the archive holds the class
// name and the common view state, and loading it makes a view of that class. The Auto Layout state
// of the archive (whether the autoresizing mask is translated, the content hugging and compression
// resistance priorities, the constraints the view owns) has to reach that view, or a window whose
// content is built of custom views is laid out as if the nib had no constraints.
//
// Build: clang -fobjc-arc -framework AppKit appkit-custom-view-auto-layout-state.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface AppSpecificView : NSView
@end
@implementation AppSpecificView
@end

// Stands in for NSCustomView in an archive; the constraint it owns has the view itself as item.
@interface CustomViewStandIn : NSObject <NSCoding>
@property(copy) NSString *viewClassName;
@property BOOL withLayoutState;
@end
@implementation CustomViewStandIn
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.viewClassName forKey:@"NSClassName"];
    [coder encodeRect:NSMakeRect(1, 2, 30, 40) forKey:@"NSFrame"];
    [coder encodeInt:0x12 forKey:@"NSvFlags"];
    if (!self.withLayoutState)
        return;
    [coder encodeBool:YES forKey:@"NSDoNotTranslateAutoresizingMask"];
    [coder encodeObject:NSStringFromSize(NSMakeSize(300, 400)) forKey:@"NSHuggingPriority"];
    [coder encodeObject:NSStringFromSize(NSMakeSize(600, 700)) forKey:@"NSAntiCompressionPriority"];
    NSLayoutConstraint *width = [NSLayoutConstraint constraintWithItem:self
            attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationGreaterThanOrEqual
            toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:460];
    [coder encodeObject:@[width] forKey:@"NSViewConstraints"];
}
- (id)initWithCoder:(NSCoder *)coder { return [super init]; }
@end

static id decodeCustomView(NSString *className, BOOL withLayoutState) {
    CustomViewStandIn *standIn = [CustomViewStandIn new];
    standIn.viewClassName = className;
    standIn.withLayoutState = withLayoutState;
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver setClassName:@"NSCustomView" forClass:[CustomViewStandIn class]];
    [archiver encodeObject:standIn forKey:@"root"];
    [archiver finishEncoding];
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    return [unarchiver decodeObjectForKey:@"root"];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSView *plain = decodeCustomView(@"AppSpecificView", NO);
        CHECK([plain isKindOfClass:[AppSpecificView class]]);
        CHECK([plain translatesAutoresizingMaskIntoConstraints]);
        CHECK([[plain constraints] count] == 0);

        NSView *view = decodeCustomView(@"AppSpecificView", YES);
        CHECK([view isKindOfClass:[AppSpecificView class]]);
        CHECK(NSEqualRects([view frame], NSMakeRect(1, 2, 30, 40)));
        CHECK(![view translatesAutoresizingMaskIntoConstraints]);
        CHECK([view contentHuggingPriorityForOrientation:NSLayoutConstraintOrientationHorizontal] == 300);
        CHECK([view contentHuggingPriorityForOrientation:NSLayoutConstraintOrientationVertical] == 400);
        CHECK([view contentCompressionResistancePriorityForOrientation:NSLayoutConstraintOrientationHorizontal] == 600);
        CHECK([view contentCompressionResistancePriorityForOrientation:NSLayoutConstraintOrientationVertical] == 700);
        NSArray *constraints = [view constraints];
        CHECK([constraints count] == 1);
        if ([constraints count] == 1) {
            NSLayoutConstraint *c = constraints[0];
            CHECK([c firstItem] == view);
            CHECK([c firstAttribute] == NSLayoutAttributeWidth);
            CHECK([c relation] == NSLayoutRelationGreaterThanOrEqual);
            CHECK([c constant] == 460);
        }
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
