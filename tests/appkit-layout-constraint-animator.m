// Copyright (C) 2026 Lubos Dolezel
//
// -[NSLayoutConstraint animator] (NSAnimatablePropertyContainer) returns a proxy for the constraint.
// Expected values from macOS 26.7.3: the proxy is not the
// constraint itself and setting the constant through it does not raise.
// Build: clang -framework AppKit appkit-layout-constraint-animator.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    NSView *view = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 50, 50)] autorelease];
    NSLayoutConstraint *constraint = [NSLayoutConstraint constraintWithItem: view attribute: NSLayoutAttributeWidth
            relatedBy: NSLayoutRelationEqual toItem: nil attribute: NSLayoutAttributeNotAnAttribute multiplier: 1 constant: 10];
    CHECK([constraint respondsToSelector: @selector(animator)]);
    id proxy = [constraint animator];
    CHECK(proxy != nil);
    CHECK(proxy != constraint);
    // Sending an animatable property to the proxy does not raise. (macOS 26.7.3 leaves the constant of a
    // constraint that is not in a window's view hierarchy at its value; the animation is not run here.)
    @try {
        [[constraint animator] setConstant: 20];
    } @catch (NSException *e) {
        fprintf(stderr, "FAIL animator setConstant: raised %s\n", [[e name] UTF8String]);
        failures++;
    }
    if (failures == 0)
        printf("PASS appkit-layout-constraint-animator\n");
    [pool release];
    return failures != 0;
}
