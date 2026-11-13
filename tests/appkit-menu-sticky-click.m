/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Guest side of the "click, then click an item" menu test (see
// appkit-global-menu/run-sticky.py). A menu opened with a click that is
// released at once stays open; clicking an item then chooses it, and the
// application does not deactivate while its own menu is open.
//
//   appkit-menu-sticky-click LOG MODE
//
// MODE is bar (a panel only: the application's own menu bar window is used),
// strip (a titled window; the host script sets DarlingInWindowMenuBar so that it
// carries the in-window menu strip), popup (a pop-up
// button) or context (a view with a context menu). It logs lines the host
// script reads:
//   READY
//   trigger X Y     where to click to open the menu, in screen pixels from the
//                   top left
//   chose TITLE     an item was chosen
//   resigned        the application resigned active while it was running
#import <AppKit/AppKit.h>
#include <objc/message.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static FILE *logFile;

static void note(const char *format, ...) __attribute__((format(printf, 1, 2)));
static void note(const char *format, ...) {
    va_list args;

    va_start(args, format);
    vfprintf(logFile, format, args);
    va_end(args);
    fputc('\n', logFile);
    fflush(logFile);
}

static NSString *mode;

@interface ContextView : NSView
@end

@implementation ContextView
- (void) rightMouseDown: (NSEvent *) event {
    [NSMenu popUpContextMenu: [self menu] withEvent: event forView: self];
}
@end

@interface Target : NSObject <NSApplicationDelegate>
@end

@implementation Target
- (void) chose: (id) sender {
    note("chose %s", [[(NSMenuItem *) sender title] UTF8String]);
}
- (void) quit: (id) sender {
    exit(0);
}
- (void) appResigned: (NSNotification *) n {
    note("resigned");
}
- (void) applicationDidFinishLaunching: (NSNotification *) n {
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(appResigned:)
                                                 name: NSApplicationDidResignActiveNotification
                                               object: nil];
    [self performSelector: @selector(report) withObject: nil afterDelay: 1.0];
}
- (void) report {
    note("READY active=%d", (int) [NSApp isActive]);
}
@end

static Target *target;

static NSMenu *threeItems(NSString *title) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle: title];

    for (NSString *name in @[ @"Alpha", @"Beta", @"Gamma" ]) {
        NSMenuItem *item = [menu addItemWithTitle: name action: @selector(chose:) keyEquivalent: @""];
        [item setTarget: target];
    }
    return menu;
}

static NSView *findView(NSView *view, NSString *className) {
    if ([NSStringFromClass([view class]) isEqualToString: className])
        return view;
    for (NSView *sub in [view subviews]) {
        NSView *found = findView(sub, className);
        if (found != nil)
            return found;
    }
    return nil;
}

// The point to click for item INDEX of an NSMainMenuView, in screen pixels
// from the top left.
static BOOL reportMainMenuItem(NSWindow *window, NSView *view, NSUInteger wanted) {
    SEL hit = NSSelectorFromString(@"itemIndexAtPoint:rect:");
    CGFloat screenHeight = [[NSScreen mainScreen] frame].size.height;

    for (CGFloat x = 0; x < [view bounds].size.width; x += 1) {
        NSRect rect = NSZeroRect;
        NSUInteger index = ((NSUInteger(*)(id, SEL, NSPoint, NSRect *)) objc_msgSend)(
                view, hit, NSMakePoint(x, 4), &rect);
        if (index == wanted) {
            NSRect inWindow = [view convertRect: rect toView: nil];
            NSPoint screen = [window convertBaseToScreen: inWindow.origin];
            note("trigger %d %d", (int) (screen.x + inWindow.size.width / 2),
                 (int) (screenHeight - screen.y - inWindow.size.height / 2));
            return YES;
        }
    }
    return NO;
}

static void reportViewCenter(NSView *view) {
    NSRect inWindow = [view convertRect: [view bounds] toView: nil];
    NSPoint screen = [[view window] convertBaseToScreen: inWindow.origin];
    CGFloat screenHeight = [[NSScreen mainScreen] frame].size.height;

    note("trigger %d %d", (int) (screen.x + inWindow.size.width / 2),
         (int) (screenHeight - screen.y - inWindow.size.height / 2));
}

