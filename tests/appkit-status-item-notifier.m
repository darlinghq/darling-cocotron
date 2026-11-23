/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Guest side of the status item tests (see appkit-status-item/README.md).
//
//   appkit-status-item-notifier LOG tray
//       Makes two status items, one with a menu, an image, a title and a tool
//       tip, the other with an action, logs "READY", and then carries out the
//       steps below one at a time, each when the host script creates the file
//       LOG.stepN, logging "STEP N" when it is done. It logs the actions it
//       receives. "DONE" is logged after the last step.
//   appkit-status-item-notifier LOG api
//       Checks the NSStatusItem contract in-process, which has to work without
//       any session bus (the host script gives it an address nobody listens on),
//       prints PASS or FAIL lines to LOG and exits.
//
// Steps: 1 new title and tool tip on the first item; 2 the first item gets a
// template image; 3 a menu item is added; 4 the first item is hidden; 5 it is
// shown again; 6 the second item sends its action on a right click as well;
// 7 the first item is removed; 8 the second item is removed.
#import <AppKit/AppKit.h>
#import "test-argument-words.h"
#include <objc/message.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static FILE *logFile;
static const char *logPath;
static int failures;

static void note(const char *format, ...) __attribute__((format(printf, 1, 2)));
static void note(const char *format, ...) {
    va_list args;

    va_start(args, format);
    vfprintf(logFile, format, args);
    va_end(args);
    fputc('\n', logFile);
    fflush(logFile);
}

#define CHECK(cond, msg) do { \
    if (cond) note("PASS: %s", msg); else { note("FAIL: %s", msg); failures++; } \
} while (0)

static NSImage *squareImage(CGFloat side, NSColor *color, BOOL template) {
    NSImage *image = [[NSImage alloc] initWithSize: NSMakeSize(side, side)];

    [image lockFocus];
    [color set];
    NSRectFill(NSMakeRect(0, 0, side, side));
    [image unlockFocus];
    [image setTemplate: template];
    return image;
}

static NSString *toolTipOf(NSStatusItem *item) {
    return ((id (*)(id, SEL)) objc_msgSend)(item, @selector(toolTip));
}

@interface Controller : NSObject {
    int _count;
}
- (void) itemAction: (id) sender;
- (void) menuAction: (id) sender;
@end

@implementation Controller
- (void) itemAction: (id) sender {
    note("action item %d mainthread=%d", ++_count, (int) [NSThread isMainThread]);
}
- (void) menuAction: (id) sender {
    note("action menu %s", [[sender title] UTF8String]);
}
@end

static NSStatusItem *first, *second;
static NSMenu *firstMenu;
static Controller *controller;
static int nextStep = 1;

static void performStep(int step) {
    NSStatusBar *bar = [NSStatusBar systemStatusBar];

    switch (step) {
    case 1:
        [first setTitle: @"Changed"];
        [first setToolTip: @"Tip2"];
        break;
    case 2:
        [first setImage: squareImage(16, [NSColor blackColor], YES)];
        break;
    case 3: {
        NSMenuItem *gamma = [firstMenu addItemWithTitle: @"Gamma"
                                                 action: @selector(menuAction:)
                                          keyEquivalent: @""];
        [gamma setTarget: controller];
        break;
    }
    case 4:
        [first setVisible: NO];
        break;
    case 5:
        [first setVisible: YES];
        break;
    case 6:
        [second sendActionOn: NSRightMouseUpMask];
        break;
    case 7:
        [bar removeStatusItem: first];
        break;
    case 8:
        [bar removeStatusItem: second];
        break;
    }
    note("STEP %d", step);
}

static void poll(CFRunLoopTimerRef timer, void *info) {
    char path[1024];

    snprintf(path, sizeof(path), "%s.step%d", logPath, nextStep);
    if (access(path, F_OK) != 0)
        return;
    performStep(nextStep);
    if (nextStep++ == 8) {
        note("DONE");
        exit(0);
    }
}

