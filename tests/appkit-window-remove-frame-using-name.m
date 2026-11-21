/* Copyright (C) 2026 Lubos Dolezel */
// +[NSWindow removeFrameUsingName:] removes the frame data stored under a name from the user defaults
// (https://developer.apple.com/documentation/appkit/nswindow/removeframe(usingname:)); frames saved under
// another name stay. The names are unique to this test so they cannot match a real window's saved frame, and the
// saved frames are removed again when the test ends, on failure too. Needs a window system session. Build without
// ARC.
#import <AppKit/AppKit.h>
#include <stdlib.h>

static NSString *const kTested = @"RemoveFrameUsingNameTest-3f9a1c";
static NSString *const kLonger = @"RemoveFrameUsingNameTest-3f9a1c Longer";
static NSString *const kOther = @"RemoveFrameUsingNameTest-3f9a1c Other";

// -removeFrameUsingName: is the method under test, so the cleanup does not rely on it alone: it also drops the
// matching keys straight from the defaults.
static void cleanup(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (NSString *key in [[defaults dictionaryRepresentation] allKeys])
        if ([key hasPrefix:@"NSWindow frame RemoveFrameUsingNameTest-3f9a1c"])
            [defaults removeObjectForKey:key];
}

static void expect(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); cleanup(); exit(1); }
}

static NSWindow *makeWindow(NSRect frame) {
    return [[NSWindow alloc] initWithContentRect:frame
                                       styleMask:NSWindowStyleMaskTitled
                                         backing:NSBackingStoreBuffered
                                           defer:YES];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        cleanup();

        NSWindow *saver = makeWindow(NSMakeRect(120, 130, 300, 200));
        [saver saveFrameUsingName:kTested];
        [saver saveFrameUsingName:kLonger];
        [saver saveFrameUsingName:kOther];

        NSWindow *reader = makeWindow(NSMakeRect(0, 0, 50, 50));
        expect([reader setFrameUsingName:kTested], @"a saved frame can be read back");
        expect([reader setFrameUsingName:kOther], @"a second saved frame can be read back");

        [NSWindow removeFrameUsingName:kTested];
        NSWindow *after = makeWindow(NSMakeRect(0, 0, 50, 50));
        expect(![after setFrameUsingName:kTested], @"the removed frame is gone");
        expect([after setFrameUsingName:kOther], @"a frame under another name stays");
        expect([after setFrameUsingName:kLonger], @"a frame under a longer name that starts with it stays");

        // Names with nothing saved under them are accepted.
        [NSWindow removeFrameUsingName:@"RemoveFrameUsingNameTest-3f9a1c Never"];
        [NSWindow removeFrameUsingName:@""];
        [NSWindow removeFrameUsingName:nil];

        cleanup();
        printf("OK\n");
    }
    return 0;
}
