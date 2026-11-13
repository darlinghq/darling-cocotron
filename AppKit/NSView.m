/* Copyright (c) 2006-2007 Christopher J. W. Lloyd
                 2009-2010 Markus Hitter <mah@jump-ing.de>
                 2020 Lubos Dolezel

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
#import <AppKit/NSClipView.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSCursorRect.h>
#import <AppKit/NSDragging.h>
#import <AppKit/NSDraggingManager.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContextFunctions.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSObject+BindingSupport.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSPrintInfo.h>
#import <AppKit/NSPrintOperation.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSTrackingArea.h>
#import <AppKit/NSView.h>
#import <AppKit/NSViewBackingLayer.h>
#import <AppKit/NSWindow-Private.h>
#import <AppKit/NSDocument.h>
#import <AppKit/NSWindowController.h>
#import <CoreGraphics/CGWindow.h>
#import <Foundation/NSKeyedArchiver.h>
#import <Onyx2D/O2Context.h>
#import <QuartzCore/CALayerContext.h>
#import <QuartzCore/CATransaction.h>
#import <AppKit/NSLayoutAnchor.h>
#import <AppKit/NSLayoutConstraint.h>
#import <AppKit/NSLayoutGuide.h>
#import "NSLayoutConstraintInternal.h"
#import <AppKit/NSTextInput.h>
#import <AppKit/NSTextInputClient.h>
#import <objc/runtime.h>
#include <math.h>
#import "NSGestureRecognizer-Private.h"
#import "DarlingLayout.h"

@class IBMetricsTable;

NSString *const NSViewFrameDidChangeNotification =
        @"NSViewFrameDidChangeNotification";
NSString *const NSViewBoundsDidChangeNotification =
        @"NSViewBoundsDidChangeNotification";
NSString *const NSViewFocusDidChangeNotification =
        @"NSViewFocusDidChangeNotification";
const NSNotificationName NSViewGlobalFrameDidChangeNotification =
        @"NSViewGlobalFrameDidChangeNotification";

const NSViewFullScreenModeOptionKey NSFullScreenModeApplicationPresentationOptions =
        @"NSFullScreenModeApplicationPresentationOptions";

@interface NSView (NSView_forward)
- (CGAffineTransform) transformFromWindow;
- (CGAffineTransform) transformToWindow;
- (CGAffineTransform) transformToLayer;
- (void) _trackingAreasChanged;
- (void) _addLayerToSuperlayer;
- (void) _updateLayerVisibility;
- (void) _removeLayerFromSuperlayer;
@end

@implementation NSView

@synthesize identifier = _identifier;
@synthesize translatesAutoresizingMaskIntoConstraints = _translatesAutoresizingMaskIntoConstraints;
@synthesize appearance = _appearance;
@synthesize wantsBestResolutionOpenGLSurface = _wantsBestResolutionOpenGLSurface;

static BOOL NSViewLayersEnabled = YES;
static BOOL NSShowAllViews = NO;

+ (void) initialize {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    //NSViewLayersEnabled = [defaults boolForKey: @"NSViewLayersEnabled"];
    NSShowAllViews = [defaults boolForKey: @"NSShowAllViews"];
}

+ (BOOL) requiresConstraintBasedLayout {
    return NO;
}

- (NSColor *) _borderColorForNSShowAllViews {
    return [NSColor orangeColor];
}

+ (NSView *) focusView {
    return [NSCurrentFocusStack() lastObject];
}

+ (NSMenu *) defaultMenu {
    return nil;
}

+ (NSFocusRingType) defaultFocusRingType {
    NSUnimplementedMethod();
    return 0;
}

typedef struct __VFlags {
#ifdef __BIG_ENDIAN__
    unsigned int rotatedFromBase : 1;
    unsigned int rotatedOrScaledFromBase : 1;
    unsigned int autosizing : 6;
    unsigned int autoresizeSubviews : 1;
    unsigned int wantsGState : 1;
    unsigned int needsDisplay : 1;
    unsigned int validGState : 1;
    unsigned int newGState : 1;
    unsigned int noVerticalAutosizing : 1;
    unsigned int frameChangeNotesSuspended : 1;
    unsigned int needsFrameChangeNote : 1;
    unsigned int focusChangeNotesSuspended : 1;
    unsigned int boundsChangeNotesSuspended : 1;
    unsigned int needsBoundsChangeNote : 1;
    unsigned int removingWithoutInvalidation : 1;
    unsigned int interfaceStyle0 : 1;
    unsigned int needsDisplayForBounds : 1;
    unsigned int specialArchiving : 1;
    unsigned int interfaceStyle1 : 1;
    unsigned int retainCount : 6;
    unsigned int retainCountOverMax : 1;
    unsigned int aboutToResize : 1;
#else
    unsigned int aboutToResize : 1;
    unsigned int retainCountOverMax : 1;
    unsigned int retainCount : 6;
    unsigned int interfaceStyle1 : 1;
    unsigned int specialArchiving : 1;
    unsigned int needsDisplayForBounds : 1;
    unsigned int interfaceStyle0 : 1;
    unsigned int removingWithoutInvalidation : 1;
    unsigned int needsBoundsChangeNote : 1;
    unsigned int boundsChangeNotesSuspended : 1;
    unsigned int focusChangeNotesSuspended : 1;
    unsigned int needsFrameChangeNote : 1;
    unsigned int frameChangeNotesSuspended : 1;
    unsigned int noVerticalAutosizing : 1;
    unsigned int newGState : 1;
    unsigned int validGState : 1;
    unsigned int needsDisplay : 1;
    unsigned int wantsGState : 1;
    unsigned int autoresizeSubviews : 1;
    unsigned int autosizing : 6;
    unsigned int rotatedOrScaledFromBase : 1;
    unsigned int rotatedFromBase : 1;
#endif
} _VFlags;

- (void) encodeWithCoder: (NSCoder *) coder {
    [super encodeWithCoder: coder];

    if (coder.allowsKeyedCoding) {
        unsigned vFlags = 0;
        vFlags |= _autoresizingMask & 0x3f;
        vFlags |= _autoresizesSubviews ? 0x100 : 0;
        vFlags |= _isHidden ? 0x80000000 : 0;
        // TODO: there are almost certainly more vFlags

        [coder encodeInt: vFlags forKey: @"NSvFlags"];
        [coder encodeRect: _frame forKey: @"NSFrame"];
        [coder encodeRect: _bounds forKey: @"NSBounds"];
        [coder encodeInt: _tag forKey: @"NSTag"];
        // TODO: do we need to order the subviews here in back-to-front order ourselves?
        [coder encodeObject: _subviews forKey: @"NSSubviews"];
        [coder encodeObject: _window forKey: @"NSWindow"];
        [coder encodeObject: _superview forKey: @"NSSuperview"];
        [coder encodeObject: _nextKeyView forKey: @"NSNextKeyView"];
        [coder encodeObject: _shadow forKey: @"NSViewShadow"];
        [coder encodeObject: _compositingFilter
                     forKey: @"NSViewCompositeFilter"];
        //[coder encodeObject: _backgroundFilters
        //             forKey: @"NSViewBackgroundFilters"];
        [coder encodeObject: _animations forKey: @"NSViewAnimations"];
        [coder encodeBool: _canDrawConcurrently
                   forKey: @"NSViewCanDrawConcurrently"];
        [coder encodeBool: _wantsLayer forKey: @"NSViewIsLayerTreeHost"];
        [coder encodeInteger: _layerContentsRedrawPolicy
                      forKey: @"NSViewLayerContentsRedrawPolicy"];
        [coder encodeObject: _contentFilters forKey: @"NSViewContentFilters"];
        [coder encodeBool: _wantsBestResolutionOpenGLSurface
                   forKey: @"NSViewWantsBestResolutionOpenGLSurface"];
    } else {
        [NSException raise: NSInvalidArchiveOperationException
                    format: @"TODO: support unkeyed encoding in NSView"];
    }
}

- initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];

    // TODO: decode this
    _translatesAutoresizingMaskIntoConstraints = YES;
    _alphaValue = 1.0;
    _allowedTouchTypes = NSTouchTypeMaskDirect;
    [self _setDefaultLayoutPriorities];

    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;
        unsigned vFlags = [keyed decodeIntForKey: @"NSvFlags"];

        _frame = NSZeroRect;
        if ([keyed containsValueForKey: @"NSFrame"])
            _frame = [keyed decodeRectForKey: @"NSFrame"];
        else if ([keyed containsValueForKey: @"NSFrameSize"])
            _frame.size = [keyed decodeSizeForKey: @"NSFrameSize"];

        if ([keyed containsValueForKey: @"NSBounds"]) {
            _bounds = [keyed decodeRectForKey: @"NSBounds"];
        } else {
            _bounds.origin = NSMakePoint(0, 0);
            _bounds.size = _frame.size;
        }
        _window = nil;
        _superview = nil;
        _subviews = [NSMutableArray new];
        _postsNotificationOnFrameChange = YES;
        _postsNotificationOnBoundsChange = YES;
        _autoresizingMask = vFlags & 0x3F;
        if ([keyed containsValueForKey: @"NSvFlags"])
            _autoresizesSubviews = (vFlags & 0x100) ? YES : NO;
        // Despite the fact it appears _autoresizesSubviews is encoded in the
        // flags, it should always be ON
        // *** Do not turn off or base on the flags unless you have an
        // alternative for enabling it when it should be.
        _autoresizesSubviews = YES;
        _isHidden = (vFlags & 0x80000000) ? YES : NO;
        _wantsBestResolutionOpenGLSurface = [keyed
                decodeBoolForKey: @"NSViewWantsBestResolutionOpenGLSurface"];
        _tag = 0; // IB assigns a default tag id of 0 - which is different from
                  // the default in the docs.
        if ([keyed containsValueForKey: @"NSTag"])
            _tag = [keyed decodeIntForKey: @"NSTag"];

        // Subviews come in from the nib in back to front order
        [_subviews
                addObjectsFromArray: [keyed decodeObjectForKey: @"NSSubviews"]];
        [_subviews
                makeObjectsPerformSelector: @selector(viewWillMoveToSuperview:)
                                withObject: self];
        [_subviews makeObjectsPerformSelector: @selector(_setSuperview:)
                                   withObject: self];
        [_subviews
                makeObjectsPerformSelector: @selector(viewDidMoveToSuperview)];

        _window = [keyed decodeObjectForKey: @"NSWindow"];
        _superview = [keyed decodeObjectForKey: @"NSSuperview"];
        [self setNextKeyView: [keyed decodeObjectForKey: @"NSNextKeyView"]];

        if ([keyed containsValueForKey: @"NSViewShadow"])
            [self setShadow: [keyed decodeObjectForKey: @"NSViewShadow"]];

        if ([keyed containsValueForKey: @"NSViewCompositeFilter"])
            [self setCompositingFilter:
                            [keyed decodeObjectForKey:
                                            @"NSViewCompositeFilter"]];

        if ([keyed containsValueForKey: @"NSViewBackgroundFilters"])
            [self setBackgroundFilters:
                            [keyed decodeObjectForKey:
                                            @"NSViewBackgroundFilters"]];

        if ([keyed containsValueForKey: @"NSViewAnimations"])
            [self setAnimations:
                            [keyed decodeObjectForKey: @"NSViewAnimations"]];

        if ([keyed containsValueForKey: @"NSUserInterfaceItemIdentifier"]) {
            _identifier = [[keyed decodeObjectForKey: @"NSUserInterfaceItemIdentifier"] copy];
        } else if ([keyed containsValueForKey: @"NSReuseIdentifierKey"]) {
            _identifier = [[keyed decodeObjectForKey: @"NSReuseIdentifierKey"] copy];
        } else if ([keyed containsValueForKey: @"NSIdentifier"]) {
            _identifier = [[keyed decodeObjectForKey: @"NSIdentifier"] copy];
        }

        [self setCanDrawConcurrently:
                        [keyed decodeBoolForKey: @"NSViewCanDrawConcurrently"]];

        // TODO: NSViewConstraints, NSViewLayoutGuides, ...

        _needsDisplay = YES;
        _invalidRectCount = 0;
        _invalidRects = NULL;
        _trackingAreas = [[NSMutableArray alloc] init];
        [self setWantsLayer:
                        [keyed decodeBoolForKey: @"NSViewIsLayerTreeHost"]];

        _layerContentsRedrawPolicy =
                [keyed decodeIntegerForKey: @"NSViewLayerContentsRedrawPolicy"];

        _contentFilters =
                [[keyed decodeObjectForKey: @"NSViewContentFilters"] retain];
    } else {
        NSInteger version = [coder versionForClassName: @"NSView"];

        union {
            _VFlags vf;
            uint32_t value;
        } vflags;

        vflags.value = 0;

        if (version <= 16) {
            float dummy;
            [coder decodeValuesOfObjCTypes: "f", &dummy];

            _frame = [coder decodeRect];
            _bounds = [coder decodeRect];
            _superview = [coder decodeObject];
            _window = [coder decodeObject];

            unsigned short flags1, flags2;
            id obj;

            [coder decodeValuesOfObjCTypes: "@ss@", &_subviews, &flags1,
                                            &flags2, &obj];
            [obj release];

            vflags.vf.rotatedFromBase = (flags1 & 0x400) != 0;
            vflags.vf.rotatedOrScaledFromBase = vflags.vf.validGState =
                    (flags1 & 0x200) != 0;
            vflags.vf.autosizing = (flags2 & 0xFC00) >> 10;
            vflags.vf.autoresizeSubviews = (flags2 & 0x200) != 0;
            vflags.vf.wantsGState = (flags2 & 0x10) != 0;

            if (version < 1) {
                // macOS reads the version 1 layout before refusing it.
                [NSException raise: @"NSObjectInaccessibleException"
                            format: @"-[NSView initWithCoder:]: found NSView object version %ld; cannot unarchive NSView versions less than 1.",
                                    (long) version];
            }
        } else if (version <= 40) {
            _frame = [coder decodeRect];
            _bounds = [coder decodeRect];

            _superview = [coder decodeObject];
            _window = [coder decodeObject];

            id dummy, frameMatrix;
            [coder decodeValuesOfObjCTypes: "@@@@", &_subviews, &dummy,
                                            &frameMatrix, &_draggedTypes];
            [dummy release];
            [frameMatrix release];

            // Four flag bytes (five from version 25): rotated, rotated or
            // scaled, the autoresizing mask, whether subviews autoresize.
            // The fifth byte is read and kept out of the way: no property
            // that is observable on macOS changes with it.
            uint8_t flags1 = 0, flags2 = 0, flags3 = 0, flags4 = 0, flags5 = 0;
            [coder decodeValuesOfObjCTypes: "c", &flags1];
            [coder decodeValuesOfObjCTypes: "c", &flags2];
            [coder decodeValuesOfObjCTypes: "c", &flags3];
            [coder decodeValuesOfObjCTypes: "c", &flags4];

            vflags.vf.rotatedFromBase = flags1 & 1;
            vflags.vf.rotatedOrScaledFromBase = flags2 & 1;
            vflags.vf.autosizing = flags3 & 0x3F;
            vflags.vf.autoresizeSubviews = flags4 & 1;

            if (version >= 25) {
                [coder decodeValuesOfObjCTypes: "c", &flags5];
                [self setNextKeyView: [coder decodeObject]];
                // A second object follows the next key view; macOS keeps it
                // in a place that is not visible through the public API.
                [coder decodeObject];
            }
        } else {
            int flags;
            [coder decodeValuesOfObjCTypes: "i", &flags];

            vflags.value = flags & 0xFFC00000;

            id drawMatrix, frameMatrix;

            float fx, fy, fw, fh;
            float bx, by, bw, bh;
            [coder decodeValuesOfObjCTypes: "@@@@ffffffff", &_subviews,
                                            &drawMatrix, &frameMatrix, &_draggedTypes,
                                            &fx, &fy, &fw, &fh, &bx, &by, &bw,
                                            &bh];

            // Discard for now
            [drawMatrix release];
            [frameMatrix release];

            _frame = NSMakeRect(fx, fy, fw, fh);
            _bounds = NSMakeRect(bx, by, bw, bh);

            _superview = [coder decodeObject];
            _window = [coder decodeObject];
            [self setNextKeyView: [coder decodeObject]];
            [coder decodeObject];
        }

        // Archives hold the subviews in an immutable or mutable array; the
        // view mutates its own.
        {
            NSMutableArray *subviews = [[NSMutableArray alloc] initWithArray: _subviews];

            [_subviews release];
            _subviews = subviews;
        }

        _autoresizingMask = vflags.vf.autosizing;
        _autoresizesSubviews = vflags.vf.autoresizeSubviews;
    }

    return self;
}

- init {
    return [self initWithFrame: NSMakeRect(0, 0, 1, 1)];
}

- initWithFrame: (NSRect) frame {
    _frame = frame;
    _bounds.origin = NSMakePoint(0, 0);
    _bounds.size = frame.size;
    _window = nil;
    _menu = nil;
    _superview = nil;
    _subviews = [NSMutableArray new];
    _postsNotificationOnFrameChange = YES;
    _postsNotificationOnBoundsChange = YES;
    _autoresizesSubviews = YES;
    _autoresizingMask = NSViewNotSizable;
    _tag = -1; // according to the docs - loading from a nib gets a default of
               // 0.
    _needsDisplay = YES;
    _invalidRectCount = 0;
    _invalidRects = NULL;
    _trackingAreas = [[NSMutableArray alloc] init];

    _validTransforms = NO;
    _transformFromWindow = CGAffineTransformIdentity;
    _transformToWindow = CGAffineTransformIdentity;
    _transformToLayer = CGAffineTransformIdentity;

    // according to some Apple sample code ("Creating a Custom Metal View"),
    // it's valid for a subclass of NSView to set `wantsLayer` before invoking the superclass `initWithFrame:`.
    // thus, we might have a layer context already but with an incorrect frame.
    [_layerContext setFrame: _frame];

    _translatesAutoresizingMaskIntoConstraints = YES;
    _alphaValue = 1.0;
    _allowedTouchTypes = NSTouchTypeMaskDirect;
    [self _setDefaultLayoutPriorities];

    return self;
}

- (void) dealloc {
    [NSLayoutConstraint deactivateConstraints:[self constraints]];

    // Do this first?
    [self _unbindAllBindings];

    _window = nil;
    [_menu release];
    [_accessibilityTitle release];

    _superview = nil;
    [_subviews makeObjectsPerformSelector: @selector(_setSuperview:)
                               withObject: nil];

    [_subviews release];
    [_draggedTypes release];
    [_trackingAreas release];
    [_contentFilters release];
    [_constraints makeObjectsPerformSelector: @selector(_detachFromOwner:) withObject: self];
    [_constraints release];

    if (_invalidRects != NULL)
        NSZoneFree(NULL, _invalidRects);

    if (_rectsBeingRedrawn != NULL) {
        NSZoneFree(NULL, _rectsBeingRedrawn);
    }
    [_layer release];

    [_layerContext invalidate];
    [_layerContext release];

    [_identifier release];
    for (NSGestureRecognizer *recognizer in _gestureRecognizers)
        [recognizer _setView: nil];
    [_gestureRecognizers release];

    [super dealloc];
}

static void invalidateTransform(NSView *self) {
    self->_validTransforms = NO;
    self->_validTrackingAreas = NO;

    for (NSView *check in self->_subviews)
        invalidateTransform(check);
}

static CGAffineTransform concatViewTransform(CGAffineTransform result,
                                             NSView *view, NSView *superview,
                                             BOOL doFrame, BOOL flip)
{
    NSRect bounds = [view bounds];
    NSRect frame = [view frame];

    if (doFrame)
        result = CGAffineTransformTranslate(result, frame.origin.x,
                                            frame.origin.y);

    // Apply bounds scaling to fit in the frame
    // Empty bounds have no defined scale on that axis. Preserve translation
    // and the other axis rather than introducing 0/0 into the view hierarchy.
    CGFloat scaleX = NSWidth(bounds) == 0 ? 1 : NSWidth(frame) / NSWidth(bounds);
    CGFloat scaleY = NSHeight(bounds) == 0 ? 1 : NSHeight(frame) / NSHeight(bounds);
    CGAffineTransform scale =
            CGAffineTransformMakeScale(scaleX, scaleY);
    result = CGAffineTransformConcat(scale, result);

    if (flip) {
        CGAffineTransform flip =
                CGAffineTransformMake(1, 0, 0, -1, 0, bounds.size.height);

        result = CGAffineTransformConcat(flip, result);
    }
    result = CGAffineTransformTranslate(result, -bounds.origin.x,
                                        -bounds.origin.y);

    return result;
}

- (CGAffineTransform) createTransformToWindow {
    CGAffineTransform result;
    NSView *superview = [self superview];
    BOOL doFrame = YES;
    BOOL flip;

    if (superview == nil) {
        result = CGAffineTransformIdentity;
        flip = [self isFlipped];
    } else {
        result = [superview transformToWindow];
        flip = ([self isFlipped] != [superview isFlipped]);
    }

    result = concatViewTransform(result, self, superview, doFrame, flip);

    return result;
}

- (CGAffineTransform) createTransformToLayer {
    CGAffineTransform result = CGAffineTransformIdentity;
    NSRect bounds = [self bounds];

    if ([self isFlipped]) {
        CGAffineTransform flip =
                CGAffineTransformMake(1, 0, 0, -1, 0, bounds.size.height);

        result = CGAffineTransformConcat(flip, result);
    }
    result = CGAffineTransformTranslate(result, -bounds.origin.x,
                                        -bounds.origin.y);

    return result;
}

- (NSRect) calculateVisibleRect {
    if ([self isHiddenOrHasHiddenAncestor])
        return NSZeroRect;

    if ([self superview] == nil)
        return [self bounds];
    else {
        NSRect result = [[self superview] visibleRect];

        result = [self convertRect: result fromView: [self superview]];

        result = NSIntersectionRect(result, [self bounds]);

        return result;
    }
}

static inline void configureLayerGeometry(NSView *self) {
    CALayer *layer = self->_layer;

    if (layer == nil)
        return;

    [CATransaction begin];
    [CATransaction setDisableActions: YES];

    [layer setAnchorPoint: CGPointMake(0, 0)];

    if ([layer superlayer] == nil)
        [layer setPosition: CGPointMake(0, 0)];
    else
        [layer setPosition: self->_frame.origin];

    [layer setBounds: self->_bounds];
    [CATransaction commit];
}

static inline void buildTransformsIfNeeded(NSView *self) {
    if (!self->_validTransforms) {
        self->_transformToWindow = [self createTransformToWindow];
        self->_transformFromWindow =
                CGAffineTransformInvert(self->_transformToWindow);
        self->_transformToLayer = [self createTransformToLayer];
        self->_validTransforms = YES;

        self->_visibleRect = [self calculateVisibleRect];
        configureLayerGeometry(self);
    }
}

- (CGAffineTransform) transformFromWindow {
    buildTransformsIfNeeded(self);

    return _transformFromWindow;
}

- (CGAffineTransform) transformToWindow {
    buildTransformsIfNeeded(self);

    return _transformToWindow;
}

- (CGAffineTransform) transformToLayer {
    buildTransformsIfNeeded(self);

    return _transformToLayer;
}

- (NSRect) frame {
    return _frame;
}

- (CGFloat) frameRotation {
    return _frameRotation;
}

- (CGFloat) frameCenterRotation {
    NSUnimplementedMethod();
    return 0.;
}

- (NSRect) bounds {
    return _bounds;
}

- (CGFloat) boundsRotation {
    return _boundsRotation;
}

- (BOOL) isRotatedFromBase {
    NSUnimplementedMethod();
    return NO;
}

- (BOOL) isRotatedOrScaledFromBase {
    NSUnimplementedMethod();
    return NO;
}

- (void) translateOriginToPoint: (NSPoint) point {
    NSUnimplementedMethod();
}

- (void) rotateByAngle: (CGFloat) angle {
    [self setBoundsRotation: [self boundsRotation] + angle];
}

- (BOOL) postsFrameChangedNotifications {
    return _postsNotificationOnFrameChange;
}

- (BOOL) postsBoundsChangedNotifications {
    return _postsNotificationOnBoundsChange;
}

- (void) scaleUnitSquareToSize: (NSSize) size {
    // Negative and infinite factors are accepted, as on macOS. A zero or NaN
    // factor cannot produce usable bounds; macOS aborts the process there, so
    // raising an exception is the conservative replacement for a crash.
    if (isnan(size.width) || isnan(size.height) ||
            size.width == 0 || size.height == 0)
        [NSException raise: NSInvalidArgumentException
                    format: @"scaleUnitSquareToSize: requires non-zero, non-NaN dimensions"];

    if (size.width == 1.0 && size.height == 1.0)
        return;

    NSRect bounds = [self bounds];
    bounds.origin.x /= size.width;
    bounds.origin.y /= size.height;
    bounds.size.width /= size.width;
    bounds.size.height /= size.height;
    if (!isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) ||
            !isfinite(bounds.size.width) || !isfinite(bounds.size.height))
        [NSException raise: NSInvalidArgumentException
                    format: @"scaleUnitSquareToSize: produces non-finite bounds"];
    // A negative factor mirrors the axis; the bounds keep a positive size and
    // the origin moves to the other edge.
    if (bounds.size.width < 0) {
        bounds.origin.x += bounds.size.width;
        bounds.size.width = -bounds.size.width;
    }
    if (bounds.size.height < 0) {
        bounds.origin.y += bounds.size.height;
        bounds.size.height = -bounds.size.height;
    }
    [self setBounds: bounds];
}

- (NSWindow *) window {
    return _window;
}

- (NSView *) superview {
    return _superview;
}

- (BOOL) isDescendantOf: (NSView *) other {
    NSView *check = self;

    do {
        if (check == other)
            return YES;

        check = [check superview];
    } while (check != nil);

    return NO;
}

- (NSView *) ancestorSharedWithView: (NSView *) view {
    NSUnimplementedMethod();
    return nil;
}

- (NSScrollView *) enclosingScrollView {
    id result = [self superview];

    for (; result != nil; result = [result superview])
        if ([result isKindOfClass: [NSScrollView class]])
            return result;

    return nil;
}

- (NSRect) adjustScroll: (NSRect) toRect {
    NSUnimplementedMethod();
    return NSZeroRect;
}

- (NSArray *) subviews {
    return _subviews;
}

- (BOOL) autoresizesSubviews {
    return _autoresizesSubviews;
}

- (NSAutoresizingMaskOptions) autoresizingMask {
    return _autoresizingMask;
}

- (NSFocusRingType) focusRingType {
    return _focusRingType;
}

- (NSInteger) tag {
    return _tag;
}

- (BOOL) isFlipped {
    return NO;
}

- (BOOL) isOpaque {
    return NO;
}

- (BOOL) isDrawingFindIndicator {
    // A find indicator is active only while AppKit paints its transient
    // search highlight. Cocotron has no such painting pass yet.
    return NO;
}

- (CGFloat) alphaValue {
    return _alphaValue;
}

// Applied through the backing layer; views drawn without one ignore it.
- (void) setAlphaValue: (CGFloat) alpha {
    _alphaValue = alpha;
    [_layer setOpacity: alpha];
}

- (int) gState {
    return 0;
}

- (NSRect) visibleRect {
    buildTransformsIfNeeded(self);

    return _visibleRect;
}

- (BOOL) wantsDefaultClipping {
    NSUnimplementedMethod();
    return NO;
}

- (NSBitmapImageRep *) bitmapImageRepForCachingDisplayInRect: (NSRect) rect {
    NSUnimplementedMethod();
    return nil;
}

- (void) cacheDisplayInRect: (NSRect) rect
           toBitmapImageRep: (NSBitmapImageRep *) imageRep
{
    NSUnimplementedMethod();
}

- (BOOL) isHidden {
    return _isHidden;
}

- (BOOL) isHiddenOrHasHiddenAncestor {
    return _isHidden || [_superview isHiddenOrHasHiddenAncestor];
}

- (void) setHidden: (BOOL) flag {
    flag = flag ? YES : NO;

    if (_isHidden != flag) {
        invalidateTransform(self);
        if ((_isHidden = flag)) {
            id view = [_window firstResponder];

            if ([view isKindOfClass: [NSView class]])
                for (; view; view = [view superview]) {
                    if (self == view) {
                        [_window makeFirstResponder: [self nextValidKeyView]];
                        break;
                    }
                }
        }

        [self _updateLayerVisibility];
        [[self superview] setNeedsDisplay: YES];

        if (_isHidden)
            [self viewDidHide];
        else
            [self viewDidUnhide];
    }
}

- (void) viewDidHide {
    // do nothing?
}

- (void) viewDidUnhide {
    // do nothing?
}

- (BOOL) canBecomeKeyView {
    return [self acceptsFirstResponder] && ![self isHiddenOrHasHiddenAncestor];
}

// Cocoa does that for views, despite the "The default implementation returns
// NO" from the documentation
- (BOOL) needsPanelToBecomeKey {
    return [self acceptsFirstResponder];
}

- (NSView *) nextKeyView {
    return _nextKeyView;
}

- (NSView *) nextValidKeyView {
    NSView *result = [self nextKeyView];

    while (result != nil && ![result canBecomeKeyView]) {
        // prevent an infinite loop
        if (result == self)
            return nil;

        result = [result nextKeyView];
    }

    return result;
}

- (NSView *) previousKeyView {
    return _previousKeyView;
}

- (NSView *) previousValidKeyView {
    NSView *result = [self previousKeyView];

    while (result != nil && ![result canBecomeKeyView]) {
        // prevent an infinite loop
        if (result == self)
            return nil;
        result = [result previousKeyView];
    }

    return result;
}

- (NSMenu *) menu {
    return _menu;
}

- (NSMenu *) menuForEvent: (NSEvent *) event {
    NSMenu *result = [self menu];

    if (result == nil) {
        result = [[self class] defaultMenu];

        if (result) {
            NSArray *itemArray = [result itemArray];
            int i, count = [itemArray count];
            for (i = 0; i < count; i++) {
                NSMenuItem *item = [itemArray objectAtIndex: i];
                [item setTarget: self];
            }
        }
    }

    return result;
}

- (NSMenuItem *) enclosingMenuItem {
    NSUnimplementedMethod();
    return nil;
}

- (NSString *) toolTip {
    NSUInteger i, count = [_trackingAreas count];
    NSString *toolTip = nil;

    // In case there's more than one ToolTip the behavior
    // is undocumented. Return the first one.
    for (i = 0; i < count; i++) {
        NSTrackingArea *area = [_trackingAreas objectAtIndex: i];

        if ([area _isToolTip] == YES) {
            toolTip = [area owner];
            break;
        }
    }

    return toolTip;
}

- viewWithTag: (NSInteger) tag {
    int i, count = [_subviews count];

    if (_tag == tag)
        return self;

    for (i = 0; i < count; i++) {
        NSView *view = [[_subviews objectAtIndex: i] viewWithTag: tag];

        if (view != nil)
            return view;
    }

    return nil;
}

- (NSView *) hitTest: (NSPoint) point {
    if (_isHidden) {
        return nil;
    }

    point = [self convertPoint: point fromView: [self superview]];

    if (NSMouseInRect(point, [self visibleRect], [self isFlipped]) == NO) {
        return nil;
    } else {
        // Subviews are ordered back to front so we need to go
        // front to back in order to hit test correctly.
        NSArray *subviews = [self subviews];
        int count = [subviews count];

        while (--count >= 0) {
            NSView *check = [subviews objectAtIndex: count];
            NSView *hit = [check hitTest: point];

            if (hit != nil) {
                return hit;
            }
        }
    }
    return self;
}

- (NSPoint) convertPoint: (NSPoint) point fromView: (NSView *) viewOrNil {
    NSView *fromView =
            (viewOrNil != nil) ? viewOrNil : [[self window] _backgroundView];
    CGAffineTransform toWindow = [fromView transformToWindow];
    CGAffineTransform fromWindow = [self transformFromWindow];

    return CGPointApplyAffineTransform(
            CGPointApplyAffineTransform(point, toWindow), fromWindow);
}

- (NSPoint) convertPoint: (NSPoint) point toView: (NSView *) viewOrNil {
    NSView *toView =
            (viewOrNil != nil) ? viewOrNil : [[self window] _backgroundView];
    CGAffineTransform toWindow = [self transformToWindow];
    CGAffineTransform fromWindow = [toView transformFromWindow];

    return CGPointApplyAffineTransform(
            CGPointApplyAffineTransform(point, toWindow), fromWindow);
}

- (NSSize) convertSize: (NSSize) size fromView: (NSView *) viewOrNil {
    NSView *fromView =
            (viewOrNil != nil) ? viewOrNil : [[self window] _backgroundView];
    CGAffineTransform toWindow = [fromView transformToWindow];
    CGAffineTransform fromWindow = [self transformFromWindow];

    return CGSizeApplyAffineTransform(
            CGSizeApplyAffineTransform(size, toWindow), fromWindow);
}

- (NSSize) convertSize: (NSSize) size toView: (NSView *) viewOrNil {
    NSView *toView =
            (viewOrNil != nil) ? viewOrNil : [[self window] _backgroundView];
    CGAffineTransform toWindow = [self transformToWindow];
    CGAffineTransform fromWindow = [toView transformFromWindow];

    return CGSizeApplyAffineTransform(
            CGSizeApplyAffineTransform(size, toWindow), fromWindow);
}

- (NSRect) convertRect: (NSRect) rect fromView: (NSView *) viewOrNil {
    NSView *fromView =
            (viewOrNil != nil) ? viewOrNil : [[self window] _backgroundView];
    CGAffineTransform toWindow = [fromView transformToWindow];
    CGAffineTransform fromWindow = [self transformFromWindow];
    NSPoint point1 = rect.origin;
    NSPoint point2 = NSMakePoint(NSMaxX(rect), NSMaxY(rect));

    point1 = CGPointApplyAffineTransform(
            CGPointApplyAffineTransform(point1, toWindow), fromWindow);
    point2 = CGPointApplyAffineTransform(
            CGPointApplyAffineTransform(point2, toWindow), fromWindow);
    if (point2.y < point1.y) {
        CGFloat temp = point2.y;
        point2.y = point1.y;
        point1.y = temp;
    }

    return NSMakeRect(point1.x, point1.y, point2.x - point1.x,
                      point2.y - point1.y);
}

- (NSRect) convertRect: (NSRect) rect toView: (NSView *) viewOrNil {
    NSView *toView =
            (viewOrNil != nil) ? viewOrNil : [[self window] _backgroundView];
    CGAffineTransform toWindow = [self transformToWindow];
    CGAffineTransform fromWindow = [toView transformFromWindow];
    NSPoint point1 = rect.origin;
    NSPoint point2 = NSMakePoint(NSMaxX(rect), NSMaxY(rect));

    point1 = CGPointApplyAffineTransform(
            CGPointApplyAffineTransform(point1, toWindow), fromWindow);
    point2 = CGPointApplyAffineTransform(
            CGPointApplyAffineTransform(point2, toWindow), fromWindow);
    if (point2.y < point1.y) {
        CGFloat temp = point2.y;
        point2.y = point1.y;
        point1.y = temp;
    }

    return NSMakeRect(point1.x, point1.y, point2.x - point1.x,
                      point2.y - point1.y);
}

- (NSRect) centerScanRect: (NSRect) rect {
    CGFloat minx = floor(NSMinX(rect) + 0.5);
    CGFloat miny = floor(NSMinY(rect) + 0.5);
    CGFloat maxx = floor(NSMaxX(rect) + 0.5);
    CGFloat maxy = floor(NSMaxY(rect) + 0.5);

    return NSMakeRect(minx, miny, maxx - minx, maxy - miny);
}

// inwardBit is the axis option's NSAlign...Inward bit; Outward and Nearest are 8 and 16 bits higher.
static CGFloat alignValue(CGFloat value, NSAlignmentOptions options,
                          NSAlignmentOptions inwardBit, BOOL isMinEdge)
{
    if (options & (inwardBit << 16))
        return round(value);
    if (options & inwardBit)
        return isMinEdge ? ceil(value) : floor(value);
    if (options & (inwardBit << 8))
        return isMinEdge ? floor(value) : ceil(value);
    return value;
}

static void alignAxis(CGFloat *origin, CGFloat *length, NSAlignmentOptions options,
                      NSAlignmentOptions minBit, NSAlignmentOptions maxBit,
                      NSAlignmentOptions sizeBit)
{
    const NSAlignmentOptions anyForm = 1 | (1 << 8) | (1 << 16);
    CGFloat min = alignValue(*origin, options, minBit, YES);
    CGFloat max = alignValue(*origin + *length, options, maxBit, NO);
    if (options & (sizeBit * anyForm)) {
        CGFloat size = alignValue(*length, options, sizeBit, NO);
        if ((options & (maxBit * anyForm)) && !(options & (minBit * anyForm)))
            min = max - size;
        else
            max = min + size;
    }
    *origin = min;
    *length = max - min;
}

// Cocotron's backing store has one pixel per point in window coordinates. Without a window
// there is no backing store, so align in view coordinates.
- (NSRect) backingAlignedRect: (NSRect) rect options: (NSAlignmentOptions) options {
    BOOL inWindow = ([self window] != nil);
    NSRect base = inWindow ? [self convertRect: rect toView: nil] : rect;
    // A flipped view's min-Y edge is the max-Y edge in window coordinates.
    BOOL swapY = inWindow && [self isFlipped];
    alignAxis(&base.origin.x, &base.size.width, options, NSAlignMinXInward,
              NSAlignMaxXInward, NSAlignWidthInward);
    alignAxis(&base.origin.y, &base.size.height, options,
              swapY ? NSAlignMaxYInward : NSAlignMinYInward,
              swapY ? NSAlignMinYInward : NSAlignMaxYInward, NSAlignHeightInward);
    return inWindow ? [self convertRect: base fromView: nil] : base;
}

- (NSString *) accessibilityTitle {
    return _accessibilityTitle;
}

- (void) setAccessibilityTitle: (NSString *) title {
    title = [title copy];
    [_accessibilityTitle release];
    _accessibilityTitle = title;
}

// Stores a new frame and lays out the subviews, without posting
// NSViewFrameDidChangeNotification. Returns whether the frame changed.
static BOOL applyFrame(NSView *self, NSRect frame) {
    if (NSEqualRects(self->_frame, frame))
        return NO;

    NSSize oldSize = self->_bounds.size;

    if (self->_bounds.size.width == 0 || self->_bounds.size.height == 0) {
        // No valid current bounds value - just update it to use the frame size
        self->_bounds.size = frame.size;
    } else {
        // Get the bounds->frame transform
        CGAffineTransform transform = concatViewTransform(
                CGAffineTransformIdentity, self, nil, YES, NO);
        // ... and invert it so we can get the new bounds size from the new
        // frame size
        transform = CGAffineTransformInvert(transform);

        self->_bounds.size =
                CGSizeApplyAffineTransform(frame.size, transform);
    }
    self->_frame = frame;

    // Subviews resized below may convert their frames to window coordinates,
    // so they must see this view's new transform, and its layer the new
    // geometry.
    invalidateTransform(self);
    configureLayerGeometry(self);

    [self->_window invalidateCursorRectsForView: self]; // this also
                                                        // invalidates
                                                        // tracking areas

    if (self->_autoresizesSubviews) {
        [self resizeSubviewsWithOldSize: oldSize];
    }

    NSRect layerFrame = self->_frame;

    if (self->_superview != nil)
        layerFrame = [self->_superview convertRect: layerFrame toView: nil];

    [self->_layerContext setFrame: layerFrame];

    invalidateTransform(self);
    return YES;
}

static void postFrameChange(NSView *self) {
    if (self->_postsNotificationOnFrameChange && self->_frameChangeDepth == 0)
        [[NSNotificationCenter defaultCenter]
                postNotificationName: NSViewFrameDidChangeNotification
                              object: self];
}

- (void) setFrame: (NSRect) frame {
    // QUIRK: -setFrame: sends -setFrameOrigin: and then -setFrameSize: with
    // the new values, also when the frame does not change, so a subclass
    // overriding either sees every frame change. One
    // NSViewFrameDidChangeNotification is posted, and only when the frame
    // changed. Not documented. Evidence: black-box observation on macOS
    // 27.0.1 arm64 (tier 2) of an NSView subclass overriding both setters,
    // with the origin, the size, both or neither changed.
    // Test: appkit_view_window_macos_defaults.m (setFrame: QUIRK).
    NSRect oldFrame = _frame;

    _frameChangeDepth++;
    [self setFrameOrigin: frame.origin];
    [self setFrameSize: frame.size];
    _frameChangeDepth--;

    if (!NSEqualRects(oldFrame, _frame))
        postFrameChange(self);
}

- (void) setFrameSize: (NSSize) size {
    NSRect frame = _frame;

    frame.size = size;
    if (applyFrame(self, frame))
        postFrameChange(self);
}

- (void) setFrameOrigin: (NSPoint) origin {
    NSRect frame = _frame;

    frame.origin = origin;
    if (applyFrame(self, frame))
        postFrameChange(self);
}

- (void) setFrameRotation: (CGFloat) angle {
    NSUnimplementedMethod();
}

- (void) setFrameCenterRotation: (CGFloat) angle {
    NSUnimplementedMethod();
}

- (void) setBounds: (NSRect) bounds {
    if (!NSEqualRects(bounds, _bounds)) {
        _bounds = bounds;
        invalidateTransform(self);
        configureLayerGeometry(self);

        [_window invalidateCursorRectsForView: self]; // this also invalidates
                                                      // tracking areas

        if (_postsNotificationOnBoundsChange)
            [[NSNotificationCenter defaultCenter]
                    postNotificationName: NSViewBoundsDidChangeNotification
                                  object: self];
    }
}

- (void) setBoundsSize: (NSSize) size {
    NSRect bounds = [self bounds];

    bounds.size = size;

    [self setBounds: bounds];
}

- (void) setBoundsOrigin: (NSPoint) origin {
    NSRect bounds = [self bounds];

    bounds.origin = origin;

    [self setBounds: bounds];
}

- (void) setBoundsRotation: (CGFloat) angle {
    NSUnimplementedMethod();
}

- (void) setPostsFrameChangedNotifications: (BOOL) flag {
    _postsNotificationOnFrameChange = flag;
}

- (void) setPostsBoundsChangedNotifications: (BOOL) flag {
    _postsNotificationOnBoundsChange = flag;
}

- (void) _setWindow: (NSWindow *) window {
    if (_window != window) {
        BOOL windowRecalulatesKeyViewLoop =
                [window autorecalculatesKeyViewLoop];
        if (windowRecalulatesKeyViewLoop)
            [self setNextKeyView: nil];

        [self viewWillMoveToWindow: window];

        _window = window;

        if (_layerContext && _window == nil) {
            [self _removeLayerFromSuperlayer];
        } else if (_layerContext) {
            [_layerContext setSubwindow: [_window _createSubWindowWithFrame: [self frame]]];
            [self _updateLayerVisibility];
        } else if (_layer != nil && _window != nil) {
            [self _addLayerToSuperlayer];
        }

        [_subviews makeObjectsPerformSelector: _cmd withObject: window];
        _validTrackingAreas = NO;
        [_window invalidateCursorRectsForView: self]; // this also invalidates
                                                      // tracking areas

        if (windowRecalulatesKeyViewLoop)
            [_window recalculateKeyViewLoop];

        [self viewDidMoveToWindow];
    }
}

- (void) _setSuperview: superview {
    if (_superview == superview)
        return;
    if (_layer != nil)
        [self _removeLayerFromSuperlayer];
    _superview = superview;
    [self _updateLayerVisibility];
    if (_layer != nil && _superview != nil)
        [self _addLayerToSuperlayer];

    [_window invalidateCursorRectsForView: self]; // this also invalidates
                                                  // tracking areas

    [self setNextResponder: superview];
}

- (void) _insertSubview: (NSView *) view atIndex: (NSInteger) index {

    [view retain];
    if ([view superview] == self)
        [_subviews removeObjectIdenticalTo: view];
    else {
        [view removeFromSuperview];

        [view _setWindow: _window];

        [view viewWillMoveToSuperview: self];
        [view _setSuperview: self];
    }

    if (index == NSNotFound)
        [_subviews addObject: view];
    else
        [_subviews insertObject: view atIndex: index];
    [view release];

    invalidateTransform(view);

    [self setNeedsDisplayInRect: [view frame]];

    [view viewDidMoveToSuperview];

    if (_wantsLayer)
        [view setWantsLayer: YES];
}

- (void) addSubview: (NSView *) view {
    if (view == nil) // yes, this is silently ignored
        return;

    [self _insertSubview: view atIndex: NSNotFound];
}

- (void) addSubview: (NSView *) view
         positioned: (NSWindowOrderingMode) ordering
         relativeTo: (NSView *) relativeTo
{
    NSUInteger index = [_subviews indexOfObjectIdenticalTo: relativeTo];

    if (index == NSNotFound)
        index = (ordering == NSWindowBelow) ? 0 : NSNotFound;
    else
        index = (ordering == NSWindowBelow)
                        ? index
                        : ((index + 1 == [_subviews count]) ? NSNotFound
                                                            : index + 1);

    [self _insertSubview: view atIndex: index];
}

- (void) replaceSubview: (NSView *) oldView with: (NSView *) newView {
    NSUInteger index = [_subviews indexOfObjectIdenticalTo: oldView];

    [oldView retain];
    [oldView removeFromSuperview];
    [self _insertSubview: newView atIndex: index];
    [oldView release];
}

- (void) setSubviews: (NSArray *) array {
    // This method marks as needing display per doc.s

    while ([_subviews count])
        [[_subviews lastObject] removeFromSuperview];

    for (NSView *view in array) {
        [self addSubview: view];
        [view setNeedsDisplay: YES];
    }
}

- (void) sortSubviewsUsingFunction:
                 (NSComparisonResult (*)(id, id, void *)) compareFunction
                           context: (void *) context
{
    if (compareFunction == NULL || [_subviews count] < 2)
        return;

    [_subviews sortUsingFunction: compareFunction context: context];
    [self setNeedsDisplay: YES];
}

- (void) didAddSubview: (NSView *) subview {
    NSUnimplementedMethod();
}

- (void) willRemoveSubview: (NSView *) subview {
    NSUnimplementedMethod();
}

- (void) setAutoresizesSubviews: (BOOL) flag {
    _autoresizesSubviews = flag;
}

- (void) setAutoresizingMask: (NSAutoresizingMaskOptions) mask {
    _autoresizingMask = mask;
}

- (void) setFocusRingType: (NSFocusRingType) value {
    _focusRingType = value;
    [self setNeedsDisplay: YES];
}

- (void) setTag: (NSInteger) tag {
    _tag = tag;
}

- (void) _setPreviousKeyView: (NSView *) previous {
    _previousKeyView = previous;
}

- (void) setNextKeyView: (NSView *) next {
    if (next)
        [next _setPreviousKeyView: self];
    else
        [_nextKeyView _setPreviousKeyView: nil];

    _nextKeyView = next;
}

- (BOOL) acceptsFirstMouse: (NSEvent *) event {
    NSUnimplementedMethod();
    return NO;
}

- (BOOL) acceptsTouchEvents {
    NSUnimplementedMethod();
    return NO;
}

- (void) setAcceptsTouchEvents: (BOOL) accepts {
    NSUnimplementedMethod();
}

- (BOOL) wantsRestingTouches {
    NSUnimplementedMethod();
    return NO;
}

- (void) setWantsRestingTouches: (BOOL) wants {
    NSUnimplementedMethod();
}

- (void) setToolTip: (NSString *) string {
    [self removeAllToolTips];
    if (string != nil && ![string isEqualToString: @""])
        [self addToolTipRect: [self bounds] owner: string userData: NULL];
}

- (NSToolTipTag) addToolTipRect: (NSRect) rect
                          owner: object
                       userData: (void *) userData
{
    NSTrackingArea *area = nil;

    area = [[NSTrackingArea alloc] _initWithRect: rect
                                         options: 0
                                           owner: object
                                        userData: userData
                                  retainUserData: NO
                                       isToolTip: YES
                                        isLegacy: NO];
    [_trackingAreas addObject: area];
    [area release];

    [self _trackingAreasChanged];

    return area;
}

- (void) removeToolTip: (NSToolTipTag) tag {
    [self removeTrackingArea: tag];
}

- (void) removeAllToolTips {
    NSInteger count = [_trackingAreas count];

    while (--count >= 0) {
        if ([[_trackingAreas objectAtIndex: count] _isToolTip] == YES)
            [_trackingAreas removeObjectAtIndex: count];
    }

    [self _trackingAreasChanged];
}

- (void) addCursorRect: (NSRect) rect cursor: (NSCursor *) cursor {
    NSCursorRect *cursorRect = [[NSCursorRect alloc] initWithCursor: cursor];
    NSTrackingArea *area = nil;

    area = [[NSTrackingArea alloc]
             _initWithRect: rect
                   options: NSTrackingCursorUpdate | NSTrackingActiveInKeyWindow
                     owner: cursorRect
                  userData: NULL
            retainUserData: NO
                 isToolTip: NO
                  isLegacy: YES];
    [_trackingAreas addObject: area];
    [area release];
    [cursorRect release];

    [self _trackingAreasChanged];
}

- (void) removeCursorRect: (NSRect) rect cursor: (NSCursor *) cursor {
    NSInteger count = [_trackingAreas count];

    while (--count >= 0) {
        NSTrackingArea *area = [_trackingAreas objectAtIndex: count];
        NSObject *candidate = [area owner];

        if ([area _isLegacy] == YES &&
            [candidate isKindOfClass: [NSCursorRect class]] == YES &&
            [(NSCursorRect *) candidate cursor] == cursor) {
            [_trackingAreas removeObjectAtIndex: count];
            break;
        }
    }

    [self _trackingAreasChanged];
}

- (void) discardCursorRects {
    NSInteger count = [_trackingAreas count];

    while (--count >= 0) {
        NSTrackingArea *area = [_trackingAreas objectAtIndex: count];

        if ([area _isLegacy] == YES &&
            ([area options] & NSTrackingCursorUpdate)) {
            [_trackingAreas removeObjectAtIndex: count];
        }
    }

    [[self subviews] makeObjectsPerformSelector: _cmd];

    [self _trackingAreasChanged];
}

- (void) resetCursorRects {
    // do nothing
}

- (void) _collectTrackingAreasForWindowInto: (NSMutableArray *) collector {
    if (_isHidden == NO) {
        NSUInteger i, count;

        if (!_validTrackingAreas) {
            /* We don't clear the tracking areas, they are managed by the view
             * with add/remove
             */
            [self updateTrackingAreas];
            _validTrackingAreas = YES;
        }

        count = [_trackingAreas count];
        for (i = 0; i < count; i++) {
            NSTrackingArea *area = [_trackingAreas objectAtIndex: i];
            NSRect rectOfInterest;

            rectOfInterest = NSIntersectionRect([area rect], [self bounds]);

            if (rectOfInterest.size.width > 0. &&
                rectOfInterest.size.height > 0.) {
                [area _setView: self];

                [area _setRectInWindow: [self convertRect: rectOfInterest
                                                   toView: nil]];

                [collector addObject: [_trackingAreas objectAtIndex: i]];
            }
        }

        NSArray *subviews = [self subviews];
        // Collect subviews' areas _after_ collecting our own.
        count = [subviews count];
        for (i = 0; i < count; i++)
            [(NSView *) [subviews objectAtIndex: i]
                    _collectTrackingAreasForWindowInto: collector];
    }
}

