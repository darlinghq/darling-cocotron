// Copyright (C) 2026 Lubos Dolezel
//
// The menu of a pop-up button tells its delegate about a tracking session: -menuNeedsUpdate:, then -menuWillOpen:,
// and -menuDidClose: once the menu is gone, each once and each with the button's own menu
// (https://developer.apple.com/documentation/appkit/nsmenudelegate/menuneedsupdate(_:),
// https://developer.apple.com/documentation/appkit/nsmenudelegate/menuwillopen(_:),
// https://developer.apple.com/documentation/appkit/nsmenudelegate/menudidclose(_:)). All three are optional
// (@optional in NSMenuDelegate), so a delegate that implements only some of them is called for those only. The
// session is also bracketed by NSMenuDidBeginTrackingNotification and NSMenuDidEndTrackingNotification, posted
// whatever the delegate. Observed on macOS 26.7.3 for a pop-up button: needsUpdate, begin, willOpen, ..., didClose,
// end; for a pull-down button: begin, needsUpdate, willOpen, ..., didClose, end. The two orders differ, which is a
// QUIRK (test_quirk_pop_up_updates_before_begin_notification, the pop-up and pull-down runs below).
// The tracking is ended with Escape, queued before it starts. The list of a pop-up button opens no submenus here
// (macOS updates and opens them): not tested. Needs a window server. Build without ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", what);
    if (!condition)
        failures++;
}

static NSMutableArray *events;
static NSMenu *menuSeen;
static BOOL wrongMenu;

static void note(NSString *name, NSMenu *menu) {
    [events addObject: name];
    if (menuSeen == nil)
        menuSeen = menu;
    else if (menu != menuSeen)
        wrongMenu = YES;
}

@interface FullDelegate : NSObject <NSMenuDelegate>
@end
@implementation FullDelegate
- (void) menuNeedsUpdate: (NSMenu *) menu { note(@"needsUpdate", menu); }
- (void) menuWillOpen: (NSMenu *) menu { note(@"willOpen", menu); }
- (void) menuDidClose: (NSMenu *) menu { note(@"didClose", menu); }
@end

// Implements none of the optional methods.
@interface PlainDelegate : NSObject <NSMenuDelegate>
@end
@implementation PlainDelegate
@end

// Implements only the one that was not sent before.
@interface OpenCloseDelegate : NSObject <NSMenuDelegate>
@end
@implementation OpenCloseDelegate
- (void) menuWillOpen: (NSMenu *) menu { note(@"willOpen", menu); }
- (void) menuDidClose: (NSMenu *) menu { note(@"didClose", menu); }
@end

static NSEvent *keyDown(NSWindow *window, NSString *characters, unsigned short code) {
    return [NSEvent keyEventWithType: NSKeyDown
                            location: NSZeroPoint
                       modifierFlags: 0
                           timestamp: 2
                        windowNumber: [window windowNumber]
                             context: nil
                          characters: characters
         charactersIgnoringModifiers: characters
                           isARepeat: NO
                             keyCode: code];
}

// Opens the button's menu and dismisses it with Escape.
static void trackAndCancel(NSPopUpButton *button, NSWindow *window) {
    NSEvent *start = [NSEvent mouseEventWithType: NSLeftMouseDown
                                        location: NSMakePoint(10, 10)
                                   modifierFlags: 0
                                       timestamp: 1
                                    windowNumber: [window windowNumber]
                                         context: nil
                                     eventNumber: 0
                                      clickCount: 1
                                        pressure: 1];
    [NSApp postEvent: keyDown(window, @"\033", 53) atStart: YES];
    [[button cell] trackMouse: start inRect: [button bounds] ofView: button untilMouseUp: NO];
}

static void run(BOOL pullsDown, id delegate, NSArray *want, const char *what) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 300, 200)
                                                   styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    NSPopUpButton *button = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(20, 100, 120, 26) pullsDown: pullsDown];
    [button addItemsWithTitles: @[ @"Title", @"One", @"Two" ]];
    [[window contentView] addSubview: button];
    [window makeKeyAndOrderFront: nil];
    [[button menu] setDelegate: delegate];

    [events removeAllObjects];
    menuSeen = nil;
    wrongMenu = NO;
    trackAndCancel(button, window);

    char message[160];
    snprintf(message, sizeof message, "%s: %s", pullsDown ? "pull-down" : "pop-up", what);
    expect([events isEqualToArray: want], message);
    if (![events isEqualToArray: want])
        fprintf(stderr, "  got %s\n", [[events description] UTF8String]);
    if ([want count] > 0) {
        snprintf(message, sizeof message, "%s: every call gets the button's own menu", pullsDown ? "pull-down" : "pop-up");
        expect(!wrongMenu && menuSeen == [button menu], message);
    }
    [[button menu] setDelegate: nil];
    [window close];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        events = [[NSMutableArray alloc] init];

        FullDelegate *full = [[FullDelegate alloc] init];
        PlainDelegate *plain = [[PlainDelegate alloc] init];
        OpenCloseDelegate *openClose = [[OpenCloseDelegate alloc] init];
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        id begin = [center addObserverForName: NSMenuDidBeginTrackingNotification object: nil queue: nil
                                   usingBlock: ^(NSNotification *n) { note(@"begin", [n object]); }];
        id end = [center addObserverForName: NSMenuDidEndTrackingNotification object: nil queue: nil
                                 usingBlock: ^(NSNotification *n) { note(@"end", [n object]); }];

        for (int pullsDown = 0; pullsDown <= 1; pullsDown++) {
            // test_quirk_pop_up_updates_before_begin_notification: the update comes before the begin notification
            // for a pop-up and after it for a pull-down.
            NSArray *all = pullsDown ? @[ @"begin", @"needsUpdate", @"willOpen", @"didClose", @"end" ]
                                     : @[ @"needsUpdate", @"begin", @"willOpen", @"didClose", @"end" ];
            run(pullsDown, full, all, "the update, begin, willOpen, didClose and end calls, once each, in macOS order");
            run(pullsDown, plain, @[ @"begin", @"end" ],
                "a delegate without the optional methods is not called (and does not raise), the notifications are posted");
            run(pullsDown, openClose, @[ @"begin", @"willOpen", @"didClose", @"end" ],
                "a delegate without menuNeedsUpdate: gets the other two");
        }
        [center removeObserver: begin];
        [center removeObserver: end];

        [full release];
        [plain release];
        [openClose release];
    }
    printf(failures ? "FAIL (%d)\n" : "PASS\n", failures);
    return failures != 0;
}
