/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A titled window whose content fills the title bar area and whose title bar
// is transparent (NSWindowStyleMaskFullSizeContentView and
// titlebarAppearsTransparent) shows no title bar, but still shows its close,
// miniaturize and zoom buttons over the content, unless they are hidden. With
// no window manager frame around such a window, AppKit shows them itself:
//   - -standardWindowButton: returns buttons in the window's frame view, in
//     front of the content view, at the top left (14 by 16 points, 7, 27 and
//     47 points from the left and 3 below the top, as on Mac OS X 10.14.4);
//   - their target is the window; each is enabled when the style mask has the
//     matching bit (closable, miniaturizable, resizable);
//   - they draw (a coloured disc), and a hidden one does not;
//   - clicking them closes, miniaturizes or zooms the window (checked by the
//     -x11.sh and -wayland.sh harnesses, which click them for real).
// A window that keeps the window manager's title bar does not show them
// itself. Prints "PASS ..."/"FAIL ..." lines for the checks it can make,
// "BUTTON <window> <kind> <x> <y> <w> <h>" (from the window's top left,
// y downwards) for the harness, then READY, and reports what the clicks did
// as CLOSED, MINIATURIZING or ZOOMED lines. The argument is how long to run.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;
#define CHECK(cond, ...) do { if (cond) printf("PASS "); else { printf("FAIL "); failures++; } printf(__VA_ARGS__); printf("\n"); } while (0)

@interface FillView : NSView
@end

@implementation FillView
- (void) drawRect: (NSRect) rect {
    [[NSColor blueColor] setFill];
    NSRectFill([self bounds]);
}
@end

@interface Watcher : NSObject <NSWindowDelegate>
@end

@implementation Watcher
- (void) windowWillClose: (NSNotification *) note {
    printf("CLOSED %s\n", [[[note object] title] UTF8String]);
    fflush(stdout);
}
// The window system may not confirm miniaturization (a compositor with no
// minimized state never does), so this checks that the button asked for it.
- (void) windowWillMiniaturize: (NSNotification *) note {
    printf("MINIATURIZING %s\n", [[[note object] title] UTF8String]);
    fflush(stdout);
}
- (void) windowDidResize: (NSNotification *) note {
    NSWindow *window = [note object];
    if ([window frame].size.width > 600) {
        printf("ZOOMED %s\n", [[window title] UTF8String]);
        fflush(stdout);
    }
}
@end

static void spin(NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([deadline timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event != nil)
            [NSApp sendEvent: event];
    }
}

static const NSUInteger standard = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                   NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;

static NSWindow *makeWindow(NSString *title, NSUInteger mask, NSRect frame, Watcher *watcher) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect: frame
                                                   styleMask: mask
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    [window setTitle: title];
    [window setReleasedWhenClosed: NO];
    [window setDelegate: watcher];
    [window setContentView: [[FillView alloc] initWithFrame: NSMakeRect(0, 0, frame.size.width, frame.size.height)]];
    if (mask & NSWindowStyleMaskFullSizeContentView) {
        [window setTitlebarAppearsTransparent: YES];
        [window setTitleVisibility: NSWindowTitleHidden];
    }
    return window;
}

static NSColor *pixel(NSView *view, NSPoint point) {
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect: [view bounds]];
    [view cacheDisplayInRect: [view bounds] toBitmapImageRep: rep];
    NSPoint p = [view convertPoint: point fromView: nil];
    // bitmap rows go downwards
    NSInteger y = (NSInteger) (NSHeight([view bounds]) - p.y);
    if (p.x < 0 || p.x >= [rep pixelsWide] || y < 0 || y >= [rep pixelsHigh])
        return [NSColor blackColor];
    return [[rep colorAtX: (NSInteger) p.x y: y] colorUsingColorSpace: [NSColorSpace deviceRGBColorSpace]];
}

