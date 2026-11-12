/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSView layout guide management: a guide belongs to one view at a time.
#import <AppKit/AppKit.h>
#import <AppKit/NSLayoutGuide.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        NSView *first = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
        NSView *second = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
        NSLayoutGuide *guide = [[NSLayoutGuide alloc] init];
        [guide setIdentifier: @"content"];

        expect([[first layoutGuides] count] == 0, "a new view has no guides");
        expect([guide owningView] == nil, "a new guide has no owner");

        [first addLayoutGuide: guide];
        expect([[first layoutGuides] count] == 1 && [[first layoutGuides] objectAtIndex: 0] == guide,
               "addLayoutGuide: installs the guide");
        expect([guide owningView] == first, "the view becomes the owner");

        [first addLayoutGuide: guide];
        expect([[first layoutGuides] count] == 1, "adding twice installs it once");

        [second addLayoutGuide: guide];
        expect([[first layoutGuides] count] == 0, "adding to another view removes it from the first");
        expect([[second layoutGuides] count] == 1 && [guide owningView] == second,
               "the second view owns the guide");

        // Removing from a view that does not own the guide changes nothing.
        [first removeLayoutGuide: guide];
        expect([guide owningView] == second, "removeLayoutGuide: on a non-owner is ignored");

        [second removeLayoutGuide: guide];
        expect([[second layoutGuides] count] == 0 && [guide owningView] == nil,
               "removeLayoutGuide: releases the guide");
        expect([[guide identifier] isEqualToString: @"content"], "the identifier is kept");

        // nil is ignored.
        [first addLayoutGuide: nil];
        [first removeLayoutGuide: nil];
        expect([[first layoutGuides] count] == 0, "nil guides are ignored");

        [guide release];
        [first release];
        [second release];
    }
    printf("layout guides: %s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
