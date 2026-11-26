/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Ordering, levels, the keyboard focus, miniaturizing and fullscreen of toplevel windows of the UI layer
// (CGSWindow.h), without AppKit (the program links only CoreGraphics and Foundation): the windows are made, shown
// and ordered through CoreGraphics, the order they have is read back through _CGSOrderedToplevelWindowIDs() and
// CGWindowListCopyWindowInfo(), which must agree, and what the window system reports of them is recorded through
// the windows' event handlers. Needs an X server with a window manager that supports EWMH (DISPLAY).
// Usage: coregraphics-x11-toplevel-ordering
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>

// CGSToplevelEventKind of CGSWindow.h
enum {
    EventFocusGained = 9,
    EventFocusLost = 10,
    EventOcclusionChanged = 11,
    EventMiniaturized = 12,
    EventDeminiaturized = 13,
    EventFullscreenChanged = 14,
};
typedef struct {
    int kind;
    CGRect rect;
    bool resized;
    CGFloat oldScale;
    bool state;
} ToplevelEvent;
typedef void (*ToplevelEventProc)(id window, const ToplevelEvent *event, void *info);

typedef struct {
    CGRect frame;
    bool unmanaged;
    bool translucent;
} ToplevelAttributes;

@protocol ToplevelWindow
- (void)setToplevelEventProc:(ToplevelEventProc)proc info:(void *)info;
- (CGError)setProperty:(CFStringRef)key value:(CFTypeRef)value;
- (CGError)orderWindow:(int)place relativeTo:(id)other;
- (unsigned)windowId;
- (CGError)setToplevelLevel:(int)level;
- (CGError)setToplevelStacksByLevel:(BOOL)stacks;
- (CGError)orderToplevelAbove:(id)sibling;
- (CGError)orderToplevelBelow:(id)sibling;
- (CGError)restackToplevelForLevels;
- (CGError)requestToplevelKeyboardFocus;
- (BOOL)toplevelHoldsKeyboardFocus;
- (CGError)miniaturizeToplevel;
- (CGError)deminiaturizeToplevel;
- (BOOL)toplevelIsMiniaturized;
- (BOOL)toplevelFrameCoversDisplay:(CGRect)frame;
- (CGError)setToplevelFullscreen:(BOOL)fullscreen force:(BOOL)force;
- (BOOL)toplevelFullscreenRequested;
- (BOOL)toplevelIsFullscreen;
- (BOOL)toplevelIsOccluded;
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

#define MAX_EVENTS 256
static struct {
    unsigned window;
    ToplevelEvent event;
} heard[MAX_EVENTS];
static int heardCount;

static void record(id window, const ToplevelEvent *event, void *info) {
    if (heardCount < MAX_EVENTS) {
        heard[heardCount].window = [(id<ToplevelWindow>)window windowId];
        heard[heardCount].event = *event;
        heardCount++;
    }
}

static void listen(double seconds) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, false);
}

static int count(id<ToplevelWindow> window, int kind, int state) {
    int n = 0;
    for (int i = 0; i < heardCount; i++)
        n += heard[i].window == [window windowId] && heard[i].event.kind == kind &&
             (state < 0 || heard[i].event.state == (bool)state);
    return n;
}

// Listens until the event arrives, at most for a few seconds.
static BOOL waitForEvent(id<ToplevelWindow> window, int kind, int state) {
    for (int i = 0; i < 60 && count(window, kind, state) == 0; i++)
        listen(0.1);
    return count(window, kind, state) > 0;
}

static id<ToplevelWindow> makeWindow(const char *title, CGRect frame, BOOL unmanaged) {
    id<ToplevelWindow> (*newToplevel)(const ToplevelAttributes *) = dlsym(RTLD_DEFAULT, "_CGSNewToplevelWindow");
    ToplevelAttributes attributes = {frame, unmanaged, false};
    id<ToplevelWindow> window = newToplevel(&attributes);
    [window setToplevelEventProc:record info:NULL];
    [window setProperty:CFSTR("WindowTitle") value:[NSString stringWithUTF8String:title]];
    return window;
}

// The ids of our windows in the order the window system lists them, front to back: what CoreGraphics says of the
// toplevel windows, and what CGWindowListCopyWindowInfo() lists of the same process.
static NSArray *orderedIDs(void) {
    NSArray *(*ordered)(void) = dlsym(RTLD_DEFAULT, "_CGSOrderedToplevelWindowIDs");
    return ordered != NULL ? ordered() : nil;
}

static NSArray *listedIDs(void) {
    NSMutableArray *result = [NSMutableArray array];
    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    for (NSDictionary *info in (NSArray *)list)
        if ([info[(NSString *)kCGWindowOwnerPID] intValue] == getpid())
            [result addObject:info[(NSString *)kCGWindowNumber]];
    if (list != NULL)
        CFRelease(list);
    return result;
}

