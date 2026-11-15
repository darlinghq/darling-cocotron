/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Compositing operation values, window levels and priorities, the window depth helpers, the NSOpenGL global
// options and the *UsingOperation fill functions. Values are the public ones. The depth negotiation
// (NSBestDepth) and the NSOpenGL option and version functions are checked only for what the documentation
// states; their results on macOS were not compared.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
static void expect(BOOL condition, const char *label)
{
    printf("%s %s\n", condition ? "PASS" : "FAIL", label);
    failures += !condition;
}

static void checkValues(void)
{
    expect(sizeof(NSCompositingOperation) == sizeof(NSUInteger), "NSCompositingOperation is NSUInteger sized");
    expect(NSCompositingOperationClear == 0 && NSCompositingOperationCopy == 1 && NSCompositingOperationSourceOver == 2,
           "compositing operation values 0..2");
    expect(NSCompositingOperationXOR == 10 && NSCompositingOperationPlusLighter == 13, "compositing operation values 10 and 13");
    expect(NSCompositingOperationMultiply == 14 && NSCompositingOperationLuminosity == 28, "blend operation values");
    expect(NSCompositeSourceOver == NSCompositingOperationSourceOver && NSCompositePlusLighter == NSCompositingOperationPlusLighter,
           "the old NSComposite names equal the new ones");
    expect(NSAnimationEffectDisappearingItemDefault == 0 && NSAnimationEffectPoof == 10, "NSAnimationEffect values");
    expect(NSWindowDepthTwentyfourBitRGB == 0x208 && NSWindowDepthSixtyfourBitRGB == 0x210 &&
                   NSWindowDepthOnehundredtwentyeightBitRGB == 0x220,
           "NSWindowDepth values");
    expect(NSNormalWindowLevel == 0 && NSFloatingWindowLevel == 3, "window level values");
    expect(NSStatusWindowLevel > NSFloatingWindowLevel && NSPopUpMenuWindowLevel > NSStatusWindowLevel &&
                   NSScreenSaverWindowLevel > NSPopUpMenuWindowLevel,
           "window levels are ordered");
    expect(NSStackViewVisibilityPriorityMustHold == 1000 && NSStackViewVisibilityPriorityNotVisible == 0, "stack view priorities");
    expect(NSToolbarItemVisibilityPriorityStandard == 0 && NSToolbarItemVisibilityPriorityLow == -1000 &&
                   NSToolbarItemVisibilityPriorityHigh == 1000 && NSToolbarItemVisibilityPriorityUser == 2000,
           "toolbar item priorities");
    expect(NSTouchBarItemPriorityHigh == 1000 && NSTouchBarItemPriorityNormal == 0 && NSTouchBarItemPriorityLow == -1000,
           "touch bar item priorities");
    expect(NSOpenGLGOFormatCacheSize == 501 && NSOpenGLGOClearFormatCache == 502 && NSOpenGLGORetainRenderers == 503 &&
                   NSOpenGLGOResetLibrary == 504 && NSOpenGLGOUseBuildCache == 506,
           "NSOpenGLGlobalOption values");
}

static void checkDepths(void)
{
    const NSWindowDepth *depths = NSAvailableWindowDepths();
    int count = 0;
    BOOL has24 = NO, has64 = NO, has128 = NO;
    while (depths[count] != 0 && count < 16) {
        has24 |= depths[count] == NSWindowDepthTwentyfourBitRGB;
        has64 |= depths[count] == NSWindowDepthSixtyfourBitRGB;
        has128 |= depths[count] == NSWindowDepthOnehundredtwentyeightBitRGB;
        count++;
    }
    expect(count >= 1 && count < 16, "NSAvailableWindowDepths is zero-terminated");
    expect(has24 && has64 && has128, "the three RGB depths are available");

    expect(NSBitsPerSampleFromDepth(NSWindowDepthTwentyfourBitRGB) == 8, "24 bit RGB has 8 bits per sample");
    expect(NSBitsPerSampleFromDepth(NSWindowDepthSixtyfourBitRGB) == 16, "64 bit RGB has 16 bits per sample");
    expect(NSBitsPerSampleFromDepth(NSWindowDepthOnehundredtwentyeightBitRGB) == 32, "128 bit RGB has 32 bits per sample");
    expect(NSBitsPerPixelFromDepth(NSWindowDepthSixtyfourBitRGB) == 64, "64 bit RGB has 64 bits per pixel");
    expect(!NSPlanarFromDepth(NSWindowDepthTwentyfourBitRGB), "depths are not planar");
    expect(NSColorSpaceFromDepth(NSWindowDepthTwentyfourBitRGB) != nil, "a known depth has a colour space");
    expect(NSColorSpaceFromDepth((NSWindowDepth)0) == nil && NSBitsPerSampleFromDepth((NSWindowDepth)0) == 0,
           "the zero depth is unknown");

    BOOL exact = NO;
    NSWindowDepth depth = NSBestDepth(NSCalibratedRGBColorSpace, 8, 24, NO, &exact);
    expect(depth == NSWindowDepthTwentyfourBitRGB && exact, "NSBestDepth: 8 bit RGB matches exactly");
    exact = YES;
    depth = NSBestDepth(NSCalibratedRGBColorSpace, 16, 64, NO, &exact);
    expect(depth == NSWindowDepthSixtyfourBitRGB && exact, "NSBestDepth: 16 bit RGB matches exactly");
    exact = YES;
    depth = NSBestDepth(NSCalibratedRGBColorSpace, 8, 24, YES, &exact);
    expect(!exact, "NSBestDepth: a planar request is not an exact match");
    exact = YES;
    depth = NSBestDepth(NSCalibratedRGBColorSpace, 64, 256, NO, &exact);
    expect(depth == NSWindowDepthOnehundredtwentyeightBitRGB && !exact, "NSBestDepth: too deep falls back to the deepest depth");
    depth = NSBestDepth(NSCalibratedRGBColorSpace, 8, 24, NO, NULL);
    expect(depth == NSWindowDepthTwentyfourBitRGB, "NSBestDepth accepts a NULL exactMatch");
}

