/* Copyright (c) 2006-2007 Christopher J. W. Lloyd
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
#import <AppKit/NSResponder.h>
#import <AppKit/NSView.h>
#import <AppKit/NSApplication.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CGSubWindow.h>
#import <AppKit/NSUserInterfaceItemIdentification.h>
#import <AppKit/NSAccessibilityProtocols.h>

NS_ASSUME_NONNULL_BEGIN

@class NSView, NSEvent, NSColor, NSColorSpace, NSCursor, NSImage, NSScreen,
        NSText, NSTextView, CGWindow, NSPasteboard, NSSheetContext,
        NSTitlebarAccessoryViewController,
        NSUndoManager, NSButton, NSButtonCell, NSDrawer, NSDockTile, NSToolbar,
        NSWindowAnimationContext, NSTrackingArea, NSThemeFrame,
        NSWindowController, NSMenuItem, CARenderer, NSViewController;
@protocol NSWindowDelegate;

// Old NSWindowStyleMask constants
enum {
    NSBorderlessWindowMask = 0x00,
    NSTitledWindowMask = 0x01,
    NSClosableWindowMask = 0x02,
    NSMiniaturizableWindowMask = 0x04,
    NSResizableWindowMask = 0x08,
    NSTexturedBackgroundWindowMask = 0x100,
};

// New NSWindowStyleMask constants
typedef NS_OPTIONS(NSUInteger, NSWindowStyleMask) {
    NSWindowStyleMaskBorderless = 0,
    NSWindowStyleMaskTitled = 0x01,
    NSWindowStyleMaskClosable = 0x02,
    NSWindowStyleMaskMiniaturizable = 0x04,
    NSWindowStyleMaskResizable = 0x08,
    NSWindowStyleMaskTexturedBackground = 0x100,
    NSWindowStyleMaskUnifiedTitleAndToolbar = 0x1000,
    NSWindowStyleMaskFullScreen = 0x4000,
    NSWindowStyleMaskFullSizeContentView = 0x8000,
    // NSPanel only:
    NSWindowStyleMaskUtilityWindow = 0x10,
    NSWindowStyleMaskDocModalWindow = 0x40,
    NSWindowStyleMaskNonactivatingPanel = 0x80,
    NSWindowStyleMaskHUDWindow = 0x2000,
};

// Names used before the modern spellings; plain constants, so Swift does not see them.
enum {
    NSWindiwStyleMaskUnifiedTitleAndToolbar = NSWindowStyleMaskUnifiedTitleAndToolbar,
};

typedef NS_ENUM(NSUInteger, NSBackingStoreType) {
    NSBackingStoreRetained = 0,
    NSBackingStoreNonretained = 1,
    NSBackingStoreBuffered = 2,
};

typedef NS_ENUM(NSUInteger, NSWindowButton) {
    NSWindowCloseButton,
    NSWindowMiniaturizeButton,
    NSWindowZoomButton,
    NSWindowToolbarButton,
    NSWindowDocumentIconButton,
};

typedef NS_OPTIONS(NSUInteger, NSWindowNumberListOptions) {
    NSWindowNumberListAllApplications = 0x01,
    NSWindowNumberListAllSpaces = 0x10
};

typedef NS_ENUM(NSUInteger, NSWindowBackingLocation) {
    NSWindowBackingLocationDefault = 0x00,
    NSWindowBackingLocationVideoMemory = 0x01,
    NSWindowBackingLocationMainMemory = 0x02
};

typedef NSInteger NSWindowLevel NS_TYPED_EXTENSIBLE_ENUM;

static const NSWindowLevel NSNormalWindowLevel = kCGNormalWindowLevel;
static const NSWindowLevel NSFloatingWindowLevel = kCGFloatingWindowLevel;
static const NSWindowLevel NSSubmenuWindowLevel = kCGTornOffMenuWindowLevel;
static const NSWindowLevel NSTornOffMenuWindowLevel = kCGTornOffMenuWindowLevel;
static const NSWindowLevel NSMainMenuWindowLevel = kCGMainMenuWindowLevel;
static const NSWindowLevel NSStatusWindowLevel = kCGStatusWindowLevel;
static const NSWindowLevel NSModalPanelWindowLevel = kCGModalPanelWindowLevel;
static const NSWindowLevel NSPopUpMenuWindowLevel = kCGPopUpMenuWindowLevel;
static const NSWindowLevel NSScreenSaverWindowLevel = kCGScreenSaverWindowLevel;

typedef NS_OPTIONS(NSUInteger, NSWindowCollectionBehavior) {
    NSWindowCollectionBehaviorDefault = 0x00,
    NSWindowCollectionBehaviorCanJoinAllSpaces = 0x01,
    NSWindowCollectionBehaviorMoveToActiveSpace = 0x02,
    NSWindowCollectionBehaviorManaged = 0x04,
    NSWindowCollectionBehaviorTransient = 0x08,
    NSWindowCollectionBehaviorStationary = 0x10,
    NSWindowCollectionBehaviorParticipatesInCycle = 0x20,
    NSWindowCollectionBehaviorIgnoresCycle = 0x40,
    NSWindowCollectionBehaviorFullScreenPrimary = 0x80,
    NSWindowCollectionBehaviorFullScreenAuxiliary = 0x100,
    NSWindowCollectionBehaviorFullScreenNone = 0x200,
    NSWindowCollectionBehaviorFullScreenAllowsTiling = 0x800,
    NSWindowCollectionBehaviorFullScreenDisallowsTiling = 0x1000
};

typedef NS_ENUM(NSUInteger, NSWindowSharingType) {
    NSWindowSharingNone = 0x00,
    NSWindowSharingReadOnly = 0x01,
    NSWindowSharingReadWrite = 0x02
};

typedef NS_OPTIONS(NSUInteger, NSWindowOcclusionState) {
    NSWindowOcclusionStateVisible = 1 << 1
};

typedef NS_ENUM(NSInteger, NSWindowTabbingMode) {
    NSWindowTabbingModeAutomatic = 0,
    NSWindowTabbingModePreferred,
    NSWindowTabbingModeDisallowed,
};

typedef NS_ENUM(NSInteger, NSWindowTitleVisibility) {
    NSWindowTitleVisible = 0,
    NSWindowTitleHidden = 1,
};

typedef NS_ENUM(NSInteger, NSTitlebarSeparatorStyle) {
    NSTitlebarSeparatorStyleAutomatic = 0,
    NSTitlebarSeparatorStyleNone = 1,
    NSTitlebarSeparatorStyleLine = 2,
    NSTitlebarSeparatorStyleShadow = 3,
};

typedef NS_ENUM(NSInteger, NSWindowToolbarStyle) {
    NSWindowToolbarStyleAutomatic = 0,
    NSWindowToolbarStyleExpanded = 1,
    NSWindowToolbarStylePreference = 2,
    NSWindowToolbarStyleUnified = 3,
    NSWindowToolbarStyleUnifiedCompact = 4,
};

typedef NSString *NSWindowTabbingIdentifier NS_SWIFT_BRIDGED_TYPEDEF;
typedef NSString *NSWindowFrameAutosaveName NS_SWIFT_BRIDGED_TYPEDEF;

typedef NS_ENUM(NSInteger, NSWindowAnimationBehavior) {
    NSWindowAnimationBehaviorDefault = 0,
    NSWindowAnimationBehaviorNone = 2,
    NSWindowAnimationBehaviorDocumentWindow = 3,
    NSWindowAnimationBehaviorUtilityWindow = 4,
    NSWindowAnimationBehaviorAlertPanel = 5
};

typedef NS_ENUM(int, NSSelectionDirection) {
    NSDirectSelection = 0,
    NSSelectingNext = 1,
    NSSelectingPrevious = 2,
};

APPKIT_EXPORT const NSNotificationName NSWindowDidBecomeKeyNotification
        NS_SWIFT_NAME(NSWindow.didBecomeKeyNotification);
APPKIT_EXPORT const NSNotificationName NSWindowDidResignKeyNotification
        NS_SWIFT_NAME(NSWindow.didResignKeyNotification);
APPKIT_EXPORT const NSNotificationName NSWindowDidBecomeMainNotification
        NS_SWIFT_NAME(NSWindow.didBecomeMainNotification);
APPKIT_EXPORT const NSNotificationName NSWindowDidResignMainNotification
        NS_SWIFT_NAME(NSWindow.didResignMainNotification);
APPKIT_EXPORT const NSNotificationName NSWindowWillMiniaturizeNotification
        NS_SWIFT_NAME(NSWindow.willMiniaturizeNotification);
APPKIT_EXPORT const NSNotificationName NSWindowDidMiniaturizeNotification
        NS_SWIFT_NAME(NSWindow.didMiniaturizeNotification);
APPKIT_EXPORT const NSNotificationName NSWindowDidDeminiaturizeNotification
        NS_SWIFT_NAME(NSWindow.didDeminiaturizeNotification);
APPKIT_EXPORT const NSNotificationName NSWindowWillMoveNotification
        NS_SWIFT_NAME(NSWindow.willMoveNotification);
APPKIT_EXPORT const NSNotificationName NSWindowDidMoveNotification
        NS_SWIFT_NAME(NSWindow.didMoveNotification);
APPKIT_EXPORT const NSNotificationName NSWindowDidResizeNotification
        NS_SWIFT_NAME(NSWindow.didResizeNotification);
APPKIT_EXPORT const NSNotificationName NSWindowDidUpdateNotification
        NS_SWIFT_NAME(NSWindow.didUpdateNotification);
APPKIT_EXPORT const NSNotificationName NSWindowWillCloseNotification
        NS_SWIFT_NAME(NSWindow.willCloseNotification);
APPKIT_EXPORT const NSNotificationName NSWindowWillStartLiveResizeNotification
        NS_SWIFT_NAME(NSWindow.willStartLiveResizeNotification);
APPKIT_EXPORT const NSNotificationName NSWindowDidEndLiveResizeNotification
        NS_SWIFT_NAME(NSWindow.didEndLiveResizeNotification);
APPKIT_EXPORT const NSNotificationName NSWindowWillBeginSheetNotification
        NS_SWIFT_NAME(NSWindow.willBeginSheetNotification);

APPKIT_EXPORT const NSNotificationName NSWindowDidChangeOcclusionStateNotification
        NS_SWIFT_NAME(NSWindow.didChangeOcclusionStateNotification);
APPKIT_EXPORT const NSNotificationName NSWindowDidChangeScreenNotification
        NS_SWIFT_NAME(NSWindow.didChangeScreenNotification);
APPKIT_EXPORT const NSNotificationName NSWindowDidChangeScreenProfileNotification
        NS_SWIFT_NAME(NSWindow.didChangeScreenProfileNotification);
APPKIT_EXPORT NSString *const NSBackingPropertyOldScaleFactorKey;
APPKIT_EXPORT const NSNotificationName NSWindowDidEndSheetNotification
        NS_SWIFT_NAME(NSWindow.didEndSheetNotification);
APPKIT_EXPORT const NSNotificationName NSWindowDidEnterFullScreenNotification
        NS_SWIFT_NAME(NSWindow.didEnterFullScreenNotification);
APPKIT_EXPORT const NSNotificationName NSWindowDidExitFullScreenNotification
        NS_SWIFT_NAME(NSWindow.didExitFullScreenNotification);
APPKIT_EXPORT const NSNotificationName NSWindowDidOrderOffScreenNotification;
APPKIT_EXPORT const NSNotificationName NSWindowDidOrderOnScreenNotification;
APPKIT_EXPORT const NSNotificationName NSWindowWillEnterFullScreenNotification
        NS_SWIFT_NAME(NSWindow.willEnterFullScreenNotification);
APPKIT_EXPORT const NSNotificationName NSWindowWillExitFullScreenNotification
        NS_SWIFT_NAME(NSWindow.willExitFullScreenNotification);
APPKIT_EXPORT const NSNotificationName NSWindowDidExposeNotification
        NS_SWIFT_NAME(NSWindow.didExposeNotification);
APPKIT_EXPORT const NSNotificationName NSWindowWillEnterVersionBrowserNotification
        NS_SWIFT_NAME(NSWindow.willEnterVersionBrowserNotification);
APPKIT_EXPORT const NSNotificationName NSWindowDidEnterVersionBrowserNotification
        NS_SWIFT_NAME(NSWindow.didEnterVersionBrowserNotification);
APPKIT_EXPORT const NSNotificationName NSWindowWillExitVersionBrowserNotification
        NS_SWIFT_NAME(NSWindow.willExitVersionBrowserNotification);
APPKIT_EXPORT const NSNotificationName NSWindowDidExitVersionBrowserNotification
        NS_SWIFT_NAME(NSWindow.didExitVersionBrowserNotification);

typedef NS_ENUM(NSInteger, NSWindowUserTabbingPreference) {
    NSWindowUserTabbingPreferenceManual,
    NSWindowUserTabbingPreferenceAlways,
    NSWindowUserTabbingPreferenceInFullScreen,
};

// Legacy ObjC ABI (i386): instance size must stay 0x84, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSWindow : NSResponder <NSAnimatablePropertyContainer, NSUserInterfaceItemIdentification, NSAccessibility, NSAppearanceCustomization> {
    NSRect _frame;
    NSView *_contentView;
    id<NSWindowDelegate> _delegate;
    NSResponder *_firstResponder;
    NS_LEGACY_IVAR_PAD(_NSWindowReserved1, 8)
    CGWindow *_platformWindow;  // a slot that Apple's layout leaves unused
    NSTextView *_sharedFieldEditor;
    NS_LEGACY_IVAR_PAD(_NSWindowReserved2, 8)
    NSWindowLevel _level;
    NSColor *_backgroundColor;
    NSThemeFrame *_backgroundView;
    NS_LEGACY_IVAR_PAD(_NSWindowReserved3, 12)
    NSImage *_miniwindowImage;
    NS_LEGACY_IVAR_PAD(_NSWindowReserved4, 8)
    NSURL *_representedURL;
    NS_LEGACY_IVAR_PAD(_NSWindowReserved5, 4)
    NSString *_autosaveFrameName;
    NSToolbar *_toolbar;
    NS_LEGACY_IVAR_PAD(_NSWindowReserved6, 8)
    NSButtonCell *_defaultButtonCell;
    NSView *_initialFirstResponder;
    NS_EXTRA_IVARS_BEGIN(NSWindow)
        NSWindowStyleMask _styleMask;
        NSBackingStoreType _backingType;

        NSSize _minSize;
        NSSize _maxSize;
        NSSize _contentMinSize;
        NSSize _contentMaxSize;

        NSWindow *_parentWindow;
        NSMutableArray<NSWindow *> *_childWindows;

        NSDictionary *_animations;

        NSString *_representedFilename;
        NSString *_title;
        NSString *_miniwindowTitle;

        NSMenu *_menu;
        NSView *_menuView;
        NSViewController *_contentViewController;


        NSTextView *_currentFieldEditor;
        NSArray *_draggedTypes;

        NSMutableArray *_trackingAreas;

        NSSheetContext *_sheetContext;

        NSSize _resizeInfo;

        int _cursorRectsDisabled;
        int _flushDisabled;

        BOOL _isOpaque;
        BOOL _isVisible;
        BOOL _isDocumentEdited;
        BOOL _makeSureIsOnAScreen;

        BOOL _acceptsMouseMovedEvents;
        BOOL _excludedFromWindowsMenu;
        BOOL _isDeferred;
        BOOL _dynamicDepthLimit;
        BOOL _canStoreColor;
        BOOL _isOneShot;
        BOOL _useOptimizedDrawing;
        BOOL _releaseWhenClosed;
        BOOL _isClosed;
        BOOL _hidesOnDeactivate;
        BOOL _hiddenForDeactivate;
        BOOL _isActive;
        BOOL _viewsNeedDisplay;
        BOOL _flushNeeded;
        BOOL _isFlushWindowDisabled;
        BOOL _isAutodisplay;
        BOOL _canHide;
        BOOL _displaysWhenScreenProfileChanges;

        CGFloat _alphaValue;
        BOOL _hasShadow;
        BOOL _showsResizeIndicator;
        BOOL _showsToolbarButton;
        BOOL _ignoresMouseEvents;
        BOOL _isMovableByWindowBackground;
        NSWindowAnimationBehavior _animationBehavior;
        BOOL _allowsToolTipsWhenApplicationIsInactive;
        BOOL _defaultButtonCellKeyEquivalentDisabled;
        BOOL _autorecalculatesKeyViewLoop;
        BOOL _hasBeenOnScreen;

        BOOL _isInLiveResize;
        BOOL _preservesContentDuringLiveResize;
        NSSize _resizeIncrements;
        NSSize _contentResizeIncrements;


        NSMutableDictionary *_threadToContext;

        NSUndoManager *_undoManager;

        NSWindowController *_windowController;
        NSMutableArray *_drawers;
        BOOL _bottomCornerRounded;
        NSWindowAnimationContext *_animationContext;

        NSRect _savedFrame;
        NSMutableDictionary *_mouseDownViews;

        NSAppearance *_appearance;
        NSUserInterfaceItemIdentifier _identifier;

        BOOL _isAccessible;
        BOOL _restorable;
        NSWindowTabbingMode _tabbingMode;
        NSWindowCollectionBehavior _collectionBehavior;
        NSWindowTabbingIdentifier _tabbingIdentifier;
        NSString *_subtitle;
        NSWindowTitleVisibility _titleVisibility;
        NSSize _minFullScreenContentSize;
        NSSize _maxFullScreenContentSize;
        NSInteger _fullScreenTransition;
        NSUInteger _fullScreenTransitionGeneration;
        NSTitlebarSeparatorStyle _titlebarSeparatorStyle;
        NSWindowToolbarStyle _toolbarStyle;
        BOOL _titlebarAppearsTransparent;
        BOOL _isMovable;
        NSButton *_standardWindowButtons[3];

        NSMutableArray *_titlebarAccessoryViewControllers;
        // Inverted so that the zero-filled extras give the documented defaults.
        BOOL _concurrentViewDrawingDisabled;
        BOOL _allowsTerminationWhenModal;
        BOOL _canBecomeVisibleWithoutLogin;
        // Zeroing weak reference to the appearance source.
        id _appearanceSource;
        // Direction of the key view selection in progress; zero (direct) otherwise.
        NSSelectionDirection _keyViewSelectionDirection;
    NS_EXTRA_IVARS_END(NSWindow)
}

@property(class) BOOL allowsAutomaticWindowTabbing;
@property(getter=isRestorable) BOOL restorable;

+ (NSWindowDepth) defaultDepthLimit;

+ (NSRect) frameRectForContentRect: (NSRect) contentRect
                         styleMask: (NSWindowStyleMask) styleMask;
+ (NSRect) contentRectForFrameRect: (NSRect) frameRect
                         styleMask: (NSWindowStyleMask) styleMask;
+ (CGFloat) minFrameWidthWithTitle: (NSString *) title
                         styleMask: (NSWindowStyleMask) styleMask;
+ (NSInteger) windowNumberAtPoint: (NSPoint) point
        belowWindowWithWindowNumber: (NSInteger) window;
+ (nullable NSArray<NSNumber *> *) windowNumbersWithOptions: (NSWindowNumberListOptions) options;
+ (void) removeFrameUsingName: (null_unspecified NSString *) name;

+ (nullable NSButton *) standardWindowButton: (NSWindowButton) button
                       forStyleMask: (NSWindowStyleMask) styleMask;
+ (void) menuChanged: (NSMenu *) menu;

- (instancetype) initWithContentRect: (NSRect) contentRect
                           styleMask: (NSWindowStyleMask) styleMask
                             backing: (NSBackingStoreType) backing
                               defer: (BOOL) defer;

- (instancetype) initWithContentRect: (NSRect) contentRect
                           styleMask: (NSWindowStyleMask) styleMask
                             backing: (NSBackingStoreType) backing
                               defer: (BOOL) defer
                              screen: (nullable NSScreen *) screen;

- (nullable NSWindow *) initWithWindowRef: (void *) carbonRef NS_RETURNS_NOT_RETAINED;

@property(nullable, nonatomic, readonly) NSGraphicsContext *graphicsContext;
@property(nonatomic, readonly) NSDictionary *deviceDescription;
- (void *) windowRef;
@property(nonatomic) BOOL allowsConcurrentViewDrawing;

@property (nullable, retain) __kindof NSView *contentView;
@property (nullable, weak) id<NSWindowDelegate> delegate;
// Setting it makes the controller's view the content view.
@property (nullable, retain) NSViewController *contentViewController;
// A titled, closable, miniaturizable, resizable window sized to the
// controller's preferredContentSize, or else its view, and titled after it.
+ (instancetype) windowWithContentViewController: (NSViewController *) contentViewController;

@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *representedFilename;
@property(nullable, nonatomic, copy) NSURL *representedURL;

@property(nonatomic) NSWindowLevel level;
@property(readonly) NSRect frame;
- (NSRect) frame;
@property(nonatomic) NSWindowStyleMask styleMask;
@property(nonatomic) NSBackingStoreType backingType;
@property(nonatomic) NSWindowBackingLocation preferredBackingLocation;
@property(nonatomic, readonly) NSWindowBackingLocation backingLocation;

@property(nonatomic) NSSize minSize;
@property(nonatomic) NSSize maxSize;
@property NSSize contentMinSize;
@property NSSize contentMaxSize;
@property NSSize minFullScreenContentSize;
@property NSSize maxFullScreenContentSize;

@property(nonatomic, getter=isOneShot) BOOL oneShot;
@property (getter=isOpaque) BOOL opaque;
- (BOOL) hasDynamicDepthLimit;
@property(nonatomic, getter=isReleasedWhenClosed) BOOL releasedWhenClosed;
@property(nonatomic) BOOL preventsApplicationTerminationWhenModal;
@property(nonatomic) BOOL hidesOnDeactivate;
- (BOOL) worksWhenModal;
@property(nonatomic, getter=isSheet, readonly) BOOL sheet;
@property(nonatomic) BOOL acceptsMouseMovedEvents;
@property(nonatomic, getter=isExcludedFromWindowsMenu) BOOL excludedFromWindowsMenu;
@property(nonatomic, getter=isAutodisplay) BOOL autodisplay;
- (BOOL) isFlushWindowDisabled;
- (NSWindowFrameAutosaveName) frameAutosaveName;
@property(nonatomic) BOOL hasShadow;
@property(nonatomic) BOOL ignoresMouseEvents;
@property(nonatomic) NSSize aspectRatio;
@property(nonatomic) NSSize contentAspectRatio;
@property(nonatomic) BOOL autorecalculatesKeyViewLoop;
@property(nonatomic) BOOL canHide;
- (BOOL) canStoreColor;
@property(nonatomic) BOOL showsResizeIndicator;
@property(nonatomic) BOOL showsToolbarButton;
@property(nonatomic) BOOL displaysWhenScreenProfileChanges;
@property(nonatomic, getter=isMovableByWindowBackground) BOOL movableByWindowBackground;
@property(nonatomic) BOOL allowsToolTipsWhenApplicationIsInactive;

- (BOOL) autorecalculatesContentBorderThicknessForEdge: (NSRectEdge) edge;
- (CGFloat) contentBorderThicknessForEdge: (NSRectEdge) edge;

@property(nullable, nonatomic, retain) NSImage *miniwindowImage;
@property(null_resettable, nonatomic, copy) NSString *miniwindowTitle;
@property(nonatomic, readonly) NSDockTile *dockTile;
@property(null_resettable, nonatomic, retain) NSColor *backgroundColor;
@property(nonatomic) CGFloat alphaValue;
@property(nonatomic) NSWindowDepth depthLimit;
@property(nonatomic) NSSize resizeIncrements;
@property(nonatomic) NSSize contentResizeIncrements;
@property(nonatomic) BOOL preservesContentDuringLiveResize;
@property(nullable, nonatomic, retain) NSToolbar *toolbar;
- (nullable NSView *) initialFirstResponder;

- (void) setFrame: (NSRect) frame display: (BOOL) display;
- (void) setFrame: (NSRect) frame display: (BOOL) display animate: (BOOL) flag;
- (void) setContentSize: (NSSize) contentSize;
- (void) setFrameOrigin: (NSPoint) point;
- (void) setFrameTopLeftPoint: (NSPoint) point;
- (void) setContentBorderThickness: (CGFloat) thickness
                           forEdge: (NSRectEdge) edge;

- (void) setDynamicDepthLimit: (BOOL) value;
- (void) setAutorecalculatesContentBorderThickness: (BOOL) automatic
                                           forEdge: (NSRectEdge) edge;
- (void) setTitleWithRepresentedFilename: (NSString *) filename;

- (void) setInitialFirstResponder: (nullable NSView *) view;

- (BOOL) setFrameUsingName: (null_unspecified NSString *) name;
- (BOOL) setFrameUsingName: (null_unspecified NSString *) name force: (BOOL) force;
- (BOOL) setFrameAutosaveName: (NSWindowFrameAutosaveName) name;
- (void) saveFrameUsingName: (null_unspecified NSString *) name;
- (void) setFrameFromString: (null_unspecified NSString *) value;
- (null_unspecified NSString *) stringWithSavedFrame;

- (NSEventModifierFlags) resizeFlags;
@property(nonatomic, readonly) CGFloat userSpaceScaleFactor;
@property(nonatomic, readonly) NSResponder *firstResponder;

- (nullable NSButton *) standardWindowButton: (NSWindowButton) value;
@property(nullable, nonatomic, retain) NSButtonCell *defaultButtonCell;
@property(nullable, nonatomic, readonly) NSWindow *attachedSheet;
@property(nullable, nonatomic, readonly) NSWindow *sheetParent;
@property(nullable, nonatomic, readonly) NSArray<NSWindow *> *tabbedWindows;

@property(null_unspecified, nonatomic, retain) id windowController;
- (null_unspecified NSArray *) drawers;

@property(nonatomic, readonly) NSInteger windowNumber;
- (int) gState;

@property(nullable, readonly, strong) NSScreen *screen;
@property(nullable, readonly, strong) NSScreen *deepestScreen;

- (nullable NSScreen *) screen;
- (nullable NSScreen *) deepestScreen;
@property(nullable, nonatomic, retain) NSColorSpace *colorSpace;
@property(nonatomic, getter=isOnActiveSpace, readonly) BOOL onActiveSpace;
@property(nonatomic) NSWindowSharingType sharingType;
@property(nonatomic) NSWindowAnimationBehavior animationBehavior;

@property(nonatomic, getter=isDocumentEdited) BOOL documentEdited;
@property(nonatomic, getter=isZoomed, readonly) BOOL zoomed;
@property(readonly) NSWindowOcclusionState occlusionState;

@property(nonatomic, getter=isVisible, readonly) BOOL visible;
- (void) setIsVisible: (BOOL) flag;
@property(nonatomic, getter=isKeyWindow, readonly) BOOL keyWindow;
@property(nonatomic, getter=isMainWindow, readonly) BOOL mainWindow;
@property(nonatomic, getter=isMiniaturized, readonly) BOOL miniaturized;
@property(nonatomic, getter=isMovable) BOOL movable;
- (void) performWindowDragWithEvent: (NSEvent *) event;
@property(nonatomic, readonly) BOOL inLiveResize;
@property(nonatomic, readonly) BOOL canBecomeKeyWindow;
@property(nonatomic, readonly) BOOL canBecomeMainWindow;
@property(nonatomic) BOOL canBecomeVisibleWithoutLogin;
@property(nonatomic) NSWindowCollectionBehavior collectionBehavior;

/* Window tabbing is not implemented, so the value is stored and ignored. */
@property(nonatomic) NSWindowTabbingMode tabbingMode;
@property(copy) NSWindowTabbingIdentifier tabbingIdentifier;

