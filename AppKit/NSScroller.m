/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <AppKit/NSApplication.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsStyle.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSScroller.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSKeyedArchiver.h>
#import <Foundation/NSUserDefaults.h>
#import <QuartzCore/CALayer.h>

// The overlay states a scroller imp pair can be locked in.
enum {
    NSOverlayScrollerStateHidden = 0,
    NSOverlayScrollerStateThumbShown = 1,
    NSOverlayScrollerStateAllShown = 2,
    NSOverlayScrollerStatePulseThumb = 3,
};
typedef NSUInteger NSOverlayScrollerState;

// Private: the painter of one scroller, for clients (such as web engines) that
// draw scrollers of their own instead of using NSScroller views. It keeps the
// state a scroller has (value, knob proportion, size, style, alphas) and draws
// through an NSScroller it owns, so it looks like the scrollers of NSScrollView.
// Given a layer, it draws into a sublayer of it.
@interface NSScrollerImp : NSObject <CALayerDelegate> {
    NSScroller *_painter;
    CALayer *_layer;
    CALayer *_contentLayer;
    id _delegate;
    NSScrollerStyle _style;
    NSControlSize _controlSize;
    BOOL _horizontal;
    BOOL _enabled;
    BOOL _usePresentationValue;
    BOOL _expanded;
    BOOL _tracking;
    BOOL _mouseInScroller;
    NSScrollerKnobStyle _knobStyle;
    NSSize _boundsSize;
    double _doubleValue;
    double _presentationValue;
    CGFloat _knobProportion;
    CGFloat _uiStateTransitionProgress;
    CGFloat _expansionTransitionProgress;
    CGFloat _trackAlpha;
    CGFloat _knobAlpha;
    NSUserInterfaceLayoutDirection _userInterfaceLayoutDirection;
}
+ (NSScrollerImp *) scrollerImpWithStyle: (NSScrollerStyle) style
                             controlSize: (NSControlSize) controlSize
                              horizontal: (BOOL) horizontal
                    replacingScrollerImp: (id) previous;
+ (CGFloat) scrollerWidthForControlSize: (NSControlSize) controlSize scrollerStyle: (NSScrollerStyle) style;
@property (retain) CALayer *layer;
@property (assign) id delegate;
@property (readonly) NSScrollerStyle scrollerStyle;
@property (readonly) NSControlSize controlSize;
@property (getter=isHorizontal) BOOL horizontal;
@property (getter=isEnabled) BOOL enabled;
@property (getter=shouldUsePresentationValue) BOOL usePresentationValue;
@property (getter=isExpanded) BOOL expanded;
@property (getter=isTracking) BOOL tracking;
@property NSScrollerKnobStyle knobStyle;
@property NSSize boundsSize;
@property double doubleValue;
@property double presentationValue;
@property CGFloat knobProportion;
@property CGFloat uiStateTransitionProgress;
@property CGFloat expansionTransitionProgress;
@property CGFloat trackAlpha;
@property CGFloat knobAlpha;
@property NSUserInterfaceLayoutDirection userInterfaceLayoutDirection;
@property (readonly) CGFloat trackBoxWidth;
@property (readonly) CGFloat trackWidth;
@property (readonly) CGFloat trackSideInset;
@property (readonly) CGFloat trackEndInset;
@property (readonly) CGFloat knobEndInset;
@property (readonly) CGFloat knobMinLength;
@property (readonly) CGFloat knobOverlapEndInset;
@property (readonly) CGFloat trackOverlapEndInset;
- (void) setNeedsDisplay: (BOOL) flag;
- (NSRect) rectForPart: (NSScrollerPart) part;
- (void) drawKnobSlotInRect: (NSRect) slotRect highlight: (BOOL) flag alpha: (CGFloat) alpha;
- (void) drawKnobSlotInRect: (NSRect) slotRect highlight: (BOOL) flag;
- (void) drawKnob;
- (void) mouseEnteredScroller;
- (void) mouseExitedScroller;
@end

@interface NSObject (NSScrollerImpDelegateMethods)
- (void) scrollerImp: (NSScrollerImp *) scrollerImp animateKnobAlphaTo: (CGFloat) alpha duration: (NSTimeInterval) duration;
- (void) scrollerImp: (NSScrollerImp *) scrollerImp animateTrackAlphaTo: (CGFloat) alpha duration: (NSTimeInterval) duration;
- (void) scrollerImp: (NSScrollerImp *) scrollerImp overlayScrollerStateChangedTo: (NSOverlayScrollerState) state;
- (void) scrollerImpPair: (id) pair updateScrollerStyleForNewRecommendedScrollerStyle: (NSScrollerStyle) style;
@end

// Private: coordinates a scroll view's two scrollers. Apps create one, set its
// delegate and ask for the scroller layout direction.
@interface NSScrollerImpPair : NSObject {
    id _delegate;
    NSScrollerStyle _scrollerStyle;
    NSScrollerImp *_verticalScrollerImp;
    NSScrollerImp *_horizontalScrollerImp;
    BOOL _overlayStateLocked;
    NSOverlayScrollerState _overlayState;
}
@property (assign) id delegate;
@property NSScrollerStyle scrollerStyle;
@property (retain) NSScrollerImp *verticalScrollerImp;
@property (retain) NSScrollerImp *horizontalScrollerImp;
@end

// Every live pair, not retained, for +_updateAllScrollerImpPairsForNewRecommendedScrollerStyle:.
static CFMutableSetRef allScrollerImpPairs;
static NSLock *allScrollerImpPairsLock;

static void lockScrollerImpPairs(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allScrollerImpPairsLock = [[NSLock alloc] init];
        allScrollerImpPairs = CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
    });
    [allScrollerImpPairsLock lock];
}

// Fades the overlay scrollers of the pair to the alphas of a state, through
// the scroller imps' delegates, which run the animation (or directly when an
// imp has no delegate). Legacy scrollers are always shown.
// Observed on macOS 26.7.3 (black-box, through the delegate calls): a pair
// starts with its overlay scrollers hidden and tells the delegates only of a
// change of state, and of the track only when its alpha changes; nothing
// changes while the pair's own style is legacy, nor for a scroller that is
// not enabled. A flash fades the knob in
// over 0.5 s; scrolling shows it, and hiding or locking sets the state, at
// once. Test: tests/appkit-scrolling-spi.m
static const NSTimeInterval kOverlayScrollerFlashDuration = 0.5;

