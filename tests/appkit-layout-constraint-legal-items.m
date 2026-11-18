/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// +constraintWithItem:... accepts views and layout guides, and a nil second
// item for a constraint on one item. A nil first item, or an item of another
// kind, raises NSInvalidArgumentException.
// Prints PASS, or FAIL lines and exit status 1.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void attempt(const char *label, id first, id second, BOOL shouldRaise) {
    BOOL raised = NO;
    @try {
        [NSLayoutConstraint constraintWithItem: first
                                     attribute: NSLayoutAttributeWidth
                                     relatedBy: NSLayoutRelationEqual
                                        toItem: second
                                     attribute: second ? NSLayoutAttributeWidth : NSLayoutAttributeNotAnAttribute
                                    multiplier: 1
                                      constant: 5];
    } @catch (NSException *e) {
        raised = [[e name] isEqualToString: NSInvalidArgumentException];
        if (!raised) {
            printf("FAIL: %s raised %s\n", label, [[e name] UTF8String]);
            failures++;
            return;
        }
    }
    if (raised != shouldRaise) {
        printf("FAIL: %s %s\n", label, raised ? "raised" : "did not raise");
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSView *view = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
        NSLayoutGuide *guide = [[NSLayoutGuide alloc] init];
        attempt("view and nothing", view, nil, NO);
        attempt("view and view", view, view, NO);
        attempt("guide and nothing", guide, nil, NO);
        attempt("view and guide", view, guide, NO);
        attempt("string first", @"x", nil, YES);
        attempt("object first", [[NSObject alloc] init], view, YES);
        attempt("nil first", nil, view, YES);
        attempt("object second", view, [[NSObject alloc] init], YES);
        attempt("window first", [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 10, 10)
                                                            styleMask: NSWindowStyleMaskTitled
                                                              backing: NSBackingStoreBuffered
                                                                defer: YES], nil, YES);
        if (failures)
            return 1;
        printf("PASS\n");
        return 0;
    }
}
