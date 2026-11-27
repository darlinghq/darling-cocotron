/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// The order, the parent relation, the keyboard focus, miniaturizing and fullscreen of toplevel windows of the UI layer
// (CGSWindow.h) on the Wayland backend, without AppKit (the program links only CoreGraphics and Foundation): the windows are
// made, drawn into, shown and ordered through CoreGraphics, the order they have is read back through
// _CGSOrderedToplevelWindowIDs() and CGWindowListCopyWindowInfo(), which must agree, and what the compositor reports of the
// windows is recorded through the windows' event handlers. Needs a Wayland compositor (WAYLAND_DISPLAY) with
// DARLING_APPKIT_BACKEND=wayland.
// Usage: coregraphics-wayland-toplevel-ordering
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
    EventParentLost = 21,
    EventFullscreenSettled = 22,
};
typedef struct {
    int width, height, popupX, popupY;
    bool activated, maximized, fullscreen, suspended, minimizeAdvertised, decorationReported, clientDecorated;
} ToplevelConfigure;
typedef struct {
    int kind;
    CGRect rect;
    bool resized;
    CGFloat oldScale;
    bool state;
    CFStringRef text;
    CFRange textRange;
    ToplevelConfigure configure;
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
- (CGError)drawImage:(CGImageRef)image atPoint:(CGPoint)origin;
- (unsigned)windowId;
- (CGError)setToplevelLevel:(int)level;
- (CGError)setToplevelStacksByLevel:(BOOL)stacks;
- (CGError)orderToplevelAbove:(id)sibling;
- (CGError)orderToplevelBelow:(id)sibling;
- (BOOL)toplevelHoldsKeyboardFocus;
- (CGError)miniaturizeToplevel;
- (CGError)deminiaturizeToplevel;
- (BOOL)toplevelIsMiniaturized;
- (CGError)setToplevelFullscreen:(BOOL)fullscreen force:(BOOL)force;
- (BOOL)toplevelFullscreenRequested;
- (BOOL)toplevelIsFullscreen;
- (BOOL)toplevelFullscreenSettling;
- (BOOL)toplevelIsOccluded;
- (CGError)setToplevelParent:(id)parent;
- (id)toplevelParent;
- (CGError)setToplevelHeldBack:(BOOL)heldBack;
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

#define MAX_EVENTS 512
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

static id<ToplevelWindow> makeWindow(const char *title, CGRect frame) {
    id<ToplevelWindow> (*newToplevel)(const ToplevelAttributes *) = dlsym(RTLD_DEFAULT, "_CGSNewToplevelWindow");
    ToplevelAttributes attributes = {frame, false, false};
    id<ToplevelWindow> window = newToplevel(&attributes);
    [window setToplevelEventProc:record info:NULL];
    [window setProperty:CFSTR("WindowTitle") value:[NSString stringWithUTF8String:title]];
    return window;
}

static NSArray *orderedIDs(void) {
    NSArray *(*ordered)(void) = dlsym(RTLD_DEFAULT, "_CGSOrderedToplevelWindowIDs");
    return ordered != NULL ? ordered() : nil;
}

static NSArray *listedIDs(void) {
    NSMutableArray *result = [NSMutableArray array];
    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID);
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

static void show(id<ToplevelWindow> window) {
    [window orderWindow:1 relativeTo:nil];
    draw(window, 300, 200);
    listen(0.5);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        id<ToplevelWindow> a = makeWindow("tl-order-a", CGRectMake(100, 100, 300, 200));
        if (a == nil) {
            printf("SKIP: this window system makes no toplevel windows\n");
            return 0;
        }
        CHECK(dlsym(RTLD_DEFAULT, "_CGSOrderedToplevelWindowIDs") != NULL, "the ordered window ids are available");
        id<ToplevelWindow> b = makeWindow("tl-order-b", CGRectMake(200, 150, 300, 200));
        id<ToplevelWindow> c = makeWindow("tl-order-c", CGRectMake(300, 200, 300, 200));
        id<ToplevelWindow> d = makeWindow("tl-order-d", CGRectMake(400, 250, 300, 200));

        // Only the windows that are ordered in are listed.
        CHECK([orderedIDs() count] == 0, "windows that are not ordered in are not listed");
        for (id<ToplevelWindow> window in @[a, b, c])
            [window setToplevelStacksByLevel:YES];
        show(a);
        show(b);
        show(c);
        listen(0.5);
        NSArray *ids = orderedIDs();
        CHECK([ids count] == 3, "the three shown windows are listed");

        // A window held back from the compositor counts as ordered in, and is not one of the compositor's.
        [d setToplevelHeldBack:YES];
        ids = orderedIDs();
        CHECK([ids count] == 4 && indexOf(ids, d) != NSNotFound, "a window that is held back is listed");
        [d setToplevelHeldBack:NO];
        ids = orderedIDs();
        CHECK([ids count] == 3 && indexOf(ids, d) == NSNotFound, "a window that is not held back any more is not");

        // The order follows the activation and the requests to come to the front. The compositor decides how its windows
        // stack, so ordering behind a window, or relative to one, cannot be asked for.
        [a orderToplevelAbove:nil];
        ids = orderedIDs();
        CHECK(indexOf(ids, a) == 0, "a window ordered to the front is the first");
        [b orderToplevelAbove:nil];
        ids = orderedIDs();
        CHECK(indexOf(ids, b) == 0 && indexOf(ids, a) == 1, "the window ordered to the front last comes first");
        CHECK([c orderToplevelBelow:nil] != kCGErrorSuccess, "ordering to the back cannot be asked for");
        CHECK([c orderToplevelAbove:a] != kCGErrorSuccess, "ordering relative to another window cannot be asked for");
        CHECK([c setToplevelLevel:3] == kCGErrorSuccess && [c setToplevelStacksByLevel:YES] == kCGErrorSuccess,
              "the level is taken");
        CHECK([listedIDs() isEqualToArray:orderedIDs()] ||
                      [[listedIDs() subarrayWithRange:NSMakeRange(0, 3)] isEqualToArray:orderedIDs()],
              "the window list starts with the ordered window ids");

        // The keyboard focus is the compositor's: no more than one window of the process holds it.
        int holders = 0;
        for (id<ToplevelWindow> window in @[a, b, c])
            holders += [window toplevelHoldsKeyboardFocus];
        CHECK(holders <= 1, "at most one window holds the keyboard focus");
        int gained = 0, lost = 0;
        for (id<ToplevelWindow> window in @[a, b, c]) {
            gained += count(window, EventFocusGained, -1);
            lost += count(window, EventFocusLost, -1);
        }
        CHECK(gained - lost == holders, "the focus events add up to what the windows hold");

        // The parent relation.
        CHECK([b toplevelParent] == nil, "a window has no parent");
        CHECK([b setToplevelParent:a] == kCGErrorSuccess && [b toplevelParent] == a, "a window takes a parent");
        CHECK([a setToplevelParent:b] != kCGErrorSuccess && [a toplevelParent] == nil,
              "a window is not made a child of its own child");
        CHECK([b setToplevelParent:b] != kCGErrorSuccess, "a window is not its own parent");
        CHECK([b setToplevelParent:d] != kCGErrorSuccess && [b toplevelParent] == a,
              "a window that is not shown is not taken as a parent");
        CHECK([b setToplevelParent:nil] == kCGErrorSuccess && [b toplevelParent] == nil, "the parent is taken away");
        [c setToplevelParent:a];
        heardCount = 0;
        [a orderWindow:0 relativeTo:nil];
        listen(0.5);
        CHECK(count(c, EventParentLost, -1) == 1 && [c toplevelParent] == nil, "hiding the parent ends the relation");
        CHECK([orderedIDs() count] == 2 && indexOf(orderedIDs(), a) == NSNotFound, "a hidden window is not listed");
        show(a);

        // Fullscreen.
        heardCount = 0;
        CHECK(![b toplevelFullscreenRequested] && ![b toplevelIsFullscreen], "a window is not fullscreen");
        [b setToplevelFullscreen:YES force:NO];
        CHECK([b toplevelFullscreenRequested], "the request is remembered");
        CHECK(waitForEvent(b, EventFullscreenChanged, 1), "entering fullscreen is reported");
        CHECK([b toplevelIsFullscreen], "the window is fullscreen");
        CHECK(waitForEvent(b, EventFullscreenSettled, -1) && ![b toplevelFullscreenSettling],
              "the compositor's answer ends the wait for it");
        heardCount = 0;
        [b setToplevelFullscreen:NO force:NO];
        CHECK(waitForEvent(b, EventFullscreenChanged, 0), "leaving fullscreen is reported");
        CHECK(![b toplevelIsFullscreen] && ![b toplevelFullscreenRequested], "the window is not fullscreen again");
        CHECK(![b toplevelIsOccluded], "nothing covers the window");

        // Minimizing: the compositor decides whether it minimizes at all, and the window is shown again by asking for its
        // activation, so the checks are about what the window says of itself.
        heardCount = 0;
        CHECK(![c toplevelIsMiniaturized], "a shown window is not miniaturized");
        [c miniaturizeToplevel];
        listen(0.5);
        if ([c toplevelIsMiniaturized]) {
            CHECK(count(c, EventMiniaturized, -1) == 1, "miniaturizing is reported");
            [c deminiaturizeToplevel];
            CHECK(![c toplevelIsMiniaturized], "the window is shown again by the request");
            CHECK(waitForEvent(c, EventDeminiaturized, -1), "deminiaturizing is reported");
        } else {
            CHECK(count(c, EventMiniaturized, -1) == 0, "a compositor that does not minimize leaves the window as it is");
        }

        for (id<ToplevelWindow> window in @[a, b, c, d])
            [window setToplevelEventProc:NULL info:NULL];
    }
    printf("RESULT failures=%d\n", failures);
    fflush(stdout);
    return failures == 0 ? 0 : 1;
}
