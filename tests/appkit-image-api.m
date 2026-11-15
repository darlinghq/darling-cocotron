/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSImage: representation selection for a destination (-bestRepresentationForRect:context:hints:),
 * -recommendedLayerContentsScale: and -layerContentsForContentsScale:, hit testing, keyed archiving,
 * -initWithDataIgnoringOrientation:, -lockFocusFlipped:, -isValid and the drawing conveniences
 * (-dissolveToPoint:fraction:). Expected values are what macOS 10.14.4 and 26.7.3 answer for the same
 * calls (probe: vd-upstream/mac-probes/v615_image.m). No window server needed.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

// The API under test, declared here so that the test also builds against an SDK that predates it.
@interface NSImage (V615Test)
- (NSImageRep *) bestRepresentationForRect: (NSRect) rect context: (NSGraphicsContext *) context hints: (NSDictionary *) hints;
- (BOOL) hitTestRect: (NSRect) test withImageDestinationRect: (NSRect) dest context: (NSGraphicsContext *) context hints: (NSDictionary *) hints flipped: (BOOL) flipped;
- (CGFloat) recommendedLayerContentsScale: (CGFloat) scale;
- (id) layerContentsForContentsScale: (CGFloat) scale;
- (id) initWithDataIgnoringOrientation: (NSData *) data;
- (BOOL) matchesOnlyOnBestFittingAxis;
- (void) setMatchesOnlyOnBestFittingAxis: (BOOL) flag;
- (void) lockFocusFlipped: (BOOL) flipped;
@end

static int failures;

#define CHECK(cond, ...) \
    do { \
        if (!(cond)) { \
            failures++; \
            printf("FAIL line %d: ", __LINE__); \
            printf(__VA_ARGS__); \
            printf("\n"); \
        } \
    } while (0)

// A representation of px by px pixels that is pointSize points wide; the left half is transparent
// when halfTransparent is set.
static NSBitmapImageRep *bitmap(int px, CGFloat pointSize, int r, int g, int b, BOOL halfTransparent) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, px, px, 8, 0, space, kCGImageAlphaPremultipliedLast);
    CGContextSetRGBFillColor(c, r / 255.0, g / 255.0, b / 255.0, 1);
    CGContextFillRect(c, CGRectMake(halfTransparent ? px / 2 : 0, 0, halfTransparent ? px / 2 : px, px));
    CGImageRef image = CGBitmapContextCreateImage(c);
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithCGImage: image] autorelease];
    CGImageRelease(image);
    CGContextRelease(c);
    CGColorSpaceRelease(space);
    [rep setSize: NSMakeSize(pointSize, pointSize)];
    return rep;
}

// A context that scales drawing by `scale`, as drawing into a window of that backing scale does.
static NSGraphicsContext *scaledContext(CGFloat scale) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, (size_t) (64 * scale), (size_t) (64 * scale), 8, 0, space, kCGImageAlphaPremultipliedLast);
    CGContextScaleCTM(c, scale, scale);
    CGColorSpaceRelease(space);
    return [NSGraphicsContext graphicsContextWithGraphicsPort: c flipped: NO];
}

static NSImage *threeScales(void) {
    NSImage *image = [[[NSImage alloc] initWithSize: NSMakeSize(16, 16)] autorelease];
    [image addRepresentation: bitmap(16, 16, 255, 0, 0, NO)];
    [image addRepresentation: bitmap(32, 16, 0, 255, 0, NO)];
    [image addRepresentation: bitmap(64, 16, 0, 0, 255, NO)];
    return image;
}