static NSInteger indexOf(NSArray *ids, id<ToplevelWindow> window) {
    return [ids indexOfObject:@([window windowId])];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        id<ToplevelWindow> a = makeWindow("tl-order-a", CGRectMake(100, 100, 300, 200), NO);
        if (a == nil) {
            printf("SKIP: this window system makes no toplevel windows\n");
            return 0;
        }
        CHECK([a respondsToSelector:@selector(orderToplevelAbove:)], "the window orders itself");
        CHECK(dlsym(RTLD_DEFAULT, "_CGSOrderedToplevelWindowIDs") != NULL, "the ordered window ids are available");
        if (failures != 0) {
            printf("RESULT failures=%d\n", failures);
            return 1;
        }
        id<ToplevelWindow> b = makeWindow("tl-order-b", CGRectMake(200, 150, 300, 200), NO);
        id<ToplevelWindow> c = makeWindow("tl-order-c", CGRectMake(300, 200, 300, 200), NO);
        for (id<ToplevelWindow> window in @[a, b, c]) {
            [window setToplevelStacksByLevel:YES];
            [window orderWindow:1 relativeTo:nil];
            listen(0.4);
        }
        listen(0.6);

        // In front of everything, behind everything, and relative to another window.
        [a orderToplevelAbove:nil];
        listen(0.5);
        NSArray *ids = orderedIDs();
        CHECK([ids count] == 3 && indexOf(ids, a) == 0, "a window ordered to the front is the first");
        [c orderToplevelBelow:nil];
        listen(0.5);
        ids = orderedIDs();
        CHECK([ids count] == 3 && indexOf(ids, c) == 2, "a window ordered to the back is the last");
        [c orderToplevelAbove:b];
        listen(0.5);
        ids = orderedIDs();
        CHECK(indexOf(ids, c) == indexOf(ids, b) - 1, "a window ordered above another is directly in front of it");
        [a orderToplevelBelow:c];
        listen(0.5);
        ids = orderedIDs();
        CHECK(indexOf(ids, a) == indexOf(ids, c) + 1, "a window ordered below another is directly behind it");

        // CGWindowListCopyWindowInfo() lists the windows in the same order.
        NSArray *listed = listedIDs();
        CHECK([listed isEqualToArray:ids], "the window list and the ordered window ids agree");

        // The level order: an unmanaged window of a higher level stays above a managed window ordered to the
        // front, and one of the same level goes behind it.
        id<ToplevelWindow> u = makeWindow("tl-order-u", CGRectMake(400, 300, 200, 150), YES);
        [u setToplevelStacksByLevel:YES];
        [u setToplevelLevel:20];
        [u orderWindow:1 relativeTo:nil];
        listen(0.8);
        [b setToplevelLevel:0];
        [b orderToplevelAbove:nil];
        listen(0.6);
        ids = orderedIDs();
        CHECK(indexOf(ids, u) < indexOf(ids, b), "an unmanaged window of a higher level stays above a window ordered to the front");
        [u setToplevelLevel:0];
        listen(0.3);
        [b orderToplevelAbove:nil];
        listen(0.6);
        ids = orderedIDs();
        CHECK(indexOf(ids, b) < indexOf(ids, u), "an unmanaged window of the same level goes behind a window ordered to the front");
        // Lowering the level of the managed window puts the unmanaged window, which is now of a higher level, in
        // front of it; raising it again puts it back.
        [b setToplevelLevel:-1];
        listen(0.6);
        ids = orderedIDs();
        CHECK(indexOf(ids, u) < indexOf(ids, b), "lowering the level of a window puts an unmanaged window of a higher level in front of it");
        [b setToplevelLevel:5];
        listen(0.6);
        ids = orderedIDs();
        CHECK(indexOf(ids, b) < indexOf(ids, u), "raising the level of a window puts it in front of an unmanaged window of a lower level");
        [b setToplevelLevel:0];
        [u orderWindow:0 relativeTo:nil];
        listen(0.4);
        ids = orderedIDs();
        CHECK(indexOf(ids, u) != NSNotFound, "a window that is ordered out is still known");

        // The keyboard focus.
        heardCount = 0;
        [a requestToplevelKeyboardFocus];
        CHECK(waitForEvent(a, EventFocusGained, -1), "asking for the keyboard focus reports it");
        CHECK([a toplevelHoldsKeyboardFocus], "the window holds the keyboard focus");
        [b requestToplevelKeyboardFocus];
        CHECK(waitForEvent(a, EventFocusLost, -1), "the window that lost the focus reports it");
        CHECK(![a toplevelHoldsKeyboardFocus] && [b toplevelHoldsKeyboardFocus], "the focus is in the other window");

        // Miniaturizing.
        heardCount = 0;
        CHECK(![c toplevelIsMiniaturized], "a shown window is not miniaturized");
        [c miniaturizeToplevel];
        CHECK(waitForEvent(c, EventMiniaturized, -1), "miniaturizing is reported");
        CHECK([c toplevelIsMiniaturized], "the window is miniaturized");
        [c deminiaturizeToplevel];
        CHECK(waitForEvent(c, EventDeminiaturized, -1), "deminiaturizing is reported");
        CHECK(![c toplevelIsMiniaturized], "the window is not miniaturized again");

        // Fullscreen.
        CGRect display = CGDisplayBounds(CGMainDisplayID());
        CHECK([b toplevelFrameCoversDisplay:display], "a frame that is a display's area covers the display");
        CHECK(![b toplevelFrameCoversDisplay:CGRectInset(display, 10, 10)], "a smaller frame does not");
        heardCount = 0;
        CHECK(![b toplevelFullscreenRequested] && ![b toplevelIsFullscreen], "a window is not fullscreen");
        [b setToplevelFullscreen:YES force:NO];
        CHECK([b toplevelFullscreenRequested], "the request is remembered");
        CHECK(waitForEvent(b, EventFullscreenChanged, 1), "entering fullscreen is reported");
        CHECK([b toplevelIsFullscreen], "the window is fullscreen");
        [b setToplevelFullscreen:NO force:NO];
        CHECK(waitForEvent(b, EventFullscreenChanged, 0), "leaving fullscreen is reported");
        CHECK(![b toplevelIsFullscreen] && ![b toplevelFullscreenRequested], "the window is not fullscreen again");
        CHECK(![b toplevelIsOccluded], "nothing covers the window");

        for (id<ToplevelWindow> window in @[a, b, c, u])
            [window setToplevelEventProc:NULL info:NULL];
    }
    printf("RESULT failures=%d\n", failures);
    fflush(stdout);
    return failures == 0 ? 0 : 1;
}