static void showOverlayScroller(NSScrollerImp *imp, NSOverlayScrollerState state, NSTimeInterval duration,
                                BOOL trackChanges) {
    if (imp == nil || [imp scrollerStyle] != NSScrollerStyleOverlay || ![imp isEnabled])
        return;

    CGFloat knobAlpha = state == NSOverlayScrollerStateHidden ? 0 : 1;
    CGFloat trackAlpha = state == NSOverlayScrollerStateAllShown ? 1 : 0;
    id delegate = [imp delegate];

    if ([delegate respondsToSelector: @selector(scrollerImp:animateKnobAlphaTo:duration:)])
        [delegate scrollerImp: imp animateKnobAlphaTo: knobAlpha duration: duration];
    else
        [imp setKnobAlpha: knobAlpha];
    if (trackChanges) {
        if ([delegate respondsToSelector: @selector(scrollerImp:animateTrackAlphaTo:duration:)])
            [delegate scrollerImp: imp animateTrackAlphaTo: trackAlpha duration: duration];
        else
            [imp setTrackAlpha: trackAlpha];
    }
    if ([delegate respondsToSelector: @selector(scrollerImp:overlayScrollerStateChangedTo:)])
        [delegate scrollerImp: imp overlayScrollerStateChangedTo: state];
}

@implementation NSScrollerImpPair

@synthesize delegate = _delegate;
@synthesize scrollerStyle = _scrollerStyle;
@synthesize verticalScrollerImp = _verticalScrollerImp;
@synthesize horizontalScrollerImp = _horizontalScrollerImp;

- (void) dealloc {
    lockScrollerImpPairs();
    CFSetRemoveValue(allScrollerImpPairs, self);
    [allScrollerImpPairsLock unlock];
    [_verticalScrollerImp release];
    [_horizontalScrollerImp release];
    [super dealloc];
}

- (instancetype) init {
    self = [super init];
    if (self != nil) {
        _scrollerStyle = [NSScroller preferredScrollerStyle];
        _overlayState = NSOverlayScrollerStateHidden;
        lockScrollerImpPairs();
        CFSetAddValue(allScrollerImpPairs, self);
        [allScrollerImpPairsLock unlock];
    }
    return self;
}

+ (NSUserInterfaceLayoutDirection) scrollerLayoutDirection {
    return NSUserInterfaceLayoutDirectionLeftToRight;
}

// Asks each pair's delegate to switch to the new recommended style; the
// delegate replaces its scroller imps.
+ (void) _updateAllScrollerImpPairsForNewRecommendedScrollerStyle: (NSScrollerStyle) style {
    lockScrollerImpPairs();
    CFIndex count = CFSetGetCount(allScrollerImpPairs);
    const void **values = malloc(sizeof(void *) * (count > 0 ? count : 1));
    CFSetGetValues(allScrollerImpPairs, values);
    NSArray *pairs = [[NSArray alloc] initWithObjects: (id *) values count: count];
    free(values);
    [allScrollerImpPairsLock unlock];

    for (NSScrollerImpPair *pair in pairs) {
        id delegate = [pair delegate];
        if ([delegate respondsToSelector: @selector(scrollerImpPair:updateScrollerStyleForNewRecommendedScrollerStyle:)])
            [delegate scrollerImpPair: pair updateScrollerStyleForNewRecommendedScrollerStyle: style];
    }
    [pairs release];
}

- (void) _redrawScrollers {
    [_verticalScrollerImp setNeedsDisplay: YES];
    [_horizontalScrollerImp setNeedsDisplay: YES];
}

- (void) _showOverlayScrollers: (NSOverlayScrollerState) state duration: (NSTimeInterval) duration {
    if (_overlayStateLocked || _scrollerStyle != NSScrollerStyleOverlay || state == _overlayState)
        return;
    BOOL trackChanges = (state == NSOverlayScrollerStateAllShown) != (_overlayState == NSOverlayScrollerStateAllShown);
    _overlayState = state;
    showOverlayScroller(_verticalScrollerImp, state, duration, trackChanges);
    showOverlayScroller(_horizontalScrollerImp, state, duration, trackChanges);
}

// Overlay scrollers are shown when the content scrolls or is flashed, and stay
// shown until hidden: Darling has no timer that hides them after a while, as
// its NSScrollView keeps overlay scrollers visible.
- (void) flashScrollers {
    [self _showOverlayScrollers: NSOverlayScrollerStateThumbShown duration: kOverlayScrollerFlashDuration];
    [self _redrawScrollers];
}

- (void) hideOverlayScrollers {
    [self _showOverlayScrollers: NSOverlayScrollerStateHidden duration: 0];
}

// The overlay scrollers take the state and keep it until unlocked; scrolling
// and flashing do not change them meanwhile.
- (void) lockOverlayScrollerState: (NSOverlayScrollerState) state {
    _overlayStateLocked = NO;
    [self _showOverlayScrollers: state duration: 0];
    _overlayStateLocked = YES;
}

- (void) unlockOverlayScrollerState {
    _overlayStateLocked = NO;
}

- (BOOL) overlayScrollerStateIsLocked {
    return _overlayStateLocked;
}

- (void) contentAreaDidResize {
    [self _redrawScrollers];
}

- (void) movedToNewWindow {
    // Scroller appearance may change with its window. Both painters should be
    // redrawn after a scroll view is attached to another window.
    [self contentAreaDidResize];
}

- (void) mouseEnteredContentArea {
}

- (void) mouseMovedInContentArea {
}

- (void) mouseExitedContentArea {
    // Legacy scrollers do not use hover visibility, but the painters need a
    // redraw after a tracking transition.
    [self contentAreaDidResize];
}

- (void) contentAreaWillDraw {
    // Legacy scrollers paint with their owning view's display pass.
}

- (void) contentAreaScrolled {
    // Clients report each scroll through this, with no argument, so the imp
    // pair shows the overlay scrollers and redraws its painters.
    [self _showOverlayScrollers: NSOverlayScrollerStateThumbShown duration: 0];
    [self contentAreaDidResize];
}

