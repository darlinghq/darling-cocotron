/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSWindow API with documented behaviour: titlebar accessory insertion and
// removal by index, the appearance source, sheets, display gamut, the user's
// tabbing preference, the tab actions of a window that has no tabs,
// trackEventsMatchingMask:timeout:mode:handler:, the stored defaults, and
// delivery of the window notifications to the delegate. Expected values were
// observed on macOS 10.14.4 and 26.7.3; the methods that are newer than
// 10.14 are only checked where the system has them.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

@interface NSWindow (WindowMissingApiTest)
- (void) insertTitlebarAccessoryViewController: (NSTitlebarAccessoryViewController *) c
                                       atIndex: (NSInteger) index;
- (void) removeTitlebarAccessoryViewControllerAtIndex: (NSInteger) index;
- (NSArray *) sheets;
- (id) appearanceSource;
- (void) setAppearanceSource: (id) source;
- (BOOL) canRepresentDisplayGamut: (NSInteger) gamut;
+ (NSInteger) userTabbingPreference;
- (NSInteger) windowTitlebarLayoutDirection;
- (NSRect) cascadingReferenceFrame;
- (void) selectNextTab: (id) sender;
- (void) selectPreviousTab: (id) sender;
- (void) moveTabToNewWindow: (id) sender;
- (void) toggleTabBar: (id) sender;
- (void) toggleTabOverview: (id) sender;
- (void) trackEventsMatchingMask: (NSEventMask) mask
                         timeout: (NSTimeInterval) timeout
                            mode: (NSRunLoopMode) mode
                         handler: (void (^)(NSEvent *event, BOOL *stop)) handler;
- (BOOL) allowsConcurrentViewDrawing;
- (BOOL) preventsApplicationTerminationWhenModal;
- (BOOL) canBecomeVisibleWithoutLogin;
- (void) setAllowsConcurrentViewDrawing: (BOOL) flag;
- (void) setPreventsApplicationTerminationWhenModal: (BOOL) flag;
- (void) setCanBecomeVisibleWithoutLogin: (BOOL) flag;
@end

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

@interface Delegate : NSObject <NSWindowDelegate> {
  @public
    NSMutableArray *seen;
}
@end

