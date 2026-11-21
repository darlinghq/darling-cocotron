// Copyright (C) 2026 Lubos Dolezel
//
// +[NSImage imageNamed:] answers the system template images (the NSImageName...Template constants) with
// template images of the point sizes they have on macOS 10.14.4 (black-box: -size of the named image), each
// returned again for the same name and drawing some opaque and some transparent pixels.
// Passes on macOS 10.14.4. macOS 26.7.3 has larger images (for example 12 x 16 for NSImageNameGoRightTemplate
// against 9 x 12), so the size checks fail there.
//
// Build: clang -framework AppKit appkit-system-template-images.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c, name) do { if (!(c)) { fprintf(stderr, "FAIL line %d %s: %s\n", __LINE__, [name UTF8String], #c); failures++; } } while (0)

static const struct {
    NSString *name;
    CGFloat width, height;
} expected[] = {
        {@"NSActionTemplate", 14, 14},
        {@"NSBluetoothTemplate", 7, 14},
        {@"NSBookmarksTemplate", 17, 18},
        {@"NSColumnViewTemplate", 16, 10},
        {@"NSEnterFullScreenTemplate", 15, 15},
        {@"NSExitFullScreenTemplate", 15, 15},
        {@"NSFlowViewTemplate", 18, 10},
        {@"NSFollowLinkFreestandingTemplate", 14, 14},
        {@"NSGoBackTemplate", 9, 12},
        {@"NSGoForwardTemplate", 9, 12},
        {@"NSGoLeftTemplate", 9, 12},
        {@"NSGoRightTemplate", 9, 12},
        {@"NSHomeTemplate", 14, 14},
        {@"NSIChatTheaterTemplate", 15, 13},
        {@"NSIconViewTemplate", 14, 10},
        {@"NSInvalidDataFreestandingTemplate", 14, 14},
        {@"NSLeftFacingTriangleTemplate", 9, 12},
        {@"NSListViewTemplate", 14, 10},
        {@"NSLockLockedTemplate", 10, 14},
        {@"NSLockUnlockedTemplate", 10, 14},
        {@"NSPathTemplate", 16, 10},
        {@"NSQuickLookTemplate", 19, 12},
        {@"NSRefreshFreestandingTemplate", 14, 14},
        {@"NSRefreshTemplate", 11, 15},
        {@"NSRevealFreestandingTemplate", 14, 14},
        {@"NSRightFacingTriangleTemplate", 9, 12},
        {@"NSShareTemplate", 11, 16},
        {@"NSSlideshowTemplate", 17, 14},
        {@"NSSmartBadgeTemplate", 14, 14},
        {@"NSStopProgressFreestandingTemplate", 14, 14},
        {@"NSStopProgressTemplate", 11, 11},
        {@"NSTouchBarAddTemplate", 14, 30},
        {@"NSTouchBarBookmarksTemplate", 22, 30},
        {@"NSTouchBarEnterFullScreenTemplate", 18, 30},
        {@"NSTouchBarExitFullScreenTemplate", 18, 30},
        {@"NSTouchBarFastForwardTemplate", 22, 30},
        {@"NSTouchBarGoBackTemplate", 10, 30},
        {@"NSTouchBarGoDownTemplate", 16, 30},
        {@"NSTouchBarGoForwardTemplate", 10, 30},
        {@"NSTouchBarGoUpTemplate", 16, 30},
        {@"NSTouchBarIconViewTemplate", 20, 30},
        {@"NSTouchBarListViewTemplate", 18, 30},
        {@"NSTouchBarPauseTemplate", 11, 30},
        {@"NSTouchBarPlayPauseTemplate", 23, 30},
        {@"NSTouchBarPlayTemplate", 14, 30},
        {@"NSTouchBarQuickLookTemplate", 22, 30},
        {@"NSTouchBarRecordStartTemplate", 14, 30},
        {@"NSTouchBarRecordStopTemplate", 12, 30},
        {@"NSTouchBarRefreshTemplate", 19, 30},
        {@"NSTouchBarRemoveTemplate", 14, 30},
        {@"NSTouchBarRewindTemplate", 22, 30},
        {@"NSTouchBarSearchTemplate", 19, 30},
        {@"NSTouchBarShareTemplate", 15, 30},
        {@"NSTouchBarSkipToEndTemplate", 12, 30},
        {@"NSTouchBarSkipToStartTemplate", 12, 30},
        {@"NSTouchBarSlideshowTemplate", 22, 30},
        {@"NSTouchBarVolumeDownTemplate", 15, 30},
        {@"NSTouchBarVolumeUpTemplate", 23, 30},
};

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        for (size_t i = 0; i < sizeof(expected) / sizeof(expected[0]); i++) {
            NSString *name = expected[i].name;
            NSImage *image = [NSImage imageNamed: name];

            CHECK(image != nil, name);
            if (image == nil)
                continue;
            CHECK([image isTemplate], name);
            CHECK(NSEqualSizes([image size], NSMakeSize(expected[i].width, expected[i].height)), name);
            CHECK([NSImage imageNamed: name] == image, name);

            NSInteger w = (NSInteger) expected[i].width, h = (NSInteger) expected[i].height;
            NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                                                              pixelsWide: w
                                                                              pixelsHigh: h
                                                                           bitsPerSample: 8
                                                                         samplesPerPixel: 4
                                                                                hasAlpha: YES
                                                                                isPlanar: NO
                                                                          colorSpaceName: NSDeviceRGBColorSpace
                                                                             bytesPerRow: w * 4
                                                                            bitsPerPixel: 32] autorelease];
            memset([rep bitmapData], 0, w * h * 4);
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: rep]];
            [image drawInRect: NSMakeRect(0, 0, w, h) fromRect: NSZeroRect operation: NSCompositeSourceOver fraction: 1];
            [NSGraphicsContext restoreGraphicsState];
            int opaque = 0, clear = 0;
            unsigned char *p = [rep bitmapData];
            for (NSInteger k = 0; k < w * h; k++) {
                if (p[k * 4 + 3] > 128)
                    opaque++;
                else if (p[k * 4 + 3] == 0)
                    clear++;
            }
            CHECK(opaque > 0, name);
            CHECK(clear > 0, name);
        }
    }
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
