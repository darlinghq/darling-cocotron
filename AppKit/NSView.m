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
#import <AppKit/NSText.h>
#import <AppKit/NSTrackingArea.h>
#import <AppKit/NSView.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSViewBackingLayer.h>
#import <AppKit/NSWindow-Private.h>
#import <AppKit/NSDocument.h>
#import <AppKit/NSWindowController.h>
#import <CoreGraphics/CGWindowPrivate.h>
#import <Foundation/NSKeyedArchiver.h>
#import <Onyx2D/O2Context.h>
#import <QuartzCore/CALayerContext.h>
#import <QuartzCore/CATransaction.h>
#import <AppKit/NSLayoutAnchor.h>
#import <QuartzCore/CADisplayLink.h>
#import <Foundation/NSHashTable.h>
#import <objc/message.h>
#import <AppKit/NSLayoutConstraint.h>
#import <AppKit/NSLayoutGuide.h>
#import "NSLayoutConstraintInternal.h"
#import "NSViewLayoutInternal.h"
#import <AppKit/NSTextInput.h>
#import <AppKit/NSTextInputClient.h>
#import <objc/runtime.h>
#import <AppKit/NSTouch.h>
#include <math.h>
#include <mach-o/dyld_priv.h>
#import "NSGestureRecognizer-Private.h"
#import "DarlingLayout.h"
#import "NSGraphics-Private.h"

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
const NSViewFullScreenModeOptionKey NSFullScreenModeAllScreens =
        @"NSFullScreenModeAllScreens";

@interface NSView (NSView_forward)
- (CGAffineTransform) transformFromWindow;
- (CGAffineTransform) transformToWindow;
- (CGAffineTransform) transformToLayer;
- (void) _trackingAreasChanged;
- (void) _removeAreaWithTag: (NSInteger) tag;
- (void) _addLayerToSuperlayer;
- (void) _synchronizeSublayerOrder;
- (void) _updateLayerVisibility;
- (void) _removeLayerFromSuperlayer;
@end

@interface CADisplayLink (AppKitRefreshRate)
- (void)_setRefreshRateProvider:(double (^)(void))provider;
@end

@interface _NSViewDisplayLinkTarget : NSObject {
    NSHashTable *_view;
    id _target;
    SEL _selector;
}
- (instancetype)initWithView:(NSView *)view target:(id)target selector:(SEL)selector;
- (void)frame:(CADisplayLink *)link;
- (double)refreshRate;
@end

@implementation _NSViewDisplayLinkTarget
- (instancetype)initWithView:(NSView *)view target:(id)target selector:(SEL)selector {
    if (!(self = [super init])) return nil;
    if (!target || !selector || ![target respondsToSelector:selector]) {
        [self release];
        [NSException raise:NSInvalidArgumentException format:@"A display link requires a target and selector"];
        return nil;
    }
    _view = [[NSHashTable weakObjectsHashTable] retain];
    [_view addObject:view];
    _target = [target retain];
    _selector = selector;
    return self;
}
- (void)frame:(CADisplayLink *)link {
    NSView *view = [_view anyObject];
    NSWindow *window = [view window];
    if (view && ![view isHiddenOrHasHiddenAncestor] && [window isVisible] &&
        ![window isMiniaturized] && [window screen])
        ((void (*)(id, SEL, id))objc_msgSend)(_target, _selector, link);
}
// The refresh rate of the screen the view's window is on (the main screen
// while it has none), in Hz.
- (double)refreshRate {
    // The provider runs while the link is scheduled, possibly right before the
    // caller drops its last reference to the view. Keep the autoreleased view
    // from outliving that release.
    @autoreleasepool {
        NSView *view = [_view anyObject];
        NSScreen *screen = [[view window] screen];
        if (screen == nil)
            screen = [NSScreen mainScreen];
        NSTimeInterval interval = [screen minimumRefreshInterval];
        return interval > 0 ? 1.0 / interval : 0;
    }
}
- (void)dealloc {
    [_view release];
    [_target release];
    [super dealloc];
}
@end

@implementation NSView

NS_EXTRA_SYNTHESIZE_COPY(NSView, identifier, _identifier, NSUserInterfaceItemIdentifier, identifier, setIdentifier:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSView, translatesAutoresizingMaskIntoConstraints, _translatesAutoresizingMaskIntoConstraints, BOOL, translatesAutoresizingMaskIntoConstraints, setTranslatesAutoresizingMaskIntoConstraints:)
NS_EXTRA_SYNTHESIZE_RETAIN(NSView, appearance, _appearance, NSAppearance *, appearance, setAppearance:)
// Until the application sets it, the property is YES for programs linked
// against SDK 10.15 or later and NO for older ones (the NSView.h documentation
// of the NSOpenGLSurfaceResolution category). A program's SDK version is what
// dyld reports for its executable.
- (BOOL) wantsBestResolutionOpenGLSurface {
    if (NS_EXTRA(NSView, self)->_wantsBestResolutionOpenGLSurfaceSet)
        return NS_EXTRA(NSView, self)->_wantsBestResolutionOpenGLSurface;
    return dyld_get_program_sdk_version() >= DYLD_MACOSX_VERSION_10_15;
}

- (void) setWantsBestResolutionOpenGLSurface: (BOOL) value {
    NS_EXTRA(NSView, self)->_wantsBestResolutionOpenGLSurface = value;
    NS_EXTRA(NSView, self)->_wantsBestResolutionOpenGLSurfaceSet = YES;
}

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
    return NSFocusRingTypeExterior;
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
        vFlags |= NS_EXTRA(NSView, self)->_autoresizingMask & 0x3f;
        vFlags |= NS_EXTRA(NSView, self)->_autoresizesSubviews ? 0x100 : 0;
        vFlags |= NS_EXTRA(NSView, self)->_isHidden ? 0x80000000 : 0;
        // TODO: there are almost certainly more vFlags

        [coder encodeInt: vFlags forKey: @"NSvFlags"];
        [coder encodeRect: _frame forKey: @"NSFrame"];
        [coder encodeRect: _bounds forKey: @"NSBounds"];
        [coder encodeInt: NS_EXTRA(NSView, self)->_tag forKey: @"NSTag"];
        // TODO: do we need to order the subviews here in back-to-front order ourselves?
        [coder encodeObject: _subviews forKey: @"NSSubviews"];
        [coder encodeObject: _window forKey: @"NSWindow"];
        [coder encodeObject: _superview forKey: @"NSSuperview"];
        [coder encodeObject: NS_EXTRA(NSView, self)->_nextKeyView forKey: @"NSNextKeyView"];
        [coder encodeObject: NS_EXTRA(NSView, self)->_shadow forKey: @"NSViewShadow"];
        [coder encodeObject: NS_EXTRA(NSView, self)->_compositingFilter
                     forKey: @"NSViewCompositeFilter"];
        //[coder encodeObject: _backgroundFilters
        //             forKey: @"NSViewBackgroundFilters"];
        [coder encodeObject: NS_EXTRA(NSView, self)->_animations forKey: @"NSViewAnimations"];
        [coder encodeBool: NS_EXTRA(NSView, self)->_canDrawConcurrently
                   forKey: @"NSViewCanDrawConcurrently"];
        [coder encodeBool: NS_EXTRA(NSView, self)->_wantsLayer forKey: @"NSViewIsLayerTreeHost"];
        [coder encodeInteger: NS_EXTRA(NSView, self)->_layerContentsRedrawPolicy
                      forKey: @"NSViewLayerContentsRedrawPolicy"];
        [coder encodeObject: NS_EXTRA(NSView, self)->_contentFilters forKey: @"NSViewContentFilters"];
        [coder encodeBool: NS_EXTRA(NSView, self)->_wantsBestResolutionOpenGLSurface
                   forKey: @"NSViewWantsBestResolutionOpenGLSurface"];

        // Auto Layout state, under the keys nibs use: a flag for views laid out by constraints,
        // the constraints that were set up in Interface Builder (the others are rebuilt by code),
        // and the content hugging and compression resistance priorities when they are not the
        // defaults, as {horizontal, vertical} sizes.
        if (![self translatesAutoresizingMaskIntoConstraints])
            [coder encodeBool: YES forKey: @"NSDoNotTranslateAutoresizingMask"];
        NSMutableArray *archivedConstraints = nil;
        for (NSLayoutConstraint *constraint in [self constraints]) {
            if ([constraint shouldBeArchived]) {
                if (archivedConstraints == nil)
                    archivedConstraints = [NSMutableArray array];
                [archivedConstraints addObject: constraint];
            }
        }
        if (archivedConstraints != nil)
            [coder encodeObject: archivedConstraints forKey: @"NSViewConstraints"];
        NSSize hugging = NSMakeSize([self contentHuggingPriorityForOrientation: NSLayoutConstraintOrientationHorizontal],
                                    [self contentHuggingPriorityForOrientation: NSLayoutConstraintOrientationVertical]);
        if (hugging.width != NSLayoutPriorityDefaultLow || hugging.height != NSLayoutPriorityDefaultLow)
            [coder encodeObject: NSStringFromSize(hugging) forKey: @"NSHuggingPriority"];
        NSSize compression = NSMakeSize([self contentCompressionResistancePriorityForOrientation: NSLayoutConstraintOrientationHorizontal],
                                        [self contentCompressionResistancePriorityForOrientation: NSLayoutConstraintOrientationVertical]);
        if (compression.width != NSLayoutPriorityDefaultHigh || compression.height != NSLayoutPriorityDefaultHigh)
            [coder encodeObject: NSStringFromSize(compression) forKey: @"NSAntiCompressionPriority"];
    } else {
        [NSException raise: NSInvalidArchiveOperationException
                    format: @"TODO: support unkeyed encoding in NSView"];
    }
}

// The Auto Layout state of a view archive: the translation of the autoresizing mask, the content
// priorities and the constraints. It is shared with NSCustomView, which makes a view of a custom
// class from the archive of a stand-in.
- (void) _decodeAutoLayoutStateFromKeyedCoder: (NSKeyedUnarchiver *) coder {
    // Auto Layout state. The nib key is the inverse of the property, and is only there for views
    // that are laid out by constraints.
    if ([coder containsValueForKey: @"NSDoNotTranslateAutoresizingMask"])
        NS_EXTRA(NSView, self)->_translatesAutoresizingMaskIntoConstraints =
                ![coder decodeBoolForKey: @"NSDoNotTranslateAutoresizingMask"];
    if ([coder containsValueForKey: @"NSHuggingPriority"]) {
        NSSize priorities = NSSizeFromString([coder decodeObjectForKey: @"NSHuggingPriority"]);

        [self setContentHuggingPriority: priorities.width forOrientation: NSLayoutConstraintOrientationHorizontal];
        [self setContentHuggingPriority: priorities.height forOrientation: NSLayoutConstraintOrientationVertical];
    }
    if ([coder containsValueForKey: @"NSAntiCompressionPriority"]) {
        NSSize priorities = NSSizeFromString([coder decodeObjectForKey: @"NSAntiCompressionPriority"]);

        [self setContentCompressionResistancePriority: priorities.width
                                       forOrientation: NSLayoutConstraintOrientationHorizontal];
        [self setContentCompressionResistancePriority: priorities.height
                                       forOrientation: NSLayoutConstraintOrientationVertical];
    }
    // The items of the constraints are this view and its subviews, which are decoded by now.
    [self addConstraints: [coder decodeObjectForKey: @"NSViewConstraints"]];
}

