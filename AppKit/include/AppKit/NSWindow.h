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

#import <AppKit/AppKitExport.h>
#import <AppKit/NSResponder.h>
#import <AppKit/NSView.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CGSubWindow.h>

@class NSView, NSEvent, NSColor, NSColorSpace, NSCursor, NSImage, NSScreen,
    NSText, NSTextView, CGWindow, NSPasteboard, NSSheetContext, NSUndoManager,
    NSButton, NSButtonCell, NSDrawer, NSDockTile, NSToolbar,
    NSWindowAnimationContext, NSTrackingArea, NSThemeFrame, NSWindowController,
    NSMenuItem, CARenderer;
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
    NSWindiwStyleMaskUnifiedTitleAndToolbar = 0x1000,
    NSWindowStyleMaskFullScreen = 0x4000,
    NSWindowStyleMaskFullSizeContentView = 0x8000,
    // NSPanel only:
    NSWindowStyleMaskUtilityWindow = 0x10,
    NSWindowStyleMaskDocModalWindow = 0x40,
    NSWindowStyleMaskNonactivatingPanel = 0x80,
    NSWindowStyleMaskHUDWindow = 0x2000,
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

enum {
    NSNormalWindowLevel = kCGNormalWindowLevel,
    NSFloatingWindowLevel = kCGFloatingWindowLevel,
    NSSubmenuWindowLevel = kCGTornOffMenuWindowLevel,
    NSTornOffMenuWindowLevel = kCGTornOffMenuWindowLevel,
    NSMainMenuWindowLevel = kCGMainMenuWindowLevel,
    NSStatusWindowLevel = kCGStatusWindowLevel,
    NSModalPanelWindowLevel = kCGModalPanelWindowLevel,
    NSPopUpMenuWindowLevel = kCGPopUpMenuWindowLevel,
    NSScreenSaverWindowLevel = kCGScreenSaverWindowLevel,
};
typedef NSInteger NSWindowLevel;

typedef NS_OPTIONS(NSUInteger, NSWindowCollectionBehavior) {
    NSWindowCollectionBehaviorDefault = 0x00,
    NSWindowCollectionBehaviorCanJoinAllSpaces = 0x01,
    NSWindowCollectionBehaviorMoveToActiveSpace = 0x02,
    NSWindowCollectionBehaviorManaged = 0x04,
    NSWindowCollectionBehaviorTransient = 0x08,
    NSWindowCollectionBehaviorStationary = 0x10,
    NSWindowCollectionBehaviorParticipatesInCycle = 0x20,
    NSWindowCollectionBehaviorIgnoresCycle = 0x40
};

typedef NS_ENUM(NSUInteger, NSWindowSharingType) {
    NSWindowSharingNone = 0x00,
    NSWindowSharingReadOnly = 0x01,
    NSWindowSharingReadWrite = 0x02
};

typedef int NSSelectionDirection;

APPKIT_EXPORT const NSNotificationName NSWindowDidBecomeKeyNotification;
APPKIT_EXPORT const NSNotificationName NSWindowDidResignKeyNotification;
APPKIT_EXPORT const NSNotificationName NSWindowDidBecomeMainNotification;
APPKIT_EXPORT const NSNotificationName NSWindowDidResignMainNotification;
APPKIT_EXPORT const NSNotificationName NSWindowWillMiniaturizeNotification;
APPKIT_EXPORT const NSNotificationName NSWindowDidMiniaturizeNotification;
APPKIT_EXPORT const NSNotificationName NSWindowDidDeminiaturizeNotification;
APPKIT_EXPORT const NSNotificationName NSWindowWillMoveNotification;
APPKIT_EXPORT const NSNotificationName NSWindowDidMoveNotification;
APPKIT_EXPORT const NSNotificationName NSWindowDidResizeNotification;
APPKIT_EXPORT const NSNotificationName NSWindowDidUpdateNotification;
APPKIT_EXPORT const NSNotificationName NSWindowWillCloseNotification;
APPKIT_EXPORT const NSNotificationName NSWindowWillStartLiveResizeNotification;
APPKIT_EXPORT const NSNotificationName NSWindowDidEndLiveResizeNotification;
APPKIT_EXPORT const NSNotificationName NSWindowWillBeginSheetNotification;

