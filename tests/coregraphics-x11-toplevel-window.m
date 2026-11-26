/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// The toplevel window SPI of CoreGraphics (CGSWindow.h) without AppKit (the program links only
// CoreGraphics and Foundation): the window a UI layer is made
// of is created, titled, placed, sized, limited, faded, shown, hidden, recreated with a translucent
// visual and released. The X side is checked by coregraphics-x11-toplevel-window.sh, which gets the
// stages from this program: it prints READY, then waits for the files go1, go2 and go3 in the
// directory it is given and prints STAGE <n> when it has done what the stage says.
// Usage: coregraphics-x11-toplevel-window <directory>
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>

typedef struct {
    CGRect frame;
    bool unmanaged;
    bool translucent;
} ToplevelAttributes;

@protocol ToplevelWindow
- (CGError) recreateToplevelWithAttributes: (const ToplevelAttributes *) attributes;
- (CGError) setToplevelFrame: (CGRect) frame;
- (CGError) setToplevelMinimumSize: (CGSize) minimum maximumSize: (CGSize) maximum;
- (CGError) setToplevelAlpha: (CGFloat) alpha;
- (CGError) setProperty: (CFStringRef) key value: (CFTypeRef) value;
- (CGError) orderWindow: (int) place relativeTo: (id) other;
- (unsigned) windowId;
- (void *) nativeWindow;
@end

static int failures;
#define CHECK(cond, what)                                                      \
    do {                                                                       \
        if (cond)                                                              \
            printf("PASS: %s\n", what);                                        \
        else {                                                                 \
            printf("FAIL: %s (line %d)\n", what, __LINE__);                    \
            failures++;                                                        \
        }                                                                      \
    } while (0)

static NSDictionary *listing(unsigned number) {
    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow, number);
    NSDictionary *found = nil;
    if (list != NULL) {
        for (NSDictionary *entry in (NSArray *) list) {
            if ([[entry objectForKey: (NSString *) kCGWindowNumber] unsignedIntValue] == number)
                found = [[entry retain] autorelease];
        }
        CFRelease(list);
    }
    return found;
}

static CGRect boundsOf(NSDictionary *entry) {
    CGRect bounds = CGRectNull;
    CGRectMakeWithDictionaryRepresentation((CFDictionaryRef) [entry objectForKey: (NSString *) kCGWindowBounds],
                                           &bounds);
    return bounds;
}

// Cocoa's global space (y up, the origin at the bottom left of the main display) to CoreGraphics'.
static CGRect cgRect(CGRect frame) {
    CGFloat height = CGDisplayBounds(CGMainDisplayID()).size.height;
    return CGRectMake(frame.origin.x, height - frame.origin.y - frame.size.height, frame.size.width, frame.size.height);
}

