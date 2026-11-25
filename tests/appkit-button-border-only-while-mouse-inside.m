// https://developer.apple.com/documentation/appkit/nsbuttoncell/mouseentered(with:)
// https://developer.apple.com/documentation/appkit/nsbuttoncell/mouseexited(with:)
// A button whose showsBorderOnlyWhileMouseInside is true draws its border when the pointer moves onto it
// and erases it when the pointer moves off; the two messages are sent only when that property is true.
// What the documentation leaves open was observed on macOS 26.7.3 (probe in a window of its own): the button
// watches the pointer with one tracking area owned by its cell, with the button's bounds as the rectangle and
// the options mouse-entered-and-exited and active-always, and none for a button without a border; the cell
// reacts to entered and exited, the button itself does not; with the flag set and the pointer outside, a button
// without a title draws exactly what a button without a border draws; a cell drawn by a view that is not its
// button draws differently from what it draws without the flag. Built without ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static int g_failures;
#define CHECK(cond) do { \
        if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } \
    } while (0)

static NSData *render(NSView *view) {
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect: [view bounds]];
    [view cacheDisplayInRect: [view bounds] toBitmapImageRep: rep];
    return [NSData dataWithBytes: [rep bitmapData] length: [rep bytesPerRow] * [rep pixelsHigh]];
}

static NSEvent *pointerEvent(NSWindow *window, NSEventType type) {
    return [NSEvent enterExitEventWithType: type
                                  location: NSMakePoint(30, 30)
                             modifierFlags: 0
                                 timestamp: 0
                              windowNumber: [window windowNumber]
                                   context: nil
                               eventNumber: 0
                            trackingNumber: 0
                                  userData: NULL];
}

static NSTrackingArea *pointerArea(NSButton *button) {
    for (NSTrackingArea *area in [button trackingAreas]) {
        if ([area options] & NSTrackingMouseEnteredAndExited)
            return area;
    }
    return nil;
}

static BOOL watchesPointer(NSButton *button) {
    return pointerArea(button) != nil;
}

// What the window does with a tracking area: sends the event to its owner.
static void deliver(NSButton *button, NSEvent *event) {
    NSTrackingArea *area = pointerArea(button);
    if ([event type] == NSEventTypeMouseEntered)
        [[area owner] mouseEntered: event];
    else
        [[area owner] mouseExited: event];
}

static BOOL buttonDeallocated;

@interface WatchedButton : NSButton
@end
@implementation WatchedButton
- (void) dealloc {
    buttonDeallocated = YES;
    [super dealloc];
}
@end