APPKIT_EXPORT const NSNotificationName NSWindowDidChangeScreenNotification;
APPKIT_EXPORT const NSNotificationName NSWindowDidEndSheetNotification;
APPKIT_EXPORT const NSNotificationName NSWindowDidEnterFullScreenNotification;
APPKIT_EXPORT const NSNotificationName NSWindowDidExitFullScreenNotification;
APPKIT_EXPORT const NSNotificationName NSWindowDidOrderOffScreenNotification;
APPKIT_EXPORT const NSNotificationName NSWindowDidOrderOnScreenNotification;
APPKIT_EXPORT const NSNotificationName NSWindowWillEnterFullScreenNotification;
APPKIT_EXPORT const NSNotificationName NSWindowWillExitFullScreenNotification;
APPKIT_EXPORT const NSNotificationName NSWindowDidExposeNotification;

@interface NSWindow : NSResponder {
    NSRect _frame;
    NSWindowStyleMask _styleMask;
    NSBackingStoreType _backingType;
    NSWindowLevel _level;

    NSSize _minSize;
    NSSize _maxSize;
    NSSize _contentMinSize;
    NSSize _contentMaxSize;

    NSWindow *_parentWindow;
    NSMutableArray<NSWindow *> *_childWindows;

    NSString *_representedFilename;
    NSString *_title;
    NSString *_miniwindowTitle;
    NSImage *_miniwindowImage;

    NSThemeFrame *_backgroundView;
    NSMenu *_menu;
    NSView *_menuView;
    NSView *_contentView;
    NSColor *_backgroundColor;

    id<NSWindowDelegate> _delegate;
    NSResponder *_firstResponder;

    NSTextView *_sharedFieldEditor;
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
    BOOL _allowsToolTipsWhenApplicationIsInactive;
    BOOL _defaultButtonCellKeyEquivalentDisabled;
    BOOL _autorecalculatesKeyViewLoop;
    BOOL _hasBeenOnScreen;

    BOOL _isInLiveResize;
    BOOL _preservesContentDuringLiveResize;
    NSSize _resizeIncrements;
    NSSize _contentResizeIncrements;

    NSString *_autosaveFrameName;

    CGWindow *_platformWindow;
    NSMutableDictionary *_threadToContext;

    NSUndoManager *_undoManager;
    NSView *_initialFirstResponder;
    NSButtonCell *_defaultButtonCell;

    NSWindowController *_windowController;
    NSMutableArray *_drawers;
    NSToolbar *_toolbar;
    NSWindowAnimationContext *_animationContext;

    NSRect _savedFrame;
    NSPoint _mouseDownLocationInWindow;
}

@property(class) BOOL allowsAutomaticWindowTabbing;

+ (NSWindowDepth) defaultDepthLimit;

+ (NSRect) frameRectForContentRect: (NSRect) contentRect
                         styleMask: (NSWindowStyleMask) styleMask;
+ (NSRect) contentRectForFrameRect: (NSRect) frameRect
                         styleMask: (NSWindowStyleMask) styleMask;
+ (CGFloat) minFrameWidthWithTitle: (NSString *) title
                         styleMask: (NSWindowStyleMask) styleMask;
+ (NSInteger) windowNumberAtPoint: (NSPoint) point
      belowWindowWithWindowNumber: (NSInteger) window;
+ (NSArray *) windowNumbersWithOptions: (NSWindowNumberListOptions) options;
+ (void) removeFrameUsingName: (NSString *) name;

+ (NSButton *) standardWindowButton: (NSWindowButton) button
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
                              screen: (NSScreen *) screen;

- (NSWindow *) initWithWindowRef: (void *) carbonRef NS_RETURNS_NOT_RETAINED;

- (NSGraphicsContext *) graphicsContext;
- (NSDictionary *) deviceDescription;
- (void *) windowRef;
- (BOOL) allowsConcurrentViewDrawing;
- (void) setAllowsConcurrentViewDrawing: (BOOL) allows;

- (NSView *) contentView;
- (id<NSWindowDelegate>) delegate;

- (NSString *) title;
- (NSString *) representedFilename;
- (NSURL *) representedURL;