- initWithCoder: (NSCoder *) coder {
    // Decoding the next responder (the superview) can decode the whole
    // hierarchy around this view, and the superview then creates the layer of
    // this still unfinished view from its alpha value. A nib that refers to a
    // control before its superview (as the connectors of user defined runtime
    // attributes do) reaches that state, so the alpha value must be set before
    // the superclass decodes anything.
    NS_EXTRA(NSView, self)->_alphaValue = 1.0;
    [super initWithCoder: coder];

    // The defaults; the Auto Layout state of the archive is decoded below.
    NS_EXTRA(NSView, self)->_translatesAutoresizingMaskIntoConstraints = YES;
    NS_EXTRA(NSView, self)->_allowedTouchTypes = NSTouchTypeMaskDirect;
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
        NS_EXTRA(NSView, self)->_postsNotificationOnFrameChange = YES;
        NS_EXTRA(NSView, self)->_postsNotificationOnBoundsChange = YES;
        NS_EXTRA(NSView, self)->_autoresizingMask = vFlags & 0x3F;
        if ([keyed containsValueForKey: @"NSvFlags"])
            NS_EXTRA(NSView, self)->_autoresizesSubviews = (vFlags & 0x100) ? YES : NO;
        // Despite the fact it appears _autoresizesSubviews is encoded in the
        // flags, it should always be ON
        // *** Do not turn off or base on the flags unless you have an
        // alternative for enabling it when it should be.
        NS_EXTRA(NSView, self)->_autoresizesSubviews = YES;
        NS_EXTRA(NSView, self)->_isHidden = (vFlags & 0x80000000) ? YES : NO;
        // An archive without the key leaves the SDK-dependent default.
        if ([keyed containsValueForKey: @"NSViewWantsBestResolutionOpenGLSurface"]) {
            NS_EXTRA(NSView, self)->_wantsBestResolutionOpenGLSurface = [keyed
                    decodeBoolForKey: @"NSViewWantsBestResolutionOpenGLSurface"];
            NS_EXTRA(NSView, self)->_wantsBestResolutionOpenGLSurfaceSet = YES;
        }
        NS_EXTRA(NSView, self)->_tag = 0; // IB assigns a default tag id of 0 - which is different from
                  // the default in the docs.
        if ([keyed containsValueForKey: @"NSTag"])
            NS_EXTRA(NSView, self)->_tag = [keyed decodeIntForKey: @"NSTag"];

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
            NS_EXTRA(NSView, self)->_identifier = [[keyed decodeObjectForKey: @"NSUserInterfaceItemIdentifier"] copy];
        } else if ([keyed containsValueForKey: @"NSReuseIdentifierKey"]) {
            NS_EXTRA(NSView, self)->_identifier = [[keyed decodeObjectForKey: @"NSReuseIdentifierKey"] copy];
        } else if ([keyed containsValueForKey: @"NSIdentifier"]) {
            NS_EXTRA(NSView, self)->_identifier = [[keyed decodeObjectForKey: @"NSIdentifier"] copy];
        }

        [self setCanDrawConcurrently:
                        [keyed decodeBoolForKey: @"NSViewCanDrawConcurrently"]];

        [self _decodeAutoLayoutStateFromKeyedCoder: keyed];

        // TODO: NSViewLayoutGuides, ...

        NS_EXTRA(NSView, self)->_needsDisplay = YES;
        NS_EXTRA(NSView, self)->_invalidRectCount = 0;
        NS_EXTRA(NSView, self)->_invalidRects = NULL;
        NS_EXTRA(NSView, self)->_trackingAreas = [[NSMutableArray alloc] init];
        [self setWantsLayer:
                        [keyed decodeBoolForKey: @"NSViewIsLayerTreeHost"]];

        NS_EXTRA(NSView, self)->_layerContentsRedrawPolicy =
                [keyed decodeIntegerForKey: @"NSViewLayerContentsRedrawPolicy"];

        NS_EXTRA(NSView, self)->_contentFilters =
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
                                            &frameMatrix, &NS_EXTRA(NSView, self)->_draggedTypes];
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
                                            &drawMatrix, &frameMatrix, &NS_EXTRA(NSView, self)->_draggedTypes,
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

        NS_EXTRA(NSView, self)->_autoresizingMask = vflags.vf.autosizing;
        NS_EXTRA(NSView, self)->_autoresizesSubviews = vflags.vf.autoresizeSubviews;
    }

    return self;
}

- init {
    return [self initWithFrame: NSZeroRect];
}

- initWithFrame: (NSRect) frame {
    _frame = frame;
    _bounds.origin = NSMakePoint(0, 0);
    _bounds.size = frame.size;
    _window = nil;
    NS_EXTRA(NSView, self)->_menu = nil;
    _superview = nil;
    _subviews = [NSMutableArray new];
    NS_EXTRA(NSView, self)->_postsNotificationOnFrameChange = YES;
    NS_EXTRA(NSView, self)->_postsNotificationOnBoundsChange = YES;
    NS_EXTRA(NSView, self)->_autoresizesSubviews = YES;
    NS_EXTRA(NSView, self)->_autoresizingMask = NSViewNotSizable;
    NS_EXTRA(NSView, self)->_tag = -1; // according to the docs - loading from a nib gets a default of
               // 0.
    NS_EXTRA(NSView, self)->_needsDisplay = YES;
    NS_EXTRA(NSView, self)->_invalidRectCount = 0;
    NS_EXTRA(NSView, self)->_invalidRects = NULL;
    NS_EXTRA(NSView, self)->_trackingAreas = [[NSMutableArray alloc] init];

    NS_EXTRA(NSView, self)->_validTransforms = NO;
    NS_EXTRA(NSView, self)->_transformFromWindow = CGAffineTransformIdentity;
    NS_EXTRA(NSView, self)->_transformToWindow = CGAffineTransformIdentity;
    NS_EXTRA(NSView, self)->_transformToLayer = CGAffineTransformIdentity;

    // according to some Apple sample code ("Creating a Custom Metal View"),
    // it's valid for a subclass of NSView to set `wantsLayer` before invoking the superclass `initWithFrame:`.
    // thus, we might have a layer context already but with an incorrect frame.
    [NS_EXTRA(NSView, self)->_layerContext setFrame: _frame];

    NS_EXTRA(NSView, self)->_translatesAutoresizingMaskIntoConstraints = YES;
    NS_EXTRA(NSView, self)->_alphaValue = 1.0;
    NS_EXTRA(NSView, self)->_allowedTouchTypes = NSTouchTypeMaskDirect;
    [self _setDefaultLayoutPriorities];

    return self;
}

- (void) dealloc {
    [NSLayoutConstraint deactivateConstraints:[self constraints]];

    // Do this first?
    [self _unbindAllBindings];

    _window = nil;
    [NS_EXTRA(NSView, self)->_menu release];
    [NS_EXTRA(NSView, self)->_accessibilityTitle release];

    _superview = nil;
    [_subviews makeObjectsPerformSelector: @selector(_setSuperview:)
                               withObject: nil];

    [_subviews release];
    [NS_EXTRA(NSView, self)->_draggedTypes release];
    [NS_EXTRA(NSView, self)->_trackingAreas release];
    [NS_EXTRA(NSView, self)->_contentFilters release];
    [NS_EXTRA(NSView, self)->_constraints makeObjectsPerformSelector: @selector(_detachFromOwner:) withObject: self];
    [NS_EXTRA(NSView, self)->_constraints release];

    if (NS_EXTRA(NSView, self)->_invalidRects != NULL)
        NSZoneFree(NULL, NS_EXTRA(NSView, self)->_invalidRects);

    if (NS_EXTRA(NSView, self)->_rectsBeingRedrawn != NULL) {
        NSZoneFree(NULL, NS_EXTRA(NSView, self)->_rectsBeingRedrawn);
    }
    [_layer release];

    [NS_EXTRA(NSView, self)->_layerContext invalidate];
    [NS_EXTRA(NSView, self)->_layerContext release];

    [NS_EXTRA(NSView, self)->_identifier release];
    for (NSGestureRecognizer *recognizer in NS_EXTRA(NSView, self)->_gestureRecognizers)
        [recognizer _setView: nil];
    [NS_EXTRA(NSView, self)->_gestureRecognizers release];

    NS_EXTRA_FREE(NSView, self);
    [super dealloc];
}

static void invalidateTransform(NSView *self) {
    NS_EXTRA(NSView, self)->_validTransforms = NO;
    NS_EXTRA(NSView, self)->_validTrackingAreas = NO;

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
    if (!NS_EXTRA(NSView, self)->_validTransforms) {
        NS_EXTRA(NSView, self)->_transformToWindow = [self createTransformToWindow];
        NS_EXTRA(NSView, self)->_transformFromWindow =
                CGAffineTransformInvert(NS_EXTRA(NSView, self)->_transformToWindow);
        NS_EXTRA(NSView, self)->_transformToLayer = [self createTransformToLayer];
        NS_EXTRA(NSView, self)->_validTransforms = YES;

        NS_EXTRA(NSView, self)->_visibleRect = [self calculateVisibleRect];
        configureLayerGeometry(self);
    }
}

- (CGAffineTransform) transformFromWindow {
    buildTransformsIfNeeded(self);

    return NS_EXTRA(NSView, self)->_transformFromWindow;
}

- (CGAffineTransform) transformToWindow {
    buildTransformsIfNeeded(self);

    return NS_EXTRA(NSView, self)->_transformToWindow;
}

- (CGAffineTransform) transformToLayer {
    buildTransformsIfNeeded(self);

    return NS_EXTRA(NSView, self)->_transformToLayer;
}

- (NSRect) frame {
    return _frame;
}

- (CGFloat) frameRotation {
    return NS_EXTRA(NSView, self)->_frameRotation;
}

- (CGFloat) frameCenterRotation {
    NSUnimplementedMethod();
    return 0.;
}

- (NSRect) bounds {
    return _bounds;
}

