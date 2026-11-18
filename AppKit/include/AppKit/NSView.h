/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>
                 2010 Markus Hitter <mah@jump-ing.de>

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

// Reviewed for API completeness against 10.6.

#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/AppKitExport.h>
#import <AppKit/NSAnimation.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSResponder.h>
#import <AppKit/NSUserInterfaceItemIdentification.h>
#import <ApplicationServices/ApplicationServices.h>
#import <AppKit/NSUserInterfaceItemIdentification.h>
#import <AppKit/NSLayoutConstraint.h>
#import <AppKit/NSAppearance.h>
#import <AppKit/NSTouch.h>
#import <AppKit/NSUserInterfaceLayoutDirection.h>

@class NSLayoutConstraint;

NS_ASSUME_NONNULL_BEGIN

@class CADisplayLink, NSBezierPath, NSWindow, NSMenu, NSMenuItem, NSCursor, NSClipView, NSPasteboard,
        NSTextInputContext, NSImage, NSBitmapImageRep, NSScrollView,
        NSTrackingArea, NSShadow, NSScreen, CALayer, CIFilter, CALayerContext, NSView,
        NSLayoutGuide, NSGestureRecognizer, NSLayoutDimension, NSLayoutXAxisAnchor, NSLayoutYAxisAnchor;

// See Cocoa Event Handling Guide : Using Tracking-Area Objects : Compatibility
// Issues
typedef NSInteger NSTrackingRectTag NS_SWIFT_NAME(NSView.TrackingRectTag);
typedef NSInteger NSToolTipTag NS_SWIFT_NAME(NSView.ToolTipTag);
typedef NSString *NSViewFullScreenModeOptionKey NS_STRING_ENUM;

typedef NS_OPTIONS(NSUInteger, NSAutoresizingMaskOptions) {
    NSViewNotSizable = 0x00,
    NSViewMinXMargin = 0x01,
    NSViewWidthSizable = 0x02,
    NSViewMaxXMargin = 0x04,
    NSViewMinYMargin = 0x08,
    NSViewHeightSizable = 0x10,
    NSViewMaxYMargin = 0x20
};

typedef NS_ENUM(NSUInteger, NSBorderType) {
    NSNoBorder,
    NSLineBorder,
    NSBezelBorder,
    NSGrooveBorder
};

typedef NS_ENUM(NSInteger, NSViewLayerContentsPlacement) {
    NSViewLayerContentsPlacementScaleAxesIndependently = 0,
    NSViewLayerContentsPlacementScaleProportionallyToFit,
    NSViewLayerContentsPlacementScaleProportionallyToFill,
    NSViewLayerContentsPlacementCenter,
    NSViewLayerContentsPlacementTop,
    NSViewLayerContentsPlacementTopRight,
    NSViewLayerContentsPlacementRight,
    NSViewLayerContentsPlacementBottomRight,
    NSViewLayerContentsPlacementBottom,
    NSViewLayerContentsPlacementBottomLeft,
    NSViewLayerContentsPlacementLeft,
    NSViewLayerContentsPlacementTopLeft
} NS_SWIFT_NAME(NSView.LayerContentsPlacement);

typedef NS_ENUM(NSInteger, NSViewLayerContentsRedrawPolicy) {
    NSViewLayerContentsRedrawNever = 0,
    NSViewLayerContentsRedrawOnSetNeedsDisplay,
    NSViewLayerContentsRedrawDuringViewResize,
    NSViewLayerContentsRedrawBeforeViewResize
} NS_SWIFT_NAME(NSView.LayerContentsRedrawPolicy);

APPKIT_EXPORT const NSNotificationName NSViewFrameDidChangeNotification;
APPKIT_EXPORT const NSNotificationName NSViewBoundsDidChangeNotification;
APPKIT_EXPORT const NSNotificationName NSViewFocusDidChangeNotification;
APPKIT_EXPORT const NSNotificationName NSViewGlobalFrameDidChangeNotification;

