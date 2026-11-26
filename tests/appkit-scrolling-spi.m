// Copyright (C) 2026 Lubos Dolezel
//
// The private AppKit scrolling interfaces web engines use to draw and move scrollers of their own:
//  - NSScrollerImp keeps a scroller's state, lays its parts out and draws them like NSScroller does (with the
//    knob and track alphas applied to overlay scrollers); its metrics follow NSScroller's part geometry (knob at least 20 long). An
//    overlay imp starts hidden. Darling draws an imp given a layer into a sublayer of it (macOS 26.7.3 adds no
//    sublayer at once, so that part of the test is Darling's own).
//  - _NSScrollingPredominantAxisFilter keeps the larger axis of each delta and smooths the velocity, as observed
//    on macOS 26.7.3 and 10.14.4 (see NSScrollingMomentum.m).
//  - NSScrollerImpPair shows and hides overlay scrollers through the imps' delegates, keeps a locked state until
//    unlocked, and +_updateAllScrollerImpPairsForNewRecommendedScrollerStyle: reaches every live pair's delegate.
//  - _NSScrollingMomentumCalculator moves from the origin to a destination kept inside the document, in the
//    direction of the velocity, and ends exactly there after -durationUntilStop.
//  - _NSElasticDeltaForReboundDelta, _NSReboundDeltaForElasticDelta and _NSElasticDeltaForTimeDelta give the
//    values macOS 26.7.3 and 10.14.4 give.
// The momentum constants are Darling's own (not observed on macOS), so only the momentum's shape is checked.
// Build: clang -framework AppKit -framework QuartzCore appkit-scrolling-spi.m
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface NSObject (ScrollerImpSPI)
+ (id) scrollerImpWithStyle: (NSScrollerStyle) style controlSize: (NSControlSize) size horizontal: (BOOL) horizontal
       replacingScrollerImp: (id) previous;
- (void) setBoundsSize: (NSSize) size;
- (void) setKnobProportion: (CGFloat) proportion;
- (void) setPresentationValue: (double) value;
- (void) setUsePresentationValue: (BOOL) flag;
- (void) setKnobAlpha: (CGFloat) alpha;
- (CGFloat) knobAlpha;
- (void) setTrackAlpha: (CGFloat) alpha;
- (CGFloat) trackAlpha;
- (CGFloat) knobMinLength;
- (CGFloat) knobEndInset;
- (CGFloat) trackEndInset;
- (CGFloat) trackBoxWidth;
- (NSScrollerStyle) scrollerStyle;
- (NSRect) rectForPart: (NSScrollerPart) part;
- (void) drawKnobSlotInRect: (NSRect) rect highlight: (BOOL) flag;
- (void) drawKnob;
- (void) setLayer: (CALayer *) layer;
- (void) setNeedsDisplay: (BOOL) flag;
- (void) setVerticalScrollerImp: (id) imp;
- (BOOL) isHorizontal;
- (void) contentAreaScrolled;
- (void) hideOverlayScrollers;
- (void) flashScrollers;
- (void) lockOverlayScrollerState: (NSUInteger) state;
- (void) unlockOverlayScrollerState;
- (BOOL) overlayScrollerStateIsLocked;
+ (void) _updateAllScrollerImpPairsForNewRecommendedScrollerStyle: (NSScrollerStyle) style;
- (id) initWithInitialOrigin: (NSPoint) origin velocity: (NSPoint) velocity documentFrame: (NSRect) frame
   constrainedClippingOrigin: (NSPoint) constrained clippingSize: (NSSize) clipSize tolerance: (NSSize) tolerance;
- (NSPoint) positionAfterDuration: (NSTimeInterval) duration;
- (void) calculateToReachDestination;
- (NSPoint) destinationOrigin;
- (void) setDestinationOrigin: (NSPoint) origin;
- (NSTimeInterval) durationUntilStop;
- (void) filterInputDelta: (NSPoint) delta timestamp: (NSTimeInterval) timestamp outputDelta: (NSPoint *) outDelta
                 velocity: (NSPoint *) velocity;
- (void) reset;
@end

// Records what the pair and the imps ask of their delegates.
@interface Recorder : NSObject {
@public
    CGFloat lastKnobAlpha;
    int knobCalls;
    int styleUpdates;
    NSScrollerStyle lastStyle;
}
@end