- (NSArray *) trackingAreas {
    return _trackingAreas;
}

- (void) _trackingAreasChanged {
    [[self window] _invalidateTrackingAreas];
}

- (void) addTrackingArea: (NSTrackingArea *) trackingArea {
    [_trackingAreas addObject: trackingArea];
    [self _trackingAreasChanged];
}

- (void) removeTrackingArea: (NSTrackingArea *) trackingArea {
    [_trackingAreas removeObjectIdenticalTo: trackingArea];
    [self _trackingAreasChanged];
}

- (void) updateTrackingAreas {
    [self _trackingAreasChanged];
}

- (NSTrackingRectTag) addTrackingRect: (NSRect) rect
                                owner: owner
                             userData: (void *) userData
                         assumeInside: (BOOL) assumeInside
{
    NSTrackingAreaOptions options =
            NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways;
    NSTrackingArea *area = nil;

    if (assumeInside == YES)
        options |= NSTrackingAssumeInside;

    area = [[NSTrackingArea alloc] _initWithRect: rect
                                         options: options
                                           owner: owner
                                        userData: NULL
                                  retainUserData: NO
                                       isToolTip: NO
                                        isLegacy: NO];
    [_trackingAreas addObject: area];
    [area release];

    [self _trackingAreasChanged];

    return area;
}

