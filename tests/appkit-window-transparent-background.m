// Copyright (C) 2026 Lubos Dolezel
//
// A window that is not opaque and has a clear background colour keeps the area its views do not paint
// transparent, while an opaque window has its background painted. The test draws a red square in a
// content view of each kind of window, displays it and reads the window's backing bitmap (a Darling window has
// one, so the test does not run on macOS): the pixel outside the square has alpha 0 in the non-opaque window with a
// clear background and alpha 255 in an opaque one, and the square is red in both. This pins that windows which
// are made transparent explicitly stay transparent now that a new window is opaque by default. Needs a
// window server.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    failures += !ok;
}

@interface Square : NSView
@end
@implementation Square
- (void) drawRect: (NSRect) rect
{
    [[NSColor redColor] setFill];
    NSRectFill(NSMakeRect(20, 20, 40, 40));
}
@end

static void spin(double seconds)
{
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([until timeIntervalSinceNow] > 0) {
        NSEvent *e = [NSApp nextEventMatchingMask: NSEventMaskAny untilDate: until inMode: NSDefaultRunLoopMode dequeue: YES];
        if (e != nil)
            [NSApp sendEvent: e];
    }
}

// The pixel at window point (x, y), y from the top (alpha, red, green).
static BOOL pixel(NSWindow *window, int x, int y, int *alpha, int *red, int *green)
{
    CGContextRef port = (CGContextRef) [[window graphicsContext] graphicsPort];
    unsigned char *data = port != NULL ? CGBitmapContextGetData(port) : NULL;
    if (data == NULL)
        return NO;
    size_t bpr = CGBitmapContextGetBytesPerRow(port);
    size_t height = CGBitmapContextGetHeight(port);
    NSRect content = [window contentRectForFrameRect: [window frame]];
    int top = (int) (height - content.size.height);
    unsigned char *p = data + (size_t) (top + y) * bpr + (size_t) x * 4;
    BOOL little = (CGBitmapContextGetBitmapInfo(port) & kCGBitmapByteOrderMask) == kCGBitmapByteOrder32Little;
    *alpha = little ? p[3] : p[0];
    *red = little ? p[2] : p[1];
    *green = little ? p[1] : p[2];
    return YES;
}

static void run(BOOL opaque)
{
    NSString *label = opaque ? @"opaque window" : @"non-opaque window with clear background";
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 150) styleMask: NSWindowStyleMaskBorderless
                                                     backing: NSBackingStoreBuffered defer: NO];
    [window setOpaque: opaque];
    [window setBackgroundColor: opaque ? [NSColor whiteColor] : [NSColor clearColor]];
    [window setContentView: [[[Square alloc] initWithFrame: NSMakeRect(0, 0, 200, 150)] autorelease]];
    [window orderFront: nil];
    spin(0.8);
    [window displayIfNeeded];
    expect([window isOpaque] == opaque, [NSString stringWithFormat: @"%@: isOpaque is %d", label, opaque]);
    int alpha = -1, red = -1, green = -1;
    if (!pixel(window, 150, 100, &alpha, &red, &green)) {
        printf("no bitmap: pixel checks skipped\n");
    } else {
        printf("%s: outside pixel alpha %d\n", [label UTF8String], alpha);
        expect(opaque ? alpha == 255 : alpha == 0, [NSString stringWithFormat: @"%@: the area outside the square has alpha %d", label, opaque ? 255 : 0]);
        // the square is at 20..60 from the bottom of the 150 point high view: 90..130 from the top
        pixel(window, 40, 110, &alpha, &red, &green);
        expect(alpha == 255 && red > 200 && green < 50, [NSString stringWithFormat: @"%@: the square is red", label]);
    }
    [window orderOut: nil];
    [window release];
}

int main(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        run(NO);
        run(YES);
    }
    printf(failures ? "FAILED\n" : "PASS\n");
    return failures != 0;
}
