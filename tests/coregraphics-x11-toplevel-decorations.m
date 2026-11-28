/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// What a toplevel window of the UI layer (CGSWindow.h) shows of a title bar, and the window system moving it, on the X11
// backend and without AppKit (the program links only CoreGraphics and Foundation). Windows are made with each
// CGSToplevelTitlebarKind (none, standard, hidden) and the driver, coregraphics-x11-toplevel-decorations.sh, asks the X
// server what became of them: the window manager's frame (the Motif hints), the corners of a window that shows no title bar
// of its own, and a move that the window manager makes when the program asks for it from a left button press (the program
// listens to the pointer through an event tap). The program prints READY, then waits for the file go1 in the directory it is
// given (the kinds of two windows are swapped) and prints STAGE 1.
// Usage: coregraphics-x11-toplevel-decorations <directory>
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#import <CoreGraphics/CGSWindow.h>
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>

@protocol ToplevelWindow
- (CGError)setProperty:(CFStringRef)key value:(CFTypeRef)value;
- (CGError)orderWindow:(int)place relativeTo:(id)other;
- (CGError)setToplevelHints:(const CGSToplevelHints *)hints;
- (CGError)setToplevelFrame:(CGRect)frame;
- (CGError)setToplevelTitlebarKind:(CGSToplevelTitlebarKind)kind;
- (CGSToplevelTitlebarKind)toplevelTitlebarKind;
- (CGError)setToplevelPrefersClientDecoration:(BOOL)prefers;
- (CGError)setToplevelClientDecorationLayout:(const CGSToplevelDecorationLayout *)layout;
- (BOOL)toplevelClientDecorationContainsPoint:(CGPoint)point;
- (CGError)beginToplevelMoveByWindowSystem;
- (CGError)drawImage:(CGImageRef)image atPoint:(CGPoint)origin;
- (unsigned)windowId;
- (void *)nativeWindow;
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

static id<ToplevelWindow> moveWindow;
static int movesAsked, movesAccepted;

// A press of the left button asks the window system to move the window the program is shown for.
static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if (type == kCGEventLeftMouseDown && moveWindow != nil) {
        movesAsked++;
        if ([moveWindow beginToplevelMoveByWindowSystem] == 0)
            movesAccepted++;
        printf("MOVE asked=%d accepted=%d\n", movesAsked, movesAccepted);
        fflush(stdout);
    }
    return event;
}

static void listen(double seconds) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, false);
}

static void waitFor(const char *directory, const char *name) {
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", directory, name);
    for (int i = 0; i < 1200 && access(path, F_OK) != 0; i++)
        listen(0.1);
}

static void draw(id<ToplevelWindow> window, size_t width, size_t height) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, space,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(context, 0.2, 0.5, 0.8, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    [window drawImage:image atPoint:CGPointZero];
    CGImageRelease(image);
}

static id<ToplevelWindow> make(id<ToplevelWindow> (*newToplevel)(const CGSToplevelAttributes *), const char *title, CGFloat x,
                               CGSToplevelTitlebarKind kind) {
    CGSToplevelAttributes attributes = {CGRectMake(x, 300, 240, 160), false, false};
    id<ToplevelWindow> window = newToplevel(&attributes);
    if (window == nil)
        return nil;
    [window setProperty:CFSTR("WindowTitle") value:[NSString stringWithUTF8String:title]];
    CGSToplevelHints hints = {kCGSToplevelKindNormal, true, true, false, nil};
    [window setToplevelHints:&hints];
    CHECK([window setToplevelTitlebarKind:kind] == 0, "the title bar kind is accepted");
    CHECK([window toplevelTitlebarKind] == kind, "the window tells the kind it was given");
    [window orderWindow:1 relativeTo:nil];
    draw(window, 240, 160);
    return window;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2)
            return 2;
        id<ToplevelWindow> (*newToplevel)(const CGSToplevelAttributes *) = dlsym(RTLD_DEFAULT, "_CGSNewToplevelWindow");
        if (!newToplevel) {
            printf("FAIL: the toplevel window functions are missing\n");
            return 1;
        }
        id<ToplevelWindow> none = make(newToplevel, "tbk-none", 20, kCGSToplevelTitlebarNone);
        if (none == nil) {
            printf("SKIP: this window system makes no toplevel windows\n");
            return 0;
        }
        id<ToplevelWindow> standard = make(newToplevel, "tbk-standard", 300, kCGSToplevelTitlebarStandard);
        id<ToplevelWindow> hidden = make(newToplevel, "tbk-hidden", 580, kCGSToplevelTitlebarHidden);
        moveWindow = make(newToplevel, "tbk-move", 860, kCGSToplevelTitlebarNone);
        CHECK(standard != nil && hidden != nil && moveWindow != nil, "the windows are made");

        // No button is down: nothing to move.
        CHECK([moveWindow beginToplevelMoveByWindowSystem] != 0, "a move is refused while no button is down");
        // Client-side frames are the UI layer's where the window system does not offer them.
        CHECK([standard setToplevelPrefersClientDecoration:YES] == 0, "the preference for a client-side frame is accepted");
        CHECK(![standard toplevelClientDecorationContainsPoint:CGPointMake(1, 1)], "no point is on a frame the window system does not hit-test");

        // A toplevel window reports its frame, its repaints and the focus to the UI layer, which also selects the buttons and
        // the motion of the pointer it wants (see CGSWindow.h); this program is the UI layer. The masks are those of Xlib:
        // ButtonPress, ButtonRelease and PointerMotion, with what the window system's window selected for itself.
        int (*selectInput)(void *, unsigned long, long) = dlsym(RTLD_DEFAULT, "XSelectInput");
        void *(*nativeDisplay)(void) = dlsym(RTLD_DEFAULT, "_CGSNativeConnectionDisplay");
        CHECK(selectInput != NULL && nativeDisplay != NULL, "the program can select the pointer events of its window");
        if (selectInput != NULL && nativeDisplay != NULL)
            selectInput(nativeDisplay(), (unsigned long) [moveWindow nativeWindow],
                        (1L << 17) | (1L << 15) | (1L << 21) | (1L << 22) | (1L << 2) | (1L << 3) | (1L << 6));
        CGEventMask mask = CGEventMaskBit(kCGEventLeftMouseDown);
        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly, mask,
                                             tapCallback, NULL);
        if (tap != NULL) {
            CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
            CGEventTapEnable(tap, true);
        }
        CHECK(tap != NULL, "the event tap is made");
        listen(0.5);
        printf("READY\n");
        fflush(stdout);

        // The frames follow the kind while the windows are shown: the two windows swap theirs.
        waitFor(argv[1], "go1");
        CHECK([none setToplevelTitlebarKind:kCGSToplevelTitlebarStandard] == 0, "a shown window is given a title bar");
        CHECK([standard setToplevelTitlebarKind:kCGSToplevelTitlebarNone] == 0, "a shown window loses its title bar");
        listen(0.5);
        printf("STAGE 1\n");
        fflush(stdout);

        waitFor(argv[1], "go2");
        printf("RESULT failures=%d moves=%d\n", failures, movesAccepted);
        fflush(stdout);
    }
    return failures != 0;
}
