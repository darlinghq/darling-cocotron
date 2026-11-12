// Public-API smoke gate for the rebuilt frameworks, not extracted method bodies.
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    setbuf(stdout, NULL);
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 40, 40)
        styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO];
    NSView *view = [window contentView];
    [view lockFocus];
    CGContextRef port = [[NSGraphicsContext currentContext] graphicsPort];
    double expected = getenv("TEST_EXPECT_WINDOW_SCALE") ?
        strtod(getenv("TEST_EXPECT_WINDOW_SCALE"), NULL) : 1;
    double actual = CGBitmapContextGetWidth(port) / 40.0;
    printf("Public window backing: expected=%g actual=%g\n", expected, actual);
    assert(fabs(actual - expected) < 0.000001);
    CGContextRef bitmap = NULL;
    if (getenv("TEST_BITMAP_DESTINATION")) {
        CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
        bitmap = CGBitmapContextCreate(NULL, 40, 40, 8, 160, color,
            kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(color);
        assert(bitmap != NULL);
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:
            [NSGraphicsContext graphicsContextWithGraphicsPort:bitmap flipped:NO]];
        port = bitmap;
        expected = 1;
    }
    CGContextClearRect(port, CGRectMake(0, 0, 40, 40));
    __block unsigned calls = 0;
    NSImage *image = [NSImage imageWithSize:NSMakeSize(20, 20) flipped:NO
        drawingHandler:^BOOL(NSRect rect) {
            ++calls;
            CGContextRef callbackPort = [[NSGraphicsContext currentContext] graphicsPort];
            CGAffineTransform transform = CGContextGetUserSpaceToDeviceSpaceTransform(callbackPort);
            double density = hypot(transform.a, transform.b);
            printf("Deferred callback density: expected=%g actual=%g\n", expected, density);
            assert(fabs(density - expected) < 0.000001);
            [[NSColor redColor] setFill];
            NSRectFill(rect);
            return YES;
        }];
    assert(image != nil && calls == 0);
    [image drawInRect:NSMakeRect(0, 0, 20, 20) fromRect:NSZeroRect
        operation:NSCompositeCopy fraction:1];
    assert(calls == 1);
    [image drawInRect:NSMakeRect(0, 0, 20, 20) fromRect:NSZeroRect
        operation:NSCompositeCopy fraction:1];
    assert(calls == 1);
    [image recache];
    [image drawInRect:NSMakeRect(0, 0, 20, 20) fromRect:NSZeroRect
        operation:NSCompositeCopy fraction:1];
    assert(calls == 2);
    size_t bytes = CGBitmapContextGetBytesPerRow(port) * CGBitmapContextGetHeight(port);
    void *data = CGBitmapContextGetData(port);
    assert(bytes > 0 && data != NULL);
    void *rendered = malloc(bytes);
    assert(rendered != NULL);
    memcpy(rendered, data, bytes);
    CGContextClearRect(port, CGRectMake(0, 0, 40, 40));
    [[NSColor redColor] setFill];
    NSRectFill(NSMakeRect(0, 0, 20, 20));
    assert(memcmp(rendered, data, bytes) == 0);
    free(rendered);
    if (bitmap) {
        [NSGraphicsContext restoreGraphicsState];
        CGContextRelease(bitmap);
    }
    [view unlockFocus];
    [window close];
    [window release];
    [pool drain];
    puts("PASS: rebuilt public NSImage deferred drawing and observed window scale");
    return 0;
}