static void runTray(void) {
    NSStatusBar *bar = [NSStatusBar systemStatusBar];

    controller = [Controller new];

    first = [bar statusItemWithLength: NSVariableStatusItemLength];
    [first setAutosaveName: @"probe-menu"];
    [first setTitle: @"Probe"];
    [first setImage: squareImage(16, [NSColor redColor], NO)];
    [first setToolTip: @"Tip"];
    firstMenu = [[NSMenu alloc] initWithTitle: @"Probe"];
    for (NSString *title in @[ @"Alpha", @"Beta" ]) {
        NSMenuItem *item = [firstMenu addItemWithTitle: title
                                                action: @selector(menuAction:)
                                         keyEquivalent: @""];
        [item setTarget: controller];
    }
    [firstMenu addItem: [NSMenuItem separatorItem]];
    [first setMenu: firstMenu];

    second = [bar statusItemWithLength: NSSquareStatusItemLength];
    [second setAutosaveName: @"probe-action"];
    [second setTitle: @"Click me"];
    [second setTarget: controller];
    [second setAction: @selector(itemAction:)];

    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(
            kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 0.2, 0.2, 0, 0, poll, NULL);
    CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopCommonModes);
    note("READY");
}

// The contract of NSStatusBar and NSStatusItem that does not need a tray. The
// expected values were observed on macOS 10.14.4 and 26.7.3 (thickness 22, the
// menu being the object given, sendActionOn: and highlight mode defaults).
static void runApi(void) {
    NSStatusBar *bar = [NSStatusBar systemStatusBar];

    CHECK(bar != nil && bar == [NSStatusBar systemStatusBar], "systemStatusBar is a singleton");

    NSStatusItem *variable = [bar statusItemWithLength: NSVariableStatusItemLength];
    NSStatusItem *square = [bar statusItemWithLength: NSSquareStatusItemLength];
    NSStatusItem *wide = [bar statusItemWithLength: 80];

    CHECK([variable length] == NSVariableStatusItemLength, "variable length is kept");
    CHECK([square length] == NSSquareStatusItemLength, "square length is kept");
    CHECK([wide length] == 80, "fixed length is kept");
    CHECK([variable statusBar] == bar, "an item knows its status bar");
    CHECK([variable button] != nil, "the item has a button");
    CHECK([bar thickness] == 22, "the status bar is 22 points thick (macOS 10.14 and 26)");
    CHECK([variable highlightMode], "highlight mode is on by default (macOS 10.14)");
    CHECK([variable sendActionOn: NSRightMouseUpMask] == NSLeftMouseUpMask,
          "an item sends its action on left mouse up by default");
    CHECK([variable sendActionOn: NSLeftMouseUpMask] == NSRightMouseUpMask,
          "sendActionOn: returns the previous mask");
    CHECK([variable isVisible], "an item is visible by default");
    [variable setVisible: NO];
    CHECK(![variable isVisible], "an item can be hidden");
    [variable setVisible: YES];

    NSMenu *menu = [[NSMenu alloc] initWithTitle: @"m"];
    [menu addItemWithTitle: @"One" action: NULL keyEquivalent: @""];
    [variable setMenu: menu];
    CHECK([variable menu] == menu, "the item's menu is the menu given, not a copy");
    [menu addItemWithTitle: @"Two" action: NULL keyEquivalent: @""];
    CHECK([[[variable menu] itemArray] count] == 2, "changes to the menu given are seen through the item");
    [variable setMenu: nil];
    CHECK([variable menu] == nil, "the menu can be taken away");

    CHECK(toolTipOf(variable) == nil, "no tool tip by default");
    [variable setToolTip: @"Tip"];
    CHECK([toolTipOf(variable) isEqualToString: @"Tip"], "the tool tip is kept");
    CHECK([[[variable button] toolTip] isEqualToString: @"Tip"], "the tool tip is the button's");

    [variable setTitle: @"T"];
    [variable setImage: squareImage(8, [NSColor redColor], NO)];
    [bar removeStatusItem: variable];
    [bar removeStatusItem: variable];
    CHECK([[variable title] isEqualToString: @"T"], "a removed item keeps its properties");
    [bar removeStatusItem: square];
    [bar removeStatusItem: wide];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "usage: %s LOG tray|api\n", argv[0]);
            return 2;
        }
        logPath = argv[1];
        logFile = fopen(logPath, "w");
        [NSApplication sharedApplication];
        // Which window server backend the application got, for the host script's report.
        id display = ((id (*)(id, SEL)) objc_msgSend)(NSClassFromString(@"NSDisplay"), @selector(currentDisplay));
        note("backend %s", object_getClassName(display));
        if (strcmp(argv[2], "api") == 0) {
            runApi();
            note(failures ? "FAIL" : "PASS");
            return failures != 0;
        }
        runTray();
        TestIgnoreArgumentWords();
        [NSApp run];
    }
    return 0;
}
