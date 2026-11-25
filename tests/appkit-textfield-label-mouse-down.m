// CFLAGS: -framework AppKit -fobjc-arc
// Copyright (C) 2026 Lubos Dolezel
//
// A text field that is neither editable nor selectable (a label) doesn't take a mouse press: the press goes up the
// responder chain to its superview, and the label doesn't become first responder. Only an editable field accepts
// first responder; a selectable or an editable field takes the press and the keys. This is how a click on a label in
// a view-based table's cell reaches the table. Observed on macOS 10.14.4 and 26.7.3, where it passes unchanged. Needs
// a display.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    failures += !ok;
}

@interface Container : NSView
@property NSInteger presses;
@end

@implementation Container
- (void)mouseDown:(NSEvent *)event { _presses++; }
@end

static NSEvent *mouseEvent(NSView *view, NSEventType type)
{
    NSPoint point = [view convertPoint: NSMakePoint(NSMidX(view.bounds), NSMidY(view.bounds)) toView: nil];
    return [NSEvent mouseEventWithType: type
                              location: point
                         modifierFlags: 0
                             timestamp: [[NSProcessInfo processInfo] systemUptime]
                          windowNumber: [[view window] windowNumber]
                               context: nil
                           eventNumber: 0
                            clickCount: 1
                              pressure: type == NSEventTypeLeftMouseUp ? 0 : 1];
}

// Presses on the field and releases; whether the press reached the container, and whether the field took the keys
static void press(NSTextField *field, Container *container, NSString *kind, BOOL expectForwarded)
{
    NSWindow *window = field.window;
    [window makeFirstResponder: container];
    container.presses = 0;
    [NSApp postEvent: mouseEvent(field, NSEventTypeLeftMouseUp) atStart: NO];
    [window sendEvent: mouseEvent(field, NSEventTypeLeftMouseDown)];
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask: NSEventMaskAny untilDate: nil inMode: NSDefaultRunLoopMode dequeue: YES]))
        [NSApp sendEvent: event];
    id responder = [window firstResponder];
    BOOL fieldTookKeys = responder == field || ([responder isKindOfClass: [NSText class]] && [(NSText *) responder delegate] == (id) field);
    if (expectForwarded) {
        expect(container.presses == 1, [NSString stringWithFormat: @"%@: the press goes to the superview (%ld)", kind, (long) container.presses]);
        expect(!fieldTookKeys, [NSString stringWithFormat: @"%@: it doesn't become first responder", kind]);
    } else {
        expect(container.presses == 0, [NSString stringWithFormat: @"%@: the press stays with it (%ld)", kind, (long) container.presses]);
        expect(fieldTookKeys, [NSString stringWithFormat: @"%@: it becomes first responder", kind]);
    }
}

int main(void)
{
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200) styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered defer: NO];
        window.releasedWhenClosed = NO;
        Container *container = [[Container alloc] initWithFrame: [window.contentView bounds]];
        [window.contentView addSubview: container];
        NSTextField *label = [NSTextField labelWithString: @"label"];
        label.frame = NSMakeRect(10, 10, 100, 22);
        NSTextField *selectable = [NSTextField labelWithString: @"selectable"];
        selectable.selectable = YES;
        selectable.frame = NSMakeRect(10, 50, 100, 22);
        NSTextField *editable = [NSTextField textFieldWithString: @"editable"];
        editable.frame = NSMakeRect(10, 90, 100, 22);
        for (NSView *view in @[ label, selectable, editable ])
            [container addSubview: view];
        [window makeKeyAndOrderFront: nil];
        [window displayIfNeeded];

        expect(!label.isEditable && !label.isSelectable, @"labelWithString: makes a label");
        expect(!label.acceptsFirstResponder && !selectable.acceptsFirstResponder && editable.acceptsFirstResponder,
               @"only an editable field accepts first responder (a selectable one takes it when pressed)");
        press(label, container, @"a label", YES);
        press(selectable, container, @"a selectable field", NO);
        press(editable, container, @"an editable field", NO);

        printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    }
    return failures != 0;
}