static BOOL barReported;

@interface Reporter : NSObject
+ (void) bar;
+ (void) strip: (NSWindow *) window;
@end

@implementation Reporter
+ (void) bar {
    id appMenu = [[NSDisplay currentDisplay] respondsToSelector: @selector(appMenu)]
                         ? [(id) [NSDisplay currentDisplay] performSelector: @selector(appMenu)]
                         : nil;
    NSWindow *bar = nil;

    @try {
        bar = [appMenu valueForKey: @"_bar"];
    } @catch (id e) {
    }
    NSView *view = [[[bar contentView] subviews] firstObject];
    if (view == nil)
        return;
    // The items have a position once the bar has been laid out: until then,
    // the timer tries again.
    barReported = reportMainMenuItem(bar, view, 1);
}
+ (void) strip: (NSWindow *) window {
    NSView *view = findView([[window contentView] superview], @"NSMainMenuView");
    if (view == nil) {
        note("strip none");
        return;
    }
    reportMainMenuItem(window, view, 1);
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "usage: %s LOG bar|strip|popup|context\n", argv[0]);
            return 2;
        }
        logFile = fopen(argv[1], "a");
        if (logFile == NULL)
            return 2;
        mode = [NSString stringWithUTF8String: argv[2]];

        [NSApplication sharedApplication];
        target = [Target new];

        NSMenu *main = [[NSMenu alloc] initWithTitle: @"Main"];
        NSMenuItem *appItem = [main addItemWithTitle: @"App" action: NULL keyEquivalent: @""];
        NSMenu *appMenu = [[NSMenu alloc] initWithTitle: @"App"];
        NSMenuItem *quit = [appMenu addItemWithTitle: @"Quit" action: @selector(quit:) keyEquivalent: @"q"];
        [quit setTarget: target];
        [appItem setSubmenu: appMenu];
        NSMenuItem *testItem = [main addItemWithTitle: @"Test" action: NULL keyEquivalent: @""];
        [testItem setSubmenu: threeItems(@"Test")];
        [NSApp setMainMenu: main];
        [NSApp setDelegate: target];

        NSWindow *window = nil;
        if ([mode isEqualToString: @"bar"]) {
            NSPanel *panel = [[NSPanel alloc] initWithContentRect: NSMakeRect(600, 500, 240, 80)
                                                        styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskUtilityWindow
                                                          backing: NSBackingStoreBuffered
                                                            defer: NO];
            [panel setFloatingPanel: YES];
            [panel setHidesOnDeactivate: NO];
            [panel orderFront: nil];
            // The bar is shown once the application is active.
            [NSTimer scheduledTimerWithTimeInterval: 0.5 repeats: YES block: ^(NSTimer *t) {
                if (barReported)
                    [t invalidate];
                else
                    [Reporter bar];
            }];
        } else {
            window = [[NSWindow alloc] initWithContentRect: NSMakeRect(600, 500, 320, 200)
                                                 styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                   backing: NSBackingStoreBuffered
                                                     defer: NO];
            [window setTitle: @"Sticky"];
            NSView *content = [window contentView];
            if ([mode isEqualToString: @"popup"]) {
                NSPopUpButton *button = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(40, 80, 120, 26)
                                                                   pullsDown: NO];
                [button setMenu: threeItems(@"Popup")];
                [content addSubview: button];
                [window makeKeyAndOrderFront: nil];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                    reportViewCenter(button);
                });
            } else if ([mode isEqualToString: @"context"]) {
                ContextView *view = [[ContextView alloc] initWithFrame: NSMakeRect(20, 20, 280, 120)];
                [view setMenu: threeItems(@"Context")];
                [content addSubview: view];
                [window makeKeyAndOrderFront: nil];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                    reportViewCenter(view);
                });
            } else {
                [window makeKeyAndOrderFront: nil];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                    [Reporter strip: window];
                });
            }
        }

        // A bounded run, in case the host script goes away.
        [NSTimer scheduledTimerWithTimeInterval: 60 repeats: NO block: ^(NSTimer *t) {
            note("timeout");
            exit(3);
        }];
        [NSApp run];
    }
    return 0;
}
