/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

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

#import <AppKit/NSWindow.h>
#import <AppKit/NSDisplay.h>

@class CGWindow;

// style flag for private windows (that NSApp doesn't have to know about)
#define NSAppKitPrivateWindow 0x8000000

@interface NSWindow (NSWindow_private)
- (CGWindow *) platformWindow;
// Whether a window with this style mask shows nothing of a title bar of its
// own; the window system then gives it no frame either.
- (BOOL) _hasInvisibleTitlebarForStyleMask: (NSUInteger) styleMask;
// Whether a window with this style mask has a title bar at all: a titled
// window, or a resizable one in a program built against an SDK older than
// 10.7 (see the QUIRK in NSWindow.m).
- (BOOL) _hasTitlebarForStyleMask: (NSUInteger) styleMask;
// The CGSToplevelTitlebarKind of the window, and telling the platform window of it.
- (int) _titlebarKindForStyleMask: (NSUInteger) styleMask;
- (void) _updatePlatformTitlebarKindForStyleMask: (NSUInteger) styleMask;
// What the window is to the window system: a DarlingWindowPresentation (see
// DarlingWindowPresentation.h), decided from the window's current state.
- (int) _windowPresentation;
// The smallest and largest frame sizes that user resizing is limited to: minSize and maxSize, but
// only in a dimension where the content limit is set, so that the title bar a window always has is not
// a limit of its own. A 0 minimum or a maximum of FLT_MAX or more (or of 0 or less) is no limit.
- (NSSize) _minFrameSize;
- (NSSize) _maxFrameSize;
- (CGContextRef) cgContext;
- (BOOL) _isActive;
- (BOOL) _isHiddenForDeactivation;
// Whether the window is being closed on behalf of the user (see
// -_closeOnBehalfOfUser) at this moment.
- (BOOL) _isClosingByUser;
- (void) _closeOnBehalfOfUser;
- (void) _setVisible: (BOOL) visible;
// Whether the window is shown and not miniaturized, which is when the views
// in it count as appeared for their view controllers.
- (BOOL) _isShownForViewAppearance;
- (NSArray *) _draggedTypes;
- (void) _addCursorRect: (NSRect) rect
                 cursor: (NSCursor *) cursor
                   view: (NSView *) view;
- (void) _removeCursorRect: (NSRect) rect
                    cursor: (NSCursor *) cursor
                      view: (NSView *) view;
- (void) _discardCursorRectsForView: (NSView *) view;
- (void) _discardTrackingRectsForView: (NSView *) view
                         toolTipsOnly: (BOOL) toolTipsOnly;
- (NSTrackingRectTag) _addTrackingRect: (NSRect) rect
                                  view: (NSView *) view
                               flipped: (BOOL) flipped
                                 owner: owner
                              userData: (void *) userData
                          assumeInside: (BOOL) assumeInside
                             isToolTip: (BOOL) isToolTip;
- (void) _removeTrackingRect: (NSTrackingRectTag) tag;
- (void) _removeAllToolTips;
- (void) _attachSheetContextOrderFrontAndAnimate:
        (NSSheetContext *) sheetContext;
- (void) _setSheetContext: (NSSheetContext *) sheetContext;
- (NSSheetContext *) _sheetContext;
- (void) _detachSheetContextAnimateAndOrderOut;
- (void) _attachDrawer: (NSDrawer *) drawer;
- (void) _detachDrawer: (NSDrawer *) drawer;
// Takes a child window off this window's child windows.
- (void) _detachChildWindow: (NSWindow *) child;
// Moves the attached child windows along with this window.
- (void) _moveChildWindowsBy: (NSSize) delta;
- (NSView *) _backgroundView;
- (void) _fitContentSizeToConstraints;
- (void) _layoutAndDisplayIfNeeded;
- (void) _hideMenuViewIfNeeded;
- (void) _showMenuViewIfNeeded;
- (void) _updateTrackingAreas;
- (void) _invalidateTrackingAreas;
- (void) _setFrameAutosaveNameNoIO: (NSString *) name;
- (NSWindowAnimationContext *) _animationContext;
- (void) undo: sender;
- (void) redo: sender;
- (BOOL) validateMenuItem: (NSMenuItem *) item;
- (void) dirtyRect: (NSRect) rect;
// The restoration class that -encodeRestorableStateWithCoder: recorded in state, or Nil.
+ (Class) _restorationClassFromState: (NSCoder *) state;
@end

// Sent by NSWindow to a platform window that implements it when one of the size limits changed.
@interface NSObject (NSWindow_sizeLimits)
- (void) sizeLimitsChanged;
@end

// Sent by NSWindow when the color space of its content changes.
@interface NSObject (NSWindow_colorSpace)
- (void) colorSpaceChanged;
@end

@interface NSApplication (NSApplication_private)
// Posts NSApplicationDidChangeOcclusionStateNotification when -occlusionState changed.
- (void) _updateOcclusionState;
@end

// Used by the persistent window state restoration in NSStateRestoration.m.
@interface NSView (NSStateRestoration)
// Whether -invalidateRestorableState was called.
- (BOOL) _hasInvalidatedRestorableState;
@end

@interface NSWindow (NSStateRestoration)
// Whether the window was closed and not ordered in since.
- (BOOL) _isClosedForRestoration;
// The name this window has in the window-system session. Setting it before the native window
// exists takes effect when the native window is created. A restoring name is used only if it can
// be sent before the first commit; backends fall back to adding a new session entry otherwise.
- (void) _setSessionToplevelName: (NSString *) name restoring: (BOOL) restoring;
- (NSString *) _sessionToplevelName;
- (BOOL) _isRestoringSessionToplevel;
@end

@interface NSDisplay (NSSessionRestoration)
// Starts the window-system session before restored windows are mapped. A backend without sessions
// ignores this. The identifier is the one the compositor gave the previous session.
- (void) beginWindowSessionWithReason: (NSUInteger) reason identifier: (NSString *) identifier;
// The identifier of the current session, for saving with the application state; nil if none.
- (NSString *) windowSessionIdentifier;
// Whether the window system offers sessions. The marker file of a running application (see
// NSStateRestoration.m) is only written and read where it does.
- (BOOL) supportsWindowSessions;
@end

// Persistent window state restoration, in NSStateRestoration.m.
@interface NSApplication (NSStateRestoration)
- (void) _saveRestorableStateForTermination;
- (void) _restoreWindowsFromSavedState;
- (void) _finishRestoringWindowsAfterLaunch;
- (void) _applyRestoredState: (NSData *) stateData toWindow: (NSWindow *) window;
- (void) _postDidFinishRestoringWindowsIfDone;
- (void) _extendStateRestoration;
- (void) _completeStateRestoration;
- (BOOL) _restorableStateUsesSecureCoding;
// A marker left while the application is running lets the next launch distinguish a clean
// exit from a crash, and carries the session identifier when no saved state was written. It exists
// only where the window system has sessions (-[NSDisplay supportsWindowSessions]).
- (void) _writeWindowSessionMarkerWithIdentifier: (NSString *) identifier;
- (void) _removeWindowSessionMarker;
@end

// Defined in NSView.m.
extern NSRect _NSAlignRectToPixelGrid(NSRect rect,
                                    NSAlignmentOptions options);