@implementation Recorder
- (void) scrollerImp: (id) imp animateKnobAlphaTo: (CGFloat) alpha duration: (NSTimeInterval) duration {
    lastKnobAlpha = alpha;
    knobCalls++;
    [imp setKnobAlpha: alpha];
}
- (void) scrollerImp: (id) imp animateTrackAlphaTo: (CGFloat) alpha duration: (NSTimeInterval) duration {
    [imp setTrackAlpha: alpha];
}
- (void) scrollerImp: (id) imp overlayScrollerStateChangedTo: (NSUInteger) state {
}
- (void) scrollerImpPair: (id) pair updateScrollerStyleForNewRecommendedScrollerStyle: (NSScrollerStyle) style {
    styleUpdates++;
    lastStyle = style;
}
// macOS calls these on a pair's delegate without checking for them.
- (BOOL) inLiveResizeForScrollerImpPair: (id) pair {
    return NO;
}
- (NSRect) contentAreaRectForScrollerImpPair: (id) pair {
    return NSMakeRect(0, 0, 100, 120);
}
- (NSPoint) mouseLocationInContentAreaForScrollerImpPair: (id) pair {
    return NSMakePoint(-1, -1);
}
- (NSPoint) scrollerImpPair: (id) pair convertContentPoint: (NSPoint) point toScrollerImp: (id) imp {
    return point;
}
- (void) scrollerImpPair: (id) pair setContentAreaNeedsDisplayInRect: (NSRect) rect {
}
// and these on an enabled scroller imp's delegate
- (NSRect) convertRectToBacking: (NSRect) rect {
    return rect;
}
- (NSRect) convertRectFromBacking: (NSRect) rect {
    return rect;
}
- (CALayer *) layer {
    return nil;
}
- (NSPoint) mouseLocationInScrollerForScrollerImp: (id) imp {
    return NSZeroPoint;
}
- (BOOL) shouldUseLayerPerPartForScrollerImp: (id) imp {
    return NO;
}
- (NSAppearance *) effectiveAppearanceForScrollerImp: (id) imp {
    return [NSAppearance currentAppearance];
}
- (void) scrollerImp: (id) imp animateUIStateTransitionWithDuration: (NSTimeInterval) duration {
}
- (void) scrollerImp: (id) imp animateExpansionTransitionWithDuration: (NSTimeInterval) duration {
}
@end

static double gray(NSBitmapImageRep *rep, NSInteger x, NSInteger y) {
    return [[[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedWhiteColorSpace] whiteComponent];
}

// Draws the imp's slot and knob into a bitmap, with the parts laid out from the top left like a client does.
static NSBitmapImageRep *drawImp(id imp, NSInteger width, NSInteger height) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: width
            pixelsHigh: height bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO
            colorSpaceName: NSCalibratedRGBColorSpace bytesPerRow: 0 bitsPerPixel: 0];
    CGContextRef cg = [[NSGraphicsContext graphicsContextWithBitmapImageRep: rep] CGContext];

    CGContextSetRGBFillColor(cg, 1, 1, 1, 1);
    CGContextFillRect(cg, CGRectMake(0, 0, width, height));
    CGContextTranslateCTM(cg, 0, height);
    CGContextScaleCTM(cg, 1, -1);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithCGContext: cg flipped: YES]];
    [imp drawKnobSlotInRect: [imp rectForPart: NSScrollerKnobSlot] highlight: NO];
    [imp drawKnob];
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}

static id legacyImp(void) {
    id imp = [NSClassFromString(@"NSScrollerImp") scrollerImpWithStyle: NSScrollerStyleLegacy
                                                           controlSize: NSControlSizeRegular horizontal: NO
                                                  replacingScrollerImp: nil];
    [imp setBoundsSize: NSMakeSize(15, 120)];
    [imp setEnabled: YES];
    [imp setKnobProportion: 0.3];
    [imp setDoubleValue: 0.5];
    return imp;
}