static void testRepresentationSelection(void) {
    NSImage *image = threeScales();
    CHECK([image matchesOnMultipleResolution] && ![image matchesOnlyOnBestFittingAxis], "defaults");

    // pixels needed = destination size * the scale of the context, rounded up; the smallest
    // representation with enough pixels, else the largest
    CGFloat contextScale[] = { 1, 2, 3 };
    NSInteger expect16[] = { 16, 32, 64 };
    NSInteger expect32[] = { 32, 64, 64 };
    for (int i = 0; i < 3; i++) {
        NSGraphicsContext *c = scaledContext(contextScale[i]);
        NSImageRep *rep = [image bestRepresentationForRect: NSMakeRect(0, 0, 16, 16) context: c hints: nil];
        CHECK([rep pixelsWide] == expect16[i], "16 points at scale %g: %ld pixels", contextScale[i], (long) [rep pixelsWide]);
        rep = [image bestRepresentationForRect: NSMakeRect(0, 0, 32, 32) context: c hints: nil];
        CHECK([rep pixelsWide] == expect32[i], "32 points at scale %g: %ld pixels", contextScale[i], (long) [rep pixelsWide]);
    }

    // The CTM hint stands for the context's scale
    NSAffineTransform *ctm = [NSAffineTransform transform];
    [ctm scaleBy: 2];
    NSImageRep *rep = [image bestRepresentationForRect: NSMakeRect(0, 0, 16, 16) context: scaledContext(1)
                                                 hints: [NSDictionary dictionaryWithObject: ctm forKey: NSImageHintCTM]];
    CHECK([rep pixelsWide] == 32, "CTM hint of scale 2");

    // One representation is the answer whatever the scale
    NSImage *single = [[[NSImage alloc] initWithSize: NSMakeSize(16, 16)] autorelease];
    [single addRepresentation: bitmap(16, 16, 1, 2, 3, NO)];
    rep = [single bestRepresentationForRect: NSMakeRect(0, 0, 16, 16) context: scaledContext(2) hints: nil];
    CHECK([rep pixelsWide] == 16, "single representation");

    // The scale counts with multiple resolution matching off too
    [image setMatchesOnMultipleResolution: NO];
    rep = [image bestRepresentationForRect: NSMakeRect(0, 0, 16, 16) context: scaledContext(2) hints: nil];
    CHECK([rep pixelsWide] == 32, "matching off: the scale still counts");
    [image setMatchesOnMultipleResolution: YES];

    [image setMatchesOnlyOnBestFittingAxis: YES];
    CHECK([image matchesOnlyOnBestFittingAxis], "stored");
    [image setMatchesOnlyOnBestFittingAxis: NO];
}

static void testLayerContents(void) {
    NSImage *image = threeScales();
    CGFloat preferred[] = { 0, 1, 2, 3, 4 };
    CGFloat expect[] = { 1, 1, 2, 4, 4 };
    for (int i = 0; i < 5; i++)
        CHECK([image recommendedLayerContentsScale: preferred[i]] == expect[i], "recommended scale for %g: %g", preferred[i], [image recommendedLayerContentsScale: preferred[i]]);

    NSImage *single = [[[NSImage alloc] initWithSize: NSMakeSize(16, 16)] autorelease];
    [single addRepresentation: bitmap(16, 16, 1, 2, 3, NO)];
    CHECK([single recommendedLayerContentsScale: 2] == 1, "a 1x image is 1x for any layer");
    CHECK([image layerContentsForContentsScale: 2] != nil, "layer contents for 2");
    CHECK([single layerContentsForContentsScale: 1] != nil, "layer contents for a 1x image");
}

static void testHitTest(void) {
    NSImage *half = [[[NSImage alloc] initWithSize: NSMakeSize(16, 16)] autorelease];
    [half addRepresentation: bitmap(16, 16, 9, 9, 9, YES)];
    NSGraphicsContext *c = scaledContext(1);
    NSRect dest = NSMakeRect(0, 0, 16, 16);
    CHECK([half hitTestRect: NSMakeRect(12, 4, 1, 1) withImageDestinationRect: dest context: c hints: nil flipped: NO], "opaque half is hit");
    CHECK(![half hitTestRect: NSMakeRect(2, 4, 1, 1) withImageDestinationRect: dest context: c hints: nil flipped: NO], "transparent half is not");
    CHECK(![half hitTestRect: NSMakeRect(40, 4, 1, 1) withImageDestinationRect: dest context: c hints: nil flipped: NO], "outside is not");
    CHECK([half hitTestRect: NSMakeRect(0, 0, 16, 16) withImageDestinationRect: dest context: c hints: nil flipped: NO], "a rect over both halves hits");
    CHECK([half hitTestRect: NSMakeRect(24, 8, 1, 1) withImageDestinationRect: NSMakeRect(0, 0, 32, 32) context: c hints: nil flipped: NO], "image drawn scaled up");
    CHECK(![half hitTestRect: NSMakeRect(2, 4, 1, 1) withImageDestinationRect: dest context: c hints: nil flipped: YES], "flipped, transparent half");
    CHECK([half hitTestRect: NSMakeRect(12, 4, 1, 1) withImageDestinationRect: dest context: c hints: nil flipped: YES], "flipped, opaque half");
}