/* Title bar and toolbar appearance. The window manager draws the title bar,
 * so these are stored for callers to read back. */
@property(copy) NSString *subtitle;
@property NSWindowTitleVisibility titleVisibility;
@property BOOL titlebarAppearsTransparent;
@property NSTitlebarSeparatorStyle titlebarSeparatorStyle;
@property NSWindowToolbarStyle toolbarStyle;

- (NSPoint) convertBaseToScreen: (NSPoint) point;
- (NSPoint) convertScreenToBase: (NSPoint) point;
- (NSPoint) convertPointToScreen: (NSPoint) point;
- (NSPoint) convertPointFromScreen: (NSPoint) point;
- (NSRect) convertRectToScreen: (NSRect) rect;
- (NSRect) convertRectFromScreen: (NSRect) rect;
@property (readonly) CGFloat backingScaleFactor;
- (NSRect) convertRectToBacking: (NSRect) rect;
- (NSRect) convertRectFromBacking: (NSRect) rect;
- (NSPoint) convertPointToBacking: (NSPoint) point;
- (NSPoint) convertPointFromBacking: (NSPoint) point;
- (NSSize) convertSizeToBacking: (NSSize) size;
- (NSSize) convertSizeFromBacking: (NSSize) size;

- (void) beginSheet: (NSWindow *) sheet
        completionHandler: (void (^)(NSInteger returnCode)) handler;
