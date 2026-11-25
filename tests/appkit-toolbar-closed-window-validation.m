// CFLAGS: -framework Foundation -framework AppKit
// Copyright (C) 2026 Lubos Dolezel
//
// A window's toolbar is validated while the window is shown, not after it has been closed: an event the window
// handled just before closing does not lead to validating the toolbar later (its items' targets may be gone by
// then), nor by updateWindows, which updates the windows on screen. The program passes unchanged on macOS 26.7.3
// and 10.14.4.
//
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

@interface CountingToolbar : NSToolbar {
@public
    int validations;
}
@end

@implementation CountingToolbar
- (void) validateVisibleItems {
    validations++;
    [super validateVisibleItems];
}
@end

@interface Delegate : NSObject <NSToolbarDelegate>
@end

@implementation Delegate
- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *) toolbar {
    return @[ @"item" ];
}
- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *) toolbar {
    return @[ @"item" ];
}
- (NSToolbarItem *) toolbar: (NSToolbar *) toolbar itemForItemIdentifier: (NSString *) identifier
    willBeInsertedIntoToolbar: (BOOL) flag {
    NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier: identifier] autorelease];
    [item setLabel: @"Item"];
    [item setAction: @selector(itemAction:)];
    return item;
}
- (void) itemAction: (id) sender {
}
@end

static void spin(NSTimeInterval seconds)
{
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];

    Delegate *delegate = [[Delegate alloc] init];
    CountingToolbar *toolbar = [[CountingToolbar alloc] initWithIdentifier: @"closed-window-validation"];
    [toolbar setDelegate: delegate];
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                                   styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    [window setReleasedWhenClosed: NO];
    [window setToolbar: toolbar];
    [window makeKeyAndOrderFront: nil];
    spin(1);

    NSEvent *key = [NSEvent keyEventWithType: NSEventTypeKeyDown location: NSZeroPoint modifierFlags: 0 timestamp: 0
                                windowNumber: [window windowNumber] context: nil characters: @"a"
                 charactersIgnoringModifiers: @"a" isARepeat: NO keyCode: 0];
    [window sendEvent: key];
    [window close];
    toolbar->validations = 0;
    spin(1.5);
    expect(toolbar->validations == 0, "a closed window's toolbar is not validated after an event it handled");
    [NSApp updateWindows];
    expect(toolbar->validations == 0, "updateWindows leaves a closed window alone");

    [window setToolbar: nil];
    [window release];
    [toolbar release];
    [delegate release];
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    [pool release];
    return failures != 0;
}