- (NSWindowLevel) level;
@property(readonly) NSRect frame;
- (NSRect) frame;
- (NSWindowStyleMask) styleMask;
- (NSBackingStoreType) backingType;
- (NSWindowBackingLocation) preferredBackingLocation;
- (void) setPreferredBackingLocation: (NSWindowBackingLocation) location;
- (NSWindowBackingLocation) backingLocation;

- (NSSize) minSize;
- (NSSize) maxSize;
- (NSSize) contentMinSize;
- (NSSize) contentMaxSize;

- (BOOL) isOneShot;
- (BOOL) isOpaque;
- (BOOL) hasDynamicDepthLimit;
- (BOOL) isReleasedWhenClosed;
- (BOOL) preventsApplicationTerminationWhenModal;
- (void) setPreventsApplicationTerminationWhenModal: (BOOL) prevents;
- (BOOL) hidesOnDeactivate;
- (BOOL) worksWhenModal;
- (BOOL) isSheet;
- (BOOL) acceptsMouseMovedEvents;
- (BOOL) isExcludedFromWindowsMenu;
- (BOOL) isAutodisplay;
- (BOOL) isFlushWindowDisabled;
- (NSString *) frameAutosaveName;
- (BOOL) hasShadow;
- (BOOL) ignoresMouseEvents;
- (NSSize) aspectRatio;
- (NSSize) contentAspectRatio;
- (BOOL) autorecalculatesKeyViewLoop;
- (BOOL) canHide;
- (BOOL) canStoreColor;
- (BOOL) showsResizeIndicator;
- (BOOL) showsToolbarButton;
- (BOOL) displaysWhenScreenProfileChanges;
- (BOOL) isMovableByWindowBackground;
- (BOOL) allowsToolTipsWhenApplicationIsInactive;

- (BOOL) autorecalculatesContentBorderThicknessForEdge: (NSRectEdge) edge;
- (CGFloat) contentBorderThicknessForEdge: (NSRectEdge) edge;

- (NSImage *) miniwindowImage;
- (NSString *) miniwindowTitle;
- (NSDockTile *) dockTile;
- (NSColor *) backgroundColor;
- (CGFloat) alphaValue;
- (NSWindowDepth) depthLimit;
- (NSSize) resizeIncrements;
- (NSSize) contentResizeIncrements;
- (BOOL) preservesContentDuringLiveResize;
- (NSToolbar *) toolbar;
- (NSView *) initialFirstResponder;

- (void) setDelegate: (id<NSWindowDelegate>) delegate;
- (void) setFrame: (NSRect) frame display: (BOOL) display;
- (void) setFrame: (NSRect) frame display: (BOOL) display animate: (BOOL) flag;
- (void) setContentSize: (NSSize) contentSize;
- (void) setFrameOrigin: (NSPoint) point;
- (void) setFrameTopLeftPoint: (NSPoint) point;
- (void) setStyleMask: (NSWindowStyleMask) styleMask;
- (void) setMinSize: (NSSize) size;
- (void) setMaxSize: (NSSize) size;
- (void) setContentMinSize: (NSSize) value;
- (void) setContentMaxSize: (NSSize) value;
- (void) setContentBorderThickness: (CGFloat) thickness
                           forEdge: (NSRectEdge) edge;
- (void) setMovable: (BOOL) movable;

- (void) setBackingType: (NSBackingStoreType) value;
- (void) setDynamicDepthLimit: (BOOL) value;
- (void) setOneShot: (BOOL) flag;
- (void) setReleasedWhenClosed: (BOOL) flag;
- (void) setHidesOnDeactivate: (BOOL) flag;
- (void) setAcceptsMouseMovedEvents: (BOOL) flag;
- (void) setExcludedFromWindowsMenu: (BOOL) value;
- (void) setAutodisplay: (BOOL) value;
- (void) setAutorecalculatesContentBorderThickness: (BOOL) automatic
                                           forEdge: (NSRectEdge) edge;
- (void) setTitle: (NSString *) title;
- (void) setTitleWithRepresentedFilename: (NSString *) filename;
- (void) setContentView: (NSView *) view;