APPKIT_EXPORT const NSViewFullScreenModeOptionKey NSFullScreenModeApplicationPresentationOptions;
APPKIT_EXPORT const NSViewFullScreenModeOptionKey NSFullScreenModeAllScreens;

// Legacy ObjC ABI (i386): instance size must stay 0x50, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSView : NSResponder <NSAnimatablePropertyContainer, NSUserInterfaceItemIdentification, NSAppearanceCustomization> {
    NSRect _frame;
    NSRect _bounds;
    NSView *_superview;
    NSMutableArray *_subviews;
    NSWindow *_window;
    NS_LEGACY_IVAR_PAD(_NSViewReserved1, 8)
    CALayer *_layer;
    NS_LEGACY_IVAR_PAD(_NSViewReserved2, 12)
    NS_EXTRA_IVARS_BEGIN(NSView)
        NSMenu *_menu;
        NSView *_nextKeyView;
        NSView *_previousKeyView;
        BOOL _isHidden;
        CGFloat _alphaValue;
        BOOL _postsNotificationOnFrameChange;
        BOOL _postsNotificationOnBoundsChange;
        BOOL _autoresizesSubviews;
        BOOL _inLiveResize;
        NSAutoresizingMaskOptions _autoresizingMask;
        NSInteger _tag;
        NSArray *_draggedTypes;
        NSMutableArray *_trackingAreas;
        BOOL _needsDisplay;
        NSUInteger _invalidRectCount;
        NSRect *_invalidRects;
        NSRect *_rectsBeingRedrawn;
        NSInteger _rectsBeingRedrawnCount;
        CGFloat _frameRotation;
        CGFloat _boundsRotation;
        BOOL _translatesAutoresizingMaskIntoConstraints;

        BOOL _validTrackingAreas;
        BOOL _validTransforms;
        CGAffineTransform _transformFromWindow;
        CGAffineTransform _transformToWindow;
        CGAffineTransform _transformToLayer;
        NSRect _visibleRect;
        NSFocusRingType _focusRingType;

        BOOL _wantsLayer;
        NSArray *_contentFilters;
        CIFilter *_compositingFilter;
        NSViewLayerContentsPlacement _layerContentsPlacement;
        NSViewLayerContentsRedrawPolicy _layerContentsRedrawPolicy;
        NSShadow *_shadow;
        NSDictionary *_animations;

        CALayerContext *_layerContext;
        id __remove;
        NSUserInterfaceItemIdentifier _identifier;
        NSLayoutPriority _horizontalContentHuggingPriority;
        BOOL _wantsBestResolutionOpenGLSurface;
        BOOL _wantsBestResolutionOpenGLSurfaceSet;
        NSLayoutPriority _verticalContentHuggingPriority;
        NSLayoutPriority _horizontalContentCompressionResistancePriority;
        NSLayoutPriority _verticalContentCompressionResistancePriority;
        NSString *_accessibilityTitle;

        NSAppearance *_appearance;
        NSTouchTypeMask _allowedTouchTypes;
        BOOL _canDrawSubviewsIntoLayer;
        BOOL _hasExplicitUserInterfaceLayoutDirection;
        NSUserInterfaceLayoutDirection _userInterfaceLayoutDirection;
        int _frameChangeDepth;
        BOOL _canDrawConcurrently;
        NSMutableArray *_gestureRecognizers;

        NSMutableArray *_constraints;

        BOOL _needsLayout;
        BOOL _needsUpdateConstraints;
        BOOL _clipsToBounds;
        BOOL _hasPreparedContentRect;
        NSRect _preparedContentRect;
        BOOL _acceptsTouchEvents;
        BOOL _wantsRestingTouches;
        BOOL _layerUsesCoreImageFilters;
        BOOL _prefersCompactControlSizeMetrics;
        NSEdgeInsets _additionalSafeAreaInsets;
    NS_EXTRA_IVARS_END(NSView)
}

