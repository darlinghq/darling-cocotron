// Copyright (C) 2026 Lubos Dolezel
//
// A rounded push button in a frame sized for the bezel plus room for its shadow (as in a nib) draws its
// bezel inside the frame: the topmost row of the frame stays clear and the bezel is not cut off. Checked on
// macOS 10.14.4 and 26.7.3 (see vd-upstream mac-probes/ua6-push-bezel.m for the dumped rows).
//
// Build: clang -fobjc-arc -framework AppKit appkit-push-button-bezel-not-clipped.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// Row range (top row first) of the pixels that are not background.
static BOOL inkRows(NSBitmapImageRep *rep, NSInteger *first, NSInteger *last) {
    *first = -1;
    for (NSInteger y = 0; y < [rep pixelsHigh]; y++)
        for (NSInteger x = 0; x < [rep pixelsWide]; x++) {
            NSColor *c = [[rep colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
            if ([c alphaComponent] > 0.1 && ([c redComponent] < 0.9 || [c greenComponent] < 0.9 || [c blueComponent] < 0.9)) {
                if (*first < 0) *first = y;
                *last = y;
                break;
            }
        }
    return *first >= 0;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSControlSize sizes[2] = {NSControlSizeRegular, NSControlSizeSmall};
        for (int k = 0; k < 2; k++) {
            NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 32)];
            [b setBezelStyle:NSBezelStyleRounded];
            [b setButtonType:NSButtonTypeMomentaryPushIn];
            [b setTitle:@""];
            [[b cell] setControlSize:sizes[k]];
            NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 60) styleMask:NSWindowStyleMaskTitled
                    backing:NSBackingStoreBuffered defer:NO];
            [[w contentView] addSubview:b];
            NSBitmapImageRep *rep = [b bitmapImageRepForCachingDisplayInRect:[b bounds]];
            [b cacheDisplayInRect:[b bounds] toBitmapImageRep:rep];
            NSInteger first, last;
            CHECK(inkRows(rep, &first, &last));
            fprintf(stderr, "control size %d: ink rows %ld to %ld of %ld\n", k, (long)first, (long)last, (long)[rep pixelsHigh]);
            CHECK(first >= 1);                         // the top edge of the bezel is drawn, not cut off
            CHECK(last - first >= 12);                 // and the bezel is a normal height
        }
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
