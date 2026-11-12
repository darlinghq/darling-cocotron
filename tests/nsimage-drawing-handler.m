// Copyright (C) 2026 Lubos Dolezel
//
// +[NSImage imageWithSize:flipped:drawingHandler:] and the scaled drawing of
// bitmap images, drawn into bitmap contexts (no window or X server needed).
// Checks, from the public contract:
//  - the handler is not run when the image is created, is run with the image
//    rectangle when it is drawn, and may be a stack block (the image copies it);
//  - the flipped argument decides whether the handler's y axis points down;
//  - the image drawn at 1x, with a 2x scale on the destination and stretched to
//    twice the size produces the same pixels as drawing the shapes directly;
//  - a handler that returns NO draws nothing and is called again later;
//  - a handler that raises leaves the current graphics context as it found it
//    and the image usable afterwards;
//  - copies draw independently of the original;
//  - repeatedly stretching a small bitmap image to different sizes keeps
//    producing correct pixels.
// With the argument "strict" it also checks that Darling reuses the raster of
// an unchanged destination (macOS does not promise how often the handler runs).
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static int failures;
static BOOL strict;

#define CHECK(cond, ...) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL line %d: ", __LINE__); \
            fprintf(stderr, __VA_ARGS__); \
            fputc('\n', stderr); \
            failures++; \
        } \
    } while (0)

enum { DW = 40, DH = 40 };

static CGContextRef newCanvas(void) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef port = CGBitmapContextCreate(NULL, DW, DH, 8, DW * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGContextClearRect(port, CGRectMake(0, 0, DW, DH));
    return port;
}

// Pixel at x, y counted from the top row of the bitmap.
static void pixel(CGContextRef port, int x, int y, unsigned char *rgba) {
    const unsigned char *data = CGBitmapContextGetData(port);
    memcpy(rgba, data + y * CGBitmapContextGetBytesPerRow(port) + x * 4, 4);
}

static BOOL isRed(CGContextRef port, int x, int y) {
    unsigned char p[4];
    pixel(port, x, y, p);
    return p[0] == 255 && p[1] == 0 && p[2] == 0 && p[3] == 255;
}

static BOOL isClear(CGContextRef port, int x, int y) {
    unsigned char p[4];
    pixel(port, x, y, p);
    return p[3] == 0;
}

// Draws image with the canvas as current context, drawing rect in unflipped
// points scaled by `scale`.
static void drawImageIn(NSImage *image, NSGraphicsContext *context, CGContextRef canvas, NSRect rect, CGFloat scale) {
    NSGraphicsContext *saved = [NSGraphicsContext currentContext];
    [NSGraphicsContext setCurrentContext: context];
    CGContextSaveGState(canvas);
    CGContextScaleCTM(canvas, scale, scale);
    [image drawInRect: rect fromRect: NSZeroRect operation: NSCompositeSourceOver fraction: 1.0];
    CGContextRestoreGState(canvas);
    [NSGraphicsContext setCurrentContext: saved];
}

static void drawImage(NSImage *image, CGContextRef canvas, NSRect rect, CGFloat scale) {
    drawImageIn(image, [NSGraphicsContext graphicsContextWithGraphicsPort: canvas flipped: NO], canvas, rect, scale);
}

// Number of rows (counted from the top of the bitmap) that are red in column x.
static int redRunFromTop(CGContextRef canvas, int x) {
    int n = 0;
    while (n < DH && isRed(canvas, x, n))
        n++;
    return n;
}

static NSImage *makeImage(BOOL flipped, unsigned *calls, NSRect *lastRect) {
    // A stack block: +imageWithSize:flipped:drawingHandler: must copy it.
    return [NSImage imageWithSize: NSMakeSize(20, 20)
                          flipped: flipped
                   drawingHandler: ^BOOL(NSRect rect) {
                       (*calls)++;
                       *lastRect = rect;
                       // The lower (y = 0 .. 10) half in the handler's own coordinates.
                       [[NSColor redColor] setFill];
                       NSRectFill(NSMakeRect(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height / 2));
                       return YES;
                   }];
}