// Draws a cell with a control view that is not a button, as a matrix or a table does.
@interface CellHost : NSView {
    NSButtonCell *hostedCell;
}
- (void) setHostedCell: (NSButtonCell *) cell;
@end
@implementation CellHost
- (void) setHostedCell: (NSButtonCell *) cell {
    [hostedCell autorelease];
    hostedCell = [cell retain];
}
- (void) drawRect: (NSRect) rect {
    [hostedCell drawWithFrame: [self bounds] inView: self];
}
- (void) dealloc {
    [hostedCell release];
    [super dealloc];
}
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 100)
                                                        styleMask: NSWindowStyleMaskTitled
                                                          backing: NSBackingStoreBuffered
                                                            defer: NO] autorelease];
        NSButton *button = [[[NSButton alloc] initWithFrame: NSMakeRect(20, 20, 120, 32)] autorelease];
        [button setTitle: @"Title"];
        [button setBezelStyle: NSRoundedBezelStyle];
        [[window contentView] addSubview: button];

        // Without the property the border is always drawn and the messages change nothing.
        NSData *bordered = render(button);
        [[button cell] mouseEntered: pointerEvent(window, NSEventTypeMouseEntered)];
        CHECK([render(button) isEqual: bordered]);
        [[button cell] mouseExited: pointerEvent(window, NSEventTypeMouseExited)];
        CHECK([render(button) isEqual: bordered]);
        CHECK(!watchesPointer(button));

        [button setShowsBorderOnlyWhileMouseInside: YES];
        CHECK(watchesPointer(button));
        NSData *borderless = render(button);
        CHECK(![borderless isEqual: bordered]);           // the border is gone until the pointer enters

        // The area as observed on macOS: owned by the cell, the button's bounds, entered-and-exited and active-always.
        NSTrackingArea *area = pointerArea(button);
        CHECK([button trackingAreas] != nil && [[button trackingAreas] count] == 1);
        CHECK([area owner] == [button cell]);
        CHECK(NSEqualRects([area rect], [button bounds]));
        CHECK([area options] == (NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways));

        // The button itself does not react to the pointer, its cell does.
        [button mouseEntered: pointerEvent(window, NSEventTypeMouseEntered)];
        CHECK([render(button) isEqual: borderless]);
        deliver(button, pointerEvent(window, NSEventTypeMouseEntered));   // what the window sends the area's owner
        CHECK([render(button) isEqual: bordered]);
        deliver(button, pointerEvent(window, NSEventTypeMouseExited));
        CHECK([render(button) isEqual: borderless]);

        // Without a border there is nothing to show and nothing to watch.
        [button setBordered: NO];
        CHECK(!watchesPointer(button));
        [button setBordered: YES];
        CHECK(watchesPointer(button));

        // With no title the hidden border leaves exactly what a button without a border draws.
        {
            NSButton *plain = [[[NSButton alloc] initWithFrame: NSMakeRect(20, 20, 120, 32)] autorelease];
            [plain setTitle: @""];
            [plain setBezelStyle: NSRoundedBezelStyle];
            [[window contentView] addSubview: plain];
            [plain setBordered: NO];
            NSData *noBorder = render(plain);
            [plain setBordered: YES];
            NSData *withBorder = render(plain);
            [plain setShowsBorderOnlyWhileMouseInside: YES];
            CHECK(![noBorder isEqual: withBorder]);
            CHECK([render(plain) isEqual: noBorder]);
            [plain removeFromSuperview];
        }

        [button setShowsBorderOnlyWhileMouseInside: NO];
        CHECK(!watchesPointer(button));
        CHECK([render(button) isEqual: bordered]);

        // The property set on the cell, not the button, after the button was drawn: the button is told.
        [[button cell] setShowsBorderOnlyWhileMouseInside: YES];
        CHECK(watchesPointer(button));
        [button setNeedsDisplay: YES];
        CHECK([render(button) isEqual: borderless]);

        // The view rebuilds its tracking areas when it or an ancestor moves or resizes; the new area never
        // saw the pointer come in, so the cell is told where the pointer is now (the window's mouse location;
        // a pointer over the button counts as inside, whether or not the application is active).
        deliver(button, pointerEvent(window, NSEventTypeMouseEntered));
        CHECK([render(button) isEqual: bordered]);
        [button updateTrackingAreas];
        // The pointer's position cannot be set here: when it happens to be over the button the border is
        // rightly kept, so that case is not checked.
        NSPoint pointer = [button convertPoint: [window mouseLocationOutsideOfEventStream] fromView: nil];
        if (!NSMouseInRect(pointer, [button bounds], [button isFlipped]))
            CHECK([render(button) isEqual: borderless]);
        [[button cell] setShowsBorderOnlyWhileMouseInside: NO];
        CHECK(!watchesPointer(button));

        // The property set after the button is in a window, and a cell supplied later, both install it.
        NSButtonCell *replacement = [[[NSButtonCell alloc] initTextCell: @"Title"] autorelease];
        [replacement setBezelStyle: NSRoundedBezelStyle];
        [replacement setShowsBorderOnlyWhileMouseInside: YES];
        [button setCell: replacement];
        CHECK(watchesPointer(button));
        [button setCell: [[[NSButtonCell alloc] initTextCell: @"Title"] autorelease]];
        CHECK(!watchesPointer(button));

        // A cell that is not in a button never hears of the pointer, so its border stays hidden (observed: it draws
        // differently from what it draws without the flag).
        NSButtonCell *hosted = [[[NSButtonCell alloc] initTextCell: @"Title"] autorelease];
        [hosted setBezelStyle: NSRoundedBezelStyle];
        CellHost *host = [[[CellHost alloc] initWithFrame: NSMakeRect(0, 0, 120, 32)] autorelease];
        [host setHostedCell: hosted];
        NSData *hostedBordered = render(host);
        [hosted setShowsBorderOnlyWhileMouseInside: YES];
        CHECK(![render(host) isEqual: hostedBordered]);
    }

    // The tracking area does not keep the button alive.
    @autoreleasepool {
        WatchedButton *watched = [[WatchedButton alloc] initWithFrame: NSMakeRect(0, 0, 100, 30)];
        [watched setShowsBorderOnlyWhileMouseInside: YES];
        CHECK(watchesPointer(watched));
        [watched release];
    }
    CHECK(buttonDeallocated);
    if (g_failures) { printf("%d failure(s)\n", g_failures); return 1; }
    printf("ok\n");
    return 0;
}
