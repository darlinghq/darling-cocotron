/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// After a menu opened from the menu bar is closed with Escape, or with a second click on its title,
// the menu tracking has ended: the next key press goes to the key window's first responder and the
// next click to the view under the pointer, instead of both being taken by a tracking loop that is
// still running for the bar.
//
//   appkit-menu-dismiss-click SECONDS
//
// The program has a titled window "dismiss-click-host" whose content is a view that does not accept
// first mouse, and a main menu App / File / Edit. It prints, for the host scripts
// appkit-menu-dismiss-click-x11.sh and -wayland.sh to read:
//   READY
//   WHERE bar|strip       the titles are in the application's own menu bar window (positions are
//                         screen pixels from the top left) or in a strip drawn in the window
//                         (positions are from the window's top left)
//   TITLE <index> <x> <y> centre of the titles 0 (App), 1 (File), 2 (Edit)
//   VIEW <x> <y>          centre of the view, in screen pixels from the top left
//   MENUS <n>             the number of menus open
//   DOWN <n> <key>        the view got its n-th mouse down; key is 1 when the window was key
//   TYPED <characters>    the view, the first responder, got a key down
//   KEY <0|1>             the window became or resigned the key window
// The program exits after SECONDS.
#import <AppKit/AppKit.h>
#import "test-argument-words.h"
#include <objc/message.h>
#include <stdio.h>
#include <stdlib.h>

static void say(const char *line) {
    puts(line);
    fflush(stdout);
}

static int openMenus;
static int downs;

@interface ClickView : NSView
@end

@implementation ClickView
- (BOOL) acceptsFirstResponder {
    return YES;
}
- (void) keyDown: (NSEvent *) event {
    printf("TYPED %s\n", [[event characters] UTF8String]);
    fflush(stdout);
}
- (void) mouseDown: (NSEvent *) event {
    printf("DOWN %d %d\n", ++downs, [[self window] isKeyWindow] ? 1 : 0);
    fflush(stdout);
}
@end

@interface Target : NSObject <NSMenuDelegate>
@end

@implementation Target
- (void) menuWillOpen: (NSMenu *) menu {
    printf("MENUS %d\n", ++openMenus);
    fflush(stdout);
}
- (void) menuDidClose: (NSMenu *) menu {
    printf("MENUS %d\n", --openMenus);
    fflush(stdout);
}
- (void) choose: (NSMenuItem *) sender {
}
- (void) keyChanged: (NSNotification *) note {
    say([[note name] isEqualToString: NSWindowDidBecomeKeyNotification] ? "KEY 1" : "KEY 0");
}
@end

static Target *target;

static NSMenu *makeMenu(NSString *title, NSArray *items) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle: title];

    [menu setDelegate: target];
    for (NSString *name in items)
        [[menu addItemWithTitle: name action: @selector(choose:) keyEquivalent: @""] setTarget: target];
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

static BOOL reported;
static NSView *clickView;

