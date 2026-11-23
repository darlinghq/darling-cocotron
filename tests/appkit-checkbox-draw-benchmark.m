/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Benchmark and contract for drawing check boxes and radio buttons: the same state drawn at different
// positions gives the same pixels, the states differ from each other, and a full window of 300 controls
// can be drawn in a short time. Preferences windows hold many of them and are drawn again at every
// switch of the section shown.
// Prints "BENCH <what>: <ms>" lines (informational), then PASS or FAIL. The time limit is generous: a
// page of 300 toggles drawn 20 times must take less than 20 seconds.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <sys/time.h>

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: %s\n", __LINE__, [[NSString stringWithFormat: __VA_ARGS__] UTF8String]); } } while (0)

static double now(void) { struct timeval tv; gettimeofday(&tv, NULL); return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0; }

@interface FlippedHost : NSView
@end
@implementation FlippedHost
- (BOOL) isFlipped { return YES; }
@end

static NSButtonCell *cellFor(NSInteger state, BOOL radio, BOOL enabled) {
    NSButtonCell *cell = [[NSButtonCell alloc] init];
    [cell setButtonType: radio ? NSRadioButton : NSSwitchButton];
    [cell setTitle: @""];
    [cell setState: state];
    [cell setEnabled: enabled];
    return cell;
}

// Renders one control into a fresh bitmap at the given origin, returns the pixels.
static NSBitmapImageRep *render(NSInteger state, BOOL radio, BOOL enabled, NSPoint origin, FlippedHost *host) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: 80 pixelsHigh: 60 bitsPerSample: 8
                                                               samplesPerPixel: 4 hasAlpha: YES isPlanar: NO
                                                                colorSpaceName: NSDeviceRGBColorSpace bytesPerRow: 0 bitsPerPixel: 0];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep: rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: context];
    [[NSColor whiteColor] set];
    NSRectFill(NSMakeRect(0, 0, 80, 60));
    NSAffineTransform *flip = [NSAffineTransform transform];
    [flip translateXBy: 0 yBy: 60];
    [flip scaleXBy: 1 yBy: -1];
    [flip concat];
    [cellFor(state, radio, enabled) drawWithFrame: NSMakeRect(origin.x, origin.y, 18, 18) inView: host];
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}

static NSData *pixelsAround(NSBitmapImageRep *rep, NSPoint origin) {
    NSMutableData *data = [NSMutableData data];
    for (int y = 0; y < 18; y++)
        for (int x = 0; x < 18; x++) {
            NSUInteger px[4];
            [rep getPixel: px atX: (NSInteger) origin.x + x y: (NSInteger) origin.y + y];
            for (int i = 0; i < 4; i++) { unsigned char b = (unsigned char) px[i]; [data appendBytes: &b length: 1]; }
        }
    return data;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        FlippedHost *host = [[FlippedHost alloc] initWithFrame: NSMakeRect(0, 0, 80, 60)];
        NSInteger states[3] = {NSOffState, NSOnState, NSMixedState};

        // Same pixels at different positions, for every state, kind and enabled flag.
        NSMutableArray *looks = [NSMutableArray array];
        for (int radio = 0; radio < 2; radio++)
            for (int enabled = 0; enabled < 2; enabled++)
                for (int s = 0; s < 3; s++) {
                    NSData *a = pixelsAround(render(states[s], radio, enabled, NSMakePoint(10, 10), host), NSMakePoint(10, 10));
                    NSData *b = pixelsAround(render(states[s], radio, enabled, NSMakePoint(41, 27), host), NSMakePoint(41, 27));
                    CHECK([a isEqual: b], @"radio %d enabled %d state %ld: different pixels at two positions", radio, enabled, (long) states[s]);
                    [looks addObject: a];
                }
        // Index: radio * 6 + enabled * 3 + state (off, on, mixed). An enabled off check box differs from an on one.
        CHECK(![looks[3] isEqual: looks[4]], @"check box: the off and on looks are the same");

        // A window of controls, drawn repeatedly.
        NSBitmapImageRep *page = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: 900 pixelsHigh: 600 bitsPerSample: 8
                                                                    samplesPerPixel: 4 hasAlpha: YES isPlanar: NO
                                                                     colorSpaceName: NSDeviceRGBColorSpace bytesPerRow: 0 bitsPerPixel: 0];
        NSMutableArray *cells = [NSMutableArray array];
        for (int i = 0; i < 300; i++) [cells addObject: cellFor(states[i % 3], (i / 3) % 2, (i % 7) != 0)];
        double t0 = now();
        for (int round = 0; round < 20; round++) {
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: page]];
            NSAffineTransform *flip = [NSAffineTransform transform];
            [flip translateXBy: 0 yBy: 600];
            [flip scaleXBy: 1 yBy: -1];
            [flip concat];
            for (int i = 0; i < 300; i++)
                [cells[i] drawWithFrame: NSMakeRect(10 + (i % 15) * 58, 10 + (i / 15) * 28, 18, 18) inView: host];
            [NSGraphicsContext restoreGraphicsState];
        }
        double elapsed = now() - t0;
        printf("BENCH 6000 toggle draws (20 pages of 300): %.0f ms, %.1f us per toggle\n", elapsed, elapsed * 1000 / 6000);
        CHECK(elapsed < 20000, @"drawing 6000 toggles took %.0f ms", elapsed);
    }
    printf(failures ? "FAIL (%d)\n" : "PASS\n", failures);
    return failures != 0;
}
