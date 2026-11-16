// Copyright (C) 2026 Lubos Dolezel
//
// A key event sent to a window whose first responder is the window itself and that handles nothing
// goes on along the responder chain: -[NSWindow keyDown:] reaches the next responder that was set
// on the window with -setNextResponder:. Games use a window like that, with no views, as the
// receiver of the keyboard and put their own responder after it. Black-box observation of macOS 10.14.4.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

@interface Catcher : NSResponder {
@public
    NSString *characters;
    int keyUps, flags;
}
@end
@implementation Catcher
- (void) keyDown: (NSEvent *) event { characters = [[event characters] copy]; }
- (void) keyUp: (NSEvent *) event { keyUps++; }
- (void) flagsChanged: (NSEvent *) event { flags++; }
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 50, 1)
                                                        styleMask: NSWindowStyleMaskTitled
                                                          backing: NSBackingStoreBuffered
                                                            defer: YES];
        Catcher *catcher = [[Catcher alloc] init];
        [window setNextResponder: catcher];
        CHECK([window nextResponder] == catcher, "next responder not kept");
        CHECK([window firstResponder] == window, "first responder is not the window");

        NSEvent *down = [NSEvent keyEventWithType: NSEventTypeKeyDown location: NSZeroPoint modifierFlags: 0 timestamp: 0
                                      windowNumber: [window windowNumber] context: nil characters: @"p"
                                charactersIgnoringModifiers: @"p" isARepeat: NO keyCode: 35];
        NSEvent *up = [NSEvent keyEventWithType: NSEventTypeKeyUp location: NSZeroPoint modifierFlags: 0 timestamp: 0
                                    windowNumber: [window windowNumber] context: nil characters: @"p"
                              charactersIgnoringModifiers: @"p" isARepeat: NO keyCode: 35];
        [window sendEvent: down];
        [window sendEvent: up];
        CHECK([catcher->characters isEqualToString: @"p"], "keyDown not forwarded: %s", [catcher->characters UTF8String]);
        CHECK(catcher->keyUps == 1, "keyUp not forwarded: %d", catcher->keyUps);
    }
    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures != 0;
}