- (void) contentAreaScrolledInDirection: (NSPoint) direction {
    [self contentAreaScrolled];
}

- (void) windowOrderedOut {
}

- (void) windowOrderedIn {
    [self _redrawScrollers];
}

- (void) startLiveResize {
}

- (void) endLiveResize {
    [self _redrawScrollers];
}

- (void) beginScrollGesture {
    [self _showOverlayScrollers: NSOverlayScrollerStateThumbShown duration: 0];
}

- (void) endScrollGesture {
}

@end

// The scroller style the system recommends, the one of the "Show scroll bars"
// setting.
NSScrollerStyle _NSRecommendedScrollerStyle(void) {
    return [NSScroller preferredScrollerStyle];
}

@implementation NSScroller

// Operated at once: the click that activates the window is delivered to it
// (see -[NSWindow sendEvent:]).
- (BOOL) acceptsFirstMouse: (NSEvent *) event {
    return YES;
}

NS_EXTRA_DEALLOC(NSScroller)

+ (CGFloat) scrollerWidth {
    return [[NSDisplay currentDisplay] scrollerWidth];
}

+ (NSScrollerStyle) preferredScrollerStyle {
    // The "Show scroll bars" setting. Its automatic choice depends on
    // whether a trackpad is in use, which is not known here, so it gives
    // the scrollers a mouse gets.
    NSString *setting = [[NSUserDefaults standardUserDefaults]
            stringForKey: @"AppleShowScrollBars"];

    if ([setting isEqualToString: @"WhenScrolling"])
        return NSScrollerStyleOverlay;
    return NSScrollerStyleLegacy;
}

// Legacy scrollers are 15 points thick for the regular control size and 11 for the small and mini sizes;
// overlay scrollers are 16 and 14 points.
// QUIRK: the widths are not documented. Evidence: black-box observation on macOS 10.14.4 (tier 2), probe
// mac-probes/aqua-scroller-divider.m. Test: tests/appkit-scroller-parts.m (test_quirk_scroller_widths)
+ (CGFloat) scrollerWidthForControlSize: (NSControlSize) controlSize
                          scrollerStyle: (NSScrollerStyle) scrollerStyle
{
    BOOL regular = controlSize == NSControlSizeRegular;

    if (scrollerStyle == NSScrollerStyleOverlay)
        return regular ? 16 : 14;
    return regular ? 15 : 11;
}
/* OS X has a global default "AppleScrollBarVariant" with the values: Single,
 DoubleMin, DoubleMax, and DoubleBoth This controls the default position of the
 scroller. This should be controlling the positioning.
 */

typedef enum {
    NSAppleScrollBarVariantSingle,
    NSAppleScrollBarVariantDoubleMin,
    NSAppleScrollBarVariantDoubleMax,
    NSAppleScrollBarVariantDoubleBoth,
} NSAppleScrollBarVariant;

static NSAppleScrollBarVariant appleScrollBarVariant(NSScroller *self) {
    return NSAppleScrollBarVariantSingle;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    NSUnimplementedMethod();
}

- initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];

    if ([coder allowsKeyedCoding]) {
        NS_EXTRA(NSScroller, self)->sFlags.isHoriz = (_bounds.size.width < _bounds.size.height) ? NO : YES;
        _floatValue = 0;
        _knobProportion = 0;
        [self checkSpaceForParts];
    } else {
        // Layout per class version as recorded from Mac archives: the target, the value,
        // the knob proportion and the action, then up to version 16 a short and from 17
        // two separate bytes. The first byte and the short have an unknown meaning. In
        // the second byte, bits 5-6 hold the control size and the low two bits the arrows
        // position (only the values for the default and for none were observed).
        NSInteger version = [coder versionForClassName: @"NSScroller"];
        NS_EXTRA(NSScroller, self)->sFlags.isHoriz = (_bounds.size.width < _bounds.size.height) ? NO : YES;
        _floatValue = 0;
        _knobProportion = 0;

        id target = [coder decodeObject];
        float floatVal = 0, knobProp = 0;
        SEL action = NULL;
        char unknownByte = 0, flagsByte = 0;

        if (version >= 17) {
            [coder decodeValuesOfObjCTypes: "ff:", &floatVal, &knobProp, &action];
            [coder decodeValuesOfObjCTypes: "c", &unknownByte];
            [coder decodeValuesOfObjCTypes: "c", &flagsByte];
        } else {
            short unknownShort = 0;
            [coder decodeValuesOfObjCTypes: "ff:s", &floatVal, &knobProp, &action, &unknownShort];
        }
        _floatValue = floatVal;
        _knobProportion = knobProp;
        NS_EXTRA(NSScroller, self)->_controlSize = (NSControlSize) ((flagsByte >> 5) & 3);
        NS_EXTRA(NSScroller, self)->_arrowsPosition = (flagsByte & 3) == 2 ? NSScrollerArrowsNone : NSScrollerArrowsMaxEnd;
        [self setTarget: target];
        [self setAction: action];
        [self checkSpaceForParts];
    }
    return self;
}

- initWithFrame: (NSRect) frame {
    [super initWithFrame: frame];
    NS_EXTRA(NSScroller, self)->sFlags.isHoriz = (_bounds.size.width < _bounds.size.height) ? NO : YES;
    _floatValue = 0;
    _knobProportion = 0;
    [self checkSpaceForParts];
    return self;
}

- (BOOL) isFlipped {
    return YES;
}

- (BOOL) refusesFirstResponder {
    return YES;
}

- (BOOL) acceptsFirstResponder {
    return NO;
}

// -setFrame: goes through -setFrameSize: as well.
- (void) setFrameSize: (NSSize) size {
    [super setFrameSize: size];
    [self checkSpaceForParts];
}

- (id) target {
    return NS_EXTRA(NSScroller, self)->_target;
}

- (void) setTarget: (id) target {
    NS_EXTRA(NSScroller, self)->_target = target;
}

- (SEL) action {
    return NS_EXTRA(NSScroller, self)->_action;
}

- (void) setAction: (SEL) action {
    NS_EXTRA(NSScroller, self)->_action = action;
}

- (BOOL) isEnabled {
    return NS_EXTRA(NSScroller, self)->_isEnabled;
}