- (void) endSheet: (NSWindow *) sheet;
- (void) endSheet: (NSWindow *) sheet returnCode: (NSInteger) returnCode;

@property(readonly, strong) NSAppearance *effectiveAppearance;

- (NSRect) frameRectForContentRect: (NSRect) rect;
- (NSRect) contentRectForFrameRect: (NSRect) rect;
@property(readonly) NSRect contentLayoutRect;
- (NSRect) backingAlignedRect: (NSRect) rect options: (NSAlignmentOptions) options;
- (NSRect) accessibilityFrame;
- (NSRect) constrainFrameRect: (NSRect) rect toScreen: (nullable NSScreen *) screen;

@property(nullable, nonatomic, retain) NSWindow *parentWindow;
@property(nullable, nonatomic, readonly) NSArray<__kindof NSWindow *> *childWindows;
- (void) addChildWindow: (NSWindow *) child
                ordered: (NSWindowOrderingMode) ordered;
- (void) removeChildWindow: (NSWindow *) child;

- (BOOL) makeFirstResponder: (nullable NSResponder *) responder;

- (void) makeKeyWindow;
- (void) makeMainWindow;

- (void) becomeKeyWindow;
- (void) resignKeyWindow;
- (void) becomeMainWindow;
- (void) resignMainWindow;

