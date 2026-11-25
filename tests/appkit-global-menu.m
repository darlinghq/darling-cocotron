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
//   appkit-global-menu LOG window [SECONDS]
//                                  like panel, with a titled window instead,
//                                  and log whether it carries the strip
//   appkit-global-menu LOG borderless [SECONDS]
//                                  like window, with a borderless window
//   appkit-global-menu LOG nowindow [SECONDS]
//                                  like window, with no window at all
//   appkit-global-menu LOG swap [SECONDS]
//                                  like nowindow; a titled window is shown from
//                                  the 5th second and closed at the 10th,
//                                  logging "STEP window opened" and
//                                  "STEP window closed"
//   appkit-global-menu LOG owner [SECONDS [HELPER [HELPERMODE]]]
//                                  a regular application with a main menu and
//                                  no window but an offscreen borderless one;
//                                  from the 3rd second it starts the program
//                                  HELPER (a path, possibly the executable of an
//                                  LSUIElement bundle) with its own log
//                                  (LOG.helper) and the mode HELPERMODE
//                                  (default "helper")
//   appkit-global-menu LOG helper [SECONDS]
//                                  an application with a titled window that it
//                                  makes key and active; "helper-accessory"
//                                  first switches to the accessory activation
//                                  policy; it exits after SECONDS, or when the
//                                  file LOG.quit exists
//   appkit-global-menu LOG hiding  with a titled window as the key window, go
//                                  through the states in which the menu bar is
//                                  hidden or shown, logging "STEP <state>" after
//                                  each change and waiting for the host to look
//
//   appkit-global-menu LOG policy  logs "RUNNING policy=P url=U" (NSRunningApplication's activation
//                                  policy and bundle URL for this process) and "NSAPP policy=P", then
//                                  exits: what the bundle layout on disk decides
//   appkit-global-menu LOG bundled [SECONDS]
//                                  like borderless, but keeps the activation policy the bundle (or its
//                                  absence) gives, as an application that never sets one
//   appkit-global-menu LOG parent [SECONDS [DELAYMS]]
//                                  like borderless; DELAYMS (default 0) after the menu bar is
//                                  ordered in it starts this program again in the mode "windowless"
//                                  (LOG.child), a process outside any bundle with no window and no
//                                  menu that activates itself, logging "STEP child launched"
//   appkit-global-menu LOG windowless [SECONDS]
//                                  an AppKit process with no window that activates itself (at start
//                                  and every half second); logs "POLICY"
//   appkit-global-menu LOG startup [SECONDS [DELAYMS]]
//                                  like borderless; DELAYMS after the menu bar is ordered in the
//                                  window is closed, logging "STEP window closed"
//
// Every mode also logs "OWNER owner=O front=F" (O: NSWorkspace's
// menuBarOwningApplication is this process; F: frontmostApplication is "self",
// "other" or "none") whenever the pair changes, and "KVO owner" when the
// menuBarOwningApplication property is observed to change.
//
// Every mode logs "STATE active=A bar=B windows=W" whenever one of the values
// changes (A: the application is active, B: its menu bar window is ordered in,
// W: visible windows that carry the in-window menu strip), and "ACTIVE" and
// "RESIGN" for the activation notifications.
//
// A line "READY" is logged once the application is active and the menu is set.
#import <AppKit/AppKit.h>
#import "test-argument-words.h"
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
    NSMenu *_rebuilt;
    BOOL _rebuildOnOpen;
    NSMenu *_fileMenu;
    int _updates;
}
- (NSMenu *) fileMenu;
- (void) setFileMenu: (NSMenu *) menu;
@end