// Constraints installed on this view, in the order they were added. A
// constraint is installed on the closest common ancestor of its items, see
// -[NSLayoutConstraint setActive:].
@property(readonly, copy) NSArray<NSLayoutConstraint *> *constraints;
// Adding a constraint activates it with this view as its owner; removing it
// deactivates it, and either marks the view as needing a constraint update.
// Adding one that is already installed here does nothing.
- (void) addConstraint: (NSLayoutConstraint *) constraint;
- (void) addConstraints: (NSArray<NSLayoutConstraint *> *) constraints;
- (void) removeConstraint: (NSLayoutConstraint *) constraint;
- (void) removeConstraints: (NSArray<NSLayoutConstraint *> *) constraints;

@property(class, readonly) BOOL requiresConstraintBasedLayout;
@property BOOL translatesAutoresizingMaskIntoConstraints;
@property NSUserInterfaceLayoutDirection userInterfaceLayoutDirection;

// NSViewNoIntrinsicMetric in both dimensions; subclasses that know their own
// size override it.
@property(readonly) NSSize intrinsicContentSize;
// The intrinsic size is read when the layout is solved, so a change to it
// shows at the next -layoutSubtreeIfNeeded.
- (void) invalidateIntrinsicContentSize;

// Sent by -layoutSubtreeIfNeeded to each view that needs layout. The base
// implementation clears needsLayout. Subclasses override and call super.
- (void) layout;
// Override to update stored constraints; call super last.
- (void) updateConstraints;
// Sends -updateConstraints to the views of this subtree that need it,
// subviews before their superview.
- (void) updateConstraintsForSubtreeIfNeeded;

// How strongly the view resists growing beyond, and shrinking below, its
// intrinsic size when constraints are solved. Defaults are 250 (hugging) and
// 750 (compression resistance).
- (NSLayoutPriority) contentHuggingPriorityForOrientation: (NSLayoutConstraintOrientation) orientation;
- (void) setContentHuggingPriority: (NSLayoutPriority) priority
                    forOrientation: (NSLayoutConstraintOrientation) orientation;
- (NSLayoutPriority) contentCompressionResistancePriorityForOrientation: (NSLayoutConstraintOrientation) orientation;
- (void) setContentCompressionResistancePriority: (NSLayoutPriority) priority
                                  forOrientation: (NSLayoutConstraintOrientation) orientation;

@property(readonly, copy) NSArray<NSLayoutGuide *> *layoutGuides;
- (void) addLayoutGuide: (NSLayoutGuide *) guide;
- (void) removeLayoutGuide: (NSLayoutGuide *) guide;

+ (nullable NSView *) focusView;
+ (nullable NSMenu *) defaultMenu;
+ (NSFocusRingType) defaultFocusRingType;

- (instancetype) initWithFrame: (NSRect) frame NS_DESIGNATED_INITIALIZER;
- (nullable instancetype) initWithCoder: (NSCoder *) coder NS_DESIGNATED_INITIALIZER;

@property NSRect frame;
@property(nonatomic) CGFloat frameRotation;
@property(nonatomic) CGFloat frameCenterRotation;
@property NSRect bounds;
@property(nonatomic) CGFloat boundsRotation;
@property(nonatomic, getter=isRotatedFromBase, readonly) BOOL rotatedFromBase;
@property(nonatomic, getter=isRotatedOrScaledFromBase, readonly) BOOL rotatedOrScaledFromBase;
- (void) translateOriginToPoint: (NSPoint) point;
- (void) rotateByAngle: (CGFloat) angle;
@property(nonatomic) BOOL postsFrameChangedNotifications;
@property(nonatomic) BOOL postsBoundsChangedNotifications;

- (void) scaleUnitSquareToSize: (NSSize) size;

@property (nullable, readonly, weak) NSWindow *window;
@property (nullable, readonly, weak) NSView *superview;
- (BOOL) isDescendantOf: (NSView *) other;
- (nullable NSView *) ancestorSharedWithView: (NSView *) view;
@property(nullable, nonatomic, readonly) NSScrollView *enclosingScrollView;
- (NSRect) adjustScroll: (NSRect) toRect;

@property (copy, nonnull) NSArray<__kindof NSView *> *subviews;
@property BOOL autoresizesSubviews;
@property(nonatomic) NSAutoresizingMaskOptions autoresizingMask;
@property(nonatomic) NSFocusRingType focusRingType;