static void test_scroller_imp_state_and_parts(void) {
    id imp = legacyImp();

    CHECK(imp != nil);
    CHECK([imp isEnabled] && [imp doubleValue] == 0.5 && [imp knobProportion] == (CGFloat) 0.3);
    // The same part rectangles as an NSScroller of that size and state.
    NSScroller *s = [[NSScroller alloc] initWithFrame: NSMakeRect(0, 0, 15, 120)];
    [s setEnabled: YES];
    [s setKnobProportion: 0.3];
    [s setDoubleValue: 0.5];
    // (macOS 26.7.3 does not round the imp's knob as NSScroller does)
    NSRect knob = [imp rectForPart: NSScrollerKnob], scrollerKnob = [s rectForPart: NSScrollerKnob];
    CHECK(fabs(NSMinY(knob) - NSMinY(scrollerKnob)) <= 0.5 && fabs(NSHeight(knob) - NSHeight(scrollerKnob)) <= 0.5);
    CHECK(NSMinX(knob) == NSMinX(scrollerKnob) && NSWidth(knob) == NSWidth(scrollerKnob));
    NSRect slot = [imp rectForPart: NSScrollerKnobSlot];
    CHECK(NSEqualRects(slot, [s rectForPart: NSScrollerKnobSlot]));
    CHECK([imp knobMinLength] == 20);
    CHECK(NSHeight(slot) == 120 - 2 * [imp trackEndInset]);
    // While the presentation value is not used, it does not move the knob.
    [imp setPresentationValue: 0];
    CHECK(NSEqualRects([imp rectForPart: NSScrollerKnob], knob));
    // A replacement keeps the state of the imp it replaces.
    id overlay = [NSClassFromString(@"NSScrollerImp") scrollerImpWithStyle: NSScrollerStyleOverlay
                                                               controlSize: NSControlSizeRegular horizontal: NO
                                                      replacingScrollerImp: imp];
    CHECK([overlay scrollerStyle] == NSScrollerStyleOverlay && [overlay doubleValue] == 0.5);
    CHECK([overlay knobProportion] == (CGFloat) 0.3 && [overlay isEnabled]);
    CHECK([overlay trackAlpha] == 0 && [overlay knobAlpha] == 0);
    // A horizontal imp lays its parts out along x.
    id h = [NSClassFromString(@"NSScrollerImp") scrollerImpWithStyle: NSScrollerStyleLegacy
                                                         controlSize: NSControlSizeRegular horizontal: YES
                                                replacingScrollerImp: nil];
    [h setBoundsSize: NSMakeSize(120, 15)];
    [h setEnabled: YES];
    [h setKnobProportion: 0.3];
    [h setDoubleValue: 0.5];
    CHECK([h isHorizontal]);
    NSRect hk = [h rectForPart: NSScrollerKnob];
    CHECK(NSMinX(hk) == NSMinY(knob) && NSWidth(hk) == NSHeight(knob) && NSHeight(hk) == NSWidth(knob));
}

static void test_scroller_imp_drawing(void) {
    id imp = legacyImp();
    // The knob covers the middle rows, the track the rest; the knob is darker.
    NSBitmapImageRep *rep = drawImp(imp, 15, 120);
    double knob = gray(rep, 7, 60), track = gray(rep, 7, 20);
    CHECK(knob < track - 0.1);
    // The alphas do not change a legacy scroller.
    [imp setKnobAlpha: 0];
    [imp setTrackAlpha: 0];
    rep = drawImp(imp, 15, 120);
    CHECK(fabs(gray(rep, 7, 60) - knob) < 0.01 && fabs(gray(rep, 7, 20) - track) < 0.01);
    // An overlay scroller starts hidden; its knob shows with knob alpha, its track with track alpha.
    id overlay = [NSClassFromString(@"NSScrollerImp") scrollerImpWithStyle: NSScrollerStyleOverlay
                                                               controlSize: NSControlSizeRegular horizontal: NO
                                                      replacingScrollerImp: legacyImp()];
    rep = drawImp(overlay, 15, 120);
    CHECK(gray(rep, 7, 60) > 0.995 && gray(rep, 7, 20) > 0.995);
    [overlay setKnobAlpha: 1];
    rep = drawImp(overlay, 15, 120);
    CHECK(gray(rep, 7, 60) < 0.9 && gray(rep, 7, 20) > 0.995);
    [overlay setTrackAlpha: 1];
    rep = drawImp(overlay, 15, 120);
    CHECK(gray(rep, 7, 20) < 0.995);
}