- (void) removeTrackingRect: (NSTrackingRectTag) tag {
    [self removeTrackingArea: tag];
}

static char inputContextKey;

// Created on first use for a view that is a text input client.
- (NSTextInputContext *) inputContext {
    if (![self conformsToProtocol: @protocol(NSTextInputClient)])
        return nil;

    NSTextInputContext *context =
            objc_getAssociatedObject(self, &inputContextKey);
    if (context == nil) {
        context = [[NSTextInputContext alloc]
                initWithClient: (id<NSTextInputClient>) self];
        objc_setAssociatedObject(self, &inputContextKey, context,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [context release];
    }
    return context;
}

- (void) registerForDraggedTypes: (NSArray *) types {
    types = [types copy];
    [_draggedTypes release];
    _draggedTypes = types;
}

- (void) unregisterDraggedTypes {
    [_draggedTypes release];
    _draggedTypes = nil;
}

- (NSArray *) registeredDraggedTypes {
    return _draggedTypes;
}

- (void) _deepResignFirstResponder {
    if ([_window firstResponder] == self)
        [_window makeFirstResponder: nil];

    [[self subviews] makeObjectsPerformSelector: _cmd];
}

- (void) removeFromSuperview {
    [[self retain] autorelease];
    [_superview setNeedsDisplayInRect: [self frame]];
    [self removeFromSuperviewWithoutNeedingDisplay];
}

- (void) _removeViewWithoutDisplay: (NSView *) view {
    [_subviews removeObjectIdenticalTo: view];
}

- (void) removeFromSuperviewWithoutNeedingDisplay {
    [[self retain] autorelease];
    NSView *removeFrom = [_superview retain];
    NSWindow *window = [[self window] retain];

    for (NSView *ancestor = _superview; ancestor != nil; ancestor = [ancestor superview]) {
        for (NSLayoutConstraint *constraint in [ancestor constraints]) {
            NSView *first = [constraint firstItem], *second = [constraint secondItem];
            if (([first isKindOfClass:[NSView class]] && [first isDescendantOf:self]) ||
                ([second isKindOfClass:[NSView class]] && [second isDescendantOf:self]))
                [constraint setActive:NO];
        }
    }

    [self _deepResignFirstResponder];
    [self _setSuperview: nil];
    [self _setWindow: nil];

    [removeFrom _removeViewWithoutDisplay: self];
    [window _invalidateTrackingAreas];
    [window release];
    [removeFrom release];
}

- (void) viewWillMoveToSuperview: (NSView *) view {
    // Intentionally empty.
}

- (void) viewDidMoveToSuperview {
    // Intentionally empty.
}

- (void) viewDidChangeBackingProperties {
}

- (void) viewDidChangeEffectiveAppearance {
}

- (void) viewWillMoveToWindow: (NSWindow *) window {
    // Intentionally empty.
}

- (void) viewDidMoveToWindow {
    // Default implementation does nothing
}

- (BOOL) shouldDelayWindowOrderingForEvent: (NSEvent *) event {
    NSUnimplementedMethod();
    return NO;
}

- (void) resizeSubviewsWithOldSize: (NSSize) oldSize {
    int i, count = [_subviews count];

    for (i = 0; i < count; i++)
        [[_subviews objectAtIndex: i] resizeWithOldSuperviewSize: oldSize];
}

- (void) resizeWithOldSuperviewSize: (NSSize) oldSize {
    NSRect superFrame = [_superview frame];
    NSRect frame = [self frame];
    BOOL originChanged = NO, sizeChanged = NO;

    if (_autoresizingMask & NSViewMinXMargin) {
        if (_autoresizingMask & NSViewWidthSizable) {
            if (_autoresizingMask & NSViewMaxXMargin) {
                frame.origin.x += ((superFrame.size.width - oldSize.width) / 3);
                frame.size.width +=
                        ((superFrame.size.width - oldSize.width) / 3);
            } else {
                frame.origin.x += ((superFrame.size.width - oldSize.width) / 2);
                frame.size.width +=
                        ((superFrame.size.width - oldSize.width) / 2);
            }
            originChanged = YES;
            sizeChanged = YES;
        } else if (_autoresizingMask & NSViewMaxXMargin) {
            frame.origin.x += ((superFrame.size.width - oldSize.width) / 2);
            originChanged = YES;
        } else {
            frame.origin.x += superFrame.size.width - oldSize.width;
            originChanged = YES;
        }
    } else if (_autoresizingMask & NSViewWidthSizable) {
        if (_autoresizingMask & NSViewMaxXMargin)
            frame.size.width += ((superFrame.size.width - oldSize.width) / 2);
        else
            frame.size.width += superFrame.size.width - oldSize.width;
        sizeChanged = YES;
    } else if (_autoresizingMask & NSViewMaxXMargin) {
        // don't move or resize
    }

    if (_autoresizingMask & NSViewMinYMargin) {
        if (_autoresizingMask & NSViewHeightSizable) {
            if (_autoresizingMask & NSViewMaxYMargin) {
                frame.origin.y +=
                        ((superFrame.size.height - oldSize.height) / 3);
                frame.size.height +=
                        ((superFrame.size.height - oldSize.height) / 3);
            } else {
                frame.origin.y +=
                        ((superFrame.size.height - oldSize.height) / 2);
                frame.size.height +=
                        ((superFrame.size.height - oldSize.height) / 2);
            }
            originChanged = YES;
            sizeChanged = YES;
        } else if (_autoresizingMask & NSViewMaxYMargin) {
            frame.origin.y += ((superFrame.size.height - oldSize.height) / 2);
            originChanged = YES;
        } else {
            frame.origin.y += superFrame.size.height - oldSize.height;
            originChanged = YES;
        }
    } else if (_autoresizingMask & NSViewHeightSizable) {
        if (_autoresizingMask & NSViewMaxYMargin)
            frame.size.height +=
                    ((superFrame.size.height - oldSize.height) / 2);
        else
            frame.size.height += superFrame.size.height - oldSize.height;
        sizeChanged = YES;
    }

    if (originChanged || sizeChanged)
        [self setFrame: frame];
}

- (BOOL) inLiveResize {
    return _inLiveResize;
}

- (BOOL) preservesContentDuringLiveResize {
    NSUnimplementedMethod();
    return NO;
}

- (NSRect) rectPreservedDuringLiveResize {
    NSUnimplementedMethod();
    return NSZeroRect;
}

- (void) viewWillStartLiveResize {
    _inLiveResize = YES;
    [_subviews makeObjectsPerformSelector: _cmd];
}

- (void) viewDidEndLiveResize {
    _inLiveResize = NO;
    [_subviews makeObjectsPerformSelector: _cmd];
}

- (BOOL) enterFullScreenMode: (NSScreen *) screen
                 withOptions: (NSDictionary *) options
{
    NSUnimplementedMethod();
    return NO;
}

- (BOOL) isInFullScreenMode {
    // dont issue warning
    return NO;
}

- (void) exitFullScreenModeWithOptions: (NSDictionary *) options {
    NSUnimplementedMethod();
}

- (NSClipView *) _enclosingClipView {
    id result = [self superview];

    for (; result != nil; result = [result superview])
        if ([result isKindOfClass: [NSClipView class]])
            return result;

    return nil;
}

- (void) scrollPoint: (NSPoint) point {
    NSClipView *clipView = [self _enclosingClipView];

    if (clipView != nil) {
        NSPoint origin = [self convertPoint: point toView: clipView];

        [clipView scrollToPoint: origin];
    }
}

- (BOOL) scrollRectToVisible: (NSRect) rect {
    NSClipView *clipView = [self _enclosingClipView];
    NSView *documentView = [clipView documentView];
    // Current the document view visible rect in document view space
    NSRect vRect = [clipView documentVisibleRect];
    // Convert what we want in the document view space
    rect = [documentView convertRect: rect fromView: self];

    // Do the minimal amount of scrolling to show the rect

    // Missing amount on the four directions
    CGFloat missingLeft = NSMinX(vRect) - NSMinX(rect);
    CGFloat missingRight = NSMaxX(rect) - NSMaxX(vRect);

    CGFloat missingTop = NSMinY(vRect) - NSMinY(rect);
    CGFloat missingBottom = NSMaxY(rect) - NSMaxY(vRect);

    CGFloat dx = 0.;
    CGFloat dy = 0.;

    if (missingLeft * missingRight < 0) {
        // We need to scroll in one direction - no need to scroll if we're
        // missing bits both ways or if everything is visible

        // Let's do the minimal amount of scrolling
        if (fabs(missingLeft) < fabs(missingRight)) {
            dx = -missingLeft;
        } else {
            dx = missingRight;
        }
    }

    if (missingTop * missingBottom < 0) {
        // We need to scroll in one direction - no need to scroll if we're
        // missing bits both ways or if everything is visible

        // Let's do the minimal amount of scrolling
        if (fabs(missingTop) < fabs(missingBottom)) {
            dy = -missingTop;
        } else {
            dy = missingBottom;
        }
    }
    if (dx != 0 || dy != 0) {
        NSPoint pt = vRect.origin;
        pt.x += dx;
        pt.y += dy;
        pt = [documentView convertPoint: pt toView: clipView];
        [clipView scrollToPoint: pt];
        return YES;
    }
    return NO;
}

- (void) scrollClipView: (NSClipView *) clipView toPoint: (NSPoint) newOrigin {
    NSUnimplementedMethod();
}

- (BOOL) mouse: (NSPoint) point inRect: (NSRect) rect {
    return NSMouseInRect(point, rect, [self isFlipped]);
}

- (void) reflectScrolledClipView: (NSClipView *) view {
    NSUnimplementedMethod();
}

- (void) allocateGState {
    // unimplemented
}

- (void) releaseGState {
    // unimplemented
}

- (void) setUpGState {
    // do nothing
}

- (void) renewGState {
    // do nothing
}

- (BOOL) wantsLayer {
    return _wantsLayer;
}

- (CALayer *) layer {
    return _layer;
}

- (BOOL) wantsUpdateLayer {
    return NO;
}

- (void) updateLayer {
}

- (void) prepareForReuse {
    [self setAlphaValue: 1.0];
    [self setHidden: NO];
}

- (NSEdgeInsets) alignmentRectInsets {
    return NSEdgeInsetsMake(0, 0, 0, 0);
}

// The insets are measured in the view's own coordinates, so which of top and
// bottom touches the frame's origin depends on whether the view is flipped.
- (NSRect) frameForAlignmentRect: (NSRect) alignmentRect {
    NSEdgeInsets insets = [self alignmentRectInsets];
    CGFloat originInset = [self isFlipped] ? insets.top : insets.bottom;
    return NSMakeRect(alignmentRect.origin.x - insets.left, alignmentRect.origin.y - originInset,
                      alignmentRect.size.width + insets.left + insets.right,
                      alignmentRect.size.height + insets.top + insets.bottom);
}

- (NSRect) alignmentRectForFrame: (NSRect) frame {
    NSEdgeInsets insets = [self alignmentRectInsets];
    CGFloat originInset = [self isFlipped] ? insets.top : insets.bottom;
    return NSMakeRect(frame.origin.x + insets.left, frame.origin.y + originInset,
                      frame.size.width - insets.left - insets.right,
                      frame.size.height - insets.top - insets.bottom);
}

- (BOOL) canDrawSubviewsIntoLayer {
    return _canDrawSubviewsIntoLayer;
}

- (void) setCanDrawSubviewsIntoLayer: (BOOL) value {
    _canDrawSubviewsIntoLayer = value;
}

- (NSTouchTypeMask) allowedTouchTypes {
    return _allowedTouchTypes;
}

- (void) setAllowedTouchTypes: (NSTouchTypeMask) value {
    _allowedTouchTypes = value;
}

- (CALayer *) makeBackingLayer {
    return [NSViewBackingLayer layer];
}

- (void) _removeLayerFromSuperlayer {
    [_layer removeFromSuperlayer];
    [_layerContext invalidate];
    [_layerContext release];
    _layerContext = nil;
}

// Native root-layer windows must follow the view tree as well as CALayer.
- (void) _updateLayerVisibility {
    BOOL hidden = [self isHiddenOrHasHiddenAncestor];
    [_layer setHidden: hidden];
    [_layerContext setHidden: hidden];
    for (NSView *child in _subviews)
        [child _updateLayerVisibility];
}

- (void) _createLayerContextIfNeeded {
    if (_layerContext == nil && [_superview layer] == nil && _window != nil) {
        _layerContext = [[CALayerContext alloc] initWithFrame: [self frame]];
        [_layerContext setLayer: _layer];
        if (_window) {
            [_layerContext setSubwindow: [_window _createSubWindowWithFrame: [self frame]]];
            [self _updateLayerVisibility];
        }
    }
}

- (void) _addLayerToSuperlayer {
    if (_layer == nil) {
        return;
    }
    CALayer *superlayer = [_superview layer];
    if (superlayer != nil) {
        if ([_layer superlayer] != superlayer || _layerContext != nil) {
            [self _removeLayerFromSuperlayer];
            [superlayer addSublayer: _layer];
        }
    } else {
        [self _createLayerContextIfNeeded];
    }
}

/*
  When turning off layering, we only turn off layers below us which did not want
  a layer Layers which did want a layer are not touched, nor are their children.
 */
- (void) _removeLayerBackedViewsFromTree {
    if (_wantsLayer) {
        [_layer removeFromSuperlayer];
        [self _createLayerContextIfNeeded];
    } else {
        [self _removeLayerFromSuperlayer];

        // A backing layer is removed regardless of whether it was set
        // implicitly or explicitly The distinction appears to be based on the
        // layers class, not how it was set (host vs. backing)
        if ([_layer isKindOfClass: [NSViewBackingLayer class]]) {
            [_layer release];
            _layer = nil;
        }

        [_subviews makeObjectsPerformSelector: _cmd];
    }
}

- (void) _createLayersInTreeIfNeeded {
    if (!NSViewLayersEnabled)
        return;

    if (_layer == nil) {
        _layer = [[self makeBackingLayer] retain];
        [_layer setOpacity: _alphaValue];
        configureLayerGeometry(self);
    }

    [self _addLayerToSuperlayer];
    [self _updateLayerVisibility];

    [_subviews makeObjectsPerformSelector: _cmd];
}

- (void) setWantsLayer: (BOOL) value {
    if (!value) {
        if (_wantsLayer) {
            _wantsLayer = NO;
            [self _removeLayerBackedViewsFromTree];
        }
    } else {
        if (!_wantsLayer) {
            _wantsLayer = YES;
            [self _createLayersInTreeIfNeeded];
        }
    }
}

- (void) setLayer: (CALayer *) value {
    if (!NSViewLayersEnabled)
        return;

    if (value != _layer) {
        [_subviews makeObjectsPerformSelector: @selector
                   (_removeLayerFromSuperlayer)];

        value = [value retain];

        if (_layer == nil) {
            if (value != nil) {
                _layer = value;
                [self _addLayerToSuperlayer];
            }
        } else if (value == nil) {
            [self _removeLayerFromSuperlayer];
            [_layer release];
            _layer = nil;
        } else {
            [[_superview layer] replaceSublayer: _layer with: value];
            [_layer release];
            _layer = value;

            // The CALayerContext is created on the wantsLayer path
            // (-_addLayerToSuperlayer), so replacing the layer here left the new
            // layer without one. A CAMetalLayer with no context cannot vend
            // drawables: -[CAMetalLayer recreateDrawables] returns early without
            // _context, so -nextDrawable times out to nil and the layer never
            // renders anything. Re-point an existing context at the new layer, or
            // create one if this is the first.
            if (_layerContext != nil)
                [_layerContext setLayer: _layer];
            else
                [self _createLayerContextIfNeeded];
        }

        [_subviews
                makeObjectsPerformSelector: @selector(_addLayerToSuperlayer)];
        [self _updateLayerVisibility];
    }
}

- (NSViewLayerContentsPlacement) layerContentsPlacement {
    return _layerContentsPlacement;
}

- (void) setLayerContentsPlacement: (NSViewLayerContentsPlacement) value {
    _layerContentsPlacement = value;
}

- (NSViewLayerContentsRedrawPolicy) layerContentsRedrawPolicy {
    return _layerContentsRedrawPolicy;
}

- (void) setLayerContentsRedrawPolicy: (NSViewLayerContentsRedrawPolicy) value {
    _layerContentsRedrawPolicy = value;
}

- (NSArray *) backgroundFilters {
    NSUnimplementedMethod();
    return nil;
}

- (void) setBackgroundFilters: (NSArray *) filters {
    // FIXME: implement but dont warn
    //   NSUnimplementedMethod();
}

- (NSArray *) contentFilters {
    return _contentFilters;
}

- (void) setContentFilters: (NSArray *) filters {
    filters = [filters copy];
    [_contentFilters release];
    _contentFilters = filters;
}

- (CIFilter *) compositingFilter {
    return _compositingFilter;
}

- (void) setCompositingFilter: (CIFilter *) filter {
    filter = [filter copy];
    [_compositingFilter release];
    _compositingFilter = filter;
}

- (NSShadow *) shadow {
    return _shadow;
}

- (void) setShadow: (NSShadow *) shadow {
    shadow = [shadow copy];
    [_shadow release];
    _shadow = shadow;
}

- (BOOL) needsDisplay {
    return _needsDisplay;
}

/*
   If _needsDisplay is YES and there are no _invalidRects, invalid rect is
   bounds If _needsDisplay is YES and there are _invalidRects, invalid rect is
   union You can't just keep a running invalid rect because setting YES then
   changing the bounds should redraw the new bounds, but changing the bounds
   should not alter the invalidated rects.
 */

static NSRect unionOfInvalidRects(NSView *self) {
    NSRect result;

    if (self->_invalidRectCount == 0)
        result = [self visibleRect];
    else {
        int i;

        result = self->_invalidRects[0];

        for (i = 1; i < self->_invalidRectCount; i++)
            result = NSUnionRect(result, self->_invalidRects[i]);
    }

    return result;
}

static void removeRectFromInvalidInVisibleRect(NSView *self, NSRect rect,
                                               NSRect visibleRect)
{
    int count = self->_invalidRectCount;

    while (--count >= 0) {
        self->_invalidRects[count] =
                NSIntersectionRect(self->_invalidRects[count], visibleRect);

        if (NSContainsRect(rect, self->_invalidRects[count])) {
            int i;

            self->_invalidRectCount--;
            for (i = count; i < self->_invalidRectCount; i++)
                self->_invalidRects[i] = self->_invalidRects[i + 1];
        }
    }
    if (self->_invalidRectCount == 0) {
        if (self->_invalidRects != NULL) {
            NSZoneFree(NULL, self->_invalidRects);
            self->_invalidRects = NULL;
            // We killed the last invalidRect - we're clean now
            self->_needsDisplay = NO;
        } else if (NSContainsRect(rect, visibleRect)) {
            // We had no invalidRect, which means the full visibleRect was dirty
            // We're now clean
            self->_needsDisplay = NO;
        }
    }
}

static void clearRectsBeingRedrawn(NSView *self) {
    if (self->_rectsBeingRedrawn) {
        NSZoneFree(NULL, self->_rectsBeingRedrawn);
        self->_rectsBeingRedrawn = NULL;
        self->_rectsBeingRedrawnCount = 0;
    }
}

static void clearInvalidRects(NSView *self) {
    if (self->_invalidRects != NULL)
        NSZoneFree(NULL, self->_invalidRects);
    self->_invalidRects = NULL;
    self->_invalidRectCount = 0;
    clearRectsBeingRedrawn(self);
}

static void clearNeedsDisplay(NSView *self) {
    if ([NSGraphicsContext inQuartzDebugMode]) {
        return;
    }
    clearInvalidRects(self);
    self->_needsDisplay = NO;
}

- (void) setNeedsDisplay: (BOOL) flag {
    _needsDisplay = flag;

    // We removed them for YES to indicate entire view, and NO for obvious
    // reasons
    clearInvalidRects(self);

    if (_needsDisplay)
        [[self window] setViewsNeedDisplay: YES];
}

- (void) setNeedsDisplayInRect: (NSRect) rect {
    // We only add rects if its not the entire view
    if (!_needsDisplay || _invalidRects != NULL) {
        NSRect visibleRect = [self visibleRect];
        rect = NSIntersectionRect(visibleRect, rect);
        if (NSContainsRect(rect, visibleRect)) {
            clearInvalidRects(self); // Everything is dirty
        } else {
            // All of our clipping done by the context is rounded - so we need
            // to do the same here else we might get some artifact on clipping
            // borders
            rect = [self convertRect: rect toView: nil];
            rect = NSIntegralRect(rect);
            rect = [self convertRect: rect fromView: nil];
            _invalidRectCount++;
            _invalidRects = NSZoneRealloc(NULL, _invalidRects,
                                          sizeof(NSRect) * _invalidRectCount);
            _invalidRects[_invalidRectCount - 1] = rect;
        }
        clearRectsBeingRedrawn(self);

        // We also needs to be sure all of our superviews will properly redraw
        // this area, even if they are smart about what to redraw (using
        // needsDisplayInRect:)
        NSView *opaqueAncestor = [self opaqueAncestor];
        if (opaqueAncestor != self) {
            NSRect dirtyRect = [self convertRect: rect toView: opaqueAncestor];
            [opaqueAncestor setNeedsDisplayInRect: dirtyRect];
        }
    }

    _needsDisplay = YES;
    [[self window] setViewsNeedDisplay: YES];
}

- (void) setKeyboardFocusRingNeedsDisplayInRect: (NSRect) rect {
    NSUnimplementedMethod();
}

// No mask by default; subclasses that draw one also report its bounds.
- (NSRect) focusRingMaskBounds {
    return NSZeroRect;
}

- (void) drawFocusRingMask {
}

- (void) translateRectsNeedingDisplayInRect: (NSRect) rect by: (NSSize) delta {
    NSUnimplementedMethod();
}

static NSView *viewBeingPrinted = nil;

- (BOOL) canDraw {
    return (viewBeingPrinted != nil &&
            [self isDescendantOf: viewBeingPrinted]) ||
           (_window != nil && ![self isHiddenOrHasHiddenAncestor]);
}

// Cocotron always draws views serially on the main thread, so this is only a
// hint that is stored (and archived) for callers that read it back.
- (BOOL) canDrawConcurrently {
    return _canDrawConcurrently;
}

- (void) viewWillDraw {
    [_subviews makeObjectsPerformSelector: _cmd];
}

- (void) setCanDrawConcurrently: (BOOL) canDraw {
    _canDrawConcurrently = canDraw;
}

- (void) _lockFocusInContext: (NSGraphicsContext *) context {
    NSGraphicsContext *windowContext = [_window graphicsContext];

    if (context == nil) {
        if (viewBeingPrinted != nil) {
            context = [[NSPrintOperation currentOperation] context];
        } else if (_layer != nil) {
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            CGFloat width = _frame.size.width;
            CGFloat height = _frame.size.height;
            CGContextRef graphicsPort = CGBitmapContextCreate(
                    NULL, width, height, 8, 0, colorSpace,
                    kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
            context = [NSGraphicsContext
                    graphicsContextWithGraphicsPort: graphicsPort
                                            flipped: NO];
            CGColorSpaceRelease(colorSpace);
            CGContextRelease(graphicsPort); // we'll re-fetch it below
        } else {
            context = windowContext;
        }
    }
    CGContextRef graphicsPort = [context graphicsPort];

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: context];

    [[context focusStack] addObject: self];

    CGContextSaveGState(graphicsPort);
    CGContextResetClip(graphicsPort);

    if (context == windowContext) {
        CGContextSetCTM(graphicsPort, [self transformToWindow]);
        CGContextClipToRect(graphicsPort, [self visibleRect]);
    } else {
        CGAffineTransform transform = CGAffineTransformIdentity;
        if (viewBeingPrinted != nil) {
            transform = CGAffineTransformConcat(
                    [self transformToWindow],
                    [viewBeingPrinted transformFromWindow]);
        }
        NSView *targetView = viewBeingPrinted == nil ? self : viewBeingPrinted;
        transform = CGAffineTransformConcat(transform,
                                            [targetView transformToLayer]);
        CGContextSetCTM(graphicsPort, transform);
    }

    [self setUpGState];
}

- (void) lockFocus {
    [self _lockFocusInContext: nil];
}

- (BOOL) lockFocusIfCanDraw {
    if ([self canDraw]) {
        [self lockFocus];
        return YES;
    }
    return NO;
}

- (BOOL) lockFocusIfCanDrawInContext: (NSGraphicsContext *) context {
    if (context != nil) {
        [self _lockFocusInContext: context];
        return YES;
    }
    return NO;
}

- (void) unlockFocus {
    NSGraphicsContext *graphicsContext = [NSGraphicsContext currentContext];
    CGContextRef context = [graphicsContext graphicsPort];

    if (viewBeingPrinted == nil && _layer != nil) {
        CGImageRef image = CGBitmapContextCreateImage(context);
        [_layer setContents:(id)image];
        CGImageRelease(image);
    }

    CGContextRestoreGState(context);

    [[graphicsContext focusStack] removeLastObject];
    [NSGraphicsContext restoreGraphicsState];
}

- (BOOL) needsToDrawRect: (NSRect) rect {
    BOOL needsToDrawRect = NO;

    if (NSIntersectsRect(rect, _visibleRect)) {
        const NSRect *rects;
        NSInteger count;
        [self getRectsBeingDrawn: &rects count: &count];
        if (count) {
            for (int i = 0; i < count && needsToDrawRect == NO; i++) {
                needsToDrawRect = NSIntersectsRect(rect, rects[i]);
            }
        }
    }
    return needsToDrawRect;
}

- (void) getRectsBeingDrawn: (const NSRect **) rects
                      count: (NSInteger *) count
{
    // This method returns all the rects being drawn concerning the view
    // That's all of the dirty rects from the view, but also all the ones
    // from the superview that might have caused the redraw.
    // Since invalidating a rect also invalidates the first opaque superview,
    // only the opaque views need to be checked
    *rects = _rectsBeingRedrawn;
    *count = _rectsBeingRedrawnCount;

    if (_rectsBeingRedrawn == NULL) {
        NSView *opaqueAncestor = [self opaqueAncestor];
        if (opaqueAncestor != self) {
            // Ask our opaque ancestor what to draw. opaqueAncestor is nil when
            // nothing up the chain is opaque; a message to nil fills in nothing.
            const NSRect *ancestorRects = NULL;
            NSInteger ancestorRectsCount = 0;
            [opaqueAncestor getRectsBeingDrawn: &ancestorRects
                                         count: &ancestorRectsCount];
            _rectsBeingRedrawnCount = ancestorRects ? ancestorRectsCount : 0;
            if (_rectsBeingRedrawnCount) {
                _rectsBeingRedrawn = NSZoneCalloc(NULL, _rectsBeingRedrawnCount,
                                                  sizeof(NSRect));
                int rectsCount = 0;
                for (int i = 0; i < _rectsBeingRedrawnCount; ++i) {
                    NSRect r = [opaqueAncestor convertRect: ancestorRects[i]
                                                    toView: self];
                    // No need for the rects that are outside of the visibleRect
                    if (NSIntersectsRect(r, _visibleRect)) {
                        _rectsBeingRedrawn[rectsCount++] = r;
                    }
                }
                *rects = _rectsBeingRedrawn;
                *count = rectsCount;
            }
        } else {
            // We're opaque - concatenate our invalid rect with the one from the
            // previous opaque view
            NSView *view = [self superview];
            if (view) {
                NSView *opaqueAncestor = [view opaqueAncestor];
                // Stay empty when no ancestor is opaque (opaqueAncestor is nil).
                const NSRect *ancestorRects = NULL;
                NSInteger ancestorRectsCount = 0;
                [opaqueAncestor getRectsBeingDrawn: &ancestorRects
                                             count: &ancestorRectsCount];
                if (ancestorRects == NULL)
                    ancestorRectsCount = 0;
                if (ancestorRectsCount || _invalidRectCount) {
                    _rectsBeingRedrawn = NSZoneCalloc(
                            NULL, _invalidRectCount + ancestorRectsCount,
                            sizeof(NSRect));
                    NSInteger rectsCount = 0;
                    for (int i = 0; i < ancestorRectsCount; ++i) {
                        NSRect r = [opaqueAncestor convertRect: ancestorRects[i]
                                                        toView: self];
                        // No need for the rects that are outside of the
                        // visibleRect
                        if (NSIntersectsRect(r, _visibleRect)) {
                            _rectsBeingRedrawn[rectsCount++] = r;
                        }
                    }
                    for (int i = 0; i < _invalidRectCount; ++i) {
                        _rectsBeingRedrawn[rectsCount++] = _invalidRects[i];
                    }
                    _rectsBeingRedrawnCount = rectsCount;
                    *rects = _rectsBeingRedrawn;
                    *count = _rectsBeingRedrawnCount;
                }
            }
        }
    }
    // We had no info and no opaque ancestor gave us any useful rect - just use
    // our invalid rects
    if (*rects == NULL) {
        if (_invalidRects == NULL) {
            if (_needsDisplay) {
                *rects = &_visibleRect;
                *count = 1;
            }
        } else {
            *rects = _invalidRects;
            *count = _invalidRectCount;
        }
    }
}

- (void) getRectsExposedDuringLiveResize: (NSRect) rects
                                   count: (NSInteger *) count
{
    NSUnimplementedMethod();
}

- (BOOL) shouldDrawColor {
    NSUnimplementedMethod();
    return YES;
}

- (NSView *) opaqueAncestor {
    if ([self isOpaque])
        return self;

    return [[self superview] opaqueAncestor];
}

- (void) display {
    [self displayRect: [self visibleRect]];
}

- (NSEnumerator *) _subviewsInDisplayOrderEnumerator {
    // Snapshot subviews so mutating _subviews during display passes is safe
    return [[[_subviews copy] autorelease] objectEnumerator];
}

- (void) _displayIfNeededWithoutViewWillDraw {
    if ([self needsDisplay]) {
        [self displayRect: unionOfInvalidRects(self)];
        clearNeedsDisplay(self);
    }

    NSEnumerator *viewEnumerator = [self _subviewsInDisplayOrderEnumerator];

    NSView *subView = nil;
    while ((subView = [viewEnumerator nextObject])) {
        [subView _displayIfNeededWithoutViewWillDraw];
    }
}

- (void) displayIfNeeded {
    [self viewWillDraw];
    [self _displayIfNeededWithoutViewWillDraw];
}

- (void) displayIfNeededInRect: (NSRect) rect {

    rect = NSIntersectionRect(unionOfInvalidRects(self), rect);

    if ([self needsDisplay])
        [self displayRect: rect];

    NSEnumerator *viewEnumerator = [self _subviewsInDisplayOrderEnumerator];

    NSView *child = nil;
    while ((child = [viewEnumerator nextObject])) {
        NSRect converted = NSIntersectionRect(
                [self convertRect: rect toView: child], [child bounds]);
        if (!NSIsEmptyRect(converted)) {
            [child displayIfNeededInRect: converted];
        }
    }
}

- (void) displayIfNeededInRectIgnoringOpacity: (NSRect) rect {

    rect = NSIntersectionRect(unionOfInvalidRects(self), rect);

    if ([self needsDisplay])
        [self displayRectIgnoringOpacity: rect];

    NSEnumerator *viewEnumerator = [self _subviewsInDisplayOrderEnumerator];

    NSView *child = nil;
    while ((child = [viewEnumerator nextObject])) {
        NSRect converted = NSIntersectionRect(
                [self convertRect: rect toView: child], [child bounds]);

        if (!NSIsEmptyRect(converted)) {
            [child displayIfNeededInRectIgnoringOpacity: converted];
        }
    }
}

- (void) displayIfNeededIgnoringOpacity {

    if ([self needsDisplay])
        [self displayRectIgnoringOpacity: unionOfInvalidRects(self)];

    NSEnumerator *viewEnumerator = [self _subviewsInDisplayOrderEnumerator];

    NSView *child = nil;
    while ((child = [viewEnumerator nextObject])) {
        [child displayIfNeededIgnoringOpacity];
    }
}

- (void) displayRect: (NSRect) rect {
    NSView *opaque = [self opaqueAncestor];

    if (opaque != self)
        rect = [self convertRect: rect toView: opaque];
    [opaque displayRectIgnoringOpacity: rect];
}

- (void) displayRectIgnoringOpacity: (NSRect) rect {
    NSRect visibleRect = [self visibleRect];

    rect = NSIntersectionRect(rect, visibleRect);

    if (NSIsEmptyRect(rect))
        return;

    BOOL shouldFlush = NO;

    if ([self canDraw]) {
        // This view must be locked/unlocked prior to drawing subviews otherwise
        // gState changes may affect subviews.
        [self lockFocus];

        NSGraphicsContext *context = [NSGraphicsContext currentContext];
        CGContextRef graphicsPort = [context graphicsPort];

        shouldFlush = [context isDrawingToScreen];

        CGContextClipToRect(graphicsPort, rect);

        const NSRect *rects;
        NSInteger rectsCount;
        [self getRectsBeingDrawn: &rects count: &rectsCount];
        // If there is only one rect, it's the visible rect - it's already
        // clipped
        if (rectsCount > 1)
            CGContextClipToRects(graphicsPort, rects, rectsCount);

        // [_window dirtyRect:[self convertRect:rect toView:nil]];
        if ([NSGraphicsContext inQuartzDebugMode]) {
            [[NSColor yellowColor] set];
            NSRectFill(rect);
        } else {
            if (_layer != nil && [self wantsUpdateLayer])
                [self updateLayer];
            else
                [self drawRect: rect];
            if (NSShowAllViews) {
                [[self _borderColorForNSShowAllViews] set];
                NSFrameRect(rect);
            }
        }

        [self unlockFocus];

        NSEnumerator *viewEnumerator = [self _subviewsInDisplayOrderEnumerator];

        NSView *child = nil;
        while ((child = [viewEnumerator nextObject])) {
            NSRect check = [self convertRect: rect toView: child];

            check = NSIntersectionRect(check, [child bounds]);

            if (!NSIsEmptyRect(check))
                [child displayRectIgnoringOpacity: check];
        }
    }

    [_layerContext render];

    // Don't do anything to interfere with what will be drawn in non-debug mode
    if ([NSGraphicsContext inQuartzDebugMode] == NO) {
        removeRectFromInvalidInVisibleRect(self, rect, visibleRect);

        // Rects being drawn are only valid while we redraw
        clearRectsBeingRedrawn(self);
    }

    if (shouldFlush) {
        [_layerContext flush];

        // We do the flushWindow here. If any of the display* methods are being
        // used, you want it to update on screen immediately. If the view
        // hierarchy is being displayed as needed at the end of an event,
        // flushing will be disabled and this will just mark the window as
        // needing flushing which will happen when all the views have finished
        // being displayed
        [[self window] flushWindow];
    }
}

- (void) displayRectIgnoringOpacity: (NSRect) rect
                          inContext: (NSGraphicsContext *) context
{
    NSUnimplementedMethod();
}

- (void) drawRect: (NSRect) rect {
    // do nothing
}

- (BOOL) autoscroll: (NSEvent *) event {
    return [[self superview] autoscroll: event];
}

- (void) scrollRect: (NSRect) rect by: (NSSize) delta {
    NSPoint point = rect.origin;

    point.x += delta.width;
    point.y += delta.height;

    if ([self lockFocusIfCanDraw]) {
        NSCopyBits([self gState], rect, point);
        [self unlockFocus];
    }
}

// A view that draws its whole frame is taken to handle the clicks in it; a
// transparent one lets them through to the window background.
- (BOOL) mouseDownCanMoveWindow {
    return ![self isOpaque];
}

- (void) print: sender {
    [[NSPrintOperation printOperationWithView: self] runOperation];
}

- (void) beginDocument {
    viewBeingPrinted = self;
}

- (void) endDocument {
    viewBeingPrinted = nil;
}

- (void) beginPageInRect: (NSRect) rect atPlacement: (NSPoint) placement {
    CGContextRef graphicsPort = NSCurrentGraphicsPort();
    CGRect mediaBox = NSMakeRect(0, 0, rect.size.width, rect.size.height);
    NSPrintInfo *printInfo = [[NSPrintOperation currentOperation] printInfo];
    NSRect imageableRect = [printInfo imageablePageBounds];
    CGAffineTransform transform = CGAffineTransformIdentity;

    [NSCurrentFocusStack() addObject: self];

    CGContextBeginPage(graphicsPort, &mediaBox);
    CGContextSaveGState(graphicsPort);

    transform = CGAffineTransformIdentity;
    if ([self isFlipped]) {
        transform = CGAffineTransformMake(1, 0, 0, -1, 0,
                                          [printInfo paperSize].height);
    }

    transform = CGAffineTransformTranslate(transform, -rect.origin.x,
                                           -rect.origin.y);

    CGContextConcatCTM(graphicsPort, transform);

    [self setUpGState];
}

- (void) endPage {
    CGContextRef graphicsPort = NSCurrentGraphicsPort();

    CGContextRestoreGState(graphicsPort);
    CGContextEndPage(graphicsPort);
    [NSCurrentFocusStack() removeLastObject];
}

- (NSAttributedString *) pageHeader {
    NSUnimplementedMethod();
    return nil;
}

- (NSAttributedString *) pageFooter {
    NSUnimplementedMethod();
    return nil;
}

// The window's document's display name, else the window's title.
- (NSString *) printJobTitle {
    NSWindow *window = [self window];
    NSDocument *document = [[window windowController] document];
    if (document != nil)
        return [document displayName];
    NSString *title = [window title];
    return [title length] > 0 ? title : nil;
}

- (void) drawSheetBorderWithSize: (NSSize) size {
    NSUnimplementedMethod();
}

- (void) drawPageBorderWithSize: (NSSize) size {
    NSUnimplementedMethod();
}

- (CGFloat) widthAdjustLimit {
    return 0.5;
}

- (CGFloat) heightAdjustLimit {
    return 0.5;
}

- (void) adjustPageWidthNew: (CGFloat *) adjusted
                       left: (CGFloat) left
                      right: (CGFloat) right
                      limit: (CGFloat) limit
{
    // FIX, give subviews a chance
}

- (void) adjustPageHeightNew: (CGFloat *) adjust
                         top: (CGFloat) top
                      bottom: (CGFloat) bottom
                       limit: (CGFloat) limit
{
    // FIX, give subviews a chance
}

- (BOOL) knowsPageRange: (NSRange *) range {
    return NO;
}

- (NSPoint) locationOfPrintRect: (NSRect) rect {
    return NSZeroPoint;
}

- (NSRect) rectForPage: (int) page {
    return NSZeroRect;
}

- (NSData *) dataWithEPSInsideRect: (NSRect) rect {
    NSMutableData *result = [NSMutableData data];
    NSPrintOperation *operation =
            [NSPrintOperation EPSOperationWithView: self
                                        insideRect: rect
                                            toData: result];

    [operation runOperation];

    return result;
}

- (NSData *) dataWithPDFInsideRect: (NSRect) rect {
    NSMutableData *result = [NSMutableData data];
    NSPrintOperation *operation =
            [NSPrintOperation PDFOperationWithView: self
                                        insideRect: rect
                                            toData: result];

    [operation runOperation];

    return result;
}

- (void) writeEPSInsideRect: (NSRect) rect
               toPasteboard: (NSPasteboard *) pasteboard
{
    NSData *data = [self dataWithEPSInsideRect: rect];

    [pasteboard declareTypes: [NSArray arrayWithObject: NSPostScriptPboardType]
                       owner: nil];
    [pasteboard setData: data forType: NSPostScriptPboardType];
}

- (void) writePDFInsideRect: (NSRect) rect
               toPasteboard: (NSPasteboard *) pasteboard
{
    NSData *data = [self dataWithPDFInsideRect: rect];

    [pasteboard declareTypes: [NSArray arrayWithObject: NSPDFPboardType]
                       owner: nil];
    [pasteboard setData: data forType: NSPDFPboardType];
}

- (void) dragImage: (NSImage *) image
                at: (NSPoint) location
            offset: (NSSize) offset
             event: (NSEvent *) event
        pasteboard: (NSPasteboard *) pasteboard
            source: source
         slideBack: (BOOL) slideBack
{
    location = [self convertPoint: location toView: nil];
    if ([NSDraggingManager draggingManager] == nil) {
        // The window runs the drag in-process.
        [[self window] dragImage: image
                              at: location
                          offset: offset
                           event: event
                      pasteboard: pasteboard
                          source: source
                       slideBack: slideBack];
        return;
    }
    [[NSDraggingManager draggingManager] dragImage: image
                                                at: location
                                            offset: offset
                                             event: event
                                        pasteboard: pasteboard
                                            source: source
                                         slideBack: slideBack];
}

- (BOOL) dragFile: (NSString *) path
         fromRect: (NSRect) rect
        slideBack: (BOOL) slideBack
            event: (NSEvent *) event
{
    NSUnimplementedMethod();
    return NO;
}

- (BOOL) acceptsFirstResponder {
    return NO;
}

- (void) scrollWheel: (NSEvent *) event {
    NSScrollView *scrollView = [self enclosingScrollView];

    if (scrollView == nil || scrollView == self) {
        [super scrollWheel: event];
    } else {
        [scrollView scrollWheel: event];
    }
}

- (BOOL) performKeyEquivalent: (NSEvent *) event {
    int i, count = [_subviews count];

    for (i = 0; i < count; i++) {
        NSView *check = [_subviews objectAtIndex: i];

        if ([check performKeyEquivalent: event])
            return YES;
    }
    return NO;
}

- (BOOL) performMnemonic: (NSString *) string {
    NSUnimplementedMethod();
    return NO;
}

- (void) setMenu: (NSMenu *) menu {
    menu = [menu retain];
    [_menu release];
    _menu = menu;
}

- (void) rightMouseDown: (NSEvent *) event {
    [NSMenu popUpContextMenu: [self menuForEvent: event]
                   withEvent: event
                     forView: self];
}

// default NSDraggingDestination
- (NSDragOperation) draggingEntered: (id<NSDraggingInfo>) sender {
    return NSDragOperationNone;
}

- (NSDragOperation) draggingUpdated: (id<NSDraggingInfo>) sender {
    return [sender draggingSourceOperationMask];
}

- (void) draggingExited: (id<NSDraggingInfo>) sender {
    // do nothing
}

- (BOOL) prepareForDragOperation: (id<NSDraggingInfo>) sender {
    // Apple documents prepareForDragOperation: as optional; an absent implementation
    // is treated as accepting (prepared to receive data). Return YES by default so
    // views implementing draggingEntered: and performDragOperation: accept drops.
    return YES;
}

- (BOOL) performDragOperation: (id<NSDraggingInfo>) sender {
    return NO;
}

- (void) concludeDragOperation: (id<NSDraggingInfo>) sender {
    // do nothing
}

- (NSArray *) _draggedTypes {
    return _draggedTypes;
}

- (BOOL) dragPromisedFilesOfTypes: (NSArray *) types
                         fromRect: (NSRect) rect
                           source: (id) source
                        slideBack: (BOOL) slideBack
                            event: (NSEvent *) event
{
    NSUnimplementedMethod();
    return NO;
}

- (NSPoint) convertPointFromBase: (NSPoint) aPoint; {
    return aPoint;
}

- (NSPoint) convertPointToBase: (NSPoint) aPoint; {
    return aPoint;
}

- (NSSize) convertSizeFromBase: (NSSize) aSize {
    return aSize;
}

- (NSSize) convertSizeToBase: (NSSize) aSize {
    return aSize;
}

- (NSRect) convertRectFromBase: (NSRect) aRect {
    return aRect;
}

- (NSRect) convertRectToBase: (NSRect) aRect {
    return aRect;
}

static NSRect scaleRect(NSRect rect, CGFloat scale) {
    return NSMakeRect(rect.origin.x * scale, rect.origin.y * scale,
                      rect.size.width * scale, rect.size.height * scale);
}

static CGFloat backingScaleFactor(NSView *view) {
    NSWindow *window = [view window];
    return window != nil ? [window backingScaleFactor] : 1.0;
}

- (NSRect) convertRectToBacking: (NSRect) rect {
    return scaleRect(rect, backingScaleFactor(self));
}

- (NSRect) convertRectFromBacking: (NSRect) rect {
    return scaleRect(rect, 1.0 / backingScaleFactor(self));
}

- (NSPoint) convertPointToBacking: (NSPoint) point {
    return [self convertRectToBacking: (NSRect){point, NSZeroSize}].origin;
}

- (NSPoint) convertPointFromBacking: (NSPoint) point {
    return [self convertRectFromBacking: (NSRect){point, NSZeroSize}].origin;
}

- (NSSize) convertSizeToBacking: (NSSize) size {
    return [self convertRectToBacking: (NSRect){NSZeroPoint, size}].size;
}

- (NSSize) convertSizeFromBacking: (NSSize) size {
    return [self convertRectFromBacking: (NSRect){NSZeroPoint, size}].size;
}

- (void) showDefinitionForAttributedString: (NSAttributedString *) string
                                   atPoint: (NSPoint) origin
{
    NSUnimplementedMethod();
}

+ defaultAnimationForKey: (NSString *) key {
    NSUnimplementedMethod();
    return nil;
}

- animator {
    NSUnimplementedMethod();
    // should return animating proxy. returning self does not animate.
    return self;
}

- (NSDictionary *) animations {
    return _animations;
}

- animationForKey: (NSString *) key {
    return [_animations objectForKey: key];
}

- (void) setAnimations: (NSDictionary *) dictionary {
    dictionary = [dictionary copy];
    [_animations release];
    _animations = dictionary;
}

#ifdef __BLOCKS__
- (void) showDefinitionForAttributedString: (NSAttributedString *) string
                                     range: (NSRange) range
                                   options: (NSDictionary *) options
                    baselineOriginProvider:
                            (NSPoint (^)(NSRange adjustedRange)) originProvider
{
    NSUnimplementedMethod();
}
#endif

- (NSString *) description {
    return [NSString stringWithFormat: @"<%@[%p] frame: %@>", [self class],
                                       self, NSStringFromRect(_frame)];
}

// XXX: this probably shouldn't be here, but it's a convenient way for CALayers to request a re-render
- (void)displayLayer: (CALayer*)layer
{
    [self display];
}

+ (IBMetricsTable *) ibLayoutMetrics {
    NSUnimplementedMethod();
    return nil;
}

- (void) _nsib_setUsesPointIntegralizationForLayout: (BOOL) usesPointIntegralizationForLayout {
    NSUnimplementedMethod();
}

- (void) _setDefaultLayoutPriorities {
    _horizontalContentHuggingPriority = NSLayoutPriorityDefaultLow;
    _verticalContentHuggingPriority = NSLayoutPriorityDefaultLow;
    _horizontalContentCompressionResistancePriority = NSLayoutPriorityDefaultHigh;
    _verticalContentCompressionResistancePriority = NSLayoutPriorityDefaultHigh;
}

- (NSLayoutPriority) contentHuggingPriorityForOrientation: (NSLayoutConstraintOrientation) orientation {
    if (orientation == NSLayoutConstraintOrientationHorizontal) {
        return _horizontalContentHuggingPriority;
    } else {
        return _verticalContentHuggingPriority;
    }
}

- (void) setContentHuggingPriority: (NSLayoutPriority) contentHuggingPriority forOrientation: (NSLayoutConstraintOrientation) orientation {
    if (orientation == NSLayoutConstraintOrientationHorizontal) {
        _horizontalContentHuggingPriority = contentHuggingPriority;
    } else {
        _verticalContentHuggingPriority = contentHuggingPriority;
    }
}

- (NSLayoutPriority) contentCompressionResistancePriorityForOrientation: (NSLayoutConstraintOrientation) orientation {
    if (orientation == NSLayoutConstraintOrientationHorizontal) {
        return _horizontalContentCompressionResistancePriority;
    } else {
        return _verticalContentCompressionResistancePriority;
    }
}

- (void) setContentCompressionResistancePriority: (NSLayoutPriority) contentCompressionResistancePriority forOrientation: (NSLayoutConstraintOrientation) orientation {
    if (orientation == NSLayoutConstraintOrientationHorizontal) {
        _horizontalContentCompressionResistancePriority = contentCompressionResistancePriority;
    } else {
        _verticalContentCompressionResistancePriority = contentCompressionResistancePriority;
    }
}

- (NSSize) intrinsicContentSize {
    return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric);
}

