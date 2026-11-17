// Copyright (C) 2026 Lubos Dolezel
//
// The intrinsic content size of an NSImageView is the size of its image, zero without one. With an image
// frame style other than NSImageFrameNone it has none (QUIRK, test_quirk_image_view_frame_style_has_no_
// intrinsic_size), as observed on macOS 10.14.4 and 26.7.3 (vd-upstream mac-probes/ua7-imageview-size.m).
// Without the fix the view reports the 10000 x 10000 "no preference" size of a plain cell, which makes an
// image view pinned to its superview's edges widen the whole window.
//
// Build: clang -fobjc-arc -framework AppKit appkit-image-view-intrinsic-size.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSImageView *view = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 50, 50)];
        NSSize s = [view intrinsicContentSize];
        CHECK(s.width == 0 && s.height == 0);

        [view setImage:[[NSImage alloc] initWithSize:NSMakeSize(466, 96)]];
        s = [view intrinsicContentSize];
        CHECK(s.width == 466 && s.height == 96);
        [view setImageScaling:NSImageScaleProportionallyUpOrDown];
        s = [view intrinsicContentSize];
        CHECK(s.width == 466 && s.height == 96);

        // Changing the image changes the size the view reports.
        [view setImage:[[NSImage alloc] initWithSize:NSMakeSize(16, 16)]];
        s = [view intrinsicContentSize];
        CHECK(s.width == 16 && s.height == 16);

        // test_quirk_image_view_frame_style_has_no_intrinsic_size
        NSImageFrameStyle styles[] = {NSImageFrameGrayBezel, NSImageFramePhoto, NSImageFrameButton, NSImageFrameGroove};
        for (int i = 0; i < 4; i++) {
            [view setImageFrameStyle:styles[i]];
            s = [view intrinsicContentSize];
            CHECK(s.width == NSViewNoIntrinsicMetric && s.height == NSViewNoIntrinsicMetric);
        }
        [view setImageFrameStyle:NSImageFrameNone];
        s = [view intrinsicContentSize];
        CHECK(s.width == 16 && s.height == 16);
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