@implementation Delegate
- (instancetype) init {
    self = [super init];
    seen = [[NSMutableArray alloc] init];
    return self;
}
#define RECORD(name)                                                          \
    -(void) name: (NSNotification *) note {                                   \
        [seen addObject: @ #name];                                           \
    }
RECORD(windowDidChangeScreen)
RECORD(windowDidChangeScreenProfile)
RECORD(windowDidExpose)
RECORD(windowDidChangeBackingProperties)
RECORD(windowWillStartLiveResize)
RECORD(windowDidEndLiveResize)
RECORD(windowWillEnterFullScreen)
RECORD(windowDidEnterFullScreen)
RECORD(windowWillExitFullScreen)
RECORD(windowDidExitFullScreen)
RECORD(windowWillBeginSheet)
RECORD(windowDidEndSheet)
@end

static NSWindow *makeWindow(void) {
    return [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                       styleMask: NSWindowStyleMaskTitled |
                                                  NSWindowStyleMaskClosable
                                         backing: NSBackingStoreBuffered
                                           defer: YES];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        if (argc > 1 && strcmp(argv[argc - 1], "-print-tabbing-preference") == 0) {
            printf("%ld\n", (long) [NSWindow userTabbingPreference]);
            return 0;
        }
        NSWindow *window = makeWindow();

        // Defaults that are stored.
        expect([window allowsConcurrentViewDrawing], "concurrent drawing allowed by default");
        expect([window preventsApplicationTerminationWhenModal],
               "modal window prevents termination by default");
        expect(![window canBecomeVisibleWithoutLogin],
               "not visible without login by default");
        [window setAllowsConcurrentViewDrawing: NO];
        [window setPreventsApplicationTerminationWhenModal: NO];
        [window setCanBecomeVisibleWithoutLogin: YES];
        expect(![window allowsConcurrentViewDrawing], "concurrent drawing flag stored");
        expect(![window preventsApplicationTerminationWhenModal],
               "termination flag stored");
        expect([window canBecomeVisibleWithoutLogin], "login flag stored");

        // Titlebar accessories by index (10.10).
        NSTitlebarAccessoryViewController *a = [[NSTitlebarAccessoryViewController alloc] init];
        NSTitlebarAccessoryViewController *b = [[NSTitlebarAccessoryViewController alloc] init];
        NSTitlebarAccessoryViewController *c = [[NSTitlebarAccessoryViewController alloc] init];
        [window addTitlebarAccessoryViewController: a];
        [window insertTitlebarAccessoryViewController: b atIndex: 0];
        [window insertTitlebarAccessoryViewController: c atIndex: 1];
        NSArray *list = [window titlebarAccessoryViewControllers];
        expect([list count] == 3 && list[0] == b && list[1] == c && list[2] == a,
               "accessories are inserted at their index");
        [window removeTitlebarAccessoryViewControllerAtIndex: 1];
        list = [window titlebarAccessoryViewControllers];
        expect([list count] == 2 && list[0] == b && list[1] == a,
               "accessory removed by index");
        BOOL raised = NO;
        @try {
            [window insertTitlebarAccessoryViewController: c atIndex: 99];
        } @catch (NSException *e) {
            raised = YES;
        }
        expect(raised, "inserting past the end raises");
        expect([[window titlebarAccessoryViewControllers] count] == 2,
               "a refused insert changes nothing");
        raised = NO;
        @try {
            [window removeTitlebarAccessoryViewControllerAtIndex: 99];
        } @catch (NSException *e) {
            raised = YES;
        }
        expect(raised, "removing past the end raises");
        [window insertTitlebarAccessoryViewController: a atIndex: 0];
        expect([[window titlebarAccessoryViewControllers] count] == 2,
               "an accessory already present isn't added twice");

        // Appearance source (10.14): the application until set.
        if ([window respondsToSelector: @selector(appearanceSource)]) {
            expect([window appearanceSource] == NSApp,
                   "the application is the default appearance source");
            NSView *source = [[NSView alloc] init];
            [source setAppearance: [NSAppearance appearanceNamed: NSAppearanceNameAqua]];
            [window setAppearanceSource: source];
            expect([window appearanceSource] == source, "appearance source is stored");
            expect([[[window effectiveAppearance] name] isEqual: NSAppearanceNameAqua],
                   "the window follows its appearance source");
            [window setAppearanceSource: nil];
            expect([window appearanceSource] == NSApp,
                   "resetting the source makes the application the source");
            @autoreleasepool {
                NSView *temporary = [[NSView alloc] init];
                [window setAppearanceSource: temporary];
                [temporary release];
            }
            expect([window appearanceSource] == NSApp,
                   "a released source isn't retained or left dangling");
        }

        // Sheets (10.9) and the sheet notifications.
        if ([window respondsToSelector: @selector(sheets)])
            expect([[window sheets] count] == 0, "no sheets by default");

        // Display gamut (10.12): sRGB only.
        expect([window canRepresentDisplayGamut: 1], "sRGB can be represented");

        // Tabbing preference (10.12): System Settings stores it as
        // AppleWindowTabbingMode; 0 manual, 1 always, 2 in full screen only,
        // which is also the result for a missing or unknown value. Each value
        // is passed to a copy of this program on its command line, as the
        // argument domain is read when the process starts.
        struct {
            NSString *value;
            NSInteger expected;
        } modes[] = {{@"always", 1}, {@"manual", 0}, {@"fullscreen", 2}, {@"bogus", 2}, {nil, 2}};
        for (unsigned i = 0; i < sizeof(modes) / sizeof(modes[0]); i++) {
            NSTask *task = [[NSTask alloc] init];
            NSPipe *pipe = [NSPipe pipe];
            [task setLaunchPath: [[NSBundle mainBundle] executablePath]];
            [task setArguments: modes[i].value
                    ? @[@"-AppleWindowTabbingMode", modes[i].value, @"-print-tabbing-preference"]
                    : @[@"-print-tabbing-preference"]];
            [task setStandardOutput: pipe];
            [task launch];
            NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
            [task waitUntilExit];
            NSString *text = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
            expect([text integerValue] == modes[i].expected && [text length] > 0,
                   "tabbing preference follows AppleWindowTabbingMode");
            [text release];
            [task release];
        }

        if ([window respondsToSelector: @selector(windowTitlebarLayoutDirection)])
            expect([window windowTitlebarLayoutDirection] ==
                           [NSApp userInterfaceLayoutDirection],
                   "titlebar layout direction is the application's");
        if ([window respondsToSelector: @selector(cascadingReferenceFrame)])
            expect(NSEqualRects([window cascadingReferenceFrame], [window frame]),
                   "cascading reference frame is the frame");

        // A window without tabs: the tab actions leave everything alone.
        NSUInteger windowCount = [[NSApp windows] count];
        [window selectNextTab: nil];
        [window selectPreviousTab: nil];
        [window moveTabToNewWindow: nil];
        [window toggleTabBar: nil];
        [window toggleTabOverview: nil];
        expect([[NSApp windows] count] == windowCount, "tab actions don't create windows");

        // Event tracking: nil events report timeouts, and tracking goes on
        // until the handler stops it.
        __block int calls = 0;
        __block int nilEvents = 0;
        NSDate *start = [NSDate date];
        [window trackEventsMatchingMask: NSEventMaskLeftMouseDown
                                timeout: 0.2
                                   mode: NSEventTrackingRunLoopMode
                                handler: ^(NSEvent *event, BOOL *stop) {
                                    calls++;
                                    if (event == nil)
                                        nilEvents++;
                                    if (calls == 3)
                                        *stop = YES;
                                }];
        NSTimeInterval elapsed = -[start timeIntervalSinceNow];
        expect(calls == 3 && nilEvents == 3, "each timeout calls the handler with nil");
        expect(elapsed > 0.5 && elapsed < 3, "each timeout waits for the interval");

        NSEvent *click = [NSEvent mouseEventWithType: NSEventTypeLeftMouseDown
                                            location: NSMakePoint(5, 5)
                                       modifierFlags: 0
                                           timestamp: 0
                                        windowNumber: [window windowNumber]
                                             context: nil
                                         eventNumber: 1
                                          clickCount: 1
                                            pressure: 1];
        [NSApp postEvent: click atStart: NO];
        __block NSEvent *got = nil;
        [window trackEventsMatchingMask: NSEventMaskLeftMouseDown
                                timeout: 2
                                   mode: NSEventTrackingRunLoopMode
                                handler: ^(NSEvent *event, BOOL *stop) {
                                    got = event;
                                    *stop = YES;
                                }];
        expect(got != nil && [got type] == NSEventTypeLeftMouseDown,
               "a matching posted event is passed to the handler");

        // Delegate notifications: every notification the window posts for its
        // delegate reaches the matching delegate method.
        Delegate *delegate = [[Delegate alloc] init];
        [window setDelegate: delegate];
        struct {
            NSNotificationName name;
            NSString *method;
        } notes[] = {
                {NSWindowDidChangeScreenNotification, @"windowDidChangeScreen"},
                {NSWindowDidChangeScreenProfileNotification, @"windowDidChangeScreenProfile"},
                {NSWindowDidExposeNotification, @"windowDidExpose"},
                {NSWindowDidChangeBackingPropertiesNotification, @"windowDidChangeBackingProperties"},
                {NSWindowWillStartLiveResizeNotification, @"windowWillStartLiveResize"},
                {NSWindowDidEndLiveResizeNotification, @"windowDidEndLiveResize"},
                {NSWindowWillEnterFullScreenNotification, @"windowWillEnterFullScreen"},
                {NSWindowDidEnterFullScreenNotification, @"windowDidEnterFullScreen"},
                {NSWindowWillExitFullScreenNotification, @"windowWillExitFullScreen"},
                {NSWindowDidExitFullScreenNotification, @"windowDidExitFullScreen"},
                {NSWindowWillBeginSheetNotification, @"windowWillBeginSheet"},
                {NSWindowDidEndSheetNotification, @"windowDidEndSheet"},
        };
        for (unsigned i = 0; i < sizeof(notes) / sizeof(notes[0]); i++) {
            [[NSNotificationCenter defaultCenter] postNotificationName: notes[i].name
                                                                object: window];
            char what[128];
            snprintf(what, sizeof what, "delegate receives %s",
                     [notes[i].method UTF8String]);
            expect([delegate->seen containsObject: notes[i].method], what);
        }
        [delegate->seen removeAllObjects];
        [window setDelegate: nil];
        [[NSNotificationCenter defaultCenter]
                postNotificationName: NSWindowDidExposeNotification
                              object: window];
        expect([delegate->seen count] == 0, "no delivery after the delegate is removed");
    }

    if (failures == 0)
        printf("PASS appkit-window-missing-api\n");
    return failures != 0;
}