- (NSTimeInterval) animationResizeTime: (NSRect) frame;

- (void) selectNextKeyView: (nullable id) sender;
- (void) selectPreviousKeyView: (nullable id) sender;
- (void) selectKeyViewFollowingView: (NSView *) view;
- (void) selectKeyViewPrecedingView: (NSView *) view;
- (void) recalculateKeyViewLoop;
- (NSSelectionDirection) keyViewSelectionDirection;

- (void) disableKeyEquivalentForDefaultButtonCell;
- (void) enableKeyEquivalentForDefaultButtonCell;

- (nullable NSText *) fieldEditor: (BOOL) create forObject: (nullable id) object;
- (void) endEditingFor: (nullable id) object;

- (void) disableScreenUpdatesUntilFlush;
- (void) useOptimizedDrawing: (BOOL) flag;
@property(nonatomic) BOOL viewsNeedDisplay;
- (void) disableFlushWindow;
- (void) enableFlushWindow;
- (void) flushWindow;
- (void) flushWindowIfNeeded;
- (void) displayIfNeeded;
- (void) display;
- (void) updateConstraintsIfNeeded;
- (void) layoutIfNeeded;

- (void) invalidateShadow;

- (void) cacheImageInRect: (NSRect) rect;
- (void) restoreCachedImage;
- (void) discardCachedImage;