- (CGFloat) boundsRotation {
    return NS_EXTRA(NSView, self)->_boundsRotation;
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
    return NS_EXTRA(NSView, self)->_postsNotificationOnFrameChange;
}

- (BOOL) postsBoundsChangedNotifications {
    return NS_EXTRA(NSView, self)->_postsNotificationOnBoundsChange;
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
    // The closest view that is the receiver, or an ancestor of it, and that
    // is also the other view or one of its ancestors.
    for (NSView *candidate = self; candidate != nil;
            candidate = [candidate superview]) {
        if ([view isDescendantOf: candidate])
            return candidate;
    }
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
    return NS_EXTRA(NSView, self)->_autoresizesSubviews;
}

- (NSAutoresizingMaskOptions) autoresizingMask {
    return NS_EXTRA(NSView, self)->_autoresizingMask;
}

- (NSFocusRingType) focusRingType {
    return NS_EXTRA(NSView, self)->_focusRingType;
}

- (NSInteger) tag {
    return NS_EXTRA(NSView, self)->_tag;
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
    return NS_EXTRA(NSView, self)->_alphaValue;
}

// Applied through the backing layer; views drawn without one ignore it.
- (void) setAlphaValue: (CGFloat) alpha {
    NS_EXTRA(NSView, self)->_alphaValue = alpha;
    [_layer setOpacity: alpha];
}

- (int) gState {
    return 0;
}

- (NSRect) visibleRect {
    buildTransformsIfNeeded(self);

    return NS_EXTRA(NSView, self)->_visibleRect;
}

- (BOOL) wantsDefaultClipping {
    // Documented default: the view is clipped to its bounds before drawing.
    return YES;
}

- (NSBitmapImageRep *) bitmapImageRepForCachingDisplayInRect: (NSRect) rect {
    CGFloat scale = [_window backingScaleFactor];

    if (scale < 1)
        scale = 1;
    rect = NSIntersectionRect(rect, [self bounds]);
    NSInteger width = (NSInteger) ceil(NSWidth(rect) * scale);
    NSInteger height = (NSInteger) ceil(NSHeight(rect) * scale);

    if (width <= 0 || height <= 0)
        return nil;
    return [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                                    pixelsWide: width
                                                    pixelsHigh: height
                                                 bitsPerSample: 8
                                               samplesPerPixel: 4
                                                      hasAlpha: YES
                                                      isPlanar: NO
                                                colorSpaceName: NSDeviceRGBColorSpace
                                                   bytesPerRow: 0
                                                  bitsPerPixel: 0] autorelease];
}

// The view that a first responder stands for in focus ring drawing: the view itself, or the control that a field
// editor is editing.
static NSView *focusRingViewForResponder(NSResponder *responder) {
    if ([responder isKindOfClass: [NSView class]]) {
        if ([responder isKindOfClass: [NSText class]] && [(NSText *) responder isFieldEditor]) {
            id delegate = [(NSText *) responder delegate];

            if ([delegate isKindOfClass: [NSView class]])
                return delegate;
        }
        return (NSView *) responder;
    }
    return nil;
}

// A view shows a focus ring while it has the keyboard focus (or its field editor does) in the key window, unless
// its focus ring type is NSFocusRingTypeNone, and only if it reports a mask for the ring.
static BOOL viewShowsFocusRing(NSView *view) {
    NSWindow *window = [view window];

    if (window == nil || [view isHidden] || ![window isKeyWindow])
        return NO;
    if (focusRingViewForResponder([window firstResponder]) != view)
        return NO;

    NSFocusRingType type = [view focusRingType];

    if (type == NSFocusRingTypeDefault)
        type = [[view class] defaultFocusRingType];
    if (type == NSFocusRingTypeNone)
        return NO;
    return [view _focusRingShape] != nil || !NSIsEmptyRect([view focusRingMaskBounds]);
}

static BOOL anySubviewShowsFocusRing(NSView *view) {
    for (NSView *child in [view subviews]) {
        if (viewShowsFocusRing(child))
            return YES;
    }
    return NO;
}

// Draws the focus rings of the subviews that have one, outside the shape of their mask. A ring reaches outside the
// view that owns it, so it is drawn by the superview, over the subviews, in its coordinates and clip; the port's
// clip is the rectangle being drawn, so a ring is painted again only together with the pixels under it.
static void drawSubviewFocusRings(NSView *view, CGContextRef port) {
    for (NSView *child in [view subviews]) {
        if (!viewShowsFocusRing(child))
            continue;

        NSRect frame = [child frame];
        NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithGraphicsPort: port flipped: [child isFlipped]];

        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext: context];
        CGContextSaveGState(port);
        CGContextTranslateCTM(port, frame.origin.x, frame.origin.y);
        if ([child isFlipped] != [view isFlipped]) {
            CGContextTranslateCTM(port, 0, frame.size.height);
            CGContextScaleCTM(port, 1, -1);
        }
        CGContextTranslateCTM(port, -[child bounds].origin.x, -[child bounds].origin.y);
        [context _setFocusRingPlacement: (NSInteger) NSFocusRingOnly + 1 outerOnly: YES];
        NSBezierPath *shape = [child _focusRingShape];

        if (shape != nil)
            [shape fill];
        else
            [child drawFocusRingMask];
        CGContextRestoreGState(port);
        [NSGraphicsContext restoreGraphicsState];
    }
}

// Draws the view and its visible subviews, in their own coordinates, into the
// current CGContext. The context's origin is the view's bounds origin.
static void drawViewTreeInContext(NSView *view, CGContextRef port, NSRect rect) {
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithGraphicsPort: port flipped: [view isFlipped]];

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: context];
    CGContextSaveGState(port);
    CGContextClipToRect(port, rect);
    [view drawRect: rect];
    CGContextRestoreGState(port);
    [NSGraphicsContext restoreGraphicsState];

    for (NSView *child in [view subviews]) {
        if ([child isHidden])
            continue;
        NSRect childRect = NSIntersectionRect([view convertRect: rect toView: child], [child bounds]);

        if (NSIsEmptyRect(childRect))
            continue;

        NSRect frame = [child frame];

        CGContextSaveGState(port);
        CGContextTranslateCTM(port, frame.origin.x, frame.origin.y);
        if ([child isFlipped] != [view isFlipped]) {
            CGContextTranslateCTM(port, 0, frame.size.height);
            CGContextScaleCTM(port, 1, -1);
        }
        CGContextTranslateCTM(port, -[child bounds].origin.x, -[child bounds].origin.y);
        drawViewTreeInContext(child, port, childRect);
        CGContextRestoreGState(port);
    }

    if (anySubviewShowsFocusRing(view)) {
        CGContextSaveGState(port);
        CGContextClipToRect(port, rect);
        drawSubviewFocusRings(view, port);
        CGContextRestoreGState(port);
    }
}

// Renders the view hierarchy with the view's own drawing methods. Layer
// content, and anything that draws through the window's graphics context
// instead of the current one, is not captured.
- (void) cacheDisplayInRect: (NSRect) rect
           toBitmapImageRep: (NSBitmapImageRep *) imageRep
{
    rect = NSIntersectionRect(rect, [self bounds]);
    if (imageRep == nil || NSIsEmptyRect(rect))
        return;

    NSGraphicsContext *bitmapContext = [NSGraphicsContext graphicsContextWithBitmapImageRep: imageRep];
    CGContextRef port = [bitmapContext graphicsPort];

    if (port == NULL)
        return;

    CGFloat scaleX = (CGFloat) [imageRep pixelsWide] / NSWidth(rect);
    CGFloat scaleY = (CGFloat) [imageRep pixelsHigh] / NSHeight(rect);

    CGContextSaveGState(port);
    CGContextClearRect(port, CGRectMake(0, 0, [imageRep pixelsWide], [imageRep pixelsHigh]));
    CGContextScaleCTM(port, scaleX, scaleY);
    if ([self isFlipped]) {
        CGContextTranslateCTM(port, 0, NSHeight(rect));
        CGContextScaleCTM(port, 1, -1);
    }
    CGContextTranslateCTM(port, -rect.origin.x, -rect.origin.y);
    drawViewTreeInContext(self, port, rect);
    CGContextRestoreGState(port);
}

- (BOOL) isHidden {
    return NS_EXTRA(NSView, self)->_isHidden;
}

- (BOOL) isHiddenOrHasHiddenAncestor {
    return NS_EXTRA(NSView, self)->_isHidden || [_superview isHiddenOrHasHiddenAncestor];
}