- (void) setEnabled: (BOOL) flag {
    NS_EXTRA(NSScroller, self)->_isEnabled = flag;
    [self setNeedsDisplay: YES];
}

- (BOOL) isVertical {
    return NS_EXTRA(NSScroller, self)->sFlags.isHoriz ? NO : YES;
}

- (float) floatValue {
    return _floatValue;
}

- (CGFloat) knobProportion {
    return _knobProportion;
}

- (void) setKnobProportion: (CGFloat) proportion {
    _knobProportion = MIN(1.0, MAX(0.0, proportion));
    [self setNeedsDisplay: YES];
}

- (NSScrollArrowPosition) arrowsPosition {
    return NS_EXTRA(NSScroller, self)->_arrowsPosition;
}

- (NSControlTint) controlTint {
    return NS_EXTRA(NSScroller, self)->_controlTint;
}

- (void) setControlTint: (NSControlTint) tint {
    NS_EXTRA(NSScroller, self)->_controlTint = tint;
    [self setNeedsDisplay: YES];
}

- (NSControlSize) controlSize {
    return NS_EXTRA(NSScroller, self)->_controlSize;
}

- (NSScrollerStyle) scrollerStyle {
    return NS_EXTRA(NSScroller, self)->_scrollerStyle;
}

- (NSScrollerKnobStyle) knobStyle {
    return NS_EXTRA(NSScroller, self)->_knobStyle;
}

- (id) scrollerImp {
    // Cocotron draws the scroller directly; there is no separate painter
    // object as in AppKit's private NSScrollerImp implementation.
    return self;
}


- (void) setFloatValue: (float) zeroToOneValue
        knobProportion: (CGFloat) zeroToOneKnob
{
    if (zeroToOneValue > 1)
        zeroToOneValue = 1;
    if (zeroToOneValue < 0)
        zeroToOneValue = 0;
    if (zeroToOneKnob > 1)
        zeroToOneKnob = 1;
    if (zeroToOneKnob < 0)
        zeroToOneKnob = 0;

    _floatValue = zeroToOneValue;
    _knobProportion = zeroToOneKnob;
    if (_knobProportion > 1)
        _knobProportion = 1;

    [self setNeedsDisplay: YES];
}

- (double) doubleValue {
    return _floatValue;
}

- (void) setDoubleValue: (double) zeroToOneValue {
    if (zeroToOneValue > 1)
        zeroToOneValue = 1;
    if (zeroToOneValue < 0)
        zeroToOneValue = 0;

    _floatValue = zeroToOneValue;

    [self setNeedsDisplay: YES];
}

- (void) setArrowsPosition: (NSScrollArrowPosition) position {
    NS_EXTRA(NSScroller, self)->_arrowsPosition = position;
}

- (void) setControlSize: (NSControlSize) value {
    NS_EXTRA(NSScroller, self)->_controlSize = value;
    [self setNeedsDisplay: YES];
}

- (void) setScrollerStyle: (NSScrollerStyle) style {
    NS_EXTRA(NSScroller, self)->_scrollerStyle = style;
}

- (void) setKnobStyle: (NSScrollerKnobStyle) style {
    NS_EXTRA(NSScroller, self)->_knobStyle = style;
    [self setNeedsDisplay: YES];
}

- (NSRect) frameOfDecrementPage {
    NSRect knobSlot = [self rectForPart: NSScrollerKnobSlot];
    NSRect knob = [self rectForPart: NSScrollerKnob];
    NSRect result = knobSlot;

    if (NSIsEmptyRect(knob))
        return NSZeroRect;

    if ([self isVertical]) {
        result.size.height = (knob.origin.y - knobSlot.origin.y);
        if (result.size.height <= 0)
            result = NSZeroRect;
    } else {
        result.size.width = (knob.origin.x - knobSlot.origin.x);
        if (result.size.width <= 0)
            result = NSZeroRect;
    }

    return result;
}

- (NSRect) frameOfIncrementPage {
    NSRect knobSlot = [self rectForPart: NSScrollerKnobSlot];
    NSRect knob = [self rectForPart: NSScrollerKnob];
    NSRect result = knobSlot;

    if (NSIsEmptyRect(knob))
        return NSZeroRect;

    if ([self isVertical]) {
        result.origin.y = knob.origin.y + knob.size.height;
        result.size.height =
                ((knobSlot.origin.y + knobSlot.size.height) - result.origin.y);
        if (result.size.height <= 0)
            result = NSZeroRect;
    } else {
        result.origin.x = knob.origin.x + knob.size.width;
        result.size.width =
                ((knobSlot.origin.x + knobSlot.size.width) - result.origin.x);
        if (result.size.width <= 0)
            result = NSZeroRect;
    }

    return result;
}

static inline CGFloat roundFloat(CGFloat value) {
    value += 0.5;

    return (int) value;
}

// How far inside each end of the slot the knob's travel stops, and the shortest knob (see below).
static const CGFloat kScrollerKnobEndInset = 2;
static const CGFloat kScrollerKnobMinLength = 20;

// The scroller's own geometry along its length: the knob's travel starts and ends two points inside the
// slot, and the knob is as long as the knob proportion of that travel, and at least 20 points.
// QUIRK: not documented. Evidence: black-box observation on macOS 10.14.4 (tier 2) of the part
// rectangles of enabled legacy scrollers 60, 120 and 300 points long, with knob proportions 0.05 to 1 and
// values 0, 0.25, 0.5 and 1 (probe mac-probes/ua5-scroller-parts.m): the knob is floor(proportion x
// (length - 4)) long, 20 at least; its position is 2 + (length - 4 - length of knob before rounding) x
// value, rounded up; the page before it ends at that position rounded down and the
// page after it starts at the end of the knob rounded up. A scroller shows no arrow buttons (the line
// parts are empty), also when it is not enabled, and its knob rectangle is the same when it is not
// enabled. Known deviation: where the position has a fraction, macOS rounds it up or down by a rule not
// found, so the knob can be one point off. Test: tests/appkit-scroller-parts.m (test_quirk_scroller_part_geometry)
static void scrollerKnobGeometry(CGFloat length, CGFloat proportion, CGFloat value, CGFloat *knobStart,
                                 CGFloat *knobLength, CGFloat *positionBeforeRounding,
                                 CGFloat *lengthBeforeRounding) {
    CGFloat travel = MAX(length - 2 * kScrollerKnobEndInset, 0);
    CGFloat rawLength = MIN(MAX(proportion * travel, kScrollerKnobMinLength), MAX(travel, 0));
    CGFloat rawStart = kScrollerKnobEndInset + (travel - rawLength) * value;

    *lengthBeforeRounding = rawLength;
    *positionBeforeRounding = rawStart;
    *knobLength = floor(rawLength);
    *knobStart = ceil(rawStart);
}

