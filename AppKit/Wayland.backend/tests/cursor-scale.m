// Sets an image cursor, then the arrow, hides the cursor, shows the arrow again and waits for the
// runner to change the output scale (2 to 1) with the arrow shown. It reports what the display
// picked, for cursor-scale-check.py to compare with the Wayland wire log. The runner moves the
// pointer into the window and changes the scale when "WAIT-RESCALE" appears.
// Needs DARLING_APPKIT_BACKEND=wayland.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>

// CoreGraphics' private connection calls (CoreGraphicsPrivate.h, not in the public headers).
extern int CGSMainConnectionID(void);
extern id _CGSConnectionForID(int connectionID);

@interface NSObject (CursorScaleFixture)
+ (id) currentDisplay;
- (id) cursorWithImage: (NSImage *) image hotSpot: (NSPoint) point;
- (id) cursorWithName: (NSString *) name;
- (void) setCursor: (id) cursor;
- (uint32_t) renderScale120;
@end

static id display;
static uint32_t field(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    return ivar ? *(uint32_t *) ((char *) object + ivar_getOffset(ivar)) : 0;
}
// The cursor of the pointer is CoreGraphics' (its Wayland connection's pointer decoder has it).
static id cursorObject(void) {
    id connection = _CGSConnectionForID(CGSMainConnectionID());
    Ivar decoder = class_getInstanceVariable(object_getClass(connection), "_pointerDecoder");
    id pointer = decoder ? object_getIvar(connection, decoder) : nil;
    Ivar cursor = pointer ? class_getInstanceVariable(object_getClass(pointer), "_cursorObject") : NULL;
    return cursor ? object_getIvar(pointer, cursor) : nil;
}

@interface FlatCursorImage : NSImage
@end
@implementation FlatCursorImage
- (void) drawInRect: (NSRect) rect fromRect: (NSRect) source operation: (NSCompositingOperation) operation
           fraction: (CGFloat) fraction {
    [[NSColor cyanColor] setFill];
    NSRectFill(rect);
}
@end

@interface Driver : NSObject {
@public
    id imageCursor, arrow;
}
@end
@implementation Driver
- (void) step: (NSTimer *) timer {
    static int stage;
    static NSTimeInterval until, since;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now < until || !field(display, "_pointerEnterSerial")) return;
    switch (stage++) {
    case 0:
        [display setCursor: imageCursor];
        printf("STAGE image render=%u\n", [cursorObject() renderScale120]);
        break;
    case 1:
        [display setCursor: arrow];
        printf("STAGE arrow render=%u theme=%u\n", [cursorObject() renderScale120], field(cursorObject(), "_themeScale120"));
        break;
    case 2:
        CGDisplayHideCursor(CGMainDisplayID());
        puts("STAGE hidden");
        break;
    case 3:
        CGDisplayShowCursor(CGMainDisplayID());
        [display setCursor: arrow];
        printf("STAGE shown-again render=%u\n", [cursorObject() renderScale120]);
        // The runner now changes the output scale (2 to 1) while the arrow is shown; the backend
        // has to rasterise and tag the cursor again by itself, with no new setCursor:.
        puts("WAIT-RESCALE");
        since = now;
        break;
    case 4:
        // The theme is only loaded when the compositor does not draw the named cursors itself.
        if ([cursorObject() renderScale120] != 120) {
            if (now - since > 60) { puts("STAGE rescale-timeout"); stage = 5; break; }
            stage = 4;  // poll
            return;
        }
        printf("STAGE rescaled render=%u theme=%u\n", [cursorObject() renderScale120], field(cursorObject(), "_themeScale120"));
        until = now + 2;  // let the re-applied cursor settle
        break;
    default:
        puts("DONE");
        fflush(stdout);
        exit(0);
    }
    fflush(stdout);
    if (stage != 4) until = now + 2;
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        display = [NSClassFromString(@"NSDisplay") currentDisplay];
        Driver *driver = [Driver new];
        driver->imageCursor = [[display cursorWithImage: [[[FlatCursorImage alloc] initWithSize: NSMakeSize(31, 17)] autorelease]
                                                hotSpot: NSMakePoint(3, 5)] retain];
        driver->arrow = [[display cursorWithName: @"arrowCursor"] retain];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 500, 350)
                                                       styleMask: NSTitledWindowMask
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window setTitle: @"Cursor scale fixture"];
        [window setBackgroundColor: [NSColor blackColor]];
        [window makeKeyAndOrderFront: nil];
        [NSTimer scheduledTimerWithTimeInterval: .1 target: driver selector: @selector(step:)
                                       userInfo: nil repeats: YES];
        puts("READY");
        fflush(stdout);
        [NSApp run];
    }
}