- (void) setHidden: (BOOL) flag {
    flag = flag ? YES : NO;

    if (NS_EXTRA(NSView, self)->_isHidden != flag) {
        invalidateTransform(self);
        if ((NS_EXTRA(NSView, self)->_isHidden = flag)) {
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
        // Only where the view is shows or hides something.
        [[self superview] setNeedsDisplayInRect: [self frame]];

        if (NS_EXTRA(NSView, self)->_isHidden)
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
    return NS_EXTRA(NSView, self)->_nextKeyView;
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
    return NS_EXTRA(NSView, self)->_previousKeyView;
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
    return NS_EXTRA(NSView, self)->_menu;
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
    NSUInteger i, count = [NS_EXTRA(NSView, self)->_trackingAreas count];
    NSString *toolTip = nil;

    // In case there's more than one ToolTip the behavior
    // is undocumented. Return the first one.
    for (i = 0; i < count; i++) {
        NSTrackingArea *area = [NS_EXTRA(NSView, self)->_trackingAreas objectAtIndex: i];

        if ([area _isToolTip] == YES) {
            toolTip = [area owner];
            break;
        }
    }

    return toolTip;
}

- viewWithTag: (NSInteger) tag {
    int i, count = [_subviews count];

    if (NS_EXTRA(NSView, self)->_tag == tag)
        return self;

    for (i = 0; i < count; i++) {
        NSView *view = [[_subviews objectAtIndex: i] viewWithTag: tag];

        if (view != nil)
            return view;
    }

    return nil;
}

- (NSView *) hitTest: (NSPoint) point {
    if (NS_EXTRA(NSView, self)->_isHidden) {
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

// Aligns each edge of a rect, given in a space whose unit is one backing
// pixel, as the alignment options ask. Shared with NSWindow.
NSRect _NSAlignRectToPixelGrid(NSRect rect, NSAlignmentOptions options) {
    alignAxis(&rect.origin.x, &rect.size.width, options, NSAlignMinXInward,
              NSAlignMaxXInward, NSAlignWidthInward);
    alignAxis(&rect.origin.y, &rect.size.height, options, NSAlignMinYInward,
              NSAlignMaxYInward, NSAlignHeightInward);
    return rect;
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
    return NS_EXTRA(NSView, self)->_accessibilityTitle;
}

- (void) setAccessibilityTitle: (NSString *) title {
    title = [title copy];
    [NS_EXTRA(NSView, self)->_accessibilityTitle release];
    NS_EXTRA(NSView, self)->_accessibilityTitle = title;
}

// The frame of the native window that hosts a root layer, in window coordinates. A view's own frame is in
// its superview's coordinates, which are the same only for the window's content view.
static NSRect layerContextFrame(NSView *self) {
    NSRect frame = self->_frame;

    if (self->_superview != nil)
        frame = [self->_superview convertRect: frame toView: nil];

    return frame;
}

// Moves the native windows of the root layers in a view's subtree after the view moved or resized, since their
// frames are in window coordinates.
static void updateLayerContextFrames(NSView *self) {
    [NS_EXTRA(NSView, self)->_layerContext setFrame: layerContextFrame(self)];

    for (NSView *child in self->_subviews)
        updateLayerContextFrames(child);
}

// Stores a new frame and lays out the subviews, without posting
// NSViewFrameDidChangeNotification. Returns whether the frame changed.
static BOOL applyFrame(NSView *self, NSRect frame) {
    if (NSEqualRects(self->_frame, frame))
        return NO;

    NSSize oldSize = self->_bounds.size;

    // QUIRK: a change of the frame size marks the view as needing layout, whether the new size came
    // from the constraint solver, autoresizing or a direct call, and also outside of a window.
    // Not documented. Evidence: black-box observation on macOS 10.14.4 (tier 2): needsLayout is
    // YES after -setFrameSize: of a settled view with and without a window, and -layout of a view
    // is called after constraints change its size.
    // Test: tests/appkit-layout-repeat-passes.m (frame size change sets needsLayout)
    if (!NSEqualSizes(self->_frame.size, frame.size))
        NS_EXTRA(NSView, self)->_needsLayout = YES;

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

    if (NS_EXTRA(NSView, self)->_autoresizesSubviews) {
        [self resizeSubviewsWithOldSize: oldSize];
    }

    updateLayerContextFrames(self);

    invalidateTransform(self);

    // QUIRK: a frame change marks both the view and its superview as needing display; a call that
    // leaves the frame as it is marks neither. Not documented. Evidence: black-box observation on
    // Mac OS X 10.14.4 (tier 2, MAC-EVIDENCE "setFrame: marks views for display"). macOS 26.7.3
    // keeps both flags clear because every view is layer-backed there, but the window shows the
    // view redrawn at its new size on both. The software window backing needs the repaint,
    // otherwise a view that layout resizes keeps the pixels of its old size.
    // Test: tests/appkit-view-set-frame-needs-display.m
    [self setNeedsDisplay: YES];
    [self->_superview setNeedsDisplay: YES];
    return YES;
}

static void postFrameChange(NSView *self) {
    if (NS_EXTRA(NSView, self)->_postsNotificationOnFrameChange && NS_EXTRA(NSView, self)->_frameChangeDepth == 0)
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

    NS_EXTRA(NSView, self)->_frameChangeDepth++;
    [self setFrameOrigin: frame.origin];
    [self setFrameSize: frame.size];
    NS_EXTRA(NSView, self)->_frameChangeDepth--;

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

        if (NS_EXTRA(NSView, self)->_postsNotificationOnBoundsChange)
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
    NS_EXTRA(NSView, self)->_postsNotificationOnFrameChange = flag;
}

- (void) setPostsBoundsChangedNotifications: (BOOL) flag {
    NS_EXTRA(NSView, self)->_postsNotificationOnBoundsChange = flag;
}

- (void) _setWindow: (NSWindow *) window {
    if (_window != window) {
        BOOL windowRecalulatesKeyViewLoop =
                [window autorecalculatesKeyViewLoop];
        if (windowRecalulatesKeyViewLoop)
            [self setNextKeyView: nil];

        [self viewWillMoveToWindow: window];

        _window = window;

        if (NS_EXTRA(NSView, self)->_layerContext && _window == nil) {
            [self _removeLayerFromSuperlayer];
        } else if (NS_EXTRA(NSView, self)->_layerContext) {
            [NS_EXTRA(NSView, self)->_layerContext setSubwindow: [_window _createSubWindowWithFrame: layerContextFrame(self)]];
            [self _updateLayerVisibility];
        } else if (_layer != nil && _window != nil) {
            [self _addLayerToSuperlayer];
        }

        [_subviews makeObjectsPerformSelector: _cmd withObject: window];
        NS_EXTRA(NSView, self)->_validTrackingAreas = NO;
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

    // Adding a view announces the move to the new superview first. A view
    // that already has a superview, this one included, is taken out of it
    // with -willRemoveSubview: and then added again, so the hooks run in the
    // same order for a move between superviews and for a re-add.
    // QUIRK: adding a view that is already a subview of this view
    // (-addSubview:, -addSubview:positioned:relativeTo:, -replaceSubview:with:
    // with such a view) runs all four hooks even when the order does not
    // change. Not documented. Evidence: black-box observation (tier 2) on
    // macOS 10.14.4 (x86_64 and i386); macOS 26.7.3 runs them only for
    // -addSubview: that changes the order and not for the positioned
    // variant, and the older behaviour is followed. Reorders done by
    // -sortSubviewsUsingFunction:context: and -setSubviews: run none.
    // Test: tests/appkit-view-subview-hooks.m
    [view viewWillMoveToSuperview: self];

    NSView *oldSuperview = [view superview];
    if (oldSuperview == self) {
        [self willRemoveSubview: view];
        // the index refers to the subviews before the view was taken out
        NSUInteger oldIndex = [_subviews indexOfObjectIdenticalTo: view];
        [_subviews removeObjectIdenticalTo: view];
        if (index != NSNotFound && oldIndex < (NSUInteger) index)
            index--;
    } else {
        if (oldSuperview != nil) {
            [oldSuperview setNeedsDisplayInRect: [view frame]];
            [view _removeFromSuperviewSendingMoveHooks: NO];
        }

        // QUIRK: the new superview (and with it the responder chain) is in
        // place before -viewWillMoveToWindow: and -viewDidMoveToWindow: run.
        // Not documented. Evidence: black-box observation (tier 2) on macOS
        // 26.7.3 and 10.14.4. Removal clears the superview before the window
        // callbacks in the same way.
        // Test: tests/appkit-view-window-callbacks-superview.m
        [view _setSuperview: self];
        [view _setWindow: _window];
    }

    if (index == NSNotFound)
        [_subviews addObject: view];
    else
        [_subviews insertObject: view atIndex: index];
    [view release];

    invalidateTransform(view);

    [self setNeedsDisplayInRect: [view frame]];

    [self didAddSubview: view];

    [view viewDidMoveToSuperview];

    if (NS_EXTRA(NSView, self)->_wantsLayer)
        [view setWantsLayer: YES];

    // A layer added to the superlayer goes to the end, and the layer of a view
    // that was only moved within its superview does not move at all.
    [self _synchronizeSublayerOrder];
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
    if (oldView == newView)
        return;

    NSUInteger index = [_subviews indexOfObjectIdenticalTo: oldView];

    // The new view is added at the position of the old one before the old
    // one is removed (this is the order of the hooks on macOS).
    [oldView retain];
    [self _insertSubview: newView atIndex: index];
    [oldView removeFromSuperview];
    [oldView release];
}

- (void) setSubviews: (NSArray *) array {
    // This method marks as needing display per doc.s

    NSArray *wanted = [[array copy] autorelease];

    // Views that are not in the new list are removed, the new ones are added
    // with the usual hooks.
    for (NSView *view in [[_subviews copy] autorelease]) {
        if ([wanted indexOfObjectIdenticalTo: view] == NSNotFound)
            [view removeFromSuperview];
    }

    NSMutableArray *ordered = [NSMutableArray arrayWithCapacity: [wanted count]];
    for (NSView *view in wanted) {
        if ([view superview] != self)
            [self addSubview: view];
        if ([ordered indexOfObjectIdenticalTo: view] == NSNotFound)
            [ordered addObject: view];
        [view setNeedsDisplay: YES];
    }

    // Subviews that stay are only put in the order of the list, without
    // hooks (macOS runs none for a reorder done through this method).
    if (![_subviews isEqualToArray: ordered]) {
        [_subviews setArray: ordered];
        [self _synchronizeSublayerOrder];
    }
}

- (void) sortSubviewsUsingFunction:
                 (NSComparisonResult (*)(id, id, void *)) compareFunction
                           context: (void *) context
{
    if (compareFunction == NULL || [_subviews count] < 2)
        return;

    [_subviews sortUsingFunction: compareFunction context: context];
    [self _synchronizeSublayerOrder];
    [self setNeedsDisplay: YES];
}

- (void) didAddSubview: (NSView *) subview {
    // Override hook; the default implementation does nothing.
}

- (void) willRemoveSubview: (NSView *) subview {
    // Override hook; the default implementation does nothing.
}

- (void) setAutoresizesSubviews: (BOOL) flag {
    NS_EXTRA(NSView, self)->_autoresizesSubviews = flag;
}

- (void) setAutoresizingMask: (NSAutoresizingMaskOptions) mask {
    NS_EXTRA(NSView, self)->_autoresizingMask = mask;
}

- (void) setFocusRingType: (NSFocusRingType) value {
    NS_EXTRA(NSView, self)->_focusRingType = value;
    [self setNeedsDisplay: YES];
}

- (void) setTag: (NSInteger) tag {
    NS_EXTRA(NSView, self)->_tag = tag;
}

- (void) _setPreviousKeyView: (NSView *) previous {
    NS_EXTRA(NSView, self)->_previousKeyView = previous;
}

- (void) setNextKeyView: (NSView *) next {
    if (next)
        [next _setPreviousKeyView: self];
    else
        [NS_EXTRA(NSView, self)->_nextKeyView _setPreviousKeyView: nil];

    NS_EXTRA(NSView, self)->_nextKeyView = next;
}

- (BOOL) acceptsFirstMouse: (NSEvent *) event {
    // Documented default: a click that activates the window isn't passed on.
    return NO;
}

// There are no touch devices on this platform, so no touches are ever
// delivered; the flags are stored as the documented (deprecated) properties.
- (BOOL) acceptsTouchEvents {
    return NS_EXTRA(NSView, self)->_acceptsTouchEvents;
}

- (void) setAcceptsTouchEvents: (BOOL) accepts {
    NS_EXTRA(NSView, self)->_acceptsTouchEvents = accepts;
}

- (BOOL) wantsRestingTouches {
    return NS_EXTRA(NSView, self)->_wantsRestingTouches;
}

- (void) setWantsRestingTouches: (BOOL) wants {
    NS_EXTRA(NSView, self)->_wantsRestingTouches = wants;
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
    [area _setFromTagAPI: YES];
    NSToolTipTag tag = [area _tag];
    [NS_EXTRA(NSView, self)->_trackingAreas addObject: area];
    [area release];

    [self _trackingAreasChanged];

    return tag;
}

// A tag that does not name an area of this view (it was removed, or was never
// issued) is ignored.
- (void) _removeAreaWithTag: (NSInteger) tag {
    NSMutableArray *areas = NS_EXTRA(NSView, self)->_trackingAreas;
    NSInteger count = [areas count];

    while (--count >= 0) {
        NSTrackingArea *area = [areas objectAtIndex: count];

        if ([area _isFromTagAPI] && [area _tag] == tag) {
            [areas removeObjectAtIndex: count];
            [self _trackingAreasChanged];
            break;
        }
    }
}

- (void) removeToolTip: (NSToolTipTag) tag {
    [self _removeAreaWithTag: tag];
}

- (void) removeAllToolTips {
    NSInteger count = [NS_EXTRA(NSView, self)->_trackingAreas count];

    while (--count >= 0) {
        if ([[NS_EXTRA(NSView, self)->_trackingAreas objectAtIndex: count] _isToolTip] == YES)
            [NS_EXTRA(NSView, self)->_trackingAreas removeObjectAtIndex: count];
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
    [NS_EXTRA(NSView, self)->_trackingAreas addObject: area];
    [area release];
    [cursorRect release];

    [self _trackingAreasChanged];
}

- (void) removeCursorRect: (NSRect) rect cursor: (NSCursor *) cursor {
    NSInteger count = [NS_EXTRA(NSView, self)->_trackingAreas count];

    while (--count >= 0) {
        NSTrackingArea *area = [NS_EXTRA(NSView, self)->_trackingAreas objectAtIndex: count];
        NSObject *candidate = [area owner];

        if ([area _isLegacy] == YES &&
            [candidate isKindOfClass: [NSCursorRect class]] == YES &&
            [(NSCursorRect *) candidate cursor] == cursor) {
            [NS_EXTRA(NSView, self)->_trackingAreas removeObjectAtIndex: count];
            break;
        }
    }

    [self _trackingAreasChanged];
}

- (void) discardCursorRects {
    NSInteger count = [NS_EXTRA(NSView, self)->_trackingAreas count];

    while (--count >= 0) {
        NSTrackingArea *area = [NS_EXTRA(NSView, self)->_trackingAreas objectAtIndex: count];

        if ([area _isLegacy] == YES &&
            ([area options] & NSTrackingCursorUpdate)) {
            [NS_EXTRA(NSView, self)->_trackingAreas removeObjectAtIndex: count];
        }
    }

    [[self subviews] makeObjectsPerformSelector: _cmd];

    [self _trackingAreasChanged];
}

- (void) resetCursorRects {
    // do nothing
}

- (void) _collectTrackingAreasForWindowInto: (NSMutableArray *) collector {
    if (NS_EXTRA(NSView, self)->_isHidden == NO) {
        NSUInteger i, count;

        if (!NS_EXTRA(NSView, self)->_validTrackingAreas) {
            /* We don't clear the tracking areas, they are managed by the view
             * with add/remove
             */
            [self updateTrackingAreas];
            NS_EXTRA(NSView, self)->_validTrackingAreas = YES;
        }

        count = [NS_EXTRA(NSView, self)->_trackingAreas count];
        for (i = 0; i < count; i++) {
            NSTrackingArea *area = [NS_EXTRA(NSView, self)->_trackingAreas objectAtIndex: i];
            NSRect rectOfInterest;

            rectOfInterest = NSIntersectionRect([area rect], [self bounds]);

            if (rectOfInterest.size.width > 0. &&
                rectOfInterest.size.height > 0.) {
                [area _setView: self];

                [area _setRectInWindow: [self convertRect: rectOfInterest
                                                   toView: nil]];

                [collector addObject: [NS_EXTRA(NSView, self)->_trackingAreas objectAtIndex: i]];
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

// A snapshot: -updateTrackingAreas overrides commonly walk the array while
// removing each area from the view.
- (NSArray *) trackingAreas {
    return [[NS_EXTRA(NSView, self)->_trackingAreas copy] autorelease];
}

- (void) _trackingAreasChanged {
    [[self window] _invalidateTrackingAreas];
}

- (void) addTrackingArea: (NSTrackingArea *) trackingArea {
    [NS_EXTRA(NSView, self)->_trackingAreas addObject: trackingArea];
    [self _trackingAreasChanged];
}

- (void) removeTrackingArea: (NSTrackingArea *) trackingArea {
    [NS_EXTRA(NSView, self)->_trackingAreas removeObjectIdenticalTo: trackingArea];
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
    [area _setFromTagAPI: YES];
    NSTrackingRectTag tag = [area _tag];
    [NS_EXTRA(NSView, self)->_trackingAreas addObject: area];
    [area release];

    [self _trackingAreasChanged];

    return tag;
}

- (void) removeTrackingRect: (NSTrackingRectTag) tag {
    [self _removeAreaWithTag: tag];
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
    [NS_EXTRA(NSView, self)->_draggedTypes release];
    NS_EXTRA(NSView, self)->_draggedTypes = types;
}

- (void) unregisterDraggedTypes {
    [NS_EXTRA(NSView, self)->_draggedTypes release];
    NS_EXTRA(NSView, self)->_draggedTypes = nil;
}

- (NSArray *) registeredDraggedTypes {
    return NS_EXTRA(NSView, self)->_draggedTypes;
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
    [self _removeFromSuperviewSendingMoveHooks: YES];
}

// With hooks the superview change is announced to the view itself, as
// -viewWillMoveToSuperview: nil and -viewDidMoveToSuperview. Adding the view
// to another superview announces its own move and passes NO.
- (void) _removeFromSuperviewSendingMoveHooks: (BOOL) moveHooks {
    [[self retain] autorelease];
    NSView *removeFrom = [_superview retain];
    moveHooks = moveHooks && removeFrom != nil;
    NSWindow *window = [[self window] retain];

    if (moveHooks)
        [self viewWillMoveToSuperview: nil];
    [removeFrom willRemoveSubview: self];

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
    if (moveHooks)
        [self viewDidMoveToSuperview];
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

// Tells this view and, depth first, its subviews that the window's backing
// properties changed.
- (void) _backingPropertiesDidChange {
    [self viewDidChangeBackingProperties];
    for (NSView *subview in [[[self subviews] copy] autorelease])
        [subview _backingPropertiesDidChange];
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
    // Subclasses return YES to keep a click from bringing the window forward.
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

    if (NS_EXTRA(NSView, self)->_autoresizingMask & NSViewMinXMargin) {
        if (NS_EXTRA(NSView, self)->_autoresizingMask & NSViewWidthSizable) {
            if (NS_EXTRA(NSView, self)->_autoresizingMask & NSViewMaxXMargin) {
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
        } else if (NS_EXTRA(NSView, self)->_autoresizingMask & NSViewMaxXMargin) {
            frame.origin.x += ((superFrame.size.width - oldSize.width) / 2);
            originChanged = YES;
        } else {
            frame.origin.x += superFrame.size.width - oldSize.width;
            originChanged = YES;
        }
    } else if (NS_EXTRA(NSView, self)->_autoresizingMask & NSViewWidthSizable) {
        if (NS_EXTRA(NSView, self)->_autoresizingMask & NSViewMaxXMargin)
            frame.size.width += ((superFrame.size.width - oldSize.width) / 2);
        else
            frame.size.width += superFrame.size.width - oldSize.width;
        sizeChanged = YES;
    } else if (NS_EXTRA(NSView, self)->_autoresizingMask & NSViewMaxXMargin) {
        // don't move or resize
    }

    if (NS_EXTRA(NSView, self)->_autoresizingMask & NSViewMinYMargin) {
        if (NS_EXTRA(NSView, self)->_autoresizingMask & NSViewHeightSizable) {
            if (NS_EXTRA(NSView, self)->_autoresizingMask & NSViewMaxYMargin) {
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
        } else if (NS_EXTRA(NSView, self)->_autoresizingMask & NSViewMaxYMargin) {
            frame.origin.y += ((superFrame.size.height - oldSize.height) / 2);
            originChanged = YES;
        } else {
            frame.origin.y += superFrame.size.height - oldSize.height;
            originChanged = YES;
        }
    } else if (NS_EXTRA(NSView, self)->_autoresizingMask & NSViewHeightSizable) {
        if (NS_EXTRA(NSView, self)->_autoresizingMask & NSViewMaxYMargin)
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
    return NS_EXTRA(NSView, self)->_inLiveResize;
}

- (BOOL) preservesContentDuringLiveResize {
    return NO;
}

- (NSRect) rectPreservedDuringLiveResize {
    // Nothing is preserved unless a subclass opts in.
    return NSZeroRect;
}

- (void) viewWillStartLiveResize {
    NS_EXTRA(NSView, self)->_inLiveResize = YES;
    [_subviews makeObjectsPerformSelector: _cmd];
}

- (void) viewDidEndLiveResize {
    NS_EXTRA(NSView, self)->_inLiveResize = NO;
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
    return NS_EXTRA(NSView, self)->_wantsLayer;
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
- (CGFloat) firstBaselineOffsetFromTop {
    return 0;
}

- (CGFloat) lastBaselineOffsetFromBottom {
    return 0;
}

- (CGFloat) baselineOffsetFromBottom {
    return [self lastBaselineOffsetFromBottom];
}

- (NSSize) fittingSize {
    return DarlingLayoutFittingSize(self);
}

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
    return NS_EXTRA(NSView, self)->_canDrawSubviewsIntoLayer;
}

- (void) setCanDrawSubviewsIntoLayer: (BOOL) value {
    NS_EXTRA(NSView, self)->_canDrawSubviewsIntoLayer = value;
}

- (NSTouchTypeMask) allowedTouchTypes {
    return NS_EXTRA(NSView, self)->_allowedTouchTypes;
}

- (void) setAllowedTouchTypes: (NSTouchTypeMask) value {
    NS_EXTRA(NSView, self)->_allowedTouchTypes = value;
}

- (CALayer *) makeBackingLayer {
    return [NSViewBackingLayer layer];
}

- (void) _removeLayerFromSuperlayer {
    [_layer removeFromSuperlayer];
    [NS_EXTRA(NSView, self)->_layerContext invalidate];
    [NS_EXTRA(NSView, self)->_layerContext release];
    NS_EXTRA(NSView, self)->_layerContext = nil;
}

// Native root-layer windows must follow the view tree as well as CALayer.
// The native windows of root layers are placed from the top of the platform window, so they must follow a
// window resize even when no view frame changed.
- (void) _updateLayerContextFrames {
    updateLayerContextFrames(self);
}

- (void) _updateLayerVisibility {
    BOOL hidden = [self isHiddenOrHasHiddenAncestor];
    [_layer setHidden: hidden];
    [NS_EXTRA(NSView, self)->_layerContext setHidden: hidden];
    for (NSView *child in _subviews)
        [child _updateLayerVisibility];
}

- (void) _createLayerContextIfNeeded {
    if (NS_EXTRA(NSView, self)->_layerContext == nil && [_superview layer] == nil && _window != nil) {
        NS_EXTRA(NSView, self)->_layerContext = [[CALayerContext alloc] initWithFrame: layerContextFrame(self)];
        [NS_EXTRA(NSView, self)->_layerContext setLayer: _layer];
        if (_window) {
            [NS_EXTRA(NSView, self)->_layerContext setSubwindow: [_window _createSubWindowWithFrame: layerContextFrame(self)]];
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
        if ([_layer superlayer] != superlayer || NS_EXTRA(NSView, self)->_layerContext != nil) {
            [self _removeLayerFromSuperlayer];
            [superlayer addSublayer: _layer];
        }
    } else {
        [self _createLayerContextIfNeeded];
    }
}

// The sublayers that belong to the subviews are kept in the order of the
// subviews, so that the view that is last in -subviews is drawn on top. Other
// sublayers of the view's layer (added by the application) keep their places.
- (void) _synchronizeSublayerOrder {
    if (_layer == nil)
        return;

    NSMutableArray *wanted = [NSMutableArray arrayWithCapacity: [_subviews count]];
    for (NSView *subview in _subviews) {
        CALayer *sublayer = [subview layer];
        if (sublayer != nil && [sublayer superlayer] == _layer)
            [wanted addObject: sublayer];
    }

    NSArray *current = [_layer sublayers];
    NSMutableArray *ordered = [[current mutableCopy] autorelease];
    NSUInteger next = 0;
    BOOL changed = NO;
    for (NSUInteger i = 0; i < [current count] && next < [wanted count]; i++) {
        if ([wanted indexOfObjectIdenticalTo: [current objectAtIndex: i]] == NSNotFound)
            continue;
        CALayer *sublayer = [wanted objectAtIndex: next++];
        if ([current objectAtIndex: i] != sublayer) {
            [ordered replaceObjectAtIndex: i withObject: sublayer];
            changed = YES;
        }
    }

    if (changed)
        [_layer setSublayers: ordered];
}

/*
  When turning off layering, we only turn off layers below us which did not want
  a layer Layers which did want a layer are not touched, nor are their children.
 */
- (void) _removeLayerBackedViewsFromTree {
    if (NS_EXTRA(NSView, self)->_wantsLayer) {
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
        [_layer setOpacity: NS_EXTRA(NSView, self)->_alphaValue];
        configureLayerGeometry(self);
    }

    [self _addLayerToSuperlayer];
    [self _updateLayerVisibility];

    [_subviews makeObjectsPerformSelector: _cmd];
}

- (void) setWantsLayer: (BOOL) value {
    if (!value) {
        if (NS_EXTRA(NSView, self)->_wantsLayer) {
            NS_EXTRA(NSView, self)->_wantsLayer = NO;
            [self _removeLayerBackedViewsFromTree];
        }
    } else {
        if (!NS_EXTRA(NSView, self)->_wantsLayer) {
            NS_EXTRA(NSView, self)->_wantsLayer = YES;
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
            if (NS_EXTRA(NSView, self)->_layerContext != nil)
                [NS_EXTRA(NSView, self)->_layerContext setLayer: _layer];
            else
                [self _createLayerContextIfNeeded];
        }

        [_subviews
                makeObjectsPerformSelector: @selector(_addLayerToSuperlayer)];
        [self _updateLayerVisibility];
    }
}

- (NSViewLayerContentsPlacement) layerContentsPlacement {
    return NS_EXTRA(NSView, self)->_layerContentsPlacement;
}

- (void) setLayerContentsPlacement: (NSViewLayerContentsPlacement) value {
    NS_EXTRA(NSView, self)->_layerContentsPlacement = value;
}

- (NSViewLayerContentsRedrawPolicy) layerContentsRedrawPolicy {
    return NS_EXTRA(NSView, self)->_layerContentsRedrawPolicy;
}

- (void) setLayerContentsRedrawPolicy: (NSViewLayerContentsRedrawPolicy) value {
    NS_EXTRA(NSView, self)->_layerContentsRedrawPolicy = value;
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
    return NS_EXTRA(NSView, self)->_contentFilters;
}

- (void) setContentFilters: (NSArray *) filters {
    filters = [filters copy];
    [NS_EXTRA(NSView, self)->_contentFilters release];
    NS_EXTRA(NSView, self)->_contentFilters = filters;
}

- (CIFilter *) compositingFilter {
    return NS_EXTRA(NSView, self)->_compositingFilter;
}

- (void) setCompositingFilter: (CIFilter *) filter {
    filter = [filter copy];
    [NS_EXTRA(NSView, self)->_compositingFilter release];
    NS_EXTRA(NSView, self)->_compositingFilter = filter;
}

- (NSShadow *) shadow {
    return NS_EXTRA(NSView, self)->_shadow;
}

- (void) setShadow: (NSShadow *) shadow {
    shadow = [shadow copy];
    [NS_EXTRA(NSView, self)->_shadow release];
    NS_EXTRA(NSView, self)->_shadow = shadow;
}

- (BOOL) needsDisplay {
    return NS_EXTRA(NSView, self)->_needsDisplay;
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

    if (NS_EXTRA(NSView, self)->_invalidRectCount == 0)
        result = [self visibleRect];
    else {
        int i;

        result = NS_EXTRA(NSView, self)->_invalidRects[0];

        for (i = 1; i < NS_EXTRA(NSView, self)->_invalidRectCount; i++)
            result = NSUnionRect(result, NS_EXTRA(NSView, self)->_invalidRects[i]);
    }

    return result;
}

static void removeRectFromInvalidInVisibleRect(NSView *self, NSRect rect,
                                               NSRect visibleRect)
{
    int count = NS_EXTRA(NSView, self)->_invalidRectCount;

    while (--count >= 0) {
        NS_EXTRA(NSView, self)->_invalidRects[count] =
                NSIntersectionRect(NS_EXTRA(NSView, self)->_invalidRects[count], visibleRect);

        if (NSContainsRect(rect, NS_EXTRA(NSView, self)->_invalidRects[count])) {
            int i;

            NS_EXTRA(NSView, self)->_invalidRectCount--;
            for (i = count; i < NS_EXTRA(NSView, self)->_invalidRectCount; i++)
                NS_EXTRA(NSView, self)->_invalidRects[i] = NS_EXTRA(NSView, self)->_invalidRects[i + 1];
        }
    }
    if (NS_EXTRA(NSView, self)->_invalidRectCount == 0) {
        if (NS_EXTRA(NSView, self)->_invalidRects != NULL) {
            NSZoneFree(NULL, NS_EXTRA(NSView, self)->_invalidRects);
            NS_EXTRA(NSView, self)->_invalidRects = NULL;
            // We killed the last invalidRect - we're clean now
            NS_EXTRA(NSView, self)->_needsDisplay = NO;
        } else if (NSContainsRect(rect, visibleRect)) {
            // We had no invalidRect, which means the full visibleRect was dirty
            // We're now clean
            NS_EXTRA(NSView, self)->_needsDisplay = NO;
        }
    }
}

static void clearRectsBeingRedrawn(NSView *self) {
    if (NS_EXTRA(NSView, self)->_rectsBeingRedrawn) {
        NSZoneFree(NULL, NS_EXTRA(NSView, self)->_rectsBeingRedrawn);
        NS_EXTRA(NSView, self)->_rectsBeingRedrawn = NULL;
        NS_EXTRA(NSView, self)->_rectsBeingRedrawnCount = 0;
    }
}

static void clearInvalidRects(NSView *self) {
    if (NS_EXTRA(NSView, self)->_invalidRects != NULL)
        NSZoneFree(NULL, NS_EXTRA(NSView, self)->_invalidRects);
    NS_EXTRA(NSView, self)->_invalidRects = NULL;
    NS_EXTRA(NSView, self)->_invalidRectCount = 0;
    clearRectsBeingRedrawn(self);
}

static void clearNeedsDisplay(NSView *self) {
    if ([NSGraphicsContext inQuartzDebugMode]) {
        return;
    }
    clearInvalidRects(self);
    NS_EXTRA(NSView, self)->_needsDisplay = NO;
}

- (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)selector {
    _NSViewDisplayLinkTarget *proxy = [[_NSViewDisplayLinkTarget alloc]
        initWithView:self target:target selector:selector];
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:proxy selector:@selector(frame:)];
    // The link follows the refresh rate of the screen the window is on; the
    // proxy only holds the view weakly and is owned by the link.
    [link _setRefreshRateProvider:^double {
        return [proxy refreshRate];
    }];
    [proxy release];
    return link;
}

- (void) setNeedsDisplay: (BOOL) flag {
    NS_EXTRA(NSView, self)->_needsDisplay = flag;

    // We removed them for YES to indicate entire view, and NO for obvious
    // reasons
    clearInvalidRects(self);

    if (NS_EXTRA(NSView, self)->_needsDisplay)
        [[self window] setViewsNeedDisplay: YES];
}

- (void) setNeedsDisplayInRect: (NSRect) rect {
    // We only add rects if its not the entire view
    if (!NS_EXTRA(NSView, self)->_needsDisplay || NS_EXTRA(NSView, self)->_invalidRects != NULL) {
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
            NS_EXTRA(NSView, self)->_invalidRectCount++;
            NS_EXTRA(NSView, self)->_invalidRects = NSZoneRealloc(NULL, NS_EXTRA(NSView, self)->_invalidRects,
                                          sizeof(NSRect) * NS_EXTRA(NSView, self)->_invalidRectCount);
            NS_EXTRA(NSView, self)->_invalidRects[NS_EXTRA(NSView, self)->_invalidRectCount - 1] = rect;
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

    NS_EXTRA(NSView, self)->_needsDisplay = YES;
    [[self window] setViewsNeedDisplay: YES];
}

// The ring is drawn by the superview, around the mask, so the area to redraw is the rectangle in the superview
// widened by the reach of the ring.
- (void) setKeyboardFocusRingNeedsDisplayInRect: (NSRect) rect {
    NSView *superview = [self superview];

    if (superview == nil)
        return;
    [superview setNeedsDisplayInRect: NSInsetRect([self convertRect: rect toView: superview], -4, -4)];
}

- (NSBezierPath *) _focusRingShape {
    return nil;
}

// A change of the keyboard focus to or from this view (or its field editor): redraw its ring, which is gone from
// the mask bounds once the view has lost the focus.
- (void) _focusRingStateChanged {
    NSRect mask = [self focusRingMaskBounds];

    [self setKeyboardFocusRingNeedsDisplayInRect: NSIsEmptyRect(mask) ? [self bounds] : mask];
}

+ (NSView *) _focusRingViewForResponder: (NSResponder *) responder {
    return focusRingViewForResponder(responder);
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
    return NS_EXTRA(NSView, self)->_canDrawConcurrently;
}

- (void) viewWillDraw {
    [_subviews makeObjectsPerformSelector: _cmd];
}

- (void) setCanDrawConcurrently: (BOOL) canDraw {
    NS_EXTRA(NSView, self)->_canDrawConcurrently = canDraw;
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

    if (NSIntersectsRect(rect, NS_EXTRA(NSView, self)->_visibleRect)) {
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
    *rects = NS_EXTRA(NSView, self)->_rectsBeingRedrawn;
    *count = NS_EXTRA(NSView, self)->_rectsBeingRedrawnCount;

    if (NS_EXTRA(NSView, self)->_rectsBeingRedrawn == NULL) {
        NSView *opaqueAncestor = [self opaqueAncestor];
        if (opaqueAncestor != self) {
            // Ask our opaque ancestor what to draw. opaqueAncestor is nil when
            // nothing up the chain is opaque; a message to nil fills in nothing.
            const NSRect *ancestorRects = NULL;
            NSInteger ancestorRectsCount = 0;
            [opaqueAncestor getRectsBeingDrawn: &ancestorRects
                                         count: &ancestorRectsCount];
            NS_EXTRA(NSView, self)->_rectsBeingRedrawnCount = ancestorRects ? ancestorRectsCount : 0;
            if (NS_EXTRA(NSView, self)->_rectsBeingRedrawnCount) {
                NS_EXTRA(NSView, self)->_rectsBeingRedrawn = NSZoneCalloc(NULL, NS_EXTRA(NSView, self)->_rectsBeingRedrawnCount,
                                                  sizeof(NSRect));
                int rectsCount = 0;
                for (int i = 0; i < NS_EXTRA(NSView, self)->_rectsBeingRedrawnCount; ++i) {
                    NSRect r = [opaqueAncestor convertRect: ancestorRects[i]
                                                    toView: self];
                    // No need for the rects that are outside of the visibleRect
                    if (NSIntersectsRect(r, NS_EXTRA(NSView, self)->_visibleRect)) {
                        NS_EXTRA(NSView, self)->_rectsBeingRedrawn[rectsCount++] = r;
                    }
                }
                *rects = NS_EXTRA(NSView, self)->_rectsBeingRedrawn;
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
                if (ancestorRectsCount || NS_EXTRA(NSView, self)->_invalidRectCount) {
                    NS_EXTRA(NSView, self)->_rectsBeingRedrawn = NSZoneCalloc(
                            NULL, NS_EXTRA(NSView, self)->_invalidRectCount + ancestorRectsCount,
                            sizeof(NSRect));
                    NSInteger rectsCount = 0;
                    for (int i = 0; i < ancestorRectsCount; ++i) {
                        NSRect r = [opaqueAncestor convertRect: ancestorRects[i]
                                                        toView: self];
                        // No need for the rects that are outside of the
                        // visibleRect
                        if (NSIntersectsRect(r, NS_EXTRA(NSView, self)->_visibleRect)) {
                            NS_EXTRA(NSView, self)->_rectsBeingRedrawn[rectsCount++] = r;
                        }
                    }
                    for (int i = 0; i < NS_EXTRA(NSView, self)->_invalidRectCount; ++i) {
                        NS_EXTRA(NSView, self)->_rectsBeingRedrawn[rectsCount++] = NS_EXTRA(NSView, self)->_invalidRects[i];
                    }
                    NS_EXTRA(NSView, self)->_rectsBeingRedrawnCount = rectsCount;
                    *rects = NS_EXTRA(NSView, self)->_rectsBeingRedrawn;
                    *count = NS_EXTRA(NSView, self)->_rectsBeingRedrawnCount;
                }
            }
        }
    }
    // We had no info and no opaque ancestor gave us any useful rect - just use
    // our invalid rects
    if (*rects == NULL) {
        if (NS_EXTRA(NSView, self)->_invalidRects == NULL) {
            if (NS_EXTRA(NSView, self)->_needsDisplay) {
                *rects = &NS_EXTRA(NSView, self)->_visibleRect;
                *count = 1;
            }
        } else {
            *rects = NS_EXTRA(NSView, self)->_invalidRects;
            *count = NS_EXTRA(NSView, self)->_invalidRectCount;
        }
    }
}

- (void) getRectsExposedDuringLiveResize: (NSRect) rects
                                   count: (NSInteger *) count
{
    NSUnimplementedMethod();
}

- (BOOL) shouldDrawColor {
    // Documented default: views draw in colour, printing to a black and white
    // device is the only case that turns it off.
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
            if (_layer != nil && [self wantsUpdateLayer]) {
                [self updateLayer];
                // A custom backing layer may implement -display (e.g. a Metal
                // blit layer). View invalidation must also invalidate that layer.
                [_layer setNeedsDisplay];
            }
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

        if (anySubviewShowsFocusRing(self)) {
            [self lockFocus];
            CGContextRef port = [[NSGraphicsContext currentContext] graphicsPort];

            CGContextClipToRect(port, rect);
            drawSubviewFocusRings(self, port);
            [self unlockFocus];
        }
    }

    [NS_EXTRA(NSView, self)->_layerContext render];

    // Don't do anything to interfere with what will be drawn in non-debug mode
    if ([NSGraphicsContext inQuartzDebugMode] == NO) {
        removeRectFromInvalidInVisibleRect(self, rect, visibleRect);

        // Rects being drawn are only valid while we redraw
        clearRectsBeingRedrawn(self);
    }

    if (shouldFlush) {
        [NS_EXTRA(NSView, self)->_layerContext flush];

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
    [NS_EXTRA(NSView, self)->_menu release];
    NS_EXTRA(NSView, self)->_menu = menu;
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
    return NS_EXTRA(NSView, self)->_draggedTypes;
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
    return NS_EXTRA(NSView, self)->_animations;
}

- animationForKey: (NSString *) key {
    return [NS_EXTRA(NSView, self)->_animations objectForKey: key];
}

- (void) setAnimations: (NSDictionary *) dictionary {
    dictionary = [dictionary copy];
    [NS_EXTRA(NSView, self)->_animations release];
    NS_EXTRA(NSView, self)->_animations = dictionary;
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
    NS_EXTRA(NSView, self)->_horizontalContentHuggingPriority = NSLayoutPriorityDefaultLow;
    NS_EXTRA(NSView, self)->_verticalContentHuggingPriority = NSLayoutPriorityDefaultLow;
    NS_EXTRA(NSView, self)->_horizontalContentCompressionResistancePriority = NSLayoutPriorityDefaultHigh;
    NS_EXTRA(NSView, self)->_verticalContentCompressionResistancePriority = NSLayoutPriorityDefaultHigh;
}

- (NSLayoutPriority) contentHuggingPriorityForOrientation: (NSLayoutConstraintOrientation) orientation {
    if (orientation == NSLayoutConstraintOrientationHorizontal) {
        return NS_EXTRA(NSView, self)->_horizontalContentHuggingPriority;
    } else {
        return NS_EXTRA(NSView, self)->_verticalContentHuggingPriority;
    }
}

- (void) setContentHuggingPriority: (NSLayoutPriority) contentHuggingPriority forOrientation: (NSLayoutConstraintOrientation) orientation {
    if (orientation == NSLayoutConstraintOrientationHorizontal) {
        NS_EXTRA(NSView, self)->_horizontalContentHuggingPriority = contentHuggingPriority;
    } else {
        NS_EXTRA(NSView, self)->_verticalContentHuggingPriority = contentHuggingPriority;
    }
}

- (NSLayoutPriority) contentCompressionResistancePriorityForOrientation: (NSLayoutConstraintOrientation) orientation {
    if (orientation == NSLayoutConstraintOrientationHorizontal) {
        return NS_EXTRA(NSView, self)->_horizontalContentCompressionResistancePriority;
    } else {
        return NS_EXTRA(NSView, self)->_verticalContentCompressionResistancePriority;
    }
}

- (void) setContentCompressionResistancePriority: (NSLayoutPriority) contentCompressionResistancePriority forOrientation: (NSLayoutConstraintOrientation) orientation {
    if (orientation == NSLayoutConstraintOrientationHorizontal) {
        NS_EXTRA(NSView, self)->_horizontalContentCompressionResistancePriority = contentCompressionResistancePriority;
    } else {
        NS_EXTRA(NSView, self)->_verticalContentCompressionResistancePriority = contentCompressionResistancePriority;
    }
}

- (NSSize) intrinsicContentSize {
    return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric);
}

// What the constraint solver reads as the view's intrinsic size. It is the public size unless a view
// class has a size that is known to the layout only (NSTextField: wrapped text height).
- (NSSize) _intrinsicContentSizeForLayout {
    return [self intrinsicContentSize];
}

- (NSUserInterfaceLayoutDirection) userInterfaceLayoutDirection {
    return NS_EXTRA(NSView, self)->_hasExplicitUserInterfaceLayoutDirection
                   ? NS_EXTRA(NSView, self)->_userInterfaceLayoutDirection
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
    NS_EXTRA(NSView, self)->_hasExplicitUserInterfaceLayoutDirection = YES;
    if (NS_EXTRA(NSView, self)->_userInterfaceLayoutDirection == direction)
        return;
    NS_EXTRA(NSView, self)->_userInterfaceLayoutDirection = direction;
    [self setNeedsDisplay: YES];
}

- (void) invalidateIntrinsicContentSize {
    // A view that is laid out with constraints has its intrinsic size taken into the layout when the
    // constraints are updated, so it is queued for an update; the next layout pass reads the size again.
    // QUIRK: a view whose autoresizing mask is translated into constraints is not queued, and
    // -needsLayout of the view and its superview does not change. Not documented. Evidence: black-box
    // observation on macOS 26.7.3 and 10.14.4 (tier 2, MAC-EVIDENCE V619).
    // Test: tests/appkit-view-invalidate-intrinsic-size.m (flags after invalidation)
    if (![self translatesAutoresizingMaskIntoConstraints]) {
        NS_EXTRA(NSView, self)->_needsUpdateConstraints = YES;
        [[self window] setViewsNeedDisplay: YES];
    }
    [[self superview] _subviewIntrinsicContentSizeDidChange: self];
}

- (void) _subviewIntrinsicContentSizeDidChange: (NSView *) subview {
}

- (NSArray *) constraints {
    return NS_EXTRA(NSView, self)->_constraints ? [[NS_EXTRA(NSView, self)->_constraints copy] autorelease] : [NSArray array];
}

- (void) addConstraint: (NSLayoutConstraint *) constraint {
    if ([NS_EXTRA(NSView, self)->_constraints containsObject: constraint])
        return;
    if (NS_EXTRA(NSView, self)->_constraints == nil)
        NS_EXTRA(NSView, self)->_constraints = [[NSMutableArray alloc] init];
    [NS_EXTRA(NSView, self)->_constraints addObject: constraint];
    [constraint _attachToOwner: self];
    [self setNeedsUpdateConstraints: YES];
}

- (void) addConstraints: (NSArray *) constraints {
    for (NSLayoutConstraint *constraint in constraints)
        [self addConstraint: constraint];
}

- (void) removeConstraint: (NSLayoutConstraint *) constraint {
    if (![NS_EXTRA(NSView, self)->_constraints containsObject: constraint])
        return;
    // Keep it alive until the owner link is cleared.
    [[constraint retain] autorelease];
    [NS_EXTRA(NSView, self)->_constraints removeObject: constraint];
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
    return NS_EXTRA(NSView, self)->_gestureRecognizers != nil ? [[NS_EXTRA(NSView, self)->_gestureRecognizers copy] autorelease]
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
    if (NS_EXTRA(NSView, self)->_gestureRecognizers == nil)
        NS_EXTRA(NSView, self)->_gestureRecognizers = [[NSMutableArray alloc] init];
    [NS_EXTRA(NSView, self)->_gestureRecognizers addObject: recognizer];
    [recognizer _setView: self];
}

- (void) removeGestureRecognizer: (NSGestureRecognizer *) recognizer {
    if ([recognizer view] != self)
        return;
    [recognizer _setView: nil];
    [NS_EXTRA(NSView, self)->_gestureRecognizers removeObjectIdenticalTo: recognizer];
}

@end

@implementation NSView (NSViewHooks)

- (void) prepareContentInRect: (NSRect) rect {
    // The recommended area is simply adopted.
    [self setPreparedContentRect: rect];
}

+ (BOOL) isCompatibleWithResponsiveScrolling {
    return YES;
}

- (NSRect) rectForSmartMagnificationAtPoint: (NSPoint) location
                                     inRect: (NSRect) visibleRect
{
    // Documented default: no suggestion, which makes the scroll view fall
    // back to its own smart magnification.
    return NSZeroRect;
}

- (BOOL) allowsVibrancy {
    return NO;
}

- (void) noteFocusRingMaskChanged {
    // Only a view that is drawing a ring has anything to redraw.
    if (focusRingViewForResponder([[self window] firstResponder]) != self)
        return;

    [self _focusRingStateChanged];
}

- (void) willOpenMenu: (NSMenu *) menu withEvent: (NSEvent *) event {
    // Notification hook; the default implementation does nothing.
}

- (void) didCloseMenu: (NSMenu *) menu withEvent: (NSEvent *) event {
    // Notification hook; the default implementation does nothing.
}

@end

@implementation NSView (NSViewLayerGeometry)

- (BOOL) layerUsesCoreImageFilters {
    return NS_EXTRA(NSView, self)->_layerUsesCoreImageFilters;
}

- (void) setLayerUsesCoreImageFilters: (BOOL) flag {
    NS_EXTRA(NSView, self)->_layerUsesCoreImageFilters = flag;
}

// The layer's y axis points up, so a flipped view's y axis is mirrored within
// its bounds to get to layer coordinates (and back, which is the same
// mirroring).
// QUIRK: macOS 10.14 mirrors like this; macOS 26 returns the value unchanged
// for a layer-backed flipped view. We follow the older behaviour, as the
// older platform is the wider one. Evidence: black-box observation on macOS
// 10.14.4 and 26.7.3 (tier 2). Test: appkit-view-geometry-api.
- (NSPoint) _layerPoint: (NSPoint) point {
    if ([self layer] == nil || ![self isFlipped])
        return point;
    NSRect bounds = [self bounds];
    point.y = NSMinY(bounds) + NSMaxY(bounds) - point.y;
    return point;
}

- (NSPoint) convertPointToLayer: (NSPoint) point {
    return [self _layerPoint: point];
}

- (NSPoint) convertPointFromLayer: (NSPoint) point {
    return [self _layerPoint: point];
}

- (NSSize) convertSizeToLayer: (NSSize) size {
    return size;
}

- (NSSize) convertSizeFromLayer: (NSSize) size {
    return size;
}

- (NSRect) convertRectToLayer: (NSRect) rect {
    if ([self layer] == nil || ![self isFlipped])
        return rect;
    NSRect bounds = [self bounds];
    rect.origin.y = NSMinY(bounds) + NSMaxY(bounds) - NSMaxY(rect);
    return rect;
}

- (NSRect) convertRectFromLayer: (NSRect) rect {
    return [self convertRectToLayer: rect];
}

@end

@implementation NSView (NSViewSafeAreas)

- (BOOL) prefersCompactControlSizeMetrics {
    return NS_EXTRA(NSView, self)->_prefersCompactControlSizeMetrics;
}

- (void) setPrefersCompactControlSizeMetrics: (BOOL) flag {
    NS_EXTRA(NSView, self)->_prefersCompactControlSizeMetrics = flag;
}

- (NSEdgeInsets) additionalSafeAreaInsets {
    return NS_EXTRA(NSView, self)->_additionalSafeAreaInsets;
}

- (void) setAdditionalSafeAreaInsets: (NSEdgeInsets) insets {
    NS_EXTRA(NSView, self)->_additionalSafeAreaInsets = insets;
}

- (NSEdgeInsets) safeAreaInsets {
    // No screen furniture overlaps views here, so only the additional
    // insets remain.
    return [self additionalSafeAreaInsets];
}

- (NSRect) safeAreaRect {
    NSRect rect = [self bounds];
    NSEdgeInsets insets = [self safeAreaInsets];
    rect.origin.x += insets.left;
    rect.size.width -= insets.left + insets.right;
    // The insets are given from the visual top/bottom: with a flipped view
    // the top is at the low y end.
    if ([self isFlipped]) {
        rect.origin.y += insets.top;
    } else {
        rect.origin.y += insets.bottom;
    }
    rect.size.height -= insets.top + insets.bottom;
    return rect;
}

@end

@implementation NSView (NSViewLayoutState)

- (BOOL) needsLayout {
    return NS_EXTRA(NSView, self)->_needsLayout;
}

- (void) setNeedsLayout: (BOOL) flag {
    NS_EXTRA(NSView, self)->_needsLayout = flag;
}

- (BOOL) needsUpdateConstraints {
    return NS_EXTRA(NSView, self)->_needsUpdateConstraints;
}

- (void) setNeedsUpdateConstraints: (BOOL) flag {
    NS_EXTRA(NSView, self)->_needsUpdateConstraints = flag;
    if (flag) {
        NS_EXTRA(NSView, self)->_needsLayout = YES;
        [[self window] setViewsNeedDisplay: YES];
    }
}

- (BOOL) clipsToBounds {
    return NS_EXTRA(NSView, self)->_clipsToBounds;
}

- (void) setClipsToBounds: (BOOL) flag {
    NS_EXTRA(NSView, self)->_clipsToBounds = flag;
}

- (NSRect) preparedContentRect {
    return NS_EXTRA(NSView, self)->_hasPreparedContentRect ? NS_EXTRA(NSView, self)->_preparedContentRect : [self visibleRect];
}

- (void) setPreparedContentRect: (NSRect) rect {
    NS_EXTRA(NSView, self)->_preparedContentRect = rect;
    NS_EXTRA(NSView, self)->_hasPreparedContentRect = YES;
}

- (void) updateConstraints {
    NS_EXTRA(NSView, self)->_needsUpdateConstraints = NO;
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
    if (NS_EXTRA(NSView, self)->_needsUpdateConstraints) {
        NS_EXTRA(NSView, self)->_needsUpdateConstraints = NO;
        [self updateConstraints];
    }
}

- (void) layout {
    NS_EXTRA(NSView, self)->_needsLayout = NO;
}

- (void) _layoutSubtreeAfterUpdatingConstraints {
    if (NS_EXTRA(NSView, self)->_needsLayout)
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

- (BOOL) _subtreeNeedsUpdateConstraints {
    if (NS_EXTRA(NSView, self)->_needsUpdateConstraints)
        return YES;
    for (NSView *child in _subviews) {
        if ([child _subtreeNeedsUpdateConstraints])
            return YES;
    }
    return NO;
}

// A pass can invalidate constraints: a view's -layout may change what its intrinsic size depends on
// (a wrapping label setting its preferredMaxLayoutWidth from its new width is the usual case). The
// passes then repeat until nothing is invalidated, so the sizes that result from the last layout
// are applied. The count is bounded so that views that keep invalidating each other cannot hang.
- (void) layoutSubtreeIfNeeded {
    for (int pass = 0; pass < 10; ++pass) {
        // Finish the update phase for the whole subtree before laying out any view.
        [self updateConstraintsForSubtreeIfNeeded];
        DarlingLayoutSubtree(self);
        [self _layoutSubtreeAfterUpdatingConstraints];
        if (![self _subtreeNeedsUpdateConstraints])
            break;
    }
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

- (NSLayoutYAxisAnchor *) firstBaselineAnchor {
    return anchorForView(self, [NSLayoutYAxisAnchor class], NSLayoutAttributeFirstBaseline);
}

- (NSLayoutYAxisAnchor *) lastBaselineAnchor {
    return anchorForView(self, [NSLayoutYAxisAnchor class], NSLayoutAttributeLastBaseline);
}

- (NSLayoutYAxisAnchor *) centerYAnchor {
    return anchorForView(self, [NSLayoutYAxisAnchor class], NSLayoutAttributeCenterY);
}

@end

@implementation NSView (NSViewEffectiveAppearance)

+ (NSSet *) keyPathsForValuesAffectingEffectiveAppearance {
    return [NSSet setWithObject: @"appearance"];
}

- (NSAppearance *) effectiveAppearance {
    if (NS_EXTRA(NSView, self)->_appearance != nil)
        return NS_EXTRA(NSView, self)->_appearance;
    if (_superview != nil)
        return [_superview effectiveAppearance];
    return [NSAppearance currentAppearance];
}

@end