// Prints the titles' positions once the menu bar has been laid out (as in appkit-menu-title-click.m).
static void reportTitles(NSWindow *window) {
    NSView *view = nil;
    BOOL bar = NO;

    // The application's own menu bar window: the backend's application menu
    // (X11 and Wayland) owns an NSMenuBarController, which owns the window.
    id barWindow = nil;
    @try {
        id appMenu = [[NSDisplay currentDisplay] valueForKey: @"_appMenu"];
        barWindow = [appMenu valueForKey: @"_bar"];
        if (barWindow != nil && ![barWindow isKindOfClass: [NSWindow class]])
            barWindow = [barWindow valueForKey: @"_bar"];
    } @catch (id e) {
    }
    if (barWindow != nil) {
        view = findView([barWindow contentView], @"NSMainMenuView");
        window = barWindow;
        bar = YES;
    } else {
        view = findView([[window contentView] superview], @"NSMainMenuView");
    }
    if (view == nil)
        return;

    SEL hit = NSSelectorFromString(@"itemIndexAtPoint:rect:");
    CGFloat screenHeight = [[NSScreen mainScreen] frame].size.height;
    NSMutableString *lines = [NSMutableString string];
    int found = 0;

    for (NSUInteger wanted = 0; wanted < 3; wanted++) {
        for (CGFloat x = 0; x < [view bounds].size.width; x += 1) {
            NSRect rect = NSZeroRect;
            NSUInteger index = ((NSUInteger(*)(id, SEL, NSPoint, NSRect *)) objc_msgSend)(
                    view, hit, NSMakePoint(x, 4), &rect);
            if (index != wanted)
                continue;
            NSRect inWindow = [view convertRect: rect toView: nil];
            NSPoint cx = NSMakePoint(NSMidX(inWindow), NSMidY(inWindow));
            if (bar) {
                NSPoint screen = [window convertBaseToScreen: cx];
                [lines appendFormat: @"TITLE %d %d %d\n", (int) wanted, (int) screen.x,
                                     (int) (screenHeight - screen.y)];
            } else {
                [lines appendFormat: @"TITLE %d %d %d\n", (int) wanted, (int) cx.x,
                                     (int) ([window frame].size.height - cx.y)];
            }
            found++;
            break;
        }
    }
    if (found != 3)
        return;
    NSPoint centre = [[clickView window] convertBaseToScreen:
            [clickView convertPoint: NSMakePoint(NSMidX([clickView bounds]), NSMidY([clickView bounds]))
                             toView: nil]];
    say(bar ? "WHERE bar" : "WHERE strip");
    fputs([lines UTF8String], stdout);
    printf("VIEW %d %d\n", (int) centre.x, (int) (screenHeight - centre.y));
    say("READY");
    reported = YES;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        target = [Target new];

        NSMenu *main = [[NSMenu alloc] initWithTitle: @"Main"];
        NSMenuItem *appItem = [main addItemWithTitle: @"App" action: NULL keyEquivalent: @""];
        [appItem setSubmenu: makeMenu(@"App", @[ @"About", @"Quit" ])];
        NSMenuItem *file = [main addItemWithTitle: @"File" action: NULL keyEquivalent: @""];
        [file setSubmenu: makeMenu(@"File", @[ @"New", @"Open", @"Close" ])];
        NSMenuItem *edit = [main addItemWithTitle: @"Edit" action: NULL keyEquivalent: @""];
        [edit setSubmenu: makeMenu(@"Edit", @[ @"Cut", @"Copy", @"Paste" ])];
        [NSApp setMainMenu: main];

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(300, 300, 400, 300)
                                                       styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window setTitle: @"dismiss-click-host"];
        clickView = [[ClickView alloc] initWithFrame: [[window contentView] bounds]];
        [clickView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
        [[window contentView] addSubview: clickView];
        [[NSNotificationCenter defaultCenter] addObserver: target
                                                 selector: @selector(keyChanged:)
                                                     name: NSWindowDidBecomeKeyNotification
                                                   object: window];
        [[NSNotificationCenter defaultCenter] addObserver: target
                                                 selector: @selector(keyChanged:)
                                                     name: NSWindowDidResignKeyNotification
                                                   object: window];
        [window makeKeyAndOrderFront: nil];
        [window makeFirstResponder: clickView];
        [NSApp activateIgnoringOtherApps: YES];

        [NSTimer scheduledTimerWithTimeInterval: 0.05 repeats: YES block: ^(NSTimer *t) {
            if (!reported)
                reportTitles(window);
        }];
        double seconds = argc > 1 ? atof(argv[1]) : 60;
        [NSTimer scheduledTimerWithTimeInterval: seconds repeats: NO block: ^(NSTimer *t) {
            exit(0);
        }];
        TestIgnoreArgumentWords();
        [NSApp run];
    }
    return 0;
}