static void checkButtons(NSWindow *window, NSUInteger mask, BOOL closeHidden) {
    const char *name = [[window title] UTF8String];
    NSView *frameView = [[window contentView] superview];
    static const char *kinds[] = {"close", "miniaturize", "zoom"};
    static const NSUInteger enabling[] = {NSWindowStyleMaskClosable, NSWindowStyleMaskMiniaturizable,
                                          NSWindowStyleMaskResizable};
    static const char *actions[] = {"performClose:", "miniaturize:", "zoom:"};
    NSRect frame = [window frame];

    for (NSWindowButton kind = NSWindowCloseButton; kind <= NSWindowZoomButton; kind++) {
        NSButton *button = [window standardWindowButton: kind];
        CHECK(button != nil, "%s %s: has the button", name, kinds[kind]);
        if (button == nil)
            continue;
        NSRect r = [button convertRect: [button bounds] toView: nil];
        CHECK([button superview] == frameView, "%s %s: in the frame view", name, kinds[kind]);
        CHECK(NSEqualRects(r, NSMakeRect(7 + 20 * kind, NSHeight(frame) - 19, 14, 16)),
              "%s %s: at %g,%g %gx%g in the window", name, kinds[kind], r.origin.x, r.origin.y, r.size.width,
              r.size.height);
        CHECK([button target] == window, "%s %s: targets the window", name, kinds[kind]);
        CHECK([button action] != NULL && !strcmp(sel_getName([button action]), actions[kind]), "%s %s: action %s",
              name, kinds[kind], [button action] ? sel_getName([button action]) : "NULL");
        CHECK([button isEnabled] == ((mask & enabling[kind]) != 0), "%s %s: enabled %d", name, kinds[kind],
              [button isEnabled]);
        NSPoint centre = NSMakePoint(NSMidX(r), NSMidY(r));
        BOOL hidden = kind == NSWindowCloseButton && closeHidden;
        NSView *hit = [frameView hitTest: [frameView convertPoint: centre fromView: nil]];
        CHECK(hidden ? hit != button : hit == button, "%s %s: %s clicks", name, kinds[kind],
              hidden ? "hidden, does not take" : "in front of the content, takes");
        NSColor *c = pixel(frameView, centre);
        BOOL blue = [c blueComponent] > 0.8 && [c redComponent] < 0.2 && [c greenComponent] < 0.2;
        CHECK(hidden ? blue : !blue, "%s %s: %s (pixel %.2f %.2f %.2f)", name, kinds[kind],
              hidden ? "not drawn" : "drawn over the content", [c redComponent], [c greenComponent],
              [c blueComponent]);
        printf("BUTTON %s %s %d %d %d %d\n", name, kinds[kind], (int) r.origin.x,
               (int) (NSHeight(frame) - NSMaxY(r)), (int) r.size.width, (int) r.size.height);
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        double seconds = argc > 1 ? atof(argv[1]) : 30;
        [NSApplication sharedApplication];
        Watcher *watcher = [Watcher new];
        NSUInteger fullSize = standard | NSWindowStyleMaskFullSizeContentView;
        NSUInteger closableOnly = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskFullSizeContentView;

        NSWindow *close = makeWindow(@"btn-close", fullSize, NSMakeRect(40, 600, 300, 200), watcher);
        NSWindow *mini = makeWindow(@"btn-mini", fullSize, NSMakeRect(400, 600, 300, 200), watcher);
        NSWindow *zoom = makeWindow(@"btn-zoom", fullSize, NSMakeRect(760, 600, 300, 200), watcher);
        NSWindow *partial = makeWindow(@"btn-closable", closableOnly, NSMakeRect(40, 250, 300, 200), watcher);
        NSWindow *hidden = makeWindow(@"btn-hidden", fullSize, NSMakeRect(400, 250, 300, 200), watcher);
        [[hidden standardWindowButton: NSWindowCloseButton] setHidden: YES];
        NSWindow *titled = makeWindow(@"btn-titled", standard, NSMakeRect(760, 250, 300, 200), watcher);
        for (NSWindow *window in @[close, mini, zoom, partial, hidden, titled])
            [window orderFront: nil];
        spin(1);

        checkButtons(close, fullSize, NO);
        checkButtons(mini, fullSize, NO);
        checkButtons(zoom, fullSize, NO);
        checkButtons(partial, closableOnly, NO);
        checkButtons(hidden, fullSize, YES);
        // A content view set later goes behind the buttons too.
        [close setContentView: [[FillView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)]];
        checkButtons(close, fullSize, NO);
        for (NSWindowButton kind = NSWindowCloseButton; kind <= NSWindowZoomButton; kind++)
            CHECK([[titled standardWindowButton: kind] superview] == nil,
                  "btn-titled: button %d left to the window manager's title bar", (int) kind);

        printf("READY %d\n", failures);
        fflush(stdout);
        spin(seconds);
        printf("DONE\n");
    }
    return failures != 0;
}