- (NSRect) rectForPart: (NSScrollerPart) part {
    NSRect bounds = [self bounds];
    BOOL vertical = [self isVertical];
    CGFloat length = vertical ? bounds.size.height : bounds.size.width;
    CGFloat knobStart, knobLength, rawStart, rawLength;

    scrollerKnobGeometry(length, _knobProportion, _floatValue, &knobStart, &knobLength, &rawStart, &rawLength);

    CGFloat start = 0, size = 0;

    switch (part) {
    case NSScrollerKnobSlot:
        start = 0;
        size = length;
        break;
    case NSScrollerKnob:
        start = knobStart;
        size = knobLength;
        break;
    case NSScrollerDecrementPage:
        start = 0;
        size = floor(rawStart);
        break;
    case NSScrollerIncrementPage: {
        CGFloat end = ceil(rawStart + rawLength);

        start = end;
        size = MAX(length - end, 0);
        break;
    }
    default:
        return NSZeroRect;
    }
    if (vertical)
        return NSMakeRect(bounds.origin.x, bounds.origin.y + start, bounds.size.width, size);
    return NSMakeRect(bounds.origin.x + start, bounds.origin.y, size, bounds.size.height);
}

- (void) checkSpaceForParts {
    NS_EXTRA(NSScroller, self)->sFlags.partsUsable = NSAllScrollerParts;
}

- (NSUsableScrollerParts) usableParts {
    return NS_EXTRA(NSScroller, self)->sFlags.partsUsable;
}

- (void) highlight: (BOOL) flag {
    if (NS_EXTRA(NSScroller, self)->_isHighlighted != flag) {
        NS_EXTRA(NSScroller, self)->_isHighlighted = flag;
        [self setNeedsDisplay: YES];
    }
}

- (void) drawKnobSlotInRect: (NSRect) rect highlight: (BOOL) flag {
    if (!NSIsEmptyRect(rect))
        [[self graphicsStyle] drawScrollerTrackInRect: rect vertical: [self isVertical]];
}

- (void) drawParts {
    // do nothing
}

// The knob is drawn for the scroller artwork of the control size and style, which lies against the far edge
// (the right, or the bottom) of the scroller; a thinner scroller cuts off the near side of it.
// QUIRK: not documented. Evidence: macOS 10.14.4 draws a regular knob in an 11 point scroller and a small
// one in a 15 point scroller that way (tier 2, probe mac-probes/aqua-scroller-divider-mixed.m).
// Test: tests/appkit-scroller-parts.m (test_quirk_scroller_control_sizes)
- (NSRect) _knobArtworkRect: (NSRect) knob {
    CGFloat thickness = [NSScroller scrollerWidthForControlSize: [self controlSize]
                                                  scrollerStyle: [self scrollerStyle]];

    if ([self isVertical]) {
        knob.origin.x = NSMaxX(knob) - thickness;
        knob.size.width = thickness;
    } else {
        knob.origin.y = NSMaxY(knob) - thickness;
        knob.size.height = thickness;
    }
    return knob;
}

- (void) drawKnob {
    NSRect knob = [self rectForPart: NSScrollerKnob];

    if (![self isEnabled] || NSIsEmptyRect(knob))
        return;
    knob = [self _knobArtworkRect: knob];
    if ([self scrollerStyle] == NSScrollerStyleOverlay)
        [[self graphicsStyle] drawOverlayScrollerKnobInRect: knob vertical: [self isVertical]];
    else
        [[self graphicsStyle] drawScrollerKnobInRect: knob
                                            vertical: [self isVertical]
                                           highlight: NS_EXTRA(NSScroller, self)->_isHighlighted];
}

- (void) drawArrow: (NSScrollerArrow) arrow highlight: (BOOL) highlight {
    NSRect rect = (arrow == NSScrollerIncrementArrow)
                          ? [self rectForPart: NSScrollerIncrementLine]
                          : [self rectForPart: NSScrollerDecrementLine];

    [[self graphicsStyle]
            drawScrollerButtonInRect: rect
                             enabled: [self isEnabled]
                             pressed: highlight
                            vertical: [self isVertical]
                            upOrLeft: (arrow != NSScrollerIncrementArrow)];
}

- (void) drawRect: (NSRect) rect {
    // No arrow buttons: the line parts are empty, so nothing is drawn for them. An overlay scroller shows
    // only its knob, over the content.
    if ([self scrollerStyle] == NSScrollerStyleLegacy)
        [self drawKnobSlotInRect: [self rectForPart: NSScrollerKnobSlot] highlight: NO];

    [self drawKnob];
}

- (NSScrollerPart) hitPart {
    return NS_EXTRA(NSScroller, self)->_hitPart;
}

- (NSScrollerPart) testPart: (NSPoint) point {
    // The parts that lie inside the knob slot come before it, since the slot contains them. The
    // NSScrollerPart constants are not in this order, so they are listed rather than counted.
    static const NSScrollerPart order[] = {
        NSScrollerIncrementLine, NSScrollerDecrementLine, NSScrollerKnob,
        NSScrollerIncrementPage, NSScrollerDecrementPage, NSScrollerKnobSlot};
    size_t i;

    NS_EXTRA(NSScroller, self)->_hitPart = NSScrollerNoPart;

    for (i = 0; i < sizeof(order) / sizeof(order[0]); i++) {
        NSRect rect = [self rectForPart: order[i]];

        if (NSMouseInRect(point, rect, [self isFlipped])) {
            NS_EXTRA(NSScroller, self)->_hitPart = order[i];
            break;
        }
    }

    return NS_EXTRA(NSScroller, self)->_hitPart;
}