- (BOOL) areCursorRectsEnabled;
- (void) disableCursorRects;
- (void) enableCursorRects;
- (void) discardCursorRects;
- (void) resetCursorRects;
- (void) invalidateCursorRectsForView: (NSView *) view;

- (void) close;
- (void) center;
- (void) orderWindow: (NSWindowOrderingMode) place
          relativeTo: (NSInteger) relativeTo;
- (void) orderFrontRegardless;

- (NSPoint) mouseLocationOutsideOfEventStream;

- (nullable NSEvent *) currentEvent;
- (nullable NSEvent *) nextEventMatchingMask: (NSUInteger) mask;

- (nullable NSEvent *) nextEventMatchingMask: (NSUInteger) mask
                          untilDate: (nullable NSDate *) untilDate
                             inMode: (NSRunLoopMode) mode
                            dequeue: (BOOL) dequeue;

- (void) discardEventsMatchingMask: (NSUInteger) mask
                       beforeEvent: (nullable NSEvent *) event;

- (void) sendEvent: (NSEvent *) event;
- (void) postEvent: (NSEvent *) event atStart: (BOOL) atStart;

- (BOOL) tryToPerform: (SEL) selector with: (nullable id) object;
- (void) keyDown: (NSEvent *) event;

- (NSPoint) cascadeTopLeftFromPoint: (NSPoint) topLeftPoint;