// Darling's own way of drawing an imp into a layer it is given, a sublayer that shows the scroller. macOS
// 26.7.3 adds no sublayer at once, so this part is not expected to pass there.
static void test_darling_scroller_imp_layer(void) {
    id imp = legacyImp();
    CALayer *layer = [CALayer layer];

    [layer setBounds: CGRectMake(0, 0, 15, 120)];
    [imp setLayer: layer];
    CHECK([[layer sublayers] count] == 1);
    CALayer *content = [[layer sublayers] firstObject];
    [imp setNeedsDisplay: YES];
    CHECK(CGRectEqualToRect([content frame], [layer bounds]));

    // Its content is the scroller, drawn the right way up.
    unsigned char pixels[120][15][4] = {{{0}}};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef cg = CGBitmapContextCreate(pixels, 15, 120, 8, 15 * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    [content drawInContext: cg];
    CGContextRelease(cg);
    // Bitmap row 0 is the top. The knob is at rows 43 to 76, the track above it.
    CHECK(pixels[60][7][3] == 255 && abs(pixels[60][7][0] - 194) < 10);
    CHECK(pixels[20][7][3] == 255 && pixels[20][7][0] > 240);

    [imp setLayer: nil];
    CHECK([[layer sublayers] count] == 0);
}

static void test_scroller_imp_pair_overlay_states(void) {
    id pair = [[NSClassFromString(@"NSScrollerImpPair") alloc] init];
    id imp = [NSClassFromString(@"NSScrollerImp") scrollerImpWithStyle: NSScrollerStyleOverlay
                                                           controlSize: NSControlSizeRegular horizontal: NO
                                                  replacingScrollerImp: nil];
    Recorder *recorder = [[Recorder alloc] init];

    // (a scroller that is not enabled is never shown)
    [imp setEnabled: YES];
    [imp setDelegate: recorder];
    [pair setVerticalScrollerImp: imp];
    [pair setDelegate: recorder];

    // A pair of the legacy style leaves its overlay scrollers alone.
    [pair setScrollerStyle: NSScrollerStyleLegacy];
    [pair flashScrollers];
    CHECK(recorder->knobCalls == 0 && [imp knobAlpha] == 0);
    // The scrollers start hidden; only a change of state reaches the delegate.
    [pair setScrollerStyle: NSScrollerStyleOverlay];
    [pair hideOverlayScrollers];
    CHECK(recorder->knobCalls == 0);
    [pair flashScrollers];
    CHECK(recorder->knobCalls == 1 && recorder->lastKnobAlpha == 1 && [imp knobAlpha] == 1);
    [pair contentAreaScrolled];
    CHECK(recorder->knobCalls == 1);

    // Locked, the scrollers keep the state: hiding and scrolling do nothing.
    [pair lockOverlayScrollerState: 0];
    CHECK([pair overlayScrollerStateIsLocked] && [imp knobAlpha] == 0);
    [pair contentAreaScrolled];
    [pair flashScrollers];
    CHECK([imp knobAlpha] == 0);
    [pair unlockOverlayScrollerState];
    CHECK(![pair overlayScrollerStateIsLocked]);
    [pair contentAreaScrolled];
    CHECK([imp knobAlpha] == 1);

    // Legacy scrollers are not hidden.
    id legacy = legacyImp();
    [legacy setDelegate: recorder];
    [pair setVerticalScrollerImp: legacy];
    int calls = recorder->knobCalls;
    [pair hideOverlayScrollers];
    CHECK(recorder->knobCalls == calls && [legacy knobAlpha] == 1);

    [NSClassFromString(@"NSScrollerImpPair") _updateAllScrollerImpPairsForNewRecommendedScrollerStyle: NSScrollerStyleOverlay];
    CHECK(recorder->styleUpdates == 1 && recorder->lastStyle == NSScrollerStyleOverlay);
    [pair setDelegate: nil];
    [pair release];
    // A released pair is not reached any more.
    [NSClassFromString(@"NSScrollerImpPair") _updateAllScrollerImpPairsForNewRecommendedScrollerStyle: NSScrollerStyleLegacy];
    CHECK(recorder->styleUpdates == 1);

    NSScrollerStyle (*recommended)(void) = dlsym(RTLD_DEFAULT, "_NSRecommendedScrollerStyle");
    CHECK(recommended != NULL && recommended() == [NSScroller preferredScrollerStyle]);
}

static void test_momentum_calculator(void) {
    Class cls = NSClassFromString(@"_NSScrollingMomentumCalculator");
    NSRect document = NSMakeRect(0, 0, 800, 10000);
    id calc = [[cls alloc] initWithInitialOrigin: NSMakePoint(0, 1000) velocity: NSMakePoint(0, 1000)
                                   documentFrame: document constrainedClippingOrigin: NSZeroPoint
                                    clippingSize: NSMakeSize(800, 500) tolerance: NSMakeSize(1, 1)];
    CHECK(calc != nil);

    NSPoint destination = [calc destinationOrigin];
    CHECK(destination.x == 0 && destination.y > 1000 && destination.y < 9500);
    NSTimeInterval duration = [calc durationUntilStop];
    CHECK(duration > 0 && duration < 10);
    CHECK(NSEqualPoints([calc positionAfterDuration: 0], NSMakePoint(0, 1000)));
    CHECK(NSEqualPoints([calc positionAfterDuration: duration], destination));
    // On the way it moves only forward.
    CGFloat previous = 1000;
    for (int i = 1; i <= 20; i++) {
        CGFloat y = [calc positionAfterDuration: duration * i / 20].y;
        CHECK(y >= previous && y <= destination.y);
        previous = y;
    }
    // Retargeted, it ends at the new destination.
    [calc setDestinationOrigin: NSMakePoint(0, 1200)];
    [calc calculateToReachDestination];
    CHECK(NSEqualPoints([calc positionAfterDuration: [calc durationUntilStop]], NSMakePoint(0, 1200)));
    CHECK([calc positionAfterDuration: [calc durationUntilStop] / 2].y < 1200);
    [calc release];

    // A fling past the end stops at the end: the far edge of the document less the clipping size.
    calc = [[cls alloc] initWithInitialOrigin: NSMakePoint(0, 1000) velocity: NSMakePoint(0, 1e6)
                                documentFrame: document constrainedClippingOrigin: NSZeroPoint
                                 clippingSize: NSMakeSize(800, 500) tolerance: NSMakeSize(1, 1)];
    CHECK([calc destinationOrigin].y == 9500);
    CHECK([calc positionAfterDuration: 100].y == 9500);
    [calc release];
    // No velocity, no motion.
    calc = [[cls alloc] initWithInitialOrigin: NSMakePoint(0, 1000) velocity: NSZeroPoint
                                documentFrame: document constrainedClippingOrigin: NSZeroPoint
                                 clippingSize: NSMakeSize(800, 500) tolerance: NSMakeSize(1, 1)];
    CHECK(NSEqualPoints([calc destinationOrigin], NSMakePoint(0, 1000)) && [calc durationUntilStop] == 0);
    [calc release];
}

// The values macOS 26.7.3 and 10.14.4 give.
static void test_predominant_axis_filter(void) {
    Class cls = NSClassFromString(@"_NSScrollingPredominantAxisFilter");
    id filter = [[cls alloc] init];
    NSPoint delta, velocity;

    // The first delta has no velocity; each keeps only its larger axis.
    [filter filterInputDelta: NSMakePoint(1, 10) timestamp: 0 outputDelta: &delta velocity: &velocity];
    CHECK(delta.x == 0 && delta.y == 10 && velocity.x == 0 && velocity.y == 0);
    [filter filterInputDelta: NSMakePoint(2, 10) timestamp: 0.01 outputDelta: &delta velocity: &velocity];
    CHECK(delta.x == 0 && delta.y == 10 && velocity.x == 0 && fabs(velocity.y - 1000) < 1e-6);
    // Smoothed: 0.2 of the old velocity and 0.8 of the new.
    [filter filterInputDelta: NSMakePoint(0, 20) timestamp: 0.02 outputDelta: &delta velocity: &velocity];
    CHECK(fabs(velocity.y - 1800) < 1e-6);
    // No time, the same velocity.
    [filter filterInputDelta: NSMakePoint(0, 20) timestamp: 0.02 outputDelta: &delta velocity: &velocity];
    CHECK(fabs(velocity.y - 1800) < 1e-6);
    // The other way, the new velocity as is.
    [filter filterInputDelta: NSMakePoint(0, -10) timestamp: 0.03 outputDelta: &delta velocity: &velocity];
    CHECK(fabs(velocity.y + 1000) < 1e-6);
    // The other axis: the deltas before do not lock the gesture to one; a velocity of 0 is smoothed too.
    [filter filterInputDelta: NSMakePoint(10, 1) timestamp: 0.04 outputDelta: &delta velocity: &velocity];
    CHECK(delta.x == 10 && delta.y == 0 && fabs(velocity.x - 800) < 1e-6 && fabs(velocity.y + 200) < 1e-6);
    // After a long gap, no velocity; the next one is taken as is.
    [filter filterInputDelta: NSMakePoint(10, 1) timestamp: 5 outputDelta: &delta velocity: &velocity];
    CHECK(velocity.x == 0 && velocity.y == 0);
    [filter filterInputDelta: NSMakePoint(20, 1) timestamp: 5.01 outputDelta: &delta velocity: &velocity];
    CHECK(fabs(velocity.x - 2000) < 1e-6);
    // A reset starts a new gesture; a tie keeps the vertical axis.
    [filter reset];
    [filter filterInputDelta: NSMakePoint(-5, -5) timestamp: 6 outputDelta: &delta velocity: &velocity];
    CHECK(delta.x == 0 && delta.y == -5 && velocity.y == 0);
    [filter filterInputDelta: NSMakePoint(5, 6) timestamp: 6.01 outputDelta: &delta velocity: &velocity];
    CHECK(delta.x == 0 && delta.y == 6 && fabs(velocity.y - 600) < 1e-6);
    [filter release];
}

static void test_rubber_band_curves(void) {
    CGFloat (*elasticForRebound)(CGFloat) = dlsym(RTLD_DEFAULT, "_NSElasticDeltaForReboundDelta");
    CGFloat (*reboundForElastic)(CGFloat) = dlsym(RTLD_DEFAULT, "_NSReboundDeltaForElasticDelta");
    CGFloat (*elasticForTime)(CGFloat, CGFloat, CGFloat) = dlsym(RTLD_DEFAULT, "_NSElasticDeltaForTimeDelta");

    CHECK(elasticForRebound != NULL && reboundForElastic != NULL && elasticForTime != NULL);
    if (elasticForRebound == NULL || reboundForElastic == NULL || elasticForTime == NULL)
        return;

    // the values macOS 26.7.3 and 10.14.4 give
    const CGFloat pulls[] = {0, 0.3, 10, 100, 2000, 100000, -100};
    for (size_t i = 0; i < sizeof(pulls) / sizeof(pulls[0]); i++) {
        CHECK(fabs(elasticForRebound(pulls[i]) - pulls[i] / 20) < 1e-9 * (1 + fabs(pulls[i])));
        CHECK(fabs(reboundForElastic(pulls[i]) - pulls[i] * 20) < 1e-9 * (1 + fabs(pulls[i])));
    }
    const struct { CGFloat x, v, t, stretch; } released[] = {
        {100, 0, 0, 100}, {100, 0, 0.01, 88.2496903}, {100, 0, 0.1, 28.6504797}, {100, 0, 1, 0.000372665317},
        {10, 1000, 0.02, 2.95944298}, {10, 1000, 0.05, -2.94393786}, {0, 1000, 0.1, -8.8816487},
        {100, -1000, 0.2, 13.2977698}, {100, 0, -0.1, 349.034296},
    };
    for (size_t i = 0; i < sizeof(released) / sizeof(released[0]); i++)
        CHECK(fabs(elasticForTime(released[i].x, released[i].v, released[i].t) - released[i].stretch) <
              1e-6 * (1 + fabs(released[i].stretch)));
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_scroller_imp_state_and_parts();
        test_scroller_imp_drawing();
        test_darling_scroller_imp_layer();
        test_scroller_imp_pair_overlay_states();
        test_momentum_calculator();
        test_predominant_axis_filter();
        test_rubber_band_curves();
    }
    if (failures == 0)
        printf("PASS\n");
    return failures != 0;
}