- (void) setInitialFirstResponder: (NSView *) view;
- (void) setMiniwindowImage: (NSImage *) image;
- (void) setMiniwindowTitle: (NSString *) title;
- (void) setBackgroundColor: (NSColor *) color;
- (void) setAlphaValue: (CGFloat) value;
- (void) setToolbar: (NSToolbar *) toolbar;
- (void) setDefaultButtonCell: (NSButtonCell *) cell;
- (void) setWindowController: (NSWindowController *) value;
- (void) setDocumentEdited: (BOOL) flag;
- (void) setContentAspectRatio: (NSSize) value;
- (void) setHasShadow: (BOOL) value;
- (void) setIgnoresMouseEvents: (BOOL) value;
- (void) setAspectRatio: (NSSize) value;
- (void) setAutorecalculatesKeyViewLoop: (BOOL) value;
- (void) setCanHide: (BOOL) value;
- (void) setCanBecomeVisibleWithoutLogin: (BOOL) flag;
- (void) setCollectionBehavior: (NSWindowCollectionBehavior) behavior;
- (void) setLevel: (NSInteger) value;
- (void) setOpaque: (BOOL) value;
- (void) setParentWindow: (NSWindow *) value;
- (void) setPreservesContentDuringLiveResize: (BOOL) value;
- (void) setRepresentedFilename: (NSString *) value;
- (void) setRepresentedURL: (NSURL *) newURL;
- (void) setResizeIncrements: (NSSize) value;
- (void) setShowsResizeIndicator: (BOOL) value;
- (void) setShowsToolbarButton: (BOOL) value;
- (void) setContentResizeIncrements: (NSSize) value;
- (void) setDepthLimit: (NSWindowDepth) value;
- (void) setDisplaysWhenScreenProfileChanges: (BOOL) value;
- (void) setMovableByWindowBackground: (BOOL) value;
- (void) setAllowsToolTipsWhenApplicationIsInactive: (BOOL) value;

- (BOOL) setFrameUsingName: (NSString *) name;
- (BOOL) setFrameUsingName: (NSString *) name force: (BOOL) force;
- (BOOL) setFrameAutosaveName: (NSString *) name;
- (void) saveFrameUsingName: (NSString *) name;
- (void) setFrameFromString: (NSString *) value;
- (NSString *) stringWithSavedFrame;

- (NSEventModifierFlags) resizeFlags;
- (CGFloat) userSpaceScaleFactor;
- (NSResponder *) firstResponder;

- (NSButton *) standardWindowButton: (NSWindowButton) value;
- (NSButtonCell *) defaultButtonCell;
- (NSWindow *) attachedSheet;

- (id) windowController;
- (NSArray *) drawers;

- (NSInteger) windowNumber;
- (int) gState;

@property(readonly, strong) NSScreen *screen;
@property(readonly, strong) NSScreen *deepestScreen;

- (NSScreen *) screen;
- (NSScreen *) deepestScreen;
- (NSColorSpace *) colorSpace;
- (void) setColorSpace: (NSColorSpace *) newColorSpace;
- (BOOL) isOnActiveSpace;
- (NSWindowSharingType) sharingType;
- (void) setSharingType: (NSWindowSharingType) type;

- (BOOL) isDocumentEdited;
- (BOOL) isZoomed;
- (BOOL) isVisible;
- (BOOL) isKeyWindow;
- (BOOL) isMainWindow;
- (BOOL) isMiniaturized;
- (BOOL) isMovable;
- (BOOL) inLiveResize;
- (BOOL) canBecomeKeyWindow;
- (BOOL) canBecomeMainWindow;
- (BOOL) canBecomeVisibleWithoutLogin;
- (NSWindowCollectionBehavior) collectionBehavior;

- (NSPoint) convertBaseToScreen: (NSPoint) point;
- (NSPoint) convertScreenToBase: (NSPoint) point;

- (NSRect) frameRectForContentRect: (NSRect) rect;
- (NSRect) contentRectForFrameRect: (NSRect) rect;
- (NSRect) constrainFrameRect: (NSRect) rect toScreen: (NSScreen *) screen;

- (NSWindow *) parentWindow;
- (NSArray *) childWindows;
- (void) addChildWindow: (NSWindow *) child
                ordered: (NSWindowOrderingMode) ordered;
- (void) removeChildWindow: (NSWindow *) child;

- (BOOL) makeFirstResponder: (NSResponder *) responder;