static void waitFor(const char *directory, const char *name) {
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", directory, name);
    for (int i = 0; i < 1200 && access(path, F_OK) != 0; i++)
        usleep(100000);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2)
            return 2;
        id<ToplevelWindow> (*newToplevel)(const ToplevelAttributes *) = dlsym(RTLD_DEFAULT, "_CGSNewToplevelWindow");
        CGError (*release)(int, unsigned) = dlsym(RTLD_DEFAULT, "CGSReleaseWindow");
        int (*mainConnection)(void) = dlsym(RTLD_DEFAULT, "CGSMainConnectionID");
        if (!newToplevel || !release || !mainConnection) {
            printf("FAIL: the toplevel window functions are missing\n");
            return 1;
        }
        // Every window system connection answers the toplevel SPI; one that cannot make such windows says
        // so with nil and the test skips.
        ToplevelAttributes unmanagedAttributes = {CGRectMake(200, 500, 300, 200), true, false};
        ToplevelAttributes managedAttributes = {CGRectMake(600, 500, 300, 200), false, false};
        id<ToplevelWindow> unmanaged = newToplevel(&unmanagedAttributes);
        if (unmanaged == nil) {
            printf("SKIP: this window system makes no toplevel windows\n");
            return 0;
        }
        id<ToplevelWindow> managed = newToplevel(&managedAttributes);
        CHECK(managed != nil, "a second toplevel window is made");
        unsigned unmanagedNumber = [unmanaged windowId], managedNumber = [managed windowId];
        CHECK(unmanagedNumber != 0 && managedNumber != 0 && unmanagedNumber != managedNumber, "each window has an id of its own");
        CHECK([unmanaged nativeWindow] != NULL && [managed nativeWindow] != NULL, "each window has a native window");

        // The window is listed, not yet on screen.
        NSDictionary *entry = listing(managedNumber);
        CHECK(entry == nil || ![[entry objectForKey: (NSString *) kCGWindowIsOnscreen] boolValue],
              "an unshown window is not on screen");

        CFStringRef titleKey = CFSTR("WindowTitle");
        [unmanaged setProperty: titleKey value: @"tl-unmanaged"];
        [managed setProperty: titleKey value: @"tl-managed"];
        CHECK([managed setToplevelMinimumSize: CGSizeMake(200, 150) maximumSize: CGSizeMake(800, 600)] == kCGErrorSuccess,
              "size limits are accepted");
        CHECK([managed setToplevelAlpha: 0.5] == kCGErrorSuccess, "an alpha is accepted");
        CHECK([managed setToplevelFrame: CGRectMake(600, 500, 320, 220)] == kCGErrorSuccess, "a frame is accepted");
        [unmanaged orderWindow: 1 relativeTo: nil];
        [managed orderWindow: 1 relativeTo: nil];
        usleep(500000);

        entry = listing(unmanagedNumber);
        CHECK(entry != nil && [[entry objectForKey: (NSString *) kCGWindowIsOnscreen] boolValue], "the shown window is listed on screen");
        CHECK(entry != nil && CGRectEqualToRect(boundsOf(entry), cgRect(CGRectMake(200, 500, 300, 200))),
              "its bounds are its frame in CoreGraphics' space");
        CHECK([[entry objectForKey: (NSString *) kCGWindowName] isEqual: @"tl-unmanaged"], "its listed name is its title");
        CHECK([[entry objectForKey: (NSString *) kCGWindowOwnerPID] intValue] == getpid(), "the listing names this process");
        CHECK([unmanaged setToplevelFrame: CGRectMake(250, 450, 340, 210)] == kCGErrorSuccess, "the window is moved and sized");
        usleep(200000);
        CHECK(CGRectEqualToRect(boundsOf(listing(unmanagedNumber)), cgRect(CGRectMake(250, 450, 340, 210))),
              "the new bounds are listed");
        printf("NUMBERS unmanaged=%u managed=%u\n", unmanagedNumber, managedNumber);
        printf("READY\n");
        fflush(stdout);

        waitFor(argv[1], "go1");
        [managed setToplevelAlpha: 1.0];
        [managed setToplevelMinimumSize: CGSizeZero maximumSize: CGSizeZero];
        usleep(300000);
        printf("STAGE 1\n");
        fflush(stdout);

        waitFor(argv[1], "go2");
        void *before = [managed nativeWindow];
        ToplevelAttributes translucent = {CGRectMake(600, 500, 320, 220), false, true};
        CHECK([managed recreateToplevelWithAttributes: &translucent] == kCGErrorSuccess, "the window is recreated translucent");
        CHECK([managed nativeWindow] != before && [managed windowId] == managedNumber,
              "it has another native window and keeps its id");
        [managed setProperty: titleKey value: @"tl-managed"];
        [managed orderWindow: 1 relativeTo: nil];
        usleep(500000);
        CHECK(listing(managedNumber) != nil, "the recreated window is listed under its id");
        printf("STAGE 2\n");
        fflush(stdout);

        waitFor(argv[1], "go3");
        int cid = mainConnection();
        CHECK(release(cid, unmanagedNumber) == kCGErrorSuccess && release(cid, managedNumber) == kCGErrorSuccess,
              "the windows are released");
        usleep(300000);
        CHECK(listing(unmanagedNumber) == nil && listing(managedNumber) == nil, "released windows are not listed");
        printf("STAGE 3\n");
    }
    printf("RESULT failures=%d\n", failures);
    fflush(stdout);
    return failures == 0 ? 0 : 1;
}