- (NSData *) dataWithEPSInsideRect: (NSRect) rect;
- (NSData *) dataWithPDFInsideRect: (NSRect) rect;

- (void) registerForDraggedTypes: (NSArray *) types;
- (void) unregisterDraggedTypes;

- (void) dragImage: (NSImage *) image
                at: (NSPoint) location
            offset: (NSSize) offset
             event: (NSEvent *) event
        pasteboard: (NSPasteboard *) pasteboard
            source: (id) source
         slideBack: (BOOL) slideBack;

- (nullable id) validRequestorForSendType: (null_unspecified NSString *) sendType
                      returnType: (null_unspecified NSString *) returnType;

- (void) update;

- (void) makeKeyAndOrderFront: (nullable id) sender;
- (void) orderFront: (nullable id) sender;
- (void) orderBack: (nullable id) sender;
- (void) orderOut: (nullable id) sender;

- (void) performClose: (nullable id) sender;
- (void) performMiniaturize: (nullable id) sender;
- (void) performZoom: (nullable id) sender;

- (void) zoom: (nullable id) sender;
- (void) miniaturize: (nullable id) sender;
- (void) deminiaturize: (nullable id) sender;
- (void) print: (nullable id) sender;

- (void) toggleToolbarShown: (nullable id) sender;
- (void) runToolbarCustomizationPalette: (nullable id) sender;
- (void) toggleFullScreen: (nullable id) sender;