- (NSUserInterfaceLayoutDirection) userInterfaceLayoutDirection {
    return _hasExplicitUserInterfaceLayoutDirection
                   ? _userInterfaceLayoutDirection
                   : [NSApp userInterfaceLayoutDirection];
}

- (void) setUserInterfaceLayoutDirection:
        (NSUserInterfaceLayoutDirection) direction
{
    // QUIRK: any non-zero direction is stored as right-to-left (1), and out-of-range values do not
    // raise. Not documented. Evidence: black-box observation on macOS 26.7.3 (tier 2, MAC-EVIDENCE
    // MC26.3, setting 2, 99 and -1 each read back 1).
    // Test: tests/appkit-view-layout-direction.m (out-of-range directions read back as 1)
    direction = direction != 0 ? NSUserInterfaceLayoutDirectionRightToLeft
                               : NSUserInterfaceLayoutDirectionLeftToRight;
    _hasExplicitUserInterfaceLayoutDirection = YES;
    if (_userInterfaceLayoutDirection == direction)
        return;
    _userInterfaceLayoutDirection = direction;
    [self setNeedsDisplay: YES];
}

- (void) invalidateIntrinsicContentSize {
}

- (NSArray *) constraints {
    return _constraints ? [[_constraints copy] autorelease] : [NSArray array];
}

