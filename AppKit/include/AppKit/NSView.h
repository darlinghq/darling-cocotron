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

#import <AppKit/AppKitExport.h>
#import <AppKit/NSAnimation.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSResponder.h>
#import <AppKit/NSUserInterfaceItemIdentification.h>
#import <ApplicationServices/ApplicationServices.h>
#import <AppKit/NSUserInterfaceItemIdentification.h>
#import <AppKit/NSLayoutConstraint.h>
#import <AppKit/NSAppearance.h>
#import <AppKit/NSUserInterfaceLayoutDirection.h>

typedef NS_OPTIONS(NSUInteger, NSTouchTypeMask) {
    NSTouchTypeMaskDirect = 1 << 0,
    NSTouchTypeMaskIndirect = 1 << 1,
};

@class NSWindow, NSMenu, NSMenuItem, NSCursor, NSClipView, NSPasteboard,
        NSTextInputContext, NSImage, NSBitmapImageRep, NSScrollView,
        NSTrackingArea, NSShadow, NSScreen, CALayer, CIFilter, CALayerContext, NSView,
        NSLayoutGuide, NSGestureRecognizer, NSLayoutDimension, NSLayoutXAxisAnchor, NSLayoutYAxisAnchor;

// See Cocoa Event Handling Guide : Using Tracking-Area Objects : Compatibility
// Issues
typedef NSTrackingArea *NSTrackingRectTag NS_SWIFT_NAME(NSView.TrackingRectTag);
typedef NSTrackingArea *NSToolTipTag NS_SWIFT_NAME(NSView.ToolTipTag);
typedef NSString *NSViewFullScreenModeOptionKey;

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