@end

@protocol NSWindowDelegate <NSObject>
@optional
- (void) windowWillBeginSheet: (NSNotification *) note;
- (void) windowDidEndSheet: (NSNotification *) note;
- (NSRect) window: (NSWindow *) window
        willPositionSheet: (NSWindow *) sheet
                usingRect: (NSRect) rect;

- (void) windowDidChangeScreen: (NSNotification *) note;
- (void) windowDidChangeScreenProfile: (NSNotification *) note;
- (void) windowDidExpose: (NSNotification *) note;
- (BOOL) windowShouldZoom: (NSWindow *) sender toFrame: (NSRect) frame;

- (nullable id) windowWillReturnFieldEditor: (NSWindow *) sender toObject: (nullable id) object;

- (NSRect) windowWillUseStandardFrame: (NSWindow *) sender
                         defaultFrame: (NSRect) frame;

- (nullable NSUndoManager *) windowWillReturnUndoManager: (NSWindow *) window;
- (void) windowDidBecomeKey: (NSNotification *) note;
- (void) windowDidResignKey: (NSNotification *) note;
- (void) windowDidBecomeMain: (NSNotification *) note;
- (void) windowDidResignMain: (NSNotification *) note;
- (void) windowWillMiniaturize: (NSNotification *) note;
- (void) windowDidMiniaturize: (NSNotification *) note;
- (void) windowDidDeminiaturize: (NSNotification *) note;
- (void) windowWillMove: (NSNotification *) note;
- (void) windowDidMove: (NSNotification *) note;
- (void) windowDidChangeOcclusionState: (NSNotification *) note;
- (NSSize) windowWillResize: (NSWindow *) sender toSize: (NSSize) size;
- (void) windowDidResize: (NSNotification *) note;
- (void) windowDidUpdate: (NSNotification *) note;
- (BOOL) windowShouldClose: (null_unspecified id) sender;
- (void) windowWillClose: (NSNotification *) note;

- (void) windowDidChangeBackingProperties: (NSNotification *) note;
- (void) windowWillStartLiveResize: (NSNotification *) note;
- (void) windowDidEndLiveResize: (NSNotification *) note;
- (void) windowWillEnterFullScreen: (NSNotification *) note;
- (void) windowDidEnterFullScreen: (NSNotification *) note;
- (void) windowWillExitFullScreen: (NSNotification *) note;
- (void) windowDidExitFullScreen: (NSNotification *) note;
- (void) windowWillEnterVersionBrowser: (NSNotification *) note;
- (void) windowDidEnterVersionBrowser: (NSNotification *) note;
- (void) windowWillExitVersionBrowser: (NSNotification *) note;
- (void) windowDidExitVersionBrowser: (NSNotification *) note;

// Declared for source compatibility: this implementation has no title-bar
// document icon, no custom full-screen animation and no version browser, so
// these are not sent.
- (BOOL) window: (NSWindow *) window shouldPopUpDocumentPathMenu: (NSMenu *) menu;
- (BOOL) window: (NSWindow *) window
        shouldDragDocumentWithEvent: (NSEvent *) event
                               from: (NSPoint) dragImageLocation
                     withPasteboard: (NSPasteboard *) pasteboard;