static void checkOpenGLOptions(void)
{
    GLint value = -1;
    NSOpenGLSetOption(NSOpenGLGOFormatCacheSize, 7);
    NSOpenGLGetOption(NSOpenGLGOFormatCacheSize, &value);
    expect(value == 7, "NSOpenGLGetOption returns the value set");
    NSOpenGLSetOption(NSOpenGLGOFormatCacheSize, 9);
    NSOpenGLGetOption(NSOpenGLGOFormatCacheSize, &value);
    expect(value == 9, "NSOpenGLSetOption replaces the value");
    GLint major = -1, minor = -1;
    NSOpenGLGetVersion(&major, &minor);
    expect(major >= 0 && minor >= 0, "NSOpenGLGetVersion fills both outputs");
    NSOpenGLGetVersion(&major, NULL);
    NSOpenGLGetVersion(NULL, &minor);
    NSOpenGLGetVersion(NULL, NULL);
    expect(YES, "NSOpenGLGetVersion accepts NULL outputs");
}

static NSUInteger pixelAt(NSBitmapImageRep *rep, NSInteger x, NSInteger y)
{
    NSUInteger pixel[4] = {0, 0, 0, 0};
    [rep getPixel:pixel atX:x y:y];
    return (pixel[0] << 24) | (pixel[1] << 16) | (pixel[2] << 8) | pixel[3];
}

static NSBitmapImageRep *makeRep(NSInteger bits, NSInteger samples, BOOL planar, NSInteger bitsPerPixel)
{
    return [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                    pixelsWide:5
                                                    pixelsHigh:3
                                                 bitsPerSample:bits
                                               samplesPerPixel:samples
                                                      hasAlpha:NO
                                                      isPlanar:planar
                                                colorSpaceName:samples == 1 ? NSCalibratedWhiteColorSpace : NSCalibratedRGBColorSpace
                                                  bitmapFormat:0
                                                   bytesPerRow:0
                                                  bitsPerPixel:bitsPerPixel] autorelease];
}

static void checkPixelRoundTrip(const char *what, NSBitmapImageRep *rep, NSUInteger maxValue)
{
    NSInteger samples = [rep samplesPerPixel];
    BOOL ok = YES;
    for (NSInteger y = 0; y < 3; y++) {
        for (NSInteger x = 0; x < 5; x++) {
            NSUInteger in[4] = {0, 0, 0, 0};
            for (NSInteger i = 0; i < samples; i++)
                in[i] = (x * 7 + y * 3 + i * 5) % (maxValue + 1);
            [rep setPixel:in atX:x y:y];
        }
    }
    for (NSInteger y = 0; y < 3; y++) {
        for (NSInteger x = 0; x < 5; x++) {
            NSUInteger out[4] = {99, 99, 99, 99};
            [rep getPixel:out atX:x y:y];
            for (NSInteger i = 0; i < samples; i++)
                if (out[i] != (NSUInteger)((x * 7 + y * 3 + i * 5) % (maxValue + 1)))
                    ok = NO;
        }
    }
    expect(ok, what);
}

static void checkPixels(void)
{
    checkPixelRoundTrip("getPixel/setPixel, 8 bit chunky RGB", makeRep(8, 3, NO, 24), 255);
    checkPixelRoundTrip("getPixel/setPixel, 8 bit planar RGB", makeRep(8, 3, YES, 8), 255);
    checkPixelRoundTrip("getPixel/setPixel, 16 bit chunky RGB", makeRep(16, 3, NO, 48), 65535);
    checkPixelRoundTrip("getPixel/setPixel, 4 bit gray", makeRep(4, 1, NO, 4), 15);
    checkPixelRoundTrip("getPixel/setPixel, 1 bit gray", makeRep(1, 1, NO, 1), 1);

    NSBitmapImageRep *rep = makeRep(8, 3, NO, 24);
    NSUInteger in[3] = {10, 20, 30};
    [rep setPixel:in atX:1 y:0];
    unsigned char *data = [rep bitmapData];
    expect(data[3] == 10 && data[4] == 20 && data[5] == 30, "setPixel writes the samples in order into the bitmap data");
}

static void checkFills(void)
{
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:4
                                                                    pixelsHigh:2
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSCalibratedRGBColorSpace
                                                                  bitmapFormat:0
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:32] autorelease];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    expect(context != nil, "a bitmap graphics context");
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];

    NSRect rects[2] = {NSMakeRect(0, 0, 2, 2), NSMakeRect(2, 0, 2, 2)};
    NSColor *colors[2] = {[NSColor redColor], [NSColor blueColor]};
    NSRectFillListWithColorsUsingOperation(rects, colors, 2, NSCompositingOperationCopy);
    [NSGraphicsContext restoreGraphicsState];

    NSUInteger left = pixelAt(rep, 0, 0), right = pixelAt(rep, 3, 0);
    expect((left >> 24) > 0xC0 && ((left >> 16) & 0xFF) < 0x40, "NSRectFillListWithColorsUsingOperation fills the first rect red");
    expect(((right >> 8) & 0xFF) > 0xC0 && (right >> 24) < 0x40, "NSRectFillListWithColorsUsingOperation fills the second rect blue");
}

int main(void)
{
    @autoreleasepool {
        checkValues();
        checkDepths();
        checkOpenGLOptions();
        checkPixels();
        checkFills();
    }
    return failures ? 1 : 0;
}