@property(nonatomic, readonly) NSInteger tag;
@property (readonly) BOOL isFlipped;
@property (readonly) BOOL isOpaque;
@property CGFloat alphaValue;

// Makes the view visible and opaque again before it is reused.
- (void) prepareForReuse;
- (int) gState;
@property(nonatomic, readonly) NSRect visibleRect;
@property(nonatomic, readonly) BOOL wantsDefaultClipping;

- (nullable NSBitmapImageRep *) bitmapImageRepForCachingDisplayInRect: (NSRect) rect;
- (void) cacheDisplayInRect: (NSRect) rect
           toBitmapImageRep: (NSBitmapImageRep *) imageRep;

@property (getter=isHidden) BOOL hidden;
@property (readonly) BOOL isHiddenOrHasHiddenAncestor;
@property(getter=isDrawingFindIndicator, readonly) BOOL drawingFindIndicator;
- (void) viewDidHide;
- (void) viewDidUnhide;

@property(nonatomic, readonly) BOOL canBecomeKeyView;
@property(nonatomic, readonly) BOOL needsPanelToBecomeKey;

@property(nullable, nonatomic, retain) NSView *nextKeyView;
@property(nullable, nonatomic, readonly) NSView *nextValidKeyView;

- (nullable NSView *) previousKeyView;
@property(nullable, nonatomic, readonly) NSView *previousValidKeyView;

- (nullable NSMenu *) menuForEvent: (NSEvent *) event;
@property(nullable, nonatomic, readonly) NSMenuItem *enclosingMenuItem;
@property(nullable, nonatomic, copy) NSString *toolTip;

- (null_unspecified id) viewWithTag: (NSInteger) tag;
- (nullable NSView *) hitTest: (NSPoint) point;

- (NSPoint) convertPoint: (NSPoint) point fromView: (nullable NSView *) viewOrNil;
- (NSPoint) convertPoint: (NSPoint) point toView: (nullable NSView *) viewOrNil;
- (NSSize) convertSize: (NSSize) size fromView: (nullable NSView *) viewOrNil;
- (NSSize) convertSize: (NSSize) size toView: (nullable NSView *) viewOrNil;
- (NSRect) convertRect: (NSRect) rect fromView: (nullable NSView *) viewOrNil;
- (NSRect) convertRect: (NSRect) rect toView: (nullable NSView *) viewOrNil;
- (NSRect) centerScanRect: (NSRect) rect;
- (NSRect) backingAlignedRect: (NSRect) rect options: (NSAlignmentOptions) options;
@property(nullable, copy) NSString *accessibilityTitle;

- (void) setFrameSize: (NSSize) size;
- (void) setFrameOrigin: (NSPoint) origin;

- (void) setBoundsSize: (NSSize) size;
- (void) setBoundsOrigin: (NSPoint) origin;


- (void) rotateByAngle: (CGFloat) degrees;


- (void) addSubview: (NSView *) view;
- (void) addSubview: (NSView *) view
         positioned: (NSWindowOrderingMode) ordering
         relativeTo: (nullable NSView *) relativeTo;
- (void) replaceSubview: (NSView *) oldView with: (NSView *) newView;
- (void) sortSubviewsUsingFunction:
                 (NSComparisonResult (*)(id, id, void *)) compareFunction
                           context: (nullable void *) context;
- (void) didAddSubview: (NSView *) subview;
- (void) willRemoveSubview: (NSView *) subview;

- (BOOL) acceptsFirstMouse: (nullable NSEvent *) event NS_SWIFT_NAME(acceptsFirstMouse(for:));
@property(nonatomic) BOOL acceptsTouchEvents;
@property(nonatomic) BOOL wantsRestingTouches;

- (BOOL) performKeyEquivalent: (NSEvent *) event;
- (BOOL) performMnemonic: (NSString *) string;

- (NSToolTipTag) addToolTipRect: (NSRect) rect
                          owner: (id) object
                       userData: (nullable void *) userData;
