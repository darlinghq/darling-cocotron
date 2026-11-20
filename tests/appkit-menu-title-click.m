/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Clicking the title of the open main-menu-bar menu closes that menu; clicking
// another title switches to its menu; clicking elsewhere closes the open menu;
// pressing a title and releasing over an item of its menu chooses the item.
//
//   appkit-menu-title-click SECONDS
//
// The program has a window and a main menu App / File / Edit and prints, for
// the host scripts appkit-menu-title-click-x11.sh and -wayland.sh to read:
//   READY
//   WHERE bar|strip       the titles are in the application's own menu bar
//                         window (positions are screen pixels from the top
//                         left) or in a strip drawn in the window "title-click-host"
//                         (positions are from the window's top left)
//   TITLE <index> <x> <y> centre of the titles 0 (App), 1 (File), 2 (Edit)
//   OPEN <title>          -menuWillOpen: of a menu's delegate
//   CLOSED <title>        -menuDidClose:
//   MENUS <n>             the number of menus open (OPENs minus CLOSEDs)
//   CHOSE <title>         a menu item was chosen
// The program exits after SECONDS.
#import <AppKit/AppKit.h>
#include <objc/message.h>
#include <stdio.h>
#include <stdlib.h>

static void say(const char *line) {
    puts(line);
    fflush(stdout);
}

static int openMenus;

@interface Target : NSObject <NSMenuDelegate>
@end

@implementation Target
- (void) menuWillOpen: (NSMenu *) menu {
    printf("OPEN %s\n", [[menu title] UTF8String]);
    printf("MENUS %d\n", ++openMenus);
    fflush(stdout);
}
- (void) menuDidClose: (NSMenu *) menu {
    printf("CLOSED %s\n", [[menu title] UTF8String]);
    printf("MENUS %d\n", --openMenus);
    fflush(stdout);
}
- (void) choose: (NSMenuItem *) sender {
    printf("CHOSE %s\n", [[sender title] UTF8String]);
    fflush(stdout);
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

// Prints the titles' positions once the menu bar has been laid out.
static void reportTitles(NSWindow *window) {
    NSView *view = nil;
    BOOL bar = NO;

    // The application's own menu bar window (the X11 default), found through
    // the display; otherwise the strip in the window.
    id appMenu = [[NSDisplay currentDisplay] respondsToSelector: @selector(appMenu)]
                         ? [(id) [NSDisplay currentDisplay] performSelector: @selector(appMenu)]
                         : nil;
    NSWindow *barWindow = nil;
    @try {
        barWindow = [appMenu valueForKey: @"_bar"];
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
    say(bar ? "WHERE bar" : "WHERE strip");
    fputs([lines UTF8String], stdout);
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
        [window setTitle: @"title-click-host"];
        [window makeKeyAndOrderFront: nil];
        [NSApp activateIgnoringOtherApps: YES];

        [NSTimer scheduledTimerWithTimeInterval: 0.05 repeats: YES block: ^(NSTimer *t) {
            if (!reported)
                reportTitles(window);
        }];
        double seconds = argc > 1 ? atof(argv[1]) : 60;
        [NSTimer scheduledTimerWithTimeInterval: seconds repeats: NO block: ^(NSTimer *t) {
            exit(0);
        }];
        [NSApp run];
    }
    return 0;
}