@implementation Target
// The program's own arguments (a log path, a mode) are not documents: taking them here ends the alert the document
// controller would show for each of them, as on macOS.
- (void) application: (NSApplication *) application openFiles: (NSArray *) files {
}
- (void) preferences: (id) sender {
    note("action preferences active=%d key=%d", (int) [NSApp isActive], (int) ([NSApp keyWindow] != nil));
}
- (void) newDoc: (id) sender {
    note("action newDoc mainthread=%d", (int) [NSThread isMainThread]);
}
- (void) save: (id) sender {
    note("action save active=%d key=%d", (int) [NSApp isActive], (int) ([NSApp keyWindow] != nil));
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
    NSMenuItem *item = [_fileMenu addItemWithTitle: @"Added item" action: @selector(newDoc:) keyEquivalent: @""];
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
- (NSMenu *) fileMenu {
    return _fileMenu;
}
- (void) setFileMenu: (NSMenu *) menu {
    _fileMenu = menu;
    [menu setDelegate: self];
}
// The File menu reports when it opens and closes and which item is highlighted, for the
// menu bar tracking tests (run-bar-tracking.py).
- (void) menu: (NSMenu *) menu willHighlightItem: (NSMenuItem *) item {
    if (menu == _fileMenu)
        note("highlight File %s", item == nil ? "(none)" : [[item title] UTF8String]);
}
// The application menu is filled again with new items; the quit item is the usual terminate:.
- (void) refillRebuilt {
    NSMenu *menu = _rebuilt;
    [menu removeAllItems];
    NSMenuItem *item = [menu addItemWithTitle: @"Preferences..." action: @selector(preferences:) keyEquivalent: @","];
    [item setTarget: self];
    item = [menu addItemWithTitle: @"Targeted" action: @selector(save:) keyEquivalent: @""];
    [item setTarget: self];
    [menu addItemWithTitle: @"Hide Test" action: @selector(hide:) keyEquivalent: @"h"];
    [menu addItemWithTitle: @"Quit Test" action: @selector(terminate:) keyEquivalent: @"q"];
}
- (void) setRebuilt: (NSMenu *) menu {
    _rebuilt = menu;
    _rebuildOnOpen = YES;
}
- (void) menuNeedsUpdate: (NSMenu *) menu {
    if (menu == _rebuilt) {
        note("needsUpdate rebuilt");
        [self refillRebuilt];
        return;
    }
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
    if (menu == _rebuilt && _rebuildOnOpen) {
        note("willOpen rebuilt");
        [self refillRebuilt];
    }
    if (menu == _dynamic)
        note("willOpen Dynamic");
    if (menu == _fileMenu)
        note("willOpen File");
}
- (void) menuDidClose: (NSMenu *) menu {
    if (menu == _dynamic)
        note("didClose Dynamic");
    if (menu == _fileMenu)
        note("didClose File");
}
- (void) observeValueForKeyPath: (NSString *) path ofObject: (id) object change: (NSDictionary *) change
                        context: (void *) context {
    note("KVO owner");
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
    id display = [NSDisplay currentDisplay];
    id appMenu = nil;
    NSWindow *bar = nil;

    // The display holds the object that owns the bar (X11AppMenu, WaylandAppMenu), which holds the
    // NSMenuBarController, which holds the bar window.
    @try {
        appMenu = [display valueForKey: @"_appMenu"];
        bar = [[appMenu valueForKey: @"_bar"] valueForKey: @"_bar"];
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

// Whether the application's menu bar window is ordered in (see -reportBar for how it is found).
static BOOL barWindowVisible(void) {
    @try {
        id appMenu = [[NSDisplay currentDisplay] valueForKey: @"_appMenu"];
        NSWindow *bar = [[appMenu valueForKey: @"_bar"] valueForKey: @"_bar"];
        return bar != nil && [bar isVisible];
    } @catch (id e) {
        return NO;
    }
}

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
    [target setFileMenu: file];
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

static void showPanel(void) {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect: NSMakeRect(400, 400, 240, 60)
                                                styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskUtilityWindow
                                                  backing: NSBackingStoreBuffered
                                                    defer: NO];
    [panel setTitle: @"Panel"];
    [panel setFloatingPanel: YES];
    [panel setHidesOnDeactivate: NO];
    [panel orderFront: nil];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "usage: %s LOG panel|strip|hiding|window|borderless|churn|late|standard|nowindow\n", argv[0]);
            return 2;
        }
        logFile = fopen(argv[1], "a");
        if (logFile == NULL)
            return 2;

        [NSApplication sharedApplication];
        // A program outside an application bundle is prohibited until it sets a policy, as on macOS:
        // the programs that are applications on their own are regular ones. The helper modes keep what
        // their bundle, or they themselves, declare, and the windowless one is the prohibited process.
        if (!strcmp(argv[2], "policy")) {
            // What the bundle on disk decides, before anything sets a policy: the policy and the bundle
            // URL as NSRunningApplication and NSApp report them. Needs no display.
            NSRunningApplication *me = [NSRunningApplication currentApplication];
            note("RUNNING policy=%ld url=%s", (long) [me activationPolicy],
                 [[[me bundleURL] path] UTF8String] ?: "(none)");
            note("NSAPP policy=%ld", (long) [NSApp activationPolicy]);
            return 0;
        }
        if (strcmp(argv[2], "helper") && strcmp(argv[2], "helper-accessory") && strcmp(argv[2], "windowless") &&
            strcmp(argv[2], "bundled"))
            [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        note("POLICY %d", (int) [NSApp activationPolicy]);
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
        [[NSNotificationCenter defaultCenter] addObserverForName: NSMenuDidBeginTrackingNotification object: nil
                                                           queue: nil usingBlock: ^(NSNotification *n) {
            note("tracking begin");
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName: NSMenuDidEndTrackingNotification object: nil
                                                           queue: nil usingBlock: ^(NSNotification *n) {
            note("tracking end");
        }];
        if (!strcmp(argv[2], "hiding")) {
            NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                                           styleMask: NSWindowStyleMaskTitled |
                                                                      NSWindowStyleMaskResizable
                                                             backing: NSBackingStoreBuffered
                                                                defer: NO];
            [window makeKeyAndOrderFront: nil];
            [NSApp activateIgnoringOtherApps: YES];
            // Each state is held for a while so that the host can look at the screen.
            static const char *const names[] = {"windowed", "full-screen-style", "windowed-again",
                                   "hide-menu-bar", "default-options", "auto-hide-menu-bar",
                                   "default-options-again"};
            __block int step = 0;
            [NSTimer scheduledTimerWithTimeInterval: 4.0 repeats: YES block: ^(NSTimer *t) {
                switch (step) {
                case 1:
                    [window setStyleMask: [window styleMask] | NSWindowStyleMaskFullScreen];
                    break;
                case 2:
                    [window setStyleMask: [window styleMask] & ~NSWindowStyleMaskFullScreen];
                    break;
                case 3:
                    [NSApp setPresentationOptions: NSApplicationPresentationHideMenuBar |
                                                   NSApplicationPresentationHideDock];
                    break;
                case 4:
                case 6:
                    [NSApp setPresentationOptions: NSApplicationPresentationDefault];
                    break;
                case 5:
                    [NSApp setPresentationOptions: NSApplicationPresentationAutoHideMenuBar |
                                                   NSApplicationPresentationAutoHideDock];
                    break;
                default:
                    break;
                }
                if (step >= 7) {
                    note("done");
                    exit(0);
                }
                note("STEP %s key=%d", names[step], (int) [window isKeyWindow]);
                step++;
            }];
            TestIgnoreArgumentWords();
            [NSApp run];
            return 0;
        }
        if (!strcmp(argv[2], "window")) {
            NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 400, 240)
                                                           styleMask: NSWindowStyleMaskTitled |
                                                                      NSWindowStyleMaskResizable
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO];
            NSRect frame = [NSWindow frameRectForContentRect: NSMakeRect(0, 0, 300, 200)
                                                   styleMask: NSWindowStyleMaskTitled];
            [window setTitle: @"Menu test"];
            [window makeKeyAndOrderFront: nil];
            note("strip window=%d extraFrameHeight=%d", (int) hasMainMenu(window),
                 (int) (frame.size.height - 200));
        } else if (!strcmp(argv[2], "borderless") || !strcmp(argv[2], "bundled")) {
            // A window that draws its own chrome: no title bar, so no in-window menu strip.
            NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 400, 240)
                                                           styleMask: NSWindowStyleMaskBorderless
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO];
            [window makeKeyAndOrderFront: nil];
            note("strip window=%d", (int) hasMainMenu(window));
        } else if (!strcmp(argv[2], "parent") || !strcmp(argv[2], "startup")) {
            BOOL parent = !strcmp(argv[2], "parent");
            int delay = argc > 4 ? atoi(argv[4]) : 0;
            NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 400, 132)
                                                           styleMask: NSWindowStyleMaskBorderless
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO];
            [window makeKeyAndOrderFront: nil];
            note("strip window=%d", (int) hasMainMenu(window));
            NSString *childLog = [[NSString stringWithUTF8String: argv[1]] stringByAppendingString: @".child"];
            NSString *self_ = [NSString stringWithUTF8String: argv[0]];
            // The moment the menu bar is ordered in, the second step follows after DELAYMS.
            [NSTimer scheduledTimerWithTimeInterval: 0.01 repeats: YES block: ^(NSTimer *t) {
                if (!barWindowVisible())
                    return;
                [t invalidate];
                [NSTimer scheduledTimerWithTimeInterval: delay / 1000.0 repeats: NO block: ^(NSTimer *t2) {
                    if (parent) {
                        NSTask *task = [[NSTask alloc] init];
                        [task setLaunchPath: self_];
                        [task setArguments: @[childLog, @"windowless", @"60"]];
                        [task launch];
                        note("STEP child launched");
                    } else {
                        [window close];
                        note("STEP window closed");
                    }
                }];
            }];
        } else if (!strcmp(argv[2], "windowless")) {
            [NSApp activateIgnoringOtherApps: YES];
            [NSTimer scheduledTimerWithTimeInterval: 0.5 repeats: YES block: ^(NSTimer *t) {
                [NSApp activateIgnoringOtherApps: YES];
            }];
        } else if (!strcmp(argv[2], "late")) {
            // The window exists before the main menu is set; the menu is replaced afterwards, and a
            // top-level item is added to the replacement.
            [NSApp setMainMenu: nil];
            NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 400, 240)
                                                           styleMask: NSWindowStyleMaskBorderless
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO];
            [window makeKeyAndOrderFront: nil];
            note("strip window=%d", (int) hasMainMenu(window));
            [NSTimer scheduledTimerWithTimeInterval: 1.5 repeats: NO block: ^(NSTimer *t) {
                buildMenu(target);
                note("STEP menu set");
            }];
            [NSTimer scheduledTimerWithTimeInterval: 4.0 repeats: NO block: ^(NSTimer *t) {
                buildMenu(target);
                note("STEP menu replaced");
            }];
            [NSTimer scheduledTimerWithTimeInterval: 6.5 repeats: NO block: ^(NSTimer *t) {
                NSMenuItem *extra = [[NSApp mainMenu] addItemWithTitle: @"Extra" action: NULL keyEquivalent: @""];
                NSMenu *sub = [[NSMenu alloc] initWithTitle: @"Extra"];
                [sub addItemWithTitle: @"Extra Item" action: @selector(save:) keyEquivalent: @""];
                [extra setSubmenu: sub];
                note("STEP item added");
            }];
        } else if (!strcmp(argv[2], "standard")) {
            // The usual application menu, whose items act on the first responder (no target), with a window.
            NSMenu *main = [[NSMenu alloc] initWithTitle: @"Main"];
            NSMenu *app, *services = [[NSMenu alloc] initWithTitle: @"Services"];
            NSMenuItem *item;
            submenuItem(main, @"AppItem", &app);
            [app addItemWithTitle: @"About Test" action: @selector(orderFrontStandardAboutPanel:) keyEquivalent: @""];
            [app addItem: [NSMenuItem separatorItem]];
            [app addItemWithTitle: @"Preferences..." action: @selector(preferences:) keyEquivalent: @","];
            [app addItem: [NSMenuItem separatorItem]];
            item = [app addItemWithTitle: @"Services" action: NULL keyEquivalent: @""];
            [item setSubmenu: services];
            [NSApp setServicesMenu: services];
            [app addItem: [NSMenuItem separatorItem]];
            [app addItemWithTitle: @"Hide Test" action: @selector(hide:) keyEquivalent: @"h"];
            item = [app addItemWithTitle: @"Hide Others" action: @selector(hideOtherApplications:) keyEquivalent: @"h"];
            [item setKeyEquivalentModifierMask: NSEventModifierFlagCommand | NSEventModifierFlagOption];
            [app addItemWithTitle: @"Show All" action: @selector(unhideAllApplications:) keyEquivalent: @""];
            [app addItem: [NSMenuItem separatorItem]];
            item = [app addItemWithTitle: @"Targeted" action: @selector(save:) keyEquivalent: @""];
            [item setTarget: target];
            [app addItemWithTitle: @"Quit Test" action: @selector(terminate:) keyEquivalent: @"q"];
            if (argc > 4 && !strcmp(argv[4], "rebuild")) {
                // The application menu is refilled with new items whenever it is about to be shown.
                [app setDelegate: target];
                [target setRebuilt: app];
            }
            [NSApp setMainMenu: main];
            NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 400, 240)
                                                           styleMask: NSWindowStyleMaskTitled
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO];
            [window makeKeyAndOrderFront: nil];
            [[NSNotificationCenter defaultCenter] addObserverForName: NSApplicationDidHideNotification object: nil
                                                               queue: nil usingBlock: ^(NSNotification *n) {
                note("action hide");
            }];
            [[NSNotificationCenter defaultCenter] addObserverForName: NSApplicationWillTerminateNotification object: nil
                                                               queue: nil usingBlock: ^(NSNotification *n) {
                note("action terminate");
            }];
            [[NSNotificationCenter defaultCenter] addObserverForName: NSWindowDidUpdateNotification object: nil
                                                               queue: nil usingBlock: ^(NSNotification *n) {
                static BOOL seen;
                NSWindow *w = [n object];
                if (!seen && ![w isEqual: window] && [w isVisible] && [[w title] length] > 0) {
                    seen = YES;
                    note("action about-panel");
                }
            }];
        } else if (!strcmp(argv[2], "churn")) {
            // Windows come and go as they do while an application starts up: ordered out and in again,
            // the key window changes, a second window closes, and a window is replaced by another in
            // the same pass of the run loop. The bar has to be shown at the end, and not be recreated
            // for every step.
            NSRect rect = NSMakeRect(200, 200, 400, 240);
            NSWindow *first = [[NSWindow alloc] initWithContentRect: rect styleMask: NSWindowStyleMaskBorderless
                                                            backing: NSBackingStoreBuffered defer: NO];
            // A utility panel: a titled window would carry the menu strip while it is shown, and the
            // bar would go away and come back with it (the swap mode covers that).
            NSWindow *second = [[NSPanel alloc] initWithContentRect: NSOffsetRect(rect, 100, 50)
                                                          styleMask: NSWindowStyleMaskTitled |
                                                                     NSWindowStyleMaskUtilityWindow
                                                            backing: NSBackingStoreBuffered defer: NO];
            [second setReleasedWhenClosed: NO];
            [first makeKeyAndOrderFront: nil];
            note("strip window=%d", (int) hasMainMenu(first));
            static const double times[] = {1.5, 2.5, 3.0, 3.5, 4.0, 5.0, 6.0, 7.0};
            for (int i = 0; i < 8; i++) {
                [NSTimer scheduledTimerWithTimeInterval: times[i] repeats: NO block: ^(NSTimer *t) {
                    switch (i) {
                    case 0:
                        [second makeKeyAndOrderFront: nil];
                        break;
                    case 1:
                        [first orderOut: nil];
                        [first makeKeyAndOrderFront: nil];
                        break;
                    case 2:
                        [first orderOut: nil];
                        break;
                    case 3:
                        [first makeKeyAndOrderFront: nil];
                        break;
                    case 4:
                        [first orderOut: nil];
                        [first orderFront: nil];
                        [second makeKeyWindow];
                        break;
                    case 5:
                        [second close];
                        break;
                    case 6: {
                        // Replaced in the same pass.
                        NSWindow *third = [[NSWindow alloc] initWithContentRect: rect
                                                                      styleMask: NSWindowStyleMaskBorderless
                                                                        backing: NSBackingStoreBuffered defer: NO];
                        [third makeKeyAndOrderFront: nil];
                        [first close];
                        break;
                    }
                    default:
                        note("STEP churn done active=%d barVisible=%d", (int) [NSApp isActive],
                             (int) barWindowVisible());
                        break;
                    }
                }];
            }
        } else if (!strcmp(argv[2], "swap")) {
            __block NSWindow *window = nil;
            [NSApp activateIgnoringOtherApps: YES];
            note("strip window=0");
            [NSTimer scheduledTimerWithTimeInterval: 5.0 repeats: NO block: ^(NSTimer *t) {
                window = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 400, 240)
                                                     styleMask: NSWindowStyleMaskTitled
                                                       backing: NSBackingStoreBuffered
                                                         defer: NO];
                [window setReleasedWhenClosed: NO];
                [window makeKeyAndOrderFront: nil];
                note("STEP window opened strip=%d", (int) hasMainMenu(window));
            }];
            [NSTimer scheduledTimerWithTimeInterval: 10.0 repeats: NO block: ^(NSTimer *t) {
                [window close];
                note("STEP window closed");
            }];
        } else if (!strcmp(argv[2], "owner")) {
            // No window that could carry the strip or be seen: an offscreen borderless one, key.
            NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(-300, -300, 1, 1)
                                                           styleMask: NSWindowStyleMaskBorderless
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO];
            [window makeKeyAndOrderFront: nil];
            [NSApp activateIgnoringOtherApps: YES];
            note("strip window=%d", (int) hasMainMenu(window));
            if (argc > 4) {
                NSString *helper = [NSString stringWithUTF8String: argv[4]];
                NSString *mode = [NSString stringWithUTF8String: argc > 5 ? argv[5] : "helper"];
                NSString *helperLog = [[NSString stringWithUTF8String: argv[1]] stringByAppendingString: @".helper"];
                [NSTimer scheduledTimerWithTimeInterval: 3.0 repeats: NO block: ^(NSTimer *t) {
                    NSTask *task = [[NSTask alloc] init];
                    [task setLaunchPath: helper];
                    [task setArguments: @[helperLog, mode, @"90"]];
                    [task launch];
                    note("STEP helper launched");
                }];
            }
        } else if (!strcmp(argv[2], "helper") || !strcmp(argv[2], "helper-accessory")) {
            if (!strcmp(argv[2], "helper-accessory"))
                [NSApp setActivationPolicy: NSApplicationActivationPolicyAccessory];
            NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(300, 300, 400, 240)
                                                           styleMask: NSWindowStyleMaskTitled
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO];
            [window setTitle: @"Helper"];
            [window makeKeyAndOrderFront: nil];
            [NSApp activateIgnoringOtherApps: YES];
            note("HELPER policy=%d key=%d main=%d", (int) [NSApp activationPolicy], (int) [window isKeyWindow],
                 (int) [window isMainWindow]);
            // The host ends the helper by creating LOG.quit.
            NSString *quitPath = [[NSString stringWithUTF8String: argv[1]] stringByAppendingString: @".quit"];
            [NSTimer scheduledTimerWithTimeInterval: 0.2 repeats: YES block: ^(NSTimer *t) {
                if (access([quitPath fileSystemRepresentation], F_OK) == 0) {
                    note("helper quits");
                    exit(0);
                }
            }];
        } else if (!strcmp(argv[2], "nowindow")) {
            [NSApp activateIgnoringOtherApps: YES];
            note("strip window=0");
        } else
            showPanel();

        [[NSNotificationCenter defaultCenter] addObserverForName: NSApplicationDidBecomeActiveNotification
                                                           object: nil queue: nil usingBlock: ^(NSNotification *n) {
            note("ACTIVE");
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName: NSApplicationDidResignActiveNotification
                                                           object: nil queue: nil usingBlock: ^(NSNotification *n) {
            note("RESIGN");
        }];
        [[NSWorkspace sharedWorkspace] addObserver: target forKeyPath: @"menuBarOwningApplication"
                                           options: 0 context: NULL];
        [NSTimer scheduledTimerWithTimeInterval: 0.2 repeats: YES block: ^(NSTimer *t) {
            static int lastOwner = -1, lastFront = -1;
            NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
            int owner = (int) ([[workspace menuBarOwningApplication] processIdentifier] == getpid());
            NSRunningApplication *frontApp = [workspace frontmostApplication];
            int front = frontApp == nil ? 0 : ([frontApp processIdentifier] == getpid() ? 1 : 2);
            if (owner != lastOwner || front != lastFront) {
                lastOwner = owner;
                lastFront = front;
                note("OWNER owner=%d front=%s", owner, front == 0 ? "none" : (front == 1 ? "self" : "other"));
            }
        }];
        [NSTimer scheduledTimerWithTimeInterval: 0.2 repeats: YES block: ^(NSTimer *t) {
            static int lastActive = -1, lastBar = -1, lastWindows = -1;
            int windows = 0;
            for (NSWindow *w in [NSApp windows])
                if ([w isVisible] && hasMainMenu(w))
                    windows++;
            int active = (int) [NSApp isActive], bar = (int) barWindowVisible();
            if (active != lastActive || bar != lastBar || windows != lastWindows) {
                lastActive = active;
                lastBar = bar;
                lastWindows = windows;
                note("STATE active=%d bar=%d windows=%d", active, bar, windows);
            }
        }];

        // A bounded run, in case the host script goes away.
        int lifetime = argc > 3 ? atoi(argv[3]) : 120;
        [NSTimer scheduledTimerWithTimeInterval: lifetime repeats: NO block: ^(NSTimer *t) {
            note(argc > 3 ? "done" : "timeout");
            exit(argc > 3 ? 0 : 3);
        }];
        TestIgnoreArgumentWords();
        [NSApp run];
    }
    return 0;
}