int main(int argc, char **argv) {
    strict = argc > 1 && strcmp(argv[1], "strict") == 0;
    @autoreleasepool {
        // Creation, rectangle and block ownership.
        unsigned calls = 0;
        NSRect lastRect = NSZeroRect;
        NSImage *image = makeImage(NO, &calls, &lastRect);
        CHECK(image != nil, "image created");
        CHECK(NSEqualSizes([image size], NSMakeSize(20, 20)), "size");
        CHECK(calls == 0, "handler is not run at creation (%u)", calls);

        CGContextRef canvas = newCanvas();
        drawImage(image, canvas, NSMakeRect(0, 0, 20, 20), 1);
        CHECK(calls >= 1, "handler runs when drawn");
        CHECK(NSEqualRects(lastRect, NSMakeRect(0, 0, 20, 20)), "handler rect %g,%g %gx%g", lastRect.origin.x,
              lastRect.origin.y, lastRect.size.width, lastRect.size.height);
        // Unflipped: the lower half of the image is the lower 10 rows of the 20 rows
        // that sit at the bottom of the 40 row canvas, i.e. bitmap rows 30..39.
        CHECK(isRed(canvas, 5, 35) && isRed(canvas, 19, 30) && isRed(canvas, 0, 39), "lower half is red");
        CHECK(isClear(canvas, 5, 29) && isClear(canvas, 5, 20) && isClear(canvas, 25, 35), "rest is clear");

        if (strict) {
            // The raster is kept per graphics context, so draw into one context.
            NSGraphicsContext *same = [NSGraphicsContext graphicsContextWithGraphicsPort: canvas flipped: NO];
            drawImageIn(image, same, canvas, NSMakeRect(0, 0, 20, 20), 1);
            unsigned before = calls;
            drawImageIn(image, same, canvas, NSMakeRect(0, 0, 20, 20), 1);
            CHECK(calls == before, "unchanged destination reuses the raster (%u -> %u)", before, calls);
            [image recache];
            drawImageIn(image, same, canvas, NSMakeRect(0, 0, 20, 20), 1);
            CHECK(calls == before + 1, "recache discards it (%u -> %u)", before, calls);
        }
        CGContextRelease(canvas);

        // Scale 2 on the destination and the same image stretched to 40 points.
        canvas = newCanvas();
        drawImage(image, canvas, NSMakeRect(0, 0, 20, 20), 2);
        CHECK(isRed(canvas, 1, 39) && isRed(canvas, 39, 20) && isRed(canvas, 0, 20), "2x: lower half red");
        CHECK(isClear(canvas, 20, 19) && isClear(canvas, 20, 0), "2x: upper half clear");
        CGContextRelease(canvas);
        canvas = newCanvas();
        drawImage(image, canvas, NSMakeRect(0, 0, 40, 40), 1);
        CHECK(isRed(canvas, 1, 39) && isRed(canvas, 39, 20) && isClear(canvas, 20, 19), "stretched to 2x");
        CGContextRelease(canvas);

        // Flipped images: y = 0 is the top.
        unsigned flippedCalls = 0;
        NSImage *flipped = makeImage(YES, &flippedCalls, &lastRect);
        canvas = newCanvas();
        drawImage(flipped, canvas, NSMakeRect(0, 20, 20, 20), 1);
        CHECK(NSEqualRects(lastRect, NSMakeRect(0, 0, 20, 20)), "flipped handler rect");
        CHECK(redRunFromTop(canvas, 5) == 10, "flipped: red starts at the top of the image (%d rows)", redRunFromTop(canvas, 5));
        CHECK(isClear(canvas, 5, 10) && isClear(canvas, 5, 25), "flipped: lower half clear");
        CGContextRelease(canvas);

        // A handler that returns NO draws nothing and is asked again.
        __block unsigned refused = 0;
        __block BOOL accept = NO;
        NSImage *picky = [NSImage imageWithSize: NSMakeSize(20, 20)
                                        flipped: NO
                                 drawingHandler: ^BOOL(NSRect rect) {
                                     refused++;
                                     if (!accept)
                                         return NO;
                                     [[NSColor redColor] setFill];
                                     NSRectFill(rect);
                                     return YES;
                                 }];
        canvas = newCanvas();
        drawImage(picky, canvas, NSMakeRect(0, 0, 20, 20), 1);
        CHECK(isClear(canvas, 5, 35), "a handler returning NO leaves the canvas alone");
        accept = YES;
        unsigned afterRefusal = refused;
        drawImage(picky, canvas, NSMakeRect(0, 0, 20, 20), 1);
        CHECK(refused > afterRefusal, "the handler is called again after returning NO");
        CHECK(isRed(canvas, 5, 35), "and then draws");
        CGContextRelease(canvas);

        // A handler that raises: the current context survives and the image recovers.
        __block BOOL raise = YES;
        NSImage *raising = [NSImage imageWithSize: NSMakeSize(20, 20)
                                          flipped: NO
                                   drawingHandler: ^BOOL(NSRect rect) {
                                       if (raise)
                                           [NSException raise: @"HandlerFailure" format: @"requested"];
                                       [[NSColor redColor] setFill];
                                       NSRectFill(rect);
                                       return YES;
                                   }];
        canvas = newCanvas();
        NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithGraphicsPort: canvas flipped: NO];
        [NSGraphicsContext setCurrentContext: context];
        BOOL caught = NO;
        @try {
            [raising drawInRect: NSMakeRect(0, 0, 20, 20) fromRect: NSZeroRect operation: NSCompositeSourceOver
                       fraction: 1.0];
        } @catch (NSException *e) {
            caught = [[e name] isEqualToString: @"HandlerFailure"];
        }
        CHECK(caught, "the handler's exception reaches the caller");
        CHECK([NSGraphicsContext currentContext] == context, "the current context is restored after the exception");
        raise = NO;
        [raising drawInRect: NSMakeRect(0, 0, 20, 20) fromRect: NSZeroRect operation: NSCompositeSourceOver
                   fraction: 1.0];
        CHECK(isRed(canvas, 5, 35), "the image draws once the handler stops raising");
        [NSGraphicsContext setCurrentContext: nil];
        CGContextRelease(canvas);

        // Copies draw on their own.
        NSImage *copy = [[image copy] autorelease];
        unsigned original = calls;
        canvas = newCanvas();
        drawImage(copy, canvas, NSMakeRect(0, 0, 20, 20), 1);
        CHECK(isRed(canvas, 5, 35), "the copy draws");
        [image recache];
        drawImage(copy, canvas, NSMakeRect(20, 0, 20, 20), 1);
        CHECK(isRed(canvas, 25, 35), "the copy still draws after the original is recached");
        (void) original;
        CGContextRelease(canvas);

        // Bitmap images stretched to different sizes keep correct pixels.
        NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                                                         pixelsWide: 2
                                                                         pixelsHigh: 2
                                                                      bitsPerSample: 8
                                                                    samplesPerPixel: 4
                                                                           hasAlpha: YES
                                                                           isPlanar: NO
                                                                     colorSpaceName: NSDeviceRGBColorSpace
                                                                        bytesPerRow: 8
                                                                       bitsPerPixel: 32] autorelease];
        unsigned char *bytes = [rep bitmapData];
        // Top row opaque red, bottom row opaque blue.
        for (int i = 0; i < 2; i++) {
            memcpy(bytes + i * 4, (unsigned char[]){255, 0, 0, 255}, 4);
            memcpy(bytes + 8 + i * 4, (unsigned char[]){0, 0, 255, 255}, 4);
        }
        NSImage *small = [[[NSImage alloc] initWithSize: NSMakeSize(2, 2)] autorelease];
        [small addRepresentation: rep];
        int sizes[] = {8, 16, 8, 32, 16};
        for (unsigned i = 0; i < sizeof sizes / sizeof sizes[0]; i++) {
            canvas = newCanvas();
            int n = sizes[i];
            drawImage(small, canvas, NSMakeRect(0, DH - n, n, n), 1);
            unsigned char top[4], bottom[4];
            pixel(canvas, n / 2, 1, top);
            pixel(canvas, n / 2, n - 2, bottom);
            // The rasterizer's interpolation loses a couple of alpha levels (253 for an
            // opaque source), also when the bitmap is drawn without the image cache.
            CHECK(top[0] > 200 && top[2] < 50 && top[3] >= 250, "stretched to %d: top row is red (%d,%d,%d,%d)", n,
                  top[0], top[1], top[2], top[3]);
            CHECK(bottom[2] > 200 && bottom[0] < 50 && bottom[3] >= 250, "stretched to %d: bottom row is blue", n);
            CGContextRelease(canvas);
        }
        (void) flippedCalls;
    }
    if (failures) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    puts("PASS: NSImage drawing handler and scaled drawing");
    return 0;
}