- (void) removeToolTip: (NSToolTipTag) tag;
- (void) removeAllToolTips;

- (void) addCursorRect: (NSRect) rect cursor: (NSCursor *) cursor;
- (void) removeCursorRect: (NSRect) rect cursor: (NSCursor *) cursor;
- (void) discardCursorRects;
- (void) resetCursorRects;

@property(nonatomic, readonly) NSArray<NSTrackingArea *> *trackingAreas;
- (void) addTrackingArea: (NSTrackingArea *) trackingArea;
- (void) removeTrackingArea: (NSTrackingArea *) trackingArea;
- (void) updateTrackingAreas;

- (NSTrackingRectTag) addTrackingRect: (NSRect) rect
                                owner: (id) object
                             userData: (nullable void *) userData
                         assumeInside: (BOOL) assumeInside;
- (void) removeTrackingRect: (NSTrackingRectTag) tag;

@property(nullable, nonatomic, readonly) NSTextInputContext *inputContext;

- (void) registerForDraggedTypes: (NSArray *) types;
- (void) unregisterDraggedTypes;
@property(nonatomic, readonly) NSArray *registeredDraggedTypes;

- (void) removeFromSuperview;
- (void) removeFromSuperviewWithoutNeedingDisplay;
- (void) viewWillMoveToSuperview: (nullable NSView *) view;
- (void) viewDidMoveToSuperview;

- (void) viewWillMoveToWindow: (NSWindow *_Nullable) window
        NS_SWIFT_NAME(viewWillMove(toWindow:));
- (void) viewDidMoveToWindow;
- (void) viewDidChangeBackingProperties;
- (void) viewDidChangeEffectiveAppearance;

- (BOOL) shouldDelayWindowOrderingForEvent: (NSEvent *) event;

- (void) resizeSubviewsWithOldSize: (NSSize) oldSize;
- (void) resizeWithOldSuperviewSize: (NSSize) oldSize;

@property(nonatomic, readonly) BOOL inLiveResize;
@property(nonatomic, readonly) BOOL preservesContentDuringLiveResize;
@property(nonatomic, readonly) NSRect rectPreservedDuringLiveResize;
- (void) viewWillStartLiveResize;
- (void) viewDidEndLiveResize;

- (BOOL) enterFullScreenMode: (NSScreen *) screen
                 withOptions: (nullable NSDictionary<NSViewFullScreenModeOptionKey, id> *) options;
@property(nonatomic, getter=isInFullScreenMode, readonly) BOOL inFullScreenMode;
- (void) exitFullScreenModeWithOptions: (nullable NSDictionary<NSViewFullScreenModeOptionKey, id> *) options;

- (void) scrollPoint: (NSPoint) point;
- (BOOL) scrollRectToVisible: (NSRect) rect;
- (void) scrollClipView: (NSClipView *) clipView toPoint: (NSPoint) newOrigin;
- (BOOL) mouse: (NSPoint) point inRect: (NSRect) rect;
- (void) reflectScrolledClipView: (NSClipView *) view;

- (void) allocateGState;
- (void) releaseGState;
- (void) setUpGState;
- (void) renewGState;

@property (nullable, retain) CALayer *layer;
@property BOOL wantsLayer;
@property NSViewLayerContentsPlacement layerContentsPlacement;
@property NSViewLayerContentsRedrawPolicy layerContentsRedrawPolicy;
- (CALayer *) makeBackingLayer;

// A layer-backed view that answers YES is updated with -updateLayer instead
// of being drawn with -drawRect:. The default -updateLayer does nothing.
@property(readonly) BOOL wantsUpdateLayer;
- (void) updateLayer;