@interface NSView : NSResponder <NSAnimatablePropertyContainer, NSUserInterfaceItemIdentification, NSAppearanceCustomization> {
    NSRect _frame;
    NSRect _bounds;
    NSWindow *_window;
    NSMenu *_menu;
    NSView *_superview;
    NSMutableArray *_subviews;
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
    CALayer *_layer;
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
    NSLayoutPriority _verticalContentHuggingPriority;
    NSLayoutPriority _horizontalContentCompressionResistancePriority;
    NSLayoutPriority _verticalContentCompressionResistancePriority;

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

@property(readonly, copy) NSArray *layoutGuides;
- (void) addLayoutGuide: (NSLayoutGuide *) guide;
- (void) removeLayoutGuide: (NSLayoutGuide *) guide;

+ (NSView *) focusView;
+ (NSMenu *) defaultMenu;
+ (NSFocusRingType) defaultFocusRingType;

- (instancetype) initWithFrame: (NSRect) frame NS_DESIGNATED_INITIALIZER;
- (nullable instancetype) initWithCoder: (NSCoder *) coder NS_DESIGNATED_INITIALIZER;

@property NSRect frame;
- (CGFloat) frameRotation;
- (CGFloat) frameCenterRotation;
@property NSRect bounds;
- (CGFloat) boundsRotation;
- (BOOL) isRotatedFromBase;
- (BOOL) isRotatedOrScaledFromBase;
- (void) translateOriginToPoint: (NSPoint) point;
- (void) rotateByAngle: (CGFloat) angle;
- (BOOL) postsFrameChangedNotifications;
- (BOOL) postsBoundsChangedNotifications;

- (void) scaleUnitSquareToSize: (NSSize) size;

@property (readonly, weak) NSWindow *window;
@property (readonly, weak) NSView *superview;
- (BOOL) isDescendantOf: (NSView *) other;
- (NSView *) ancestorSharedWithView: (NSView *) view;
- (NSScrollView *) enclosingScrollView;
- (NSRect) adjustScroll: (NSRect) toRect;

@property (copy, nonnull) NSArray<__kindof NSView *> *subviews;
@property BOOL autoresizesSubviews;
- (NSAutoresizingMaskOptions) autoresizingMask;
- (NSFocusRingType) focusRingType;

- (NSInteger) tag;
@property (readonly) BOOL isFlipped;
@property (readonly) BOOL isOpaque;
@property CGFloat alphaValue;

// Makes the view visible and opaque again before it is reused.
- (void) prepareForReuse;
- (int) gState;
- (NSRect) visibleRect;
- (BOOL) wantsDefaultClipping;

- (NSBitmapImageRep *) bitmapImageRepForCachingDisplayInRect: (NSRect) rect;
- (void) cacheDisplayInRect: (NSRect) rect
           toBitmapImageRep: (NSBitmapImageRep *) imageRep;

@property (getter=isHidden) BOOL hidden;
@property (readonly) BOOL isHiddenOrHasHiddenAncestor;
@property(getter=isDrawingFindIndicator, readonly) BOOL drawingFindIndicator;
- (void) viewDidHide;
- (void) viewDidUnhide;

- (BOOL) canBecomeKeyView;
- (BOOL) needsPanelToBecomeKey;

- (NSView *) nextKeyView;
- (NSView *) nextValidKeyView;

- (NSView *) previousKeyView;
- (NSView *) previousValidKeyView;

- (NSMenu *) menuForEvent: (NSEvent *) event;
- (NSMenuItem *) enclosingMenuItem;
- (NSString *) toolTip;

- viewWithTag: (NSInteger) tag;
- (NSView *) hitTest: (NSPoint) point;

- (NSPoint) convertPoint: (NSPoint) point fromView: (NSView *) viewOrNil;
- (NSPoint) convertPoint: (NSPoint) point toView: (NSView *) viewOrNil;
- (NSSize) convertSize: (NSSize) size fromView: (NSView *) viewOrNil;
- (NSSize) convertSize: (NSSize) size toView: (NSView *) viewOrNil;
- (NSRect) convertRect: (NSRect) rect fromView: (NSView *) viewOrNil;
- (NSRect) convertRect: (NSRect) rect toView: (NSView *) viewOrNil;
- (NSRect) centerScanRect: (NSRect) rect;

- (void) setFrameSize: (NSSize) size;
- (void) setFrameOrigin: (NSPoint) origin;
- (void) setFrameRotation: (CGFloat) angle;
- (void) setFrameCenterRotation: (CGFloat) angle;

- (void) setBoundsSize: (NSSize) size;
- (void) setBoundsOrigin: (NSPoint) origin;
- (void) setBoundsRotation: (CGFloat) angle;

- (CGFloat) frameRotation;
- (CGFloat) boundsRotation;

- (void) setFrameRotation: (CGFloat) degrees;
- (void) setBoundsRotation: (CGFloat) degrees;
- (void) rotateByAngle: (CGFloat) degrees;

- (void) setPostsFrameChangedNotifications: (BOOL) flag;
- (void) setPostsBoundsChangedNotifications: (BOOL) flag;

- (void) addSubview: (NSView *) view;
- (void) addSubview: (NSView *) view
         positioned: (NSWindowOrderingMode) ordering
         relativeTo: (NSView *) relativeTo;
- (void) replaceSubview: (NSView *) oldView with: (NSView *) newView;
- (void) sortSubviewsUsingFunction:
                 (NSComparisonResult (*)(id, id, void *)) compareFunction
                           context: (void *) context;
- (void) didAddSubview: (NSView *) subview;
- (void) willRemoveSubview: (NSView *) subview;
- (void) setAutoresizingMask: (NSAutoresizingMaskOptions) mask;
- (void) setFocusRingType: (NSFocusRingType) value;

- (void) setNextKeyView: (NSView *) next;
- (BOOL) acceptsFirstMouse: (NSEvent *) event NS_SWIFT_NAME(acceptsFirstMouse(for:));
- (BOOL) acceptsTouchEvents;
- (void) setAcceptsTouchEvents: (BOOL) accepts;
- (BOOL) wantsRestingTouches;
- (void) setWantsRestingTouches: (BOOL) wants;

- (BOOL) performKeyEquivalent: (NSEvent *) event;
- (BOOL) performMnemonic: (NSString *) string;

- (void) setToolTip: (NSString *) string;
- (NSToolTipTag) addToolTipRect: (NSRect) rect
                          owner: object
                       userData: (void *) userData;
- (void) removeToolTip: (NSToolTipTag) tag;
- (void) removeAllToolTips;

- (void) addCursorRect: (NSRect) rect cursor: (NSCursor *) cursor;
- (void) removeCursorRect: (NSRect) rect cursor: (NSCursor *) cursor;
- (void) discardCursorRects;
- (void) resetCursorRects;

- (NSArray *) trackingAreas;
- (void) addTrackingArea: (NSTrackingArea *) trackingArea;
- (void) removeTrackingArea: (NSTrackingArea *) trackingArea;
- (void) updateTrackingAreas;

- (NSTrackingRectTag) addTrackingRect: (NSRect) rect
                                owner: object
                             userData: (void *) userData
                         assumeInside: (BOOL) assumeInside;
- (void) removeTrackingRect: (NSTrackingRectTag) tag;

- (NSTextInputContext *) inputContext;

- (void) registerForDraggedTypes: (NSArray *) types;
- (void) unregisterDraggedTypes;
- (NSArray *) registeredDraggedTypes;

- (void) removeFromSuperview;
- (void) removeFromSuperviewWithoutNeedingDisplay;
- (void) viewWillMoveToSuperview: (NSView *) view;
- (void) viewDidMoveToSuperview;

- (void) viewWillMoveToWindow: (NSWindow *_Nullable) window
        NS_SWIFT_NAME(viewWillMove(toWindow:));
- (void) viewDidMoveToWindow;
- (void) viewDidChangeBackingProperties;
- (void) viewDidChangeEffectiveAppearance;

- (BOOL) shouldDelayWindowOrderingForEvent: (NSEvent *) event;

- (void) resizeSubviewsWithOldSize: (NSSize) oldSize;
- (void) resizeWithOldSuperviewSize: (NSSize) oldSize;

- (BOOL) inLiveResize;
- (BOOL) preservesContentDuringLiveResize;
- (NSRect) rectPreservedDuringLiveResize;
- (void) viewWillStartLiveResize;
- (void) viewDidEndLiveResize;

- (BOOL) enterFullScreenMode: (NSScreen *) screen
                 withOptions: (NSDictionary *) options;
- (BOOL) isInFullScreenMode;
- (void) exitFullScreenModeWithOptions: (NSDictionary *) options;

- (void) scrollPoint: (NSPoint) point;
- (BOOL) scrollRectToVisible: (NSRect) rect;
- (void) scrollClipView: (NSClipView *) clipView toPoint: (NSPoint) newOrigin;
- (BOOL) mouse: (NSPoint) point inRect: (NSRect) rect;
- (void) reflectScrolledClipView: (NSClipView *) view;

- (void) allocateGState;
- (void) releaseGState;
- (void) setUpGState;
- (void) renewGState;

@property (retain) CALayer *layer;
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
- (NSRect) alignmentRectForFrame: (NSRect) frame;
- (NSRect) frameForAlignmentRect: (NSRect) alignmentRect;
// Stored; subviews are drawn into their own layers either way.
@property BOOL canDrawSubviewsIntoLayer;
// Stored; there are no touch devices to send touches.
@property NSTouchTypeMask allowedTouchTypes;

- (NSArray *) backgroundFilters;
- (void) setBackgroundFilters: (NSArray *) filters;
- (NSArray *) contentFilters;
- (void) setContentFilters: (NSArray *) filters;
- (CIFilter *) compositingFilter;
- (void) setCompositingFilter: (CIFilter *) filter;
- (NSShadow *) shadow;
- (void) setShadow: (NSShadow *) shadow;

@property BOOL needsDisplay;
- (void) setNeedsDisplayInRect: (NSRect) rect;
- (void) setKeyboardFocusRingNeedsDisplayInRect: (NSRect) rect;
@property (readonly) NSRect focusRingMaskBounds;
- (void) drawFocusRingMask;
- (void) translateRectsNeedingDisplayInRect: (NSRect) rect by: (NSSize) delta;

- (BOOL) canDraw;
- (BOOL) canDrawConcurrently;
- (void) viewWillDraw;
- (void) setCanDrawConcurrently: (BOOL) canDraw;
- (void) lockFocus;
- (BOOL) lockFocusIfCanDraw;
- (BOOL) lockFocusIfCanDrawInContext: (NSGraphicsContext *) context;
- (void) unlockFocus;

- (BOOL) needsToDrawRect: (NSRect) rect;
- (void) getRectsBeingDrawn: (const NSRect **) rects count: (NSInteger *) count;
- (void) getRectsExposedDuringLiveResize: (NSRect) rects
                                   count: (NSInteger *) count;

- (BOOL) shouldDrawColor;

- (NSView *) opaqueAncestor;
- (void) display;
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
- (BOOL) mouseDownCanMoveWindow;

- (void) print: sender;

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

- (BOOL) knowsPageRange: (NSRange *) range;
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
            source: source
         slideBack: (BOOL) slideBack;
- (BOOL) dragFile: (NSString *) path
         fromRect: (NSRect) rect
        slideBack: (BOOL) slideBack
            event: (NSEvent *) event;
- (BOOL) dragPromisedFilesOfTypes: (NSArray *) types
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

- (void) showDefinitionForAttributedString: (NSAttributedString *) string
                                   atPoint: (NSPoint) origin;
// Blocks aren't supported by the compiler yet.
//-(void)showDefinitionForAttributedString:(NSAttributedString *)string
// range:(NSRange)range options:(NSDictionary *)options
// baselineOriginProvider:(NSPoint (^)(NSRange adjustedRange))originProvider;

// private,move
- (NSArray *) _draggedTypes;
- (void) _setWindow: (NSWindow *) window;
- (void) _collectTrackingAreasForWindowInto: (NSMutableArray *) collector;

@end

@interface NSView (NSViewGestureRecognizers)

@property(copy) NSArray<NSGestureRecognizer *> *gestureRecognizers;
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

@end

@interface NSView (NSViewEffectiveAppearance)

// The view's own appearance, else its superview's, else the current appearance.
@property(readonly) NSAppearance *effectiveAppearance;

@end

@protocol NSViewToolTipOwner <NSObject>
- (NSString *) view: (NSView *) view
        stringForToolTip: (NSToolTipTag) tag
                   point: (NSPoint) point
                userData: (void *) data;
@end