- (void) addConstraint: (NSLayoutConstraint *) constraint {
    if ([_constraints containsObject: constraint])
        return;
    if (_constraints == nil)
        _constraints = [[NSMutableArray alloc] init];
    [_constraints addObject: constraint];
    [constraint _attachToOwner: self];
    [self setNeedsUpdateConstraints: YES];
}

- (void) addConstraints: (NSArray *) constraints {
    for (NSLayoutConstraint *constraint in constraints)
        [self addConstraint: constraint];
}

- (void) removeConstraint: (NSLayoutConstraint *) constraint {
    if (![_constraints containsObject: constraint])
        return;
    // Keep it alive until the owner link is cleared.
    [[constraint retain] autorelease];
    [_constraints removeObject: constraint];
    [constraint _detachFromOwner: self];
    [self setNeedsUpdateConstraints: YES];
}

- (void) removeConstraints: (NSArray *) constraints {
    for (NSLayoutConstraint *constraint in constraints)
        [self removeConstraint: constraint];
}

static char installedViewLayoutGuidesKey;

static NSMutableArray *installedViewLayoutGuides(NSView *view, BOOL create) {
    NSMutableArray *guides = objc_getAssociatedObject(view, &installedViewLayoutGuidesKey);
    if (guides == nil && create) {
        guides = [NSMutableArray array];
        objc_setAssociatedObject(view, &installedViewLayoutGuidesKey, guides,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return guides;
}

- (NSArray *) layoutGuides {
    NSArray *guides = installedViewLayoutGuides(self, NO);
    return guides ? [[guides copy] autorelease] : [NSArray array];
}

- (void) addLayoutGuide: (NSLayoutGuide *) guide {
    if (guide == nil) return;
    NSView *oldOwner = [guide owningView];
    if (oldOwner != nil && oldOwner != self) {
        [oldOwner removeLayoutGuide: guide];
    }
    NSMutableArray *guides = installedViewLayoutGuides(self, YES);
    if (![guides containsObject: guide]) {
        [guides addObject: guide];
        [guide setOwningView: self];
    }
}

- (void) removeLayoutGuide: (NSLayoutGuide *) guide {
    if (guide == nil) return;
    NSMutableArray *guides = installedViewLayoutGuides(self, NO);
    if ([guides containsObject: guide]) {
        [guides removeObject: guide];
        if ([guide owningView] == self)
            [guide setOwningView: nil];
    }
}

@end

@implementation NSView (NSViewGestureRecognizers)

- (NSArray *) gestureRecognizers {
    return _gestureRecognizers != nil ? [[_gestureRecognizers copy] autorelease]
                                      : [NSArray array];
}

- (void) setGestureRecognizers: (NSArray *) recognizers {
    for (NSGestureRecognizer *recognizer in [self gestureRecognizers])
        [self removeGestureRecognizer: recognizer];
    for (NSGestureRecognizer *recognizer in recognizers)
        [self addGestureRecognizer: recognizer];
}

// A recognizer belongs to one view; adding it here takes it from any other.
- (void) addGestureRecognizer: (NSGestureRecognizer *) recognizer {
    if ([recognizer view] == self)
        return;
    [[recognizer view] removeGestureRecognizer: recognizer];
    if (_gestureRecognizers == nil)
        _gestureRecognizers = [[NSMutableArray alloc] init];
    [_gestureRecognizers addObject: recognizer];
    [recognizer _setView: self];
}

- (void) removeGestureRecognizer: (NSGestureRecognizer *) recognizer {
    if ([recognizer view] != self)
        return;
    [recognizer _setView: nil];
    [_gestureRecognizers removeObjectIdenticalTo: recognizer];
}

@end

@implementation NSView (NSViewLayoutState)

- (BOOL) needsLayout {
    return _needsLayout;
}

- (void) setNeedsLayout: (BOOL) flag {
    _needsLayout = flag;
}

- (BOOL) needsUpdateConstraints {
    return _needsUpdateConstraints;
}

- (void) setNeedsUpdateConstraints: (BOOL) flag {
    _needsUpdateConstraints = flag;
    if (flag) {
        _needsLayout = YES;
        [[self window] setViewsNeedDisplay: YES];
    }
}

- (BOOL) clipsToBounds {
    return _clipsToBounds;
}

- (void) setClipsToBounds: (BOOL) flag {
    _clipsToBounds = flag;
}

- (NSRect) preparedContentRect {
    return _hasPreparedContentRect ? _preparedContentRect : [self visibleRect];
}

- (void) setPreparedContentRect: (NSRect) rect {
    _preparedContentRect = rect;
    _hasPreparedContentRect = YES;
}

- (void) updateConstraints {
    _needsUpdateConstraints = NO;
}

- (void) updateConstraintsForSubtreeIfNeeded {
    // Constraint updates run from descendants toward their containing view.
    // An update callback can remove or reparent a sibling. Keep the snapshot
    // alive through callbacks, but only visit children still belonging here.
    NSArray *children = [_subviews copy];
    @try {
        for (NSView *child in children) {
            if ([child superview] == self)
                [child updateConstraintsForSubtreeIfNeeded];
        }
    } @finally {
        [children release];
    }
    if (_needsUpdateConstraints) {
        _needsUpdateConstraints = NO;
        [self updateConstraints];
    }
}

- (void) layout {
    _needsLayout = NO;
}

- (void) _layoutSubtreeAfterUpdatingConstraints {
    if (_needsLayout)
        [self layout];
    NSArray *children = [_subviews copy];
    @try {
        for (NSView *child in children) {
            if ([child superview] == self)
                [child _layoutSubtreeAfterUpdatingConstraints];
        }
    } @finally {
        [children release];
    }
}

- (void) layoutSubtreeIfNeeded {
    // Finish the update phase for the whole subtree before laying out any view.
    [self updateConstraintsForSubtreeIfNeeded];
    DarlingLayoutSubtree(self);
    [self _layoutSubtreeAfterUpdatingConstraints];
}

@end

@implementation NSView (NSViewLayoutAnchors)

static id anchorForView(NSView *view, Class anchorClass, NSLayoutAttribute attribute)
{
    return [[[anchorClass alloc] initWithItem: view attribute: attribute] autorelease];
}

- (NSLayoutDimension *) widthAnchor {
    return anchorForView(self, [NSLayoutDimension class], NSLayoutAttributeWidth);
}

- (NSLayoutDimension *) heightAnchor {
    return anchorForView(self, [NSLayoutDimension class], NSLayoutAttributeHeight);
}

- (NSLayoutXAxisAnchor *) leadingAnchor {
    return anchorForView(self, [NSLayoutXAxisAnchor class], NSLayoutAttributeLeading);
}

- (NSLayoutXAxisAnchor *) trailingAnchor {
    return anchorForView(self, [NSLayoutXAxisAnchor class], NSLayoutAttributeTrailing);
}

- (NSLayoutXAxisAnchor *) leftAnchor {
    return anchorForView(self, [NSLayoutXAxisAnchor class], NSLayoutAttributeLeft);
}

- (NSLayoutXAxisAnchor *) rightAnchor {
    return anchorForView(self, [NSLayoutXAxisAnchor class], NSLayoutAttributeRight);
}

- (NSLayoutXAxisAnchor *) centerXAnchor {
    return anchorForView(self, [NSLayoutXAxisAnchor class], NSLayoutAttributeCenterX);
}

- (NSLayoutYAxisAnchor *) topAnchor {
    return anchorForView(self, [NSLayoutYAxisAnchor class], NSLayoutAttributeTop);
}

- (NSLayoutYAxisAnchor *) bottomAnchor {
    return anchorForView(self, [NSLayoutYAxisAnchor class], NSLayoutAttributeBottom);
}

- (NSLayoutYAxisAnchor *) centerYAnchor {
    return anchorForView(self, [NSLayoutYAxisAnchor class], NSLayoutAttributeCenterY);
}

@end

@implementation NSView (NSViewEffectiveAppearance)

- (NSAppearance *) effectiveAppearance {
    if (_appearance != nil)
        return _appearance;
    if (_superview != nil)
        return [_superview effectiveAppearance];
    return [NSAppearance currentAppearance];
}

@end