// NSEdgeInsetsZero here; subclasses whose content sits inside their frame
// override it, and the two conversions below follow.
@property(readonly) NSEdgeInsets alignmentRectInsets;
// Distances from the top and the bottom of the alignment rectangle to the first
// and last baselines of the view's text (0 for a view without text).
@property(readonly) CGFloat firstBaselineOffsetFromTop;
@property(readonly) CGFloat lastBaselineOffsetFromBottom;
@property(readonly) CGFloat baselineOffsetFromBottom;
// The smallest size the view's constraints allow; its frame is not changed.
@property(readonly) NSSize fittingSize;
- (NSRect) alignmentRectForFrame: (NSRect) frame;
- (NSRect) frameForAlignmentRect: (NSRect) alignmentRect;
// Stored; subviews are drawn into their own layers either way.
@property BOOL canDrawSubviewsIntoLayer;
// Stored; there are no touch devices to send touches.
@property NSTouchTypeMask allowedTouchTypes;

@property(nonatomic, copy) NSArray<__kindof CIFilter *> *backgroundFilters;
@property(nonatomic, copy) NSArray<__kindof CIFilter *> *contentFilters;
@property(nullable, nonatomic, retain) CIFilter *compositingFilter;
@property(nullable, nonatomic, retain) NSShadow *shadow;

@property BOOL needsDisplay;
- (void) setNeedsDisplayInRect: (NSRect) rect;
- (void) setKeyboardFocusRingNeedsDisplayInRect: (NSRect) rect;
@property (readonly) NSRect focusRingMaskBounds;
- (void) drawFocusRingMask;
- (void) translateRectsNeedingDisplayInRect: (NSRect) rect by: (NSSize) delta;

@property(nonatomic, readonly) BOOL canDraw;
@property(nonatomic) BOOL canDrawConcurrently;
- (void) viewWillDraw;
- (void) lockFocus;
- (BOOL) lockFocusIfCanDraw;
- (BOOL) lockFocusIfCanDrawInContext: (NSGraphicsContext *) context;
- (void) unlockFocus;

- (BOOL) needsToDrawRect: (NSRect) rect;
- (void) getRectsBeingDrawn: (const NSRect * _Nullable * _Nullable) rects count: (nullable NSInteger *) count;
- (void) getRectsExposedDuringLiveResize: (NSRect) rects
                                   count: (NSInteger *) count;

- (BOOL) shouldDrawColor;

@property(nullable, nonatomic, readonly) NSView *opaqueAncestor;
- (void) display;
- (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)selector;
- (void) displayIfNeeded;
- (void) displayIfNeededIgnoringOpacity;
- (void) displayIfNeededInRect: (NSRect) rect;
- (void) displayIfNeededInRectIgnoringOpacity: (NSRect) rect;
- (void) displayRect: (NSRect) rect;
- (void) displayRectIgnoringOpacity: (NSRect) rect;
- (void) displayRectIgnoringOpacity: (NSRect) rect
                          inContext: (NSGraphicsContext *) context;
- (void) drawRect: (NSRect) rect;

- (BOOL) autoscroll: (NSEvent *) event;
- (void) scrollRect: (NSRect) rect by: (NSSize) delta;
@property(nonatomic, readonly) BOOL mouseDownCanMoveWindow;

- (void) print: (nullable id) sender;

- (void) beginDocument;
- (void) endDocument;

- (void) beginPageInRect: (NSRect) rect atPlacement: (NSPoint) placement;
- (void) endPage;

- (NSAttributedString *) pageHeader;
- (NSAttributedString *) pageFooter;
- (NSString *) printJobTitle;
- (void) drawSheetBorderWithSize: (NSSize) size;
- (void) drawPageBorderWithSize: (NSSize) size;

- (CGFloat) widthAdjustLimit;
- (CGFloat) heightAdjustLimit;
- (void) adjustPageWidthNew: (CGFloat *) adjustedRight
                       left: (CGFloat) left
                      right: (CGFloat) right
                      limit: (CGFloat) limit;
- (void) adjustPageHeightNew: (CGFloat *) adjustedBottom
                         top: (CGFloat) top
                      bottom: (CGFloat) bottom
                       limit: (CGFloat) limit;

- (BOOL) knowsPageRange: (null_unspecified NSRange *) range;
- (NSPoint) locationOfPrintRect: (NSRect) rect;
- (NSRect) rectForPage: (int) page;

