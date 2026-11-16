// Copyright (C) 2026 Lubos Dolezel
//
// -[NSImage lockFocus] / -unlockFocus: drawing into an image leaves the image with one
// bitmap-like representation that holds the pixels (the image's previous representations are
// drawn into it first and are not kept next to it), whether the image started out blank or with a
// bitmap, flipped or not. Its TIFFRepresentation holds exactly one image, upright, and drawing the
// image shows what was drawn. Expectations are from black-box observation of macOS 10.14.4
// (the image has a single NSCGImageSnapshotRep after unlockFocus); colours are compared with
// tolerance since macOS colour manages the drawing.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

#define CHECK(cond, ...) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL line %d: ", __LINE__); \
            fprintf(stderr, __VA_ARGS__); \
            fputc('\n', stderr); \
            failures++; \
        } \
    } while (0)

enum Kind { Red, Green, Blue, Yellow, Clear };

static BOOL isKind(NSBitmapImageRep *rep, int x, int y, enum Kind kind) {
    NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    CGFloat r = [c redComponent], g = [c greenComponent], b = [c blueComponent], a = [c alphaComponent];
    switch (kind) {
    case Red:
        return a > 0.9 && r > 0.9 && g < 0.3 && b < 0.1;
    case Green:
        return a > 0.9 && r < 0.1 && g > 0.9 && b < 0.1;
    case Blue:
        return a > 0.9 && r < 0.1 && g < 0.3 && b > 0.9;
    case Yellow:
        return a > 0.9 && r > 0.9 && g > 0.9 && b < 0.1;
    case Clear:
        return a < 0.05;
    }
    return NO;
}

static CGContextRef newContext(void) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, 16, 16, 8, 0, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    return ctx;
}

static NSBitmapImageRep *repOfContext(CGContextRef ctx) {
    CGImageRef image = CGBitmapContextCreateImage(ctx);
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithCGImage: image] autorelease];
    CGImageRelease(image);
    return rep;
}

static void checkSingleRep(NSImage *image, const char *name) {
    NSArray *reps = [image representations];
    CHECK([reps count] == 1, "%s: %lu representations after unlockFocus, expected 1", name, (unsigned long) [reps count]);
    for (NSImageRep *rep in reps)
        CHECK(![NSStringFromClass([rep class]) isEqualToString: @"NSCachedImageRep"], "%s: window-backed cached rep kept", name);
    CHECK(NSEqualSizes([image size], NSMakeSize(16, 16)), "%s: size changed to %s", name,
          [NSStringFromSize([image size]) UTF8String]);
}

// The TIFF has one image of the image's size and its pixels satisfy the check.
static NSBitmapImageRep *checkTIFF(NSImage *image, const char *name) {
    NSData *tiff = [image TIFFRepresentation];
    CHECK(tiff != nil, "%s: no TIFFRepresentation", name);
    NSArray *reps = [NSBitmapImageRep imageRepsWithData: tiff];
    CHECK([reps count] == 1, "%s: TIFF holds %lu images, expected 1", name, (unsigned long) [reps count]);
    NSBitmapImageRep *rep = [reps firstObject];
    CHECK([rep pixelsWide] == 16 && [rep pixelsHigh] == 16, "%s: TIFF image %ldx%ld", name, (long) [rep pixelsWide],
          (long) [rep pixelsHigh]);
    return rep;
}

// Rows of a bitmap rep run from the top of the image down.
static void blankImage(BOOL flipped) {
    const char *name = flipped ? "blank flipped" : "blank";
    NSImage *image = [[[NSImage alloc] initWithSize: NSMakeSize(16, 16)] autorelease];
    [image setFlipped: flipped];
    [image lockFocus];
    [[NSColor redColor] set];
    // the top-left quarter of the image as it is seen
    NSRectFill(NSMakeRect(0, flipped ? 0 : 8, 8, 8));
    [image unlockFocus];
    checkSingleRep(image, name);

    NSBitmapImageRep *tiff = checkTIFF(image, name);
    CHECK(isKind(tiff, 2, 2, Red), "%s: TIFF top left is not red", name);
    CHECK(isKind(tiff, 13, 2, Clear), "%s: TIFF top right is not clear", name);
    CHECK(isKind(tiff, 2, 13, Clear), "%s: TIFF bottom left is not clear", name);
    CHECK(isKind(tiff, 13, 13, Clear), "%s: TIFF bottom right is not clear", name);

    CGContextRef ctx = newContext();
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithCGContext: ctx flipped: NO]];
    [image drawInRect: NSMakeRect(0, 0, 16, 16)
             fromRect: NSZeroRect
            operation: NSCompositingOperationSourceOver
             fraction: 1.0];
    [NSGraphicsContext restoreGraphicsState];
    NSBitmapImageRep *drawn = repOfContext(ctx);
    CGContextRelease(ctx);
    CHECK(isKind(drawn, 2, 2, Red), "%s: drawn top left is not red", name);
    CHECK(isKind(drawn, 13, 13, Clear), "%s: drawn bottom right is not clear", name);
}

// An unflipped image that has a bitmap (blue, with a yellow strip along the bottom) keeps it
// as the base of what is drawn, and has only the snapshot afterwards.
static void bitmapImage(void) {
    CGContextRef ctx = newContext();
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithCGContext: ctx flipped: NO]];
    [[NSColor blueColor] set];
    NSRectFill(NSMakeRect(0, 0, 16, 16));
    [[NSColor yellowColor] set];
    NSRectFill(NSMakeRect(0, 0, 16, 4));
    [NSGraphicsContext restoreGraphicsState];
    NSBitmapImageRep *source = repOfContext(ctx);
    CGContextRelease(ctx);

    NSImage *image = [[[NSImage alloc] initWithSize: NSMakeSize(16, 16)] autorelease];
    [image addRepresentation: source];
    CHECK([[image representations] count] == 1, "bitmap image: %lu representations before", (unsigned long) [[image representations] count]);
    [image lockFocus];
    [[NSColor greenColor] set];
    NSRectFill(NSMakeRect(8, 0, 8, 16));
    [image unlockFocus];
    checkSingleRep(image, "bitmap image");

    NSBitmapImageRep *tiff = checkTIFF(image, "bitmap image");
    CHECK(isKind(tiff, 2, 2, Blue), "bitmap image: top left is not blue");
    CHECK(isKind(tiff, 2, 13, Yellow), "bitmap image: bottom left is not yellow");
    CHECK(isKind(tiff, 13, 2, Green), "bitmap image: top right is not green");
    CHECK(isKind(tiff, 13, 13, Green), "bitmap image: bottom right is not green");

    // Focusing again without drawing keeps the content and does not add representations.
    [image lockFocus];
    [image unlockFocus];
    checkSingleRep(image, "bitmap image relocked");
    tiff = checkTIFF(image, "bitmap image relocked");
    CHECK(isKind(tiff, 2, 2, Blue) && isKind(tiff, 13, 13, Green), "bitmap image: content changed by an empty lock");
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        blankImage(NO);
        blankImage(YES);
        bitmapImage();
    }
    if (failures != 0) {
        printf("image lockFocus snapshot: FAIL (%d)\n", failures);
        return 1;
    }
    printf("image lockFocus snapshot: PASS\n");
    return 0;
}
