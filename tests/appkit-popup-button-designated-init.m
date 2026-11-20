/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// -[NSPopUpButton initWithFrame:pullsDown:] is the designated initializer:
// -initWithFrame: and -init make a pop-up list through it, so a subclass that
// sets itself up in its override is set up when made either way, as AppKit
// makes a custom view of a nib with -initWithFrame:.
// Results as on macOS 26.7.3 and 10.14.4. No display needed. No ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
static int calls;
static BOOL lastPullsDown;

static void expect(BOOL ok, const char *label) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

@interface PlainPopUp : NSPopUpButton
@end

@implementation PlainPopUp
- (instancetype) initWithFrame: (NSRect) frame pullsDown: (BOOL) pullsDown {
    calls++;
    lastPullsDown = pullsDown;
    if ((self = [super initWithFrame: frame pullsDown: pullsDown]))
        [self setBordered: NO];
    return self;
}
@end

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];

        calls = 0;
        lastPullsDown = YES;
        PlainPopUp *framed = [[PlainPopUp alloc] initWithFrame: NSMakeRect(0, 0, 100, 20)];
        expect(calls == 1 && !lastPullsDown, "initWithFrame: calls initWithFrame:pullsDown: with NO once");
        expect(![framed isBordered] && ![framed pullsDown], "the subclass's set-up applies to a pop-up made with initWithFrame:");
        expect(NSEqualRects([framed frame], NSMakeRect(0, 0, 100, 20)), "the frame is kept");
        [framed release];

        calls = 0;
        lastPullsDown = YES;
        PlainPopUp *plain = [[PlainPopUp alloc] init];
        expect(calls == 1 && !lastPullsDown, "init calls initWithFrame:pullsDown: with NO once");
        [plain release];

        calls = 0;
        PlainPopUp *pullDown = [[PlainPopUp alloc] initWithFrame: NSMakeRect(0, 0, 100, 20) pullsDown: YES];
        expect(calls == 1 && [pullDown pullsDown], "initWithFrame:pullsDown: is called once when used directly");
        [pullDown release];

        NSPopUpButton *button = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 100, 20)];
        expect(![button pullsDown] && [button isBordered], "a plain NSPopUpButton is a bordered pop-up list");
        [button release];
    }
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