- (void) trackKnob: (NSEvent *) event {
    NSPoint firstPoint = [self convertPoint: [event locationInWindow]
                                   fromView: nil];
    NSRect slotRect = [self rectForPart: NSScrollerKnobSlot];
    NSRect knobRect = [self rectForPart: NSScrollerKnob];
    CGFloat totalSize;
    CGFloat startFloatValue = _floatValue;

    // The knob travels from two points inside one end of the slot to two points inside the other.
    if ([self isVertical])
        totalSize = slotRect.size.height - 4 - knobRect.size.height;
    else
        totalSize = slotRect.size.width - 4 - knobRect.size.width;

    do {
        NSPoint point;
        CGFloat delta;

        event = [[self window] nextEventMatchingMask: NSLeftMouseUpMask |
                                                      NSLeftMouseDraggedMask];

        point = [self convertPoint: [event locationInWindow] fromView: nil];

        if ([self isVertical])
            delta = point.y - firstPoint.y;
        else
            delta = point.x - firstPoint.x;

        if (totalSize == 0)
            _floatValue = 0;
        else
            _floatValue = startFloatValue + (delta / totalSize);
        if (_floatValue < 0)
            _floatValue = 0;
        else if (_floatValue > 1.0)
            _floatValue = 1.0;

        [self setNeedsDisplay: YES];

        [self sendAction: NS_EXTRA(NSScroller, self)->_action to: NS_EXTRA(NSScroller, self)->_target];

    } while ([event type] != NSLeftMouseUp);
}

- (void) trackScrollButtons: (NSEvent *) event {
    NSRect rect = [self rectForPart: [self hitPart]];
    NSPoint point = [self convertPoint: [event locationInWindow] fromView: nil];

    // fixup to make paging behavior available via the Alt key, like NEXTSTEP
    if (([event modifierFlags] & NSAlternateKeyMask) &&
        (NS_EXTRA(NSScroller, self)->_hitPart == NSScrollerIncrementLine))
        NS_EXTRA(NSScroller, self)->_hitPart = NSScrollerIncrementPage;
    else if (([event modifierFlags] & NSAlternateKeyMask) &&
             (NS_EXTRA(NSScroller, self)->_hitPart == NSScrollerDecrementLine))
        NS_EXTRA(NSScroller, self)->_hitPart = NSScrollerDecrementPage;

    // scroll every 1/2 second...
    [NSEvent startPeriodicEventsAfterDelay: 0.0 withPeriod: 0.05];

    do {
        if ([event type] != NSPeriodic) // periodic events have location of 0,0
            point = [self convertPoint: [event locationInWindow] fromView: nil];

        [self highlight: NSMouseInRect(point, rect, [self isFlipped])];
        if (NSMouseInRect(point, rect, [self isFlipped]))
            [self sendAction: NS_EXTRA(NSScroller, self)->_action to: NS_EXTRA(NSScroller, self)->_target];

        event = [[self window] nextEventMatchingMask: NSPeriodicMask |
                                                      NSLeftMouseUpMask |
                                                      NSLeftMouseDraggedMask];
    } while ([event type] != NSLeftMouseUp);

    [NSEvent stopPeriodicEvents];

    [self highlight: NO];
}

// The "Click in the scroll bar to" setting: AppleScrollerPagingBehavior is 0 (or not set) to scroll
// by a page toward the click, 1 to jump to the clicked spot.
static BOOL scrollerJumpsToClickedSpot(void) {
    return [[NSUserDefaults standardUserDefaults] integerForKey: @"AppleScrollerPagingBehavior"] == 1;
}

// A click in the page area scrolls a page toward the click, repeating while the button is held and
// until the knob reaches the pointer. The scroller's action sees the page part in -hitPart.
- (void) trackPaging: (NSEvent *) event {
    NSScrollerPart page = [self hitPart];
    BOOL paging = YES;

    [self sendAction: NS_EXTRA(NSScroller, self)->_action to: NS_EXTRA(NSScroller, self)->_target];
    [NSEvent startPeriodicEventsAfterDelay: 0.4 withPeriod: 0.1];
    do {
        event = [[self window] nextEventMatchingMask: NSPeriodicMask |
                                                      NSLeftMouseUpMask |
                                                      NSLeftMouseDraggedMask];
        if ([event type] != NSLeftMouseUp) {
            NSPoint point = [self convertPoint: [[self window] mouseLocationOutsideOfEventStream] fromView: nil];

            paging = ([self testPart: point] == page);
            if (paging) {
                NS_EXTRA(NSScroller, self)->_hitPart = page;
                [self sendAction: NS_EXTRA(NSScroller, self)->_action to: NS_EXTRA(NSScroller, self)->_target];
            }
        }
    } while ([event type] != NSLeftMouseUp);
    [NSEvent stopPeriodicEvents];
}

- (void) trackPageSlots: (NSEvent *) event {
    if (!scrollerJumpsToClickedSpot()) {
        [self trackPaging: event];
        return;
    }
    do {
        NSPoint point = [self convertPoint: [event locationInWindow]
                                  fromView: nil];
        NSRect knobRect = [self rectForPart: NSScrollerKnob];
        NSRect knobSlotRect = [self rectForPart: NSScrollerKnobSlot];
        CGFloat roundingThreshold;

        // rounding to edges when distance from edge < size of knob
        if ([self isVertical])
            roundingThreshold = knobRect.size.height / knobSlotRect.size.height;
        else
            roundingThreshold = knobRect.size.width / knobSlotRect.size.width;

        if (NSMouseInRect(point, knobSlotRect, [self isFlipped]) &&
            !NSMouseInRect(point, knobRect, [self isFlipped])) {
            // correct for knobSlot origin
            point.x -= knobSlotRect.origin.x;
            point.y -= knobSlotRect.origin.y;

            if ([self isVertical])
                _floatValue = point.y / knobSlotRect.size.height;
            else
                _floatValue = point.x / knobSlotRect.size.width;

            if (_floatValue < roundingThreshold)
                _floatValue = 0;
            else if (_floatValue > 1.0 - roundingThreshold)
                _floatValue = 1.0;

            // knobRect may now be different
            knobRect = [self rectForPart: NSScrollerKnob];
            NS_EXTRA(NSScroller, self)->_hitPart = NSScrollerKnobSlot; // for scroll-to-click

            [self highlight: YES];
            [self sendAction: NS_EXTRA(NSScroller, self)->_action to: NS_EXTRA(NSScroller, self)->_target];
        }

        event = [[self window] nextEventMatchingMask: NSLeftMouseUpMask |
                                                      NSLeftMouseDraggedMask];

    } while ([event type] != NSLeftMouseUp);

    [self highlight: NO];
}

