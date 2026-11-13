/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Guest side of the global application menu tests (see
// appkit-global-menu/README.md). It builds a main menu with a floating panel
// as the only window, and logs what happens to a file the host script reads:
//
//   appkit-global-menu LOG panel [SECONDS]
//                                  run until the Quit item is chosen, or for
//                                  SECONDS (default 120)
//   appkit-global-menu LOG strip   print whether titled windows and panels
//                                  carry the in-window menu strip, and exit
//
// A line "READY" is logged once the application is active and the menu is set.
#import <AppKit/AppKit.h>
#include <objc/message.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

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

@interface Target : NSObject <NSMenuDelegate>
{
    NSMenu *_dynamic;
    int _updates;
}
@property (assign) NSMenu *fileMenu;
@end

@implementation Target
- (void) newDoc: (id) sender {
    note("action newDoc mainthread=%d", (int) [NSThread isMainThread]);
}
- (void) save: (id) sender {
    note("action save");
}
- (void) disabledAction: (id) sender {
    note("action disabledAction");
}
- (void) checked: (id) sender {
    note("action checked");
}
- (void) dynamicItem: (id) sender {
    note("action dynamicItem %s", [[(NSMenuItem *) sender title] UTF8String]);
}
- (void) addItem: (id) sender {
    NSMenuItem *item = [self.fileMenu addItemWithTitle: @"Added item" action: @selector(newDoc:) keyEquivalent: @""];
    [item setTarget: self];
    note("action addItem");
}
- (void) quitNow: (id) sender {
    note("action quit");
    exit(0);
}
- (BOOL) validateMenuItem: (NSMenuItem *) item {
    if ([item action] == @selector(disabledAction:)) {
        note("validate disabledAction");
        return NO;
    }
    return YES;
}
- (void) setDynamic: (NSMenu *) menu {
    _dynamic = menu;
    [menu setDelegate: self];
}
- (void) menuNeedsUpdate: (NSMenu *) menu {
    if (menu != _dynamic)
        return;
    note("needsUpdate Dynamic");
    [menu removeAllItems];
    NSMenuItem *item = [menu addItemWithTitle: [NSString stringWithFormat: @"Dynamic %d", ++_updates]
                                       action: @selector(dynamicItem:)
                                keyEquivalent: @""];
    [item setTarget: self];
}
- (void) menuWillOpen: (NSMenu *) menu {
    if (menu == _dynamic)
        note("willOpen Dynamic");
}
- (void) menuDidClose: (NSMenu *) menu {
    if (menu == _dynamic)
        note("didClose Dynamic");
}
- (void) applicationDidFinishLaunching: (NSNotification *) n {
    note("READY active=%d", (int) [NSApp isActive]);
    [self performSelector: @selector(reportBar) withObject: nil afterDelay: 1.0];
}
// Logs where the items of the application's own menu bar are (the middle of
// each, in screen pixels from the top left), for a host script that clicks on
// them. The bar is not reachable through public API, so this looks for it
// through the display and the view it contains.
- (void) reportBar {
    id appMenu = [[NSDisplay currentDisplay] respondsToSelector: @selector(appMenu)]
                         ? [(id) [NSDisplay currentDisplay] performSelector: @selector(appMenu)]
                         : nil;
    NSWindow *bar = nil;

    @try {
        bar = [appMenu valueForKey: @"_bar"];
    } @catch (id e) {
    }
    NSView *view = [bar contentView];
    SEL hit = NSSelectorFromString(@"itemIndexAtPoint:rect:");

    view = [[view subviews] firstObject];
    if (bar == nil || view == nil || ![view respondsToSelector: hit]) {
        note("bar none");
        return;
    }

    NSUInteger last = NSNotFound;
    CGFloat screenHeight = [[NSScreen mainScreen] frame].size.height;
    for (CGFloat x = 0; x < [view bounds].size.width; x += 1) {
        NSRect rect = NSZeroRect;
        NSUInteger index = ((NSUInteger(*)(id, SEL, NSPoint, NSRect *)) objc_msgSend)(
                view, hit, NSMakePoint(x, 4), &rect);
        if (index != NSNotFound && index != last) {
            NSRect screen = [view convertRect: rect toView: nil];
            screen.origin = [bar convertBaseToScreen: screen.origin];
            note("bar item %lu x=%d y=%d", (unsigned long) index,
                 (int) NSMidX(screen), (int) (screenHeight - NSMidY(screen)));
            last = index;
        }
    }
    note("bar frame x=%d y=%d width=%d height=%d", (int) [bar frame].origin.x,
         (int) (screenHeight - NSMaxY([bar frame])), (int) [bar frame].size.width,
         (int) [bar frame].size.height);
}
@end

static NSMenuItem *submenuItem(NSMenu *parent, NSString *title, NSMenu **submenu) {
    NSMenuItem *item = [parent addItemWithTitle: title action: NULL keyEquivalent: @""];
    *submenu = [[NSMenu alloc] initWithTitle: title];
    [item setSubmenu: *submenu];
    return item;
}

static void buildMenu(Target *target) {
    NSMenu *main = [[NSMenu alloc] initWithTitle: @"Main"];
    NSMenu *app, *file;
    NSMenuItem *item;

    submenuItem(main, @"AppItem", &app);
    item = [app addItemWithTitle: @"About Test" action: @selector(save:) keyEquivalent: @""];
    [item setTarget: target];
    [app addItem: [NSMenuItem separatorItem]];
    item = [app addItemWithTitle: @"Quit Test" action: @selector(quitNow:) keyEquivalent: @"q"];
    [item setTarget: target];

    submenuItem(main, @"File", &file);
    target.fileMenu = file;
    item = [file addItemWithTitle: @"New_Doc" action: @selector(newDoc:) keyEquivalent: @"n"];
    [item setTarget: target];
    item = [file addItemWithTitle: @"Save" action: @selector(save:) keyEquivalent: @"s"];
    [item setKeyEquivalentModifierMask: NSEventModifierFlagCommand | NSEventModifierFlagShift];
    [item setTarget: target];
    item = [file addItemWithTitle: @"Disabled" action: @selector(disabledAction:) keyEquivalent: @""];
    [item setTarget: target];
    [file addItem: [NSMenuItem separatorItem]];
    item = [file addItemWithTitle: @"Hidden" action: @selector(save:) keyEquivalent: @""];
    [item setTarget: target];
    [item setHidden: YES];
    item = [file addItemWithTitle: @"Checked" action: @selector(checked:) keyEquivalent: @""];
    [item setTarget: target];
    [item setState: NSControlStateValueOn];
    NSMenu *dynamic;
    submenuItem(file, @"Dynamic", &dynamic);
    [target setDynamic: dynamic];
    item = [file addItemWithTitle: @"Add Item" action: @selector(addItem:) keyEquivalent: @""];
    [item setTarget: target];

    [NSApp setMainMenu: main];
}

// -[NSWindow hasMainMenu] is Cocotron's, not part of AppKit's API.
static BOOL hasMainMenu(NSWindow *window) {
    SEL sel = NSSelectorFromString(@"hasMainMenu");
    if (![window respondsToSelector: sel])
        return NO;
    return ((BOOL(*)(id, SEL)) objc_msgSend)(window, sel);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "usage: %s LOG panel|strip\n", argv[0]);
            return 2;
        }
        logFile = fopen(argv[1], "a");
        if (logFile == NULL)
            return 2;

        [NSApplication sharedApplication];
        Target *target = [Target new];
        buildMenu(target);

        if (!strcmp(argv[2], "strip")) {
            NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                                           styleMask: NSWindowStyleMaskTitled
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO];
            NSPanel *panel = [[NSPanel alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                                        styleMask: NSWindowStyleMaskTitled
                                                          backing: NSBackingStoreBuffered
                                                            defer: NO];
            NSRect frame = [NSWindow frameRectForContentRect: NSMakeRect(0, 0, 300, 200)
                                                   styleMask: NSWindowStyleMaskTitled];
            note("strip window=%d panel=%d extraFrameHeight=%d", (int) hasMainMenu(window),
                 (int) hasMainMenu(panel), (int) (frame.size.height - 200));
            return 0;
        }

        [NSApp setDelegate: target];
        NSPanel *panel = [[NSPanel alloc] initWithContentRect: NSMakeRect(400, 400, 240, 60)
                                                    styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskUtilityWindow
                                                      backing: NSBackingStoreBuffered
                                                        defer: NO];
        [panel setTitle: @"Panel"];
        [panel setFloatingPanel: YES];
        [panel setHidesOnDeactivate: NO];
        [panel orderFront: nil];

        // A bounded run, in case the host script goes away.
        int lifetime = argc > 3 ? atoi(argv[3]) : 120;
        [NSTimer scheduledTimerWithTimeInterval: lifetime repeats: NO block: ^(NSTimer *t) {
            note(argc > 3 ? "done" : "timeout");
            exit(argc > 3 ? 0 : 3);
        }];
        [NSApp run];
    }
    return 0;
}