- (void) makeKeyWindow;
- (void) makeMainWindow;

- (void) becomeKeyWindow;
- (void) resignKeyWindow;
- (void) becomeMainWindow;
- (void) resignMainWindow;

- (NSTimeInterval) animationResizeTime: (NSRect) frame;

- (void) selectNextKeyView: sender;
- (void) selectPreviousKeyView: sender;
- (void) selectKeyViewFollowingView: (NSView *) view;
- (void) selectKeyViewPrecedingView: (NSView *) view;
- (void) recalculateKeyViewLoop;
- (NSSelectionDirection) keyViewSelectionDirection;

- (void) disableKeyEquivalentForDefaultButtonCell;
- (void) enableKeyEquivalentForDefaultButtonCell;

- (NSText *) fieldEditor: (BOOL) create forObject: object;
- (void) endEditingFor: object;

- (void) disableScreenUpdatesUntilFlush;
- (void) useOptimizedDrawing: (BOOL) flag;
- (BOOL) viewsNeedDisplay;
- (void) setViewsNeedDisplay: (BOOL) flag;
- (void) disableFlushWindow;
- (void) enableFlushWindow;
- (void) flushWindow;
- (void) flushWindowIfNeeded;
- (void) displayIfNeeded;
- (void) display;

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

- (NSEvent *) currentEvent;
- (NSEvent *) nextEventMatchingMask: (NSEventMask) mask;

- (NSEvent *) nextEventMatchingMask: (NSEventMask) mask
                          untilDate: (NSDate *) untilDate
                             inMode: (NSRunLoopMode) mode
                            dequeue: (BOOL) dequeue;

- (void) discardEventsMatchingMask: (NSEventMask) mask
                       beforeEvent: (NSEvent *) event;

- (void) sendEvent: (NSEvent *) event;
- (void) postEvent: (NSEvent *) event atStart: (BOOL) atStart;

- (BOOL) tryToPerform: (SEL) selector with: (id) object;
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

- (id) validRequestorForSendType: (NSString *) sendType
                      returnType: (NSString *) returnType;

- (void) update;

- (void) makeKeyAndOrderFront: sender;
- (void) orderFront: sender;
- (void) orderBack: sender;
- (void) orderOut: sender;

- (void) performClose: sender;
- (void) performMiniaturize: sender;
- (void) performZoom: sender;

- (void) zoom: sender;
- (void) miniaturize: sender;
- (void) deminiaturize: sender;
- (void) print: sender;

- (void) toggleToolbarShown: sender;
- (void) runToolbarCustomizationPalette: sender;
- (void) toggleFullScreen: (id) sender;

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

- windowWillReturnFieldEditor: (NSWindow *) sender toObject: object;

- (NSRect) windowWillUseStandardFrame: (NSWindow *) sender
                         defaultFrame: (NSRect) frame;

- (NSUndoManager *) windowWillReturnUndoManager: (NSWindow *) window;
- (void) windowDidBecomeKey: (NSNotification *) note;
- (void) windowDidResignKey: (NSNotification *) note;
- (void) windowDidBecomeMain: (NSNotification *) note;
- (void) windowDidResignMain: (NSNotification *) note;
- (void) windowWillMiniaturize: (NSNotification *) note;
- (void) windowDidMiniaturize: (NSNotification *) note;
- (void) windowDidDeminiaturize: (NSNotification *) note;
- (void) windowWillMove: (NSNotification *) note;
- (void) windowDidMove: (NSNotification *) note;
- (NSSize) windowWillResize: (NSWindow *) sender toSize: (NSSize) size;
- (void) windowDidResize: (NSNotification *) note;
- (void) windowDidUpdate: (NSNotification *) note;
- (BOOL) windowShouldClose: sender;
- (void) windowWillClose: (NSNotification *) note;

- (CGSubWindow *) _createSubWindowWithFrame: (CGRect) frame;

@end

@interface NSWindow (Darling)
- (CGWindow *) platformWindow;
@end

// private
APPKIT_EXPORT const NSNotificationName NSWindowWillAnimateNotification;
APPKIT_EXPORT const NSNotificationName NSWindowAnimatingNotification;
APPKIT_EXPORT const NSNotificationName NSWindowDidAnimateNotification;