- (void) mouseDown: (NSEvent *) event {
    NSPoint point = [self convertPoint: [event locationInWindow] fromView: nil];
    NSScrollerPart part = [self testPart: point];

    if (![self isEnabled])
        return;

    switch (part) {
    case NSScrollerNoPart:
        return;

    case NSScrollerKnob:
        [self trackKnob: event];
        break;

    case NSScrollerKnobSlot:
        break;

    case NSScrollerIncrementLine:
    case NSScrollerDecrementLine:
        [self trackScrollButtons: event];
        break;

    case NSScrollerIncrementPage:
    case NSScrollerDecrementPage:
        [self trackPageSlots: event];
        break;
    }
}

- (void) scrollWheel: (NSEvent *) event {
    NSRect slotRect = [self rectForPart: NSScrollerKnobSlot];
    NSRect knobRect = [self rectForPart: NSScrollerKnob];

    if ([self isVertical]) {
        CGFloat delta = [event deltaY];
        CGFloat totalSize = slotRect.size.height - knobRect.size.height;

        if (totalSize == 0)
            _floatValue = 0;
        else
            _floatValue = _floatValue - (delta / totalSize);

        if (_floatValue < 0)
            _floatValue = 0;
        else if (_floatValue > 1.0)
            _floatValue = 1.0;

        [self setNeedsDisplay: YES];
        [self sendAction: NS_EXTRA(NSScroller, self)->_action to: NS_EXTRA(NSScroller, self)->_target];
    }
}

@end

NSNotificationName const NSPreferredScrollerStyleDidChangeNotification = @"NSPreferredScrollerStyleDidChangeNotification";

@implementation NSScrollerImp

@synthesize delegate = _delegate;
@synthesize scrollerStyle = _style;
@synthesize controlSize = _controlSize;
@synthesize expanded = _expanded;
@synthesize uiStateTransitionProgress = _uiStateTransitionProgress;
@synthesize expansionTransitionProgress = _expansionTransitionProgress;
@synthesize userInterfaceLayoutDirection = _userInterfaceLayoutDirection;

+ (NSScrollerImp *) scrollerImpWithStyle: (NSScrollerStyle) style
                             controlSize: (NSControlSize) controlSize
                              horizontal: (BOOL) horizontal
                    replacingScrollerImp: (id) previous
{
    return [[[self alloc] _initWithStyle: style controlSize: controlSize horizontal: horizontal
                                previous: previous] autorelease];
}

+ (CGFloat) scrollerWidthForControlSize: (NSControlSize) controlSize scrollerStyle: (NSScrollerStyle) style {
    return [NSScroller scrollerWidthForControlSize: controlSize scrollerStyle: style];
}

// The painter's orientation comes from the shape of its first frame.
- (NSScroller *) _makePainter {
    CGFloat width = [NSScroller scrollerWidthForControlSize: _controlSize scrollerStyle: _style];
    NSRect frame = _horizontal ? NSMakeRect(0, 0, 2 * width, width) : NSMakeRect(0, 0, width, 2 * width);
    NSScroller *painter = [[NSScroller alloc] initWithFrame: frame];

    [painter setControlSize: _controlSize];
    [painter setScrollerStyle: _style];
    return painter;
}

- (void) _updatePainter {
    [_painter setFrameSize: _boundsSize];
    [_painter setEnabled: _enabled];
    [_painter setKnobStyle: _knobStyle];
    [_painter setKnobProportion: _knobProportion];
    [_painter setDoubleValue: _usePresentationValue ? _presentationValue : _doubleValue];
    [_painter highlight: _tracking];
}

- (instancetype) _initWithStyle: (NSScrollerStyle) style
                    controlSize: (NSControlSize) controlSize
                     horizontal: (BOOL) horizontal
                       previous: (NSScrollerImp *) previous
{
    if ((self = [super init]) == nil)
        return nil;

    _style = style;
    _controlSize = controlSize;
    _horizontal = horizontal;
    // An overlay scroller starts hidden, knob and track, also when it
    // replaces a legacy one (observed on macOS 26.7.3); its pair shows it.
    _knobAlpha = style == NSScrollerStyleOverlay ? 0 : 1;
    _trackAlpha = style == NSScrollerStyleOverlay ? 0 : 1;
    _userInterfaceLayoutDirection = NSUserInterfaceLayoutDirectionLeftToRight;

    // A replacement (another style or size) keeps the state of the imp it
    // replaces.
    if ([previous isKindOfClass: [NSScrollerImp class]]) {
        _enabled = [previous isEnabled];
        _knobStyle = [previous knobStyle];
        _boundsSize = [previous boundsSize];
        _doubleValue = [previous doubleValue];
        _presentationValue = [previous presentationValue];
        _usePresentationValue = [previous shouldUsePresentationValue];
        _knobProportion = [previous knobProportion];
        _userInterfaceLayoutDirection = [previous userInterfaceLayoutDirection];
        _delegate = [previous delegate];
        [self setLayer: [previous layer]];
    }

    _painter = [self _makePainter];
    [self _updatePainter];
    return self;
}

- (instancetype) init {
    return [self _initWithStyle: NSScrollerStyleLegacy controlSize: NSControlSizeRegular horizontal: NO previous: nil];
}

- (void) dealloc {
    [_contentLayer setDelegate: nil];
    [_contentLayer removeFromSuperlayer];
    [_contentLayer release];
    [_layer release];
    [_painter release];
    [super dealloc];
}

- (BOOL) isHorizontal {
    return _horizontal;
}

// Changing the orientation makes a new painter, whose orientation is fixed.
- (void) setHorizontal: (BOOL) horizontal {
    if (horizontal == _horizontal)
        return;
    _horizontal = horizontal;
    [_painter release];
    _painter = [self _makePainter];
    [self _updatePainter];
    [self setNeedsDisplay: YES];
}