- (NSData *) dataWithEPSInsideRect: (NSRect) rect;
- (NSData *) dataWithPDFInsideRect: (NSRect) rect;

- (void) writeEPSInsideRect: (NSRect) rect
               toPasteboard: (NSPasteboard *) pasteboard;
- (void) writePDFInsideRect: (NSRect) rect
               toPasteboard: (NSPasteboard *) pasteboard;

- (void) dragImage: (NSImage *) image
                at: (NSPoint) location
            offset: (NSSize) offset
             event: (NSEvent *) event
        pasteboard: (NSPasteboard *) pasteboard
            source: (id) source
         slideBack: (BOOL) slideBack;
- (BOOL) dragFile: (NSString *) path
         fromRect: (NSRect) rect
        slideBack: (BOOL) slideBack
            event: (NSEvent *) event;
- (BOOL) dragPromisedFilesOfTypes: (NSArray<NSString *> *) types
                         fromRect: (NSRect) rect
                           source: (id) source
                        slideBack: (BOOL) slideBack
                            event: (NSEvent *) event;

- (NSPoint) convertPointFromBase: (NSPoint) aPoint;
- (NSPoint) convertPointToBase: (NSPoint) aPoint;
- (NSSize) convertSizeFromBase: (NSSize) aSize;
- (NSSize) convertSizeToBase: (NSSize) aSize;
- (NSRect) convertRectFromBase: (NSRect) aRect;
- (NSRect) convertRectToBase: (NSRect) aRect;

// macOS names all six convertToBacking(_:)/convertFromBacking(_:) in Swift,
// overloaded on the argument type; without these Swift sees the ObjC spellings.
- (NSRect) convertRectToBacking: (NSRect) rect NS_SWIFT_NAME(convertToBacking(_:));
- (NSRect) convertRectFromBacking: (NSRect) rect NS_SWIFT_NAME(convertFromBacking(_:));
- (NSPoint) convertPointToBacking: (NSPoint) point NS_SWIFT_NAME(convertToBacking(_:));
- (NSPoint) convertPointFromBacking: (NSPoint) point NS_SWIFT_NAME(convertFromBacking(_:));
- (NSSize) convertSizeToBacking: (NSSize) size NS_SWIFT_NAME(convertToBacking(_:));
- (NSSize) convertSizeFromBacking: (NSSize) size NS_SWIFT_NAME(convertFromBacking(_:));

// Stored and archived; the X11 backend has no high-resolution surfaces.
@property BOOL wantsBestResolutionOpenGLSurface;

- (void) showDefinitionForAttributedString: (nullable NSAttributedString *) string
                                   atPoint: (NSPoint) origin;
// Blocks aren't supported by the compiler yet.
//-(void)showDefinitionForAttributedString:(NSAttributedString *)string
// range:(NSRange)range options:(NSDictionary *)options
// baselineOriginProvider:(NSPoint (^)(NSRange adjustedRange))originProvider;

// private,move
- (null_unspecified NSArray *) _draggedTypes;
- (void) _setWindow: (null_unspecified NSWindow *) window;
- (void) _collectTrackingAreasForWindowInto: (null_unspecified NSMutableArray *) collector;

@end

@interface NSView (NSViewGestureRecognizers)

@property(copy) NSArray<__kindof NSGestureRecognizer *> *gestureRecognizers;
- (void) addGestureRecognizer: (NSGestureRecognizer *) recognizer;
- (void) removeGestureRecognizer: (NSGestureRecognizer *) recognizer;

@end

@interface NSView (NSViewLayoutState)

// Marking a view as needing layout or constraint updates makes the next
// layout pass (-layoutSubtreeIfNeeded, or before a window displays) handle it.
@property BOOL needsLayout;
@property BOOL needsUpdateConstraints;
// Stored only; drawing isn't clipped differently.
@property BOOL clipsToBounds;
// The visible rect until set.
@property NSRect preparedContentRect;

// Updates constraints and sends -layout to the views that need it.
- (void) layoutSubtreeIfNeeded;

@end

@interface NSView (NSViewLayoutAnchors)