static void testArchiving(void) {
    NSImage *image = threeScales();
    NSData *archive = [NSKeyedArchiver archivedDataWithRootObject: image];
    NSImage *back = [NSKeyedUnarchiver unarchiveObjectWithData: archive];
    CHECK(back != nil && [[back representations] count] == 3, "all representations survive: %lu", (unsigned long) [[back representations] count]);
    CHECK(back.size.width == 16 && back.size.height == 16, "size survives");

    NSImage *sized = threeScales();
    [sized setSize: NSMakeSize(20, 30)];
    back = [NSKeyedUnarchiver unarchiveObjectWithData: [NSKeyedArchiver archivedDataWithRootObject: sized]];
    CHECK(back.size.width == 20 && back.size.height == 30, "an explicit size survives: %g,%g", back.size.width, back.size.height);

    NSImage *named = threeScales();
    CHECK([named setName: @"v615-image-api-named"], "setName");
    back = [NSKeyedUnarchiver unarchiveObjectWithData: [NSKeyedArchiver archivedDataWithRootObject: named]];
    CHECK(back != nil && [[back name] isEqual: @"v615-image-api-named"], "a named image comes back with its name");
    [named setName: nil];
}

static void testInitAndFocus(void) {
    NSImage *image = threeScales();
    NSData *tiff = [image TIFFRepresentation];
    NSImage *fromData = [[[NSImage alloc] initWithDataIgnoringOrientation: tiff] autorelease];
    CHECK(fromData != nil && fromData.size.width == 16, "initWithDataIgnoringOrientation");
    CHECK([[[NSImage alloc] initWithDataIgnoringOrientation: [@"not an image" dataUsingEncoding: NSUTF8StringEncoding]] autorelease] == nil, "garbage gives nil");

    NSImage *focus = [[[NSImage alloc] initWithSize: NSMakeSize(4, 4)] autorelease];
    [focus lockFocusFlipped: YES];
    CHECK([[NSGraphicsContext currentContext] isFlipped], "lockFocusFlipped: YES gives a flipped context");
    [focus unlockFocus];
    [focus lockFocus];
    CHECK(![[NSGraphicsContext currentContext] isFlipped], "lockFocus: not flipped");
    [focus unlockFocus];
    CHECK(![focus isFlipped], "the image's own flippedness is untouched");

    CHECK([image isValid], "an image with representations is valid");
    [image cancelIncrementalLoad];
}

@interface Replacement : NSObject <NSImageDelegate> {
@public
    NSImage *image;
    int asked;
}
@end
@implementation Replacement
- (NSImage *) imageDidNotDraw: (NSImage *) sender inRect: (NSRect) rect {
    asked++;
    return image;
}
@end

static void testDelegate(void) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, 8, 8, 8, 0, space, kCGImageAlphaPremultipliedLast);
    CGContextClearRect(c, CGRectMake(0, 0, 8, 8));
    Replacement *delegate = [[[Replacement alloc] init] autorelease];
    delegate->image = [[[NSImage alloc] initWithSize: NSMakeSize(8, 8)] autorelease];
    [delegate->image addRepresentation: bitmap(8, 8, 255, 0, 0, NO)];
    NSImage *empty = [[[NSImage alloc] initWithSize: NSMakeSize(8, 8)] autorelease];
    [empty setDelegate: delegate];

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithGraphicsPort: c flipped: NO]];
    [empty drawInRect: NSMakeRect(0, 0, 8, 8)];
    [NSGraphicsContext restoreGraphicsState];

    const unsigned char *p = CGBitmapContextGetData(c);
    CHECK(delegate->asked >= 1, "imageDidNotDraw:inRect: is asked for an image with nothing to draw");
    CHECK(p[3] == 255 && p[0] == 255, "the image the delegate gave is drawn: %d %d", p[0], p[3]);
    CGContextRelease(c);
    CGColorSpaceRelease(space);
}

static void testDissolve(void) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, 8, 8, 8, 0, space, kCGImageAlphaPremultipliedLast);
    CGContextClearRect(c, CGRectMake(0, 0, 8, 8));
    NSImage *red = [[[NSImage alloc] initWithSize: NSMakeSize(8, 8)] autorelease];
    [red addRepresentation: bitmap(8, 8, 255, 0, 0, NO)];

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithGraphicsPort: c flipped: NO]];
    [red dissolveToPoint: NSZeroPoint fraction: 0.5];
    [NSGraphicsContext restoreGraphicsState];

    const unsigned char *p = CGBitmapContextGetData(c);
    int alpha = p[3];
    CHECK(alpha > 100 && alpha < 156, "dissolve at 0.5 leaves half the alpha: %d", alpha);
    CGContextRelease(c);
    CGColorSpaceRelease(space);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        testRepresentationSelection();
        testLayerContents();
        testHitTest();
        testArchiving();
        testInitAndFocus();
        testDelegate();
        testDissolve();
    }
    if (failures)
        return 1;
    puts("image api: PASS");
    return 0;
}
