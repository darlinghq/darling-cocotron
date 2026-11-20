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
- (CGContextRef) cgContext;
- (BOOL) _isActive;
- (BOOL) _isHiddenForDeactivation;
- (void) _setVisible: (BOOL) visible;
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

@interface NSApplication (NSApplication_private)
// Posts NSApplicationDidChangeOcclusionStateNotification when -occlusionState changed.
- (void) _updateOcclusionState;
@end

// Defined in NSView.m.
extern NSRect _NSAlignRectToPixelGrid(NSRect rect,
                                    NSAlignmentOptions options);