- (NSSize) window: (NSWindow *) window willUseFullScreenContentSize: (NSSize) proposedSize;
- (NSApplicationPresentationOptions) window: (NSWindow *) window
        willUseFullScreenPresentationOptions: (NSApplicationPresentationOptions) proposedOptions;
- (nullable NSArray<NSWindow *> *) customWindowsToEnterFullScreenForWindow: (NSWindow *) window;
- (nullable NSArray<NSWindow *> *) customWindowsToEnterFullScreenForWindow: (NSWindow *) window
                                                         onScreen: (NSScreen *) screen;
- (void) window: (NSWindow *) window startCustomAnimationToEnterFullScreenWithDuration: (NSTimeInterval) duration;
- (void) window: (NSWindow *) window
        startCustomAnimationToEnterFullScreenOnScreen: (NSScreen *) screen
                                         withDuration: (NSTimeInterval) duration;
- (void) windowDidFailToEnterFullScreen: (NSWindow *) window;
- (nullable NSArray<NSWindow *> *) customWindowsToExitFullScreenForWindow: (NSWindow *) window;
- (void) window: (NSWindow *) window startCustomAnimationToExitFullScreenWithDuration: (NSTimeInterval) duration;
- (void) windowDidFailToExitFullScreen: (NSWindow *) window;
- (NSSize) window: (NSWindow *) window
        willResizeForVersionBrowserWithMaxPreferredSize: (NSSize) maxPreferredFrameSize
                                         maxAllowedSize: (NSSize) maxAllowedFrameSize;
- (void) window: (NSWindow *) window willEncodeRestorableState: (NSCoder *) state;
- (void) window: (NSWindow *) window didDecodeRestorableState: (NSCoder *) state;

- (null_unspecified CGSubWindow *) _createSubWindowWithFrame: (CGRect) frame;

@end

@interface NSWindow (NSWindowTitlebarAccessories)
// Stored only: accessories aren't shown.
@property(readonly, copy) NSArray<__kindof NSTitlebarAccessoryViewController *> *titlebarAccessoryViewControllers;
- (void) addTitlebarAccessoryViewController:
        (NSTitlebarAccessoryViewController *) controller;
@end

@interface NSWindow (NSWindowTitlebarAccessoryIndexing)
// Index 0 is the first accessory. An index past the end raises.
- (void) insertTitlebarAccessoryViewController:
                 (NSTitlebarAccessoryViewController *) controller
                                       atIndex: (NSInteger) index;
- (void) removeTitlebarAccessoryViewControllerAtIndex: (NSInteger) index;
@end

@interface NSWindow (NSWindowAdditionalAPI)

// The sheets attached to the window: at most one, as sheets aren't queued.
@property(readonly, copy) NSArray<__kindof NSWindow *> *sheets;
// A critical sheet is presented like any other sheet; there is no separate
// queue for it.
- (void) beginCriticalSheet: (NSWindow *) sheetWindow
          completionHandler: (void (^_Nullable)(NSModalResponse returnCode)) handler;

// The window's own appearance, else the source's, else the application's.
// Resetting to nil makes the application the source.
@property(weak, null_resettable) NSObject<NSAppearanceCustomization> *appearanceSource;

// The windows here only have an sRGB backing store.
- (BOOL) canRepresentDisplayGamut: (NSDisplayGamut) displayGamut;

// From the AppleWindowTabbingMode default (always, manual, else in full screen).
@property(class, readonly) NSWindowUserTabbingPreference userTabbingPreference;

// The application's layout direction.
@property(readonly) NSUserInterfaceLayoutDirection windowTitlebarLayoutDirection;

// The frame cascading starts from: the window's frame.
@property(readonly) NSRect cascadingReferenceFrame;

// Window tabbing is not implemented, so every window is the only tab of its
// own tab group and these have no effect.
- (void) selectNextTab: (nullable id) sender;
- (void) selectPreviousTab: (nullable id) sender;
- (void) moveTabToNewWindow: (nullable id) sender;
- (void) toggleTabBar: (nullable id) sender;
- (void) toggleTabOverview: (nullable id) sender;

// Takes events matching the mask from the event queue in the given mode and
// passes them to the handler until it sets *stop. When no event arrives for
// `timeout` seconds the handler is called with a nil event.
- (void) trackEventsMatchingMask: (NSEventMask) mask
                         timeout: (NSTimeInterval) timeout
                            mode: (NSRunLoopMode) mode
                         handler: (void (^)(NSEvent *_Nullable event, BOOL *stop)) trackingHandler;

@end

@interface NSWindow (Darling)
- (null_unspecified CGWindow *) platformWindow;
@end

// Private AppKit compatibility used by older window subclasses.
@interface NSWindow (NSPrivateCornerStyle)
@property(nonatomic) BOOL bottomCornerRounded;
@end

// private
APPKIT_EXPORT const NSNotificationName NSWindowWillAnimateNotification;
APPKIT_EXPORT const NSNotificationName NSWindowAnimatingNotification;
APPKIT_EXPORT const NSNotificationName NSWindowDidAnimateNotification;

APPKIT_EXPORT NSNotificationName const NSWindowDidChangeBackingPropertiesNotification;
APPKIT_EXPORT NSString * const NSBackingPropertyOldColorSpaceKey;

NS_ASSUME_NONNULL_END
