/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSApplication occlusionState: NSApplicationOcclusionStateVisible while a window is visible, not
// while there is none, and not while the application is hidden. Prints PASS on success. Needs a window
// system session (X11, Wayland or a logged-in Mac session). NSApplicationDidChangeOcclusionStateNotification
// is posted once per change of the state (ordering windows in and out, hiding, unhiding), with the application as
// its object, and not when the state stays the same. Build without ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
static int notifications;
static int wrongObject;

@interface Counter : NSObject
- (void) changed: (NSNotification *) note;
@end
@implementation Counter
- (void) changed: (NSNotification *) note {
    notifications++;
    if ([note object] != NSApp)
        wrongObject++;
}
@end

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        Counter *counter = [[Counter alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver: counter
                                                 selector: @selector(changed:)
                                                     name: NSApplicationDidChangeOcclusionStateNotification
                                                   object: nil];
        expect([NSApplicationDidChangeOcclusionStateNotification
                       isEqualToString: @"NSApplicationDidChangeOcclusionStateNotification"],
               "notification name");
        expect(([app occlusionState] & NSApplicationOcclusionStateVisible) == 0,
               "an application without windows is not visible");

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 120)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        expect(([app occlusionState] & NSApplicationOcclusionStateVisible) == 0,
               "an application with only an unshown window is not visible");
        expect(notifications == 0, "creating a window posts no notification");
        [window orderFront: nil];
        expect(([app occlusionState] & NSApplicationOcclusionStateVisible) != 0,
               "an application with a visible window is visible");
        expect(notifications == 1, "becoming visible posts one notification");

        // A second visible window does not change the application's state.
        NSWindow *second = [[NSWindow alloc] initWithContentRect: NSMakeRect(300, 100, 200, 120)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [second orderFront: nil];
        [second orderOut: nil];
        expect(notifications == 1, "a second window coming and going while the first is visible posts nothing");

        [app hide: nil];
        expect(([app occlusionState] & NSApplicationOcclusionStateVisible) == 0,
               "a hidden application is not visible");
        expect(notifications == 2, "hiding posts one notification");
        [app hide: nil];
        expect(notifications == 2, "hiding a hidden application posts nothing");
        [app unhide: nil];
        expect(([app occlusionState] & NSApplicationOcclusionStateVisible) != 0,
               "an unhidden application is visible again");
        expect(notifications == 3, "unhiding posts one notification");
        [window orderOut: nil];
        expect(([app occlusionState] & NSApplicationOcclusionStateVisible) == 0,
               "an application whose only window was ordered out is not visible");
        expect(notifications == 4, "ordering out the only window posts one notification");
        expect(wrongObject == 0, "the notification's object is the application");
        [second release];
    }
    if (failures == 0)
        printf("PASS\n");
    return failures == 0 ? 0 : 1;
}