@property(readonly, retain) NSLayoutDimension *widthAnchor;
@property(readonly, retain) NSLayoutDimension *heightAnchor;
@property(readonly, retain) NSLayoutXAxisAnchor *leadingAnchor;
@property(readonly, retain) NSLayoutXAxisAnchor *trailingAnchor;
@property(readonly, retain) NSLayoutXAxisAnchor *leftAnchor;
@property(readonly, retain) NSLayoutXAxisAnchor *rightAnchor;
@property(readonly, retain) NSLayoutXAxisAnchor *centerXAnchor;
@property(readonly, retain) NSLayoutYAxisAnchor *topAnchor;
@property(readonly, retain) NSLayoutYAxisAnchor *bottomAnchor;
@property(readonly, retain) NSLayoutYAxisAnchor *centerYAnchor;
@property(readonly, retain) NSLayoutYAxisAnchor *firstBaselineAnchor;
@property(readonly, retain) NSLayoutYAxisAnchor *lastBaselineAnchor;

@end

@interface NSView (NSViewLayerGeometry)

// Conversions between the view's coordinate system and that of its backing
// layer. A view without a layer returns the value unchanged; for a flipped
// layer-backed view the y axis is mirrored within the bounds, as the layer's
// own y axis points up.
- (NSPoint) convertPointToLayer: (NSPoint) point;
- (NSPoint) convertPointFromLayer: (NSPoint) point;
- (NSSize) convertSizeToLayer: (NSSize) size;
- (NSSize) convertSizeFromLayer: (NSSize) size;
- (NSRect) convertRectToLayer: (NSRect) rect;
- (NSRect) convertRectFromLayer: (NSRect) rect;

// Stored; Core Image filters on layers are not applied by Darling's layers.
@property BOOL layerUsesCoreImageFilters;

@end

@interface NSView (NSViewHooks)

// Contextual menu notifications, sent around a menu shown for this view;
// the default implementations do nothing.
- (void) willOpenMenu: (NSMenu *) menu withEvent: (NSEvent *) event;
- (void) didCloseMenu: (NSMenu *) menu withEvent: (nullable NSEvent *) event;

// Smart magnify (double tap with two fingers): the default asks for no zoom.
- (NSRect) rectForSmartMagnificationAtPoint: (NSPoint) location
                                     inRect: (NSRect) visibleRect;

// Responsive scrolling: the default views are compatible, and the
// recommended rectangle becomes the preparedContentRect.
@property(class, readonly, getter=isCompatibleWithResponsiveScrolling) BOOL compatibleWithResponsiveScrolling;
- (void) prepareContentInRect: (NSRect) rect;

// NO by default; vibrancy isn't composited by this implementation.
@property(readonly) BOOL allowsVibrancy;

// Invalidates the area the focus ring is drawn in after its mask changed.
- (void) noteFocusRingMaskChanged;
+ (null_unspecified NSView *) _focusRingViewForResponder: (null_unspecified NSResponder *) responder;
- (void) _focusRingStateChanged;
// The shape of the focus ring when it is not the mask of -drawFocusRingMask (a control whose cell draws a bezel
// or glyph of its own), in the view's coordinates; nil by default.
- (null_unspecified NSBezierPath *) _focusRingShape;

@end

@interface NSView (NSViewSafeAreas)

// No view has a safe area of its own here: the insets are the additional
// insets and the rect is the bounds inside them.
@property(readonly) NSEdgeInsets safeAreaInsets;
@property NSEdgeInsets additionalSafeAreaInsets;
@property(readonly) NSRect safeAreaRect;
@property BOOL prefersCompactControlSizeMetrics;

@end

@interface NSView (NSViewEffectiveAppearance)

// The view's own appearance, else its superview's, else the current appearance.
@property(readonly) NSAppearance *effectiveAppearance;

@end

@protocol NSViewToolTipOwner <NSObject>
- (NSString *) view: (NSView *) view
        stringForToolTip: (NSToolTipTag) tag
                   point: (NSPoint) point
                userData: (nullable void *) data;
@end

NS_ASSUME_NONNULL_END