- (BOOL) isEnabled {
    return _enabled;
}

- (void) setEnabled: (BOOL) enabled {
    _enabled = enabled;
    [self _updatePainter];
}

- (NSScrollerKnobStyle) knobStyle {
    return _knobStyle;
}

- (void) setKnobStyle: (NSScrollerKnobStyle) style {
    _knobStyle = style;
    [self _updatePainter];
}

- (NSSize) boundsSize {
    return _boundsSize;
}

- (void) setBoundsSize: (NSSize) size {
    _boundsSize = size;
    [self _updatePainter];
}

- (double) doubleValue {
    return _doubleValue;
}

- (void) setDoubleValue: (double) value {
    _doubleValue = value;
    [self _updatePainter];
}

- (double) presentationValue {
    return _presentationValue;
}

- (void) setPresentationValue: (double) value {
    _presentationValue = value;
    [self _updatePainter];
}

// With it set, the knob is drawn at the presentation value instead of the
// value.
- (BOOL) shouldUsePresentationValue {
    return _usePresentationValue;
}

- (void) setUsePresentationValue: (BOOL) flag {
    _usePresentationValue = flag;
    [self _updatePainter];
}

- (CGFloat) knobProportion {
    return _knobProportion;
}

- (void) setKnobProportion: (CGFloat) proportion {
    _knobProportion = proportion;
    [self _updatePainter];
}

- (BOOL) isTracking {
    return _tracking;
}

// The knob is highlighted while it is being dragged.
- (void) setTracking: (BOOL) tracking {
    _tracking = tracking;
    [self _updatePainter];
}

- (CGFloat) knobAlpha {
    return _knobAlpha;
}

- (void) setKnobAlpha: (CGFloat) alpha {
    _knobAlpha = alpha;
    [self setNeedsDisplay: YES];
}

- (CGFloat) trackAlpha {
    return _trackAlpha;
}

- (void) setTrackAlpha: (CGFloat) alpha {
    _trackAlpha = alpha;
    [self setNeedsDisplay: YES];
}

// The metrics follow the NSScroller drawn: the track is the scroller's whole
// width and length, and the knob travels between kScrollerKnobEndInset points
// inside each end and is at least kScrollerKnobMinLength long.
- (CGFloat) trackBoxWidth {
    return [NSScroller scrollerWidthForControlSize: _controlSize scrollerStyle: _style];
}

- (CGFloat) trackWidth {
    return [self trackBoxWidth];
}

- (CGFloat) trackSideInset {
    return 0;
}

- (CGFloat) trackEndInset {
    return 0;
}

- (CGFloat) knobEndInset {
    return kScrollerKnobEndInset;
}

- (CGFloat) knobMinLength {
    return kScrollerKnobMinLength;
}

- (CGFloat) knobOverlapEndInset {
    return 0;
}

- (CGFloat) trackOverlapEndInset {
    return 0;
}

// In the coordinates of the scroller's bounds, origin at the top left.
- (NSRect) rectForPart: (NSScrollerPart) part {
    return [_painter rectForPart: part];
}

- (void) drawKnobSlotInRect: (NSRect) slotRect highlight: (BOOL) flag alpha: (CGFloat) alpha {
    if (alpha <= 0)
        return;

    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];

    CGContextSaveGState(context);
    CGContextSetAlpha(context, MIN(alpha, 1));
    [_painter drawKnobSlotInRect: slotRect highlight: flag];
    CGContextRestoreGState(context);
}

// The knob and track alphas fade overlay scrollers in and out; a legacy
// scroller is drawn whole whatever they are (observed on macOS 26.7.3 and
// 10.14.4).
- (CGFloat) _drawingAlpha: (CGFloat) alpha {
    return _style == NSScrollerStyleOverlay ? alpha : 1;
}

- (void) drawKnobSlotInRect: (NSRect) slotRect highlight: (BOOL) flag {
    [self drawKnobSlotInRect: slotRect highlight: flag alpha: [self _drawingAlpha: _trackAlpha]];
}

- (void) drawKnob {
    CGFloat alpha = [self _drawingAlpha: _knobAlpha];

    if (alpha <= 0)
        return;

    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];

    CGContextSaveGState(context);
    CGContextSetAlpha(context, MIN(alpha, 1));
    [_painter drawKnob];
    CGContextRestoreGState(context);
}

// Darling's overlay scrollers do not grow under the pointer, so hovering only
// is recorded.
- (void) mouseEnteredScroller {
    _mouseInScroller = YES;
}

- (void) mouseExitedScroller {
    _mouseInScroller = NO;
}

- (CALayer *) layer {
    return _layer;
}

- (void) setLayer: (CALayer *) layer {
    if (layer == _layer)
        return;

    [_contentLayer removeFromSuperlayer];
    [_layer release];
    _layer = [layer retain];
    if (_layer != nil) {
        if (_contentLayer == nil) {
            _contentLayer = [[CALayer alloc] init];
            [_contentLayer setDelegate: self];
        }
        [_layer addSublayer: _contentLayer];
    }
    [self setNeedsDisplay: YES];
}

// Redraws the scroller's sublayer of the layer it was given; without a layer
// the client draws the scroller with -drawKnobSlotInRect:highlight: and
// -drawKnob itself.
- (void) setNeedsDisplay: (BOOL) flag {
    if (!flag || _layer == nil)
        return;
    [_contentLayer setFrame: [_layer bounds]];
    [_contentLayer setNeedsDisplay];
}

- (void) drawLayer: (CALayer *) layer inContext: (CGContextRef) context {
    if (layer != _contentLayer)
        return;

    CGRect bounds = [layer bounds];
    NSGraphicsContext *graphicsContext = [NSGraphicsContext graphicsContextWithCGContext: context flipped: YES];

    // The parts are laid out from the top left.
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, bounds.origin.x, bounds.origin.y + bounds.size.height);
    CGContextScaleCTM(context, 1, -1);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: graphicsContext];
    [self drawKnobSlotInRect: [self rectForPart: NSScrollerKnobSlot] highlight: NO];
    if (_enabled)
        [self drawKnob];
    [NSGraphicsContext restoreGraphicsState];
    CGContextRestoreGState(context);
}

@end
