/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// +imageNamed: finds the images NSImageNameAddTemplate and
// NSImageNameRemoveTemplate: template images 18 x 16 and 18 x 4 points
// (sizes read on macOS 26.7.3), always the same shared object, drawing
// something.
// Prints PASS, or FAIL lines and exit status 1.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void checkImage(const char *label, NSImageName name, NSSize size) {
    NSImage *image = [NSImage imageNamed: name];
    if (image == nil) {
        printf("FAIL: %s is missing\n", label);
        failures++;
        return;
    }
    if (!NSEqualSizes([image size], size)) {
        printf("FAIL: %s size %g x %g\n", label, [image size].width, [image size].height);
        failures++;
    }
    if (![image isTemplate]) {
        printf("FAIL: %s is not a template image\n", label);
        failures++;
    }
    if (![[image name] isEqualToString: name]) {
        printf("FAIL: %s is named %s\n", label, [[image name] UTF8String]);
        failures++;
    }
    if ([NSImage imageNamed: name] != image) {
        printf("FAIL: %s is not shared\n", label);
        failures++;
    }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                                                    pixelsWide: (NSInteger) size.width
                                                                    pixelsHigh: (NSInteger) size.height
                                                                 bitsPerSample: 8
                                                               samplesPerPixel: 4
                                                                      hasAlpha: YES
                                                                      isPlanar: NO
                                                                colorSpaceName: NSCalibratedRGBColorSpace
                                                                   bytesPerRow: 0
                                                                  bitsPerPixel: 0];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: rep]];
    [image drawInRect: NSMakeRect(0, 0, size.width, size.height)];
    [NSGraphicsContext restoreGraphicsState];
    BOOL drawn = NO;
    for (NSInteger y = 0; y < (NSInteger) size.height && !drawn; y++)
        for (NSInteger x = 0; x < (NSInteger) size.width; x++)
            if ([[rep colorAtX: x y: y] alphaComponent] > 0.5) {
                drawn = YES;
                break;
            }
    if (!drawn) {
        printf("FAIL: %s draws nothing\n", label);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        checkImage("NSImageNameAddTemplate", NSImageNameAddTemplate, NSMakeSize(18, 16));
        checkImage("NSImageNameRemoveTemplate", NSImageNameRemoveTemplate, NSMakeSize(18, 4));
        if (failures)
            return 1;
        printf("PASS\n");
        return 0;
    }
}
