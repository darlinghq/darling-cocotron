/*
 This file is part of Darling.

 Copyright (C) 2020 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/
#ifndef CGSWINDOW_H
#define CGSWINDOW_H
#import <Foundation/NSObject.h>
#import <Foundation/NSDictionary.h>
#include <CoreGraphics/CoreGraphicsPrivate.h>
#include <stdatomic.h>

@class CGSSurface;
@class CGSConnection;
@class CGSWindow;
@protocol CGSDragDestination;

// What the window system tells about a toplevel window of the UI layer (see -setToplevelEventProc:info:).
// The events are those of the UI layer's window callbacks: a backend posts the ones its window system has.
typedef enum {
	kCGSToplevelEventCloseRequested = 1,  // the user asked the window system to close the window
	kCGSToplevelEventWillMove,            // the user starts moving the window
	kCGSToplevelEventDidMove,             // the user is done moving it
	kCGSToplevelEventWillBeginSizing,     // the user starts resizing the window
	kCGSToplevelEventDidEndSizing,        // the user is done resizing it
	// The window's frame (rect: the space of -setToplevelFrame:) changed, or the window system reported it
	// again; resized says whether the size is not the one last known.
	kCGSToplevelEventFrameChanged,
	// The window system asks for the window to be painted again: rect is the area, in points from the
	// window's top left corner, y down, the union of the areas the window system reported together.
	kCGSToplevelEventExposed,
	// The window's device pixels per point changed from oldScale; it already has the new frame size in
	// pixels and answers the new scale from -toplevelBackingScaleFactor.
	kCGSToplevelEventBackingScaleChanged,
	// The window holds the keyboard focus of the window system, or no longer does. Only the changes of the
	// window system's focus: a grab or the pointer passing over the window is not one.
	kCGSToplevelEventFocusGained,
	kCGSToplevelEventFocusLost,
	// Whether another client's window covers this one changed (state: it is covered now). Also posted, with the
	// state unchanged, whenever the window system's state of the window changed (see kCGSToplevelEventStateChanged),
	// so that the UI layer judges what it derives from it again.
	kCGSToplevelEventOcclusionChanged,
	// The window system hid the window in its task list (miniaturized it), or showed it again, whoever asked.
	kCGSToplevelEventMiniaturized,
	kCGSToplevelEventDeminiaturized,
	// The window system holds the window fullscreen (state: yes) or no longer does, whoever asked.
	kCGSToplevelEventFullscreenChanged,
	// The window system's state of the window (miniaturized, fullscreen) was read again. Follows the events above
	// that the change caused, and is also posted when none applies.
	kCGSToplevelEventStateChanged,
	// The window's input method (see CGSInputMethod.h) changed what it composes: text is the whole composition
	// and textRange the caret or selected part of it, in UTF-16 units; empty text means no composition any more.
	kCGSToplevelEventInputMethodPreedit,
	// The input method's final text (text), which replaces the composition if there is one.
	kCGSToplevelEventInputMethodCommit,
	// The window system configured the window: it chose a size and told the window's state (see CGSToplevelConfigure).
	// Posted by window systems whose manager decides the size and state of a window and waits for the client to
	// acknowledge it (Wayland). The window system's answers the UI layer needs to apply together arrive in one event.
	kCGSToplevelEventConfigured,
	// The window system took the window away from the screen on its own: a pop-up it dismissed (the user clicked
	// elsewhere), or a surface of the desktop whose output is gone. Not a request to close the window: the window
	// stays, but is not shown any more, and the UI layer orders it out.
	kCGSToplevelEventDismissed,
	// The window system's objects for the window were made and the window is about to be shown, before anything of it
	// is on the screen. Posted from inside -orderWindow:relativeTo: with kCGSOrderIn, once per showing, for a UI layer that
	// has to give the window system more about the window before its first frame (Wayland: before the first commit).
	kCGSToplevelEventWillShow,
	// The window's input method deleted text around the caret, which the UI layer's text input client answers for (see
	// CGSInputMethod.h, _CGSInputMethodSetSurroundingText): textRange.location is how much text before the caret and
	// textRange.length how much after it, in UTF-16 units. Posted before the commit and the preedit that come with it.
	kCGSToplevelEventInputMethodDeleteSurrounding,
	// The window the UI layer named as this window's parent (-setToplevelParent:) was hidden, and with it the relation the
	// window system kept.
	kCGSToplevelEventParentLost,
	// The window system answered a request for fullscreen or for leaving it (see -toplevelFullscreenSettling): the
	// window can present its contents at the size the window system chose.
	kCGSToplevelEventFullscreenSettled,
} CGSToplevelEventKind;

// What kCGSToplevelEventConfigured carries.
typedef struct {
	// The size the window system chose, in points; 0 in an extent leaves it to the client.
	int32_t width, height;
	// A pop-up's position in its parent window, in points from the parent's top left corner.
	int32_t popupX, popupY;
	bool activated, maximized, fullscreen, suspended;
	// Whether the window system minimizes windows when asked.
	bool minimizeAdvertised;
	// Whether the window system told who draws the window's frame (decorationReported), and that it is the client
	// (clientDecorated).
	bool decorationReported, clientDecorated;
} CGSToplevelConfigure;

typedef struct {
	CGSToplevelEventKind kind;
	CGRect rect;       // see the kinds; CGRectNull for the others
	bool resized;      // kCGSToplevelEventFrameChanged
	CGFloat oldScale;  // kCGSToplevelEventBackingScaleChanged
	bool state;        // kCGSToplevelEventOcclusionChanged, kCGSToplevelEventFullscreenChanged
	CFStringRef text;  // kCGSToplevelEventInputMethodPreedit and ...Commit; valid during the call only
	CFRange textRange; // kCGSToplevelEventInputMethodPreedit, kCGSToplevelEventInputMethodDeleteSurrounding
	CGSToplevelConfigure configure; // kCGSToplevelEventConfigured
} CGSToplevelEvent;

// Called on the thread that runs the main run loop.
typedef void (*CGSToplevelEventProc)(CGSWindow* window, const CGSToplevelEvent* event, void* info);

// What kind of window a toplevel window is to the window system's manager and its task lists.
typedef enum {
	kCGSToplevelKindNormal,
	kCGSToplevelKindUtility,       // a palette or inspector
	kCGSToplevelKindDialog,
	kCGSToplevelKindDropdownMenu,  // a menu of a menu bar
	kCGSToplevelKindPopupMenu,
	kCGSToplevelKindTooltip,
	kCGSToplevelKindDock,          // a panel of the desktop: on every desktop, above the windows
} CGSToplevelKind;

typedef struct {
	CGSToplevelKind kind;
	// The window takes keyboard input when it is made the key window.
	bool acceptsKeyboardInput;
	// Showing the window gives it the focus; not for a window that is not an application's own, or of an
	// application that is not active.
	bool takesFocusWhenShown;
	// Not listed in a task bar or pager.
	bool skipsTaskList;
	// The window it belongs to (for placement, stacking and grouping), nil for none; not retained.
	CGSWindow* transientFor;
} CGSToplevelHints;

@interface CGSWindow : NSObject {
	CGSConnection* _connection;
	CGSWindowID _windowId;
	_Atomic CGSSurfaceID _nextSurfaceId;
	NSMutableDictionary<NSNumber*, CGSSurface*>* _surfaces;
	// The window contents (see -drawImage:atPoint:): 32 bits per pixel, premultiplied alpha, the
	// first row on top, as big as the window. Guarded by @synchronized(self).
	CGContextRef _contents;
	CGSize _contentsSize;
	uint32_t _styleFlags;
	CGWindowLevel _level;
	CGSToplevelEventProc _toplevelEventProc;
	void* _toplevelEventInfo;
	id<CGSDragDestination> _dragDestination;
	BOOL _inputMethodEnabled;
	CGRect _inputMethodCursorRect;
	NSString* _inputMethodSurroundingText;
	CFRange _inputMethodSurroundingSelection;
	uint32_t _inputMethodContentHint, _inputMethodContentPurpose;
}

-(instancetype) initWithRegion:(CGSRegionRef) region
						connection:(CGSConnection*) connection
						windowID:(CGSWindowID) windowID;
-(void) dealloc;
-(CGSSurface*) surfaceForId:(CGSSurfaceID) surfaceId;

-(CGError) orderWindow:(CGSWindowOrderingMode) place relativeTo:(CGSWindow*) window;
-(CGError) moveTo:(const CGPoint*) point;
-(CGError) setRegion:(CGSRegionRef) region;
-(CGError) getRect:(CGRect*) outRect;
-(CGError) setProperty:(CFStringRef) key value:(CFTypeRef) value;
-(CGError) getProperty:(CFStringRef) key value:(CFTypeRef*) value;

// Turns this (not yet ordered in) window into a display overlay: it covers
// the display it is placed on, stays above ordinary windows, and is not managed
// by the window system's window manager. Its key and pointer input is not for
// any window of the application: the connection to the window system posts the
// events it makes of it with no window, located on the screen (a backend that
// cannot yet do so for the pointer lets it fall through to the windows below
// instead). *drawable
// receives the native handle a GL surface can be created on. Backends that
// cannot do this keep the default, which refuses.
-(CGError) becomeDisplayOverlay:(void**) drawable;
-(void) invalidate;

// Toplevel windows of an application's UI layer (AppKit). Such a window is made by
// -[CGSConnection newToplevelWindowWithAttributes:] and is a window of its connection like any other (its
// id is the number the UI layer gives the window; CGWindowListCopyWindowInfo() lists it under that
// number), but its pixels, input, ordering and decorations are the UI layer's, which draws into the
// window handle -nativeWindow gives. Backends that cannot make such windows keep the defaults, which
// refuse. The title is the kCGSWindowTitle property (-setProperty:value:), showing and hiding are
// -orderWindow:relativeTo: with kCGSOrderIn and kCGSOrderOut.
//
// Gives the window a new native window made with the attributes (its handle changes), which keeps the
// children of the old one. For a window that has not been shown yet, to follow what the UI layer
// learned about the window after it was made (that it shows what is behind it). On failure the window
// keeps its native window.
-(CGError) recreateToplevelWithAttributes:(const CGSToplevelAttributes*) attributes;
// Places and sizes the window; frame is in the global space of CGSToplevelAttributes.
-(CGError) setToplevelFrame:(CGRect) frame;
// The window's own size limits, in points, which the window system's manager keeps to when the user
// resizes it. A zero or very large extent is no limit in that dimension; limits that are both absent
// leave the size free.
-(CGError) setToplevelMinimumSize:(CGSize) minimum maximumSize:(CGSize) maximum;
// The window's opacity, 0 to 1, for a window system that composites windows.
-(CGError) setToplevelAlpha:(CGFloat) alpha;

// What the window system reports about the window goes to the process' one UI layer through this handler (NULL
// removes it; the handler is not told of events that happened before it was set, and none after the window
// is released). A backend posts an event with -postToplevelEvent:, which does nothing without a handler; the
// events a window system does not have are never posted.
-(void) setToplevelEventProc:(CGSToplevelEventProc) proc info:(void*) info;
// For the backends.
-(void) postToplevelEvent:(const CGSToplevelEvent*) event;

// Where the window is and how its pixels relate to its points. All frames are in the space of
// -setToplevelFrame:. The defaults are for a window that has none of it: a null frame and a scale of 1, the
// extents and rectangles as they are.
-(CGRect) toplevelFrame;
-(CGFloat) toplevelBackingScaleFactor;
// A frame, size and rectangle in the window system's pixels, rounded as the window's own size and position
// are (at least one pixel of extent). The rectangle of a frame is in the window system's global space; the
// others are within the window, from its top left corner.
-(CGRect) toplevelDeviceRectForFrame:(CGRect) frame;
-(CGSize) toplevelDeviceSizeForSize:(CGSize) size;
-(CGRect) toplevelDeviceRectForRect:(CGRect) rect;

// How the window looks to the window system. A call that has nothing to do on a window system (a shadow, for
// one that draws none) succeeds; the defaults refuse, like those of the calls above. The window does not
// keep these across -recreateToplevelWithAttributes: unless the description says so; the UI layer sets them
// again.
//
// Whether the window casts a shadow.
-(CGError) setToplevelHasShadow:(BOOL) hasShadow;
// Whether every pixel of the window is opaque, which a window system that composites may use to skip drawing
// what is behind it. Follows the window's size. Kept across recreation.
-(CGError) setToplevelContentsOpaque:(BOOL) opaque;
// Rounds the window's corners with this radius in points (0: square). Follows the window's size.
-(CGError) setToplevelCornerRadius:(CGFloat) radius;
// Gives the window an empty shape, so that none of it is seen or hit (for a window that must stay shown
// but has no opacity and no compositor to fade it); fails when the window system cannot.
-(CGError) setToplevelShapeEmpty:(BOOL) empty;
// Whether the window system composites windows, so that opacity applies.
-(BOOL) toplevelWindowSystemComposites;
// Pointer input goes to the windows below.
-(CGError) setToplevelIgnoresMouseEvents:(BOOL) ignores;
// Whether the window system draws a title bar and frame around the window.
-(CGError) setToplevelDecorated:(BOOL) decorated;

// What the window shows of a title bar. The UI layer says it (the decision depends on the window's style, which the UI
// layer knows); the window system's objects follow: the window manager's frame (X11), the decoration mode (Wayland).
typedef enum {
	// No title bar and no frame (a borderless window).
	kCGSToplevelTitlebarNone,
	// The window has a title bar, which the window system draws or, where it does not, the UI layer does (see
	// -setToplevelPrefersClientDecoration: and -setToplevelClientDecorationLayout:).
	kCGSToplevelTitlebarStandard,
	// A titled window that shows nothing of a title bar of its own: the application draws its header, so there is no
	// frame from the window system or the UI layer, and a window system that composites no frame of its own gives the
	// window rounded corners (kCGSToplevelHiddenTitlebarCornerRadius).
	kCGSToplevelTitlebarHidden,
} CGSToplevelTitlebarKind;
#define kCGSToplevelHiddenTitlebarCornerRadius 5.0
-(CGError) setToplevelTitlebarKind:(CGSToplevelTitlebarKind) kind;
-(CGSToplevelTitlebarKind) toplevelTitlebarKind;
// Whether a window that has a standard title bar should have it drawn by the UI layer inside its surface (a window
// system where a client can ask for that: Wayland) even when the window system offers to draw it. See
// -setToplevelClientDecorationLayout:. Does nothing on a window system whose manager always draws the frame.
-(CGError) setToplevelPrefersClientDecoration:(BOOL) prefers;

// The frame the UI layer draws around a window in its surface, as hit-testing of the window system needs it, in points
// from the top left corner of the surface. The UI layer draws the pixels (the theme is its); the window system answers the
// pointer over the frame: a press on an edge resizes the window (when resizable), one on the title bar moves it, and the
// buttons close, miniaturize and zoom it (a close request is a kCGSToplevelEventCloseRequested). The pointer over the frame
// belongs to it: it is not posted as a mouse event of the window. A rectangle that is CGRectNull is a button the window
// does not have or that is disabled; a press on the title bar there moves the window.
typedef struct {
	// The width of the border around the content and below the title bar, and the height of the title bar inside the border.
	CGFloat border, titleHeight;
	// The extents of the surface, in points: the content with the frame around it.
	CGSize size;
	bool resizable;
	CGRect closeButton, miniaturizeButton, zoomButton;
} CGSToplevelDecorationLayout;
// Sets the frame (NULL: there is none, the surface is the content).
-(CGError) setToplevelClientDecorationLayout:(const CGSToplevelDecorationLayout*) layout;
// Whether a point of the surface is on the frame set by -setToplevelClientDecorationLayout:, not on the content.
-(BOOL) toplevelClientDecorationContainsPoint:(CGPoint) point;

// Asks the window system to move the window for as long as the pointer button that is down stays down, as when the user
// drags the window's title bar (the window manager or compositor keeps the window under the pointer, and the button's
// release goes to it). Fails when the window system cannot or the left button is not down on this window.
-(CGError) beginToplevelMoveByWindowSystem;
// The window's icons for the window system's task lists: square images of 32-bit premultiplied ARGB pixels
// (alpha in the most significant byte), the side being the square root of the pixel count, one per size.
// nil or an empty array leaves the choice to the window system.
-(CGError) setToplevelIcons:(NSArray<NSData*>*) icons;
// What the window system's manager is told about the window (see CGSToplevelHints), asked at creation and
// again whenever the window may have changed what it is. A window that is shown while its hint to skip task
// lists changes is told to the manager at once.
-(CGError) setToplevelHints:(const CGSToplevelHints*) hints;
// For a dock window (see CGSToplevelKindDock) before it is shown: the window is on every desktop, outside the
// task lists, above the windows, and reserves the strip along the top edge of the screen it covers.
-(CGError) reserveToplevelDockStrip;

// What the window does with the drags over it (see CGSDrag.h); nil for none, which is what a window starts with.
// The destination is retained. The backends override -dragDestinationChanged to tell the window system that the
// window takes drops (or no more); the default window system has no drag and drop and does nothing.
-(void) setDragDestination:(id<CGSDragDestination>) destination;
-(id<CGSDragDestination>) dragDestination;
-(void) dragDestinationChanged;

// Whether the window uses the window system's input method, and where the text is being entered (see
// CGSInputMethod.h). The backends override the two hooks to tell the input method; the default window system has
// none and does nothing. A window starts with the input method off and the rectangle CGRectNull.
-(void) setInputMethodEnabled:(BOOL) enabled;
-(BOOL) inputMethodEnabled;
-(void) setInputMethodCursorRect:(CGRect) rect;
-(CGRect) inputMethodCursorRect;
-(void) inputMethodEnabledChanged;
-(void) inputMethodCursorRectChanged;
// The text around the caret and the kind of text the window takes, as _CGSInputMethodSetSurroundingText and
// _CGSInputMethodSetContentType say them. The surrounding text starts out nil, and the content type as 0 and 0.
-(void) setInputMethodSurroundingText:(NSString*) text selection:(CFRange) selection;
-(NSString*) inputMethodSurroundingText;
-(CFRange) inputMethodSurroundingSelection;
-(void) setInputMethodContentHint:(uint32_t) hint purpose:(uint32_t) purpose;
-(uint32_t) inputMethodContentHint;
-(uint32_t) inputMethodContentPurpose;
-(void) inputMethodSurroundingTextChanged;
-(void) inputMethodContentTypeChanged;

// Ordering, levels, the keyboard focus, miniaturizing and fullscreen of a toplevel window. The UI layer decides
// when; the window system's calls are made here. A backend that cannot do one of them keeps the default, which
// The address of the window's application menu on the session bus (the bus name of the service and the object path), for
// a desktop that shows application menus outside the application: the window system carries it (a property of the window
// on X11, KDE's appmenu protocol on Wayland). nil for both withdraws it. The window system keeps it for as long as the
// window exists (across the window being hidden and shown, and on X11 across -recreateToplevelWithAttributes:).
-(CGError) setToplevelApplicationMenuServiceName:(NSString*) service objectPath:(NSString*) path;

// Whether the window is the window of a menu that is being tracked while it is shown: the window system's pointer and
// keyboard are held for the newest such window, so that a click elsewhere or a key reaches the menu whichever window has the
// focus (X11; a window system with its own popup grab, Wayland, keeps it). The observer is told when the pointer is held or
// let go (-nativeConnectionMenuGrabChanged:). Does nothing in a relative mouse mode, which holds the pointer itself.
-(CGError) setToplevelHoldsInputForMenu:(BOOL) holds;

// refuses (the queries answer for a window that is not so: not miniaturized, not fullscreen, not covered, not
// holding the focus). The window must be shown (-orderWindow:relativeTo:) before it is stacked or given the focus.
//
// The level the window is stacked at (see NSWindowLevel; larger is further front) and whether it takes part in
// stacking by level. Windows that take part are put in front of those of a lower level and behind those of a
// higher level, as far as the window system's manager lets this process arrange them: a window that the
// manager does not manage (CGSToplevelAttributes.unmanaged) is restacked by the process, the managed ones
// by the manager. A menu or the menu bar does not take part. The order is applied when the window is shown,
// stacked or has its level changed, and again when the manager has stacked the window by itself.
-(CGError) setToplevelLevel:(int) level;
-(CGError) setToplevelStacksByLevel:(BOOL) stacks;
// Puts the window in front of everything (sibling nil) or in front of or behind another shown toplevel
// window, which belongs to the same connection. Stacking in front also applies the order by level.
-(CGError) orderToplevelAbove:(CGSWindow*) sibling;
-(CGError) orderToplevelBelow:(CGSWindow*) sibling;
// Applies the order by level around this window again.
-(CGError) restackToplevelForLevels;
// Asks for the window to hold the keyboard focus: the window is put in front, then the window system is
// asked to focus it. A request that cannot be made yet (the window is not on the screen yet) is repeated when
// it is. The answer is kCGSToplevelEventFocusGained.
-(CGError) requestToplevelKeyboardFocus;
// Forgets a request that waits for the window to appear.
-(void) cancelToplevelKeyboardFocusRequest;
// Whether the window system's keyboard focus is in this window now.
-(BOOL) toplevelHoldsKeyboardFocus;
// Asks the window system to hide the window in its task list, or to show it again. The answer is
// kCGSToplevelEventMiniaturized or kCGSToplevelEventDeminiaturized.
-(CGError) miniaturizeToplevel;
-(CGError) deminiaturizeToplevel;
-(BOOL) toplevelIsMiniaturized;
// Whether a frame (the space of -setToplevelFrame:) is exactly the area of one display.
-(BOOL) toplevelFrameCoversDisplay:(CGRect) frame;
// Asks the window system to hold the window fullscreen, or not. Asking for the state already asked for does
// nothing unless force is set. A window that is not shown has the state written with the others it has, which
// the window system reads when it shows the window. The answer is kCGSToplevelEventFullscreenChanged.
-(CGError) setToplevelFullscreen:(BOOL) fullscreen force:(BOOL) force;
// The state last asked for (or reported by the window system), and whether the window is shown and the window
// system holds it fullscreen.
-(BOOL) toplevelFullscreenRequested;
-(BOOL) toplevelIsFullscreen;
// Whether a window of another client covers this window (see kCGSToplevelEventOcclusionChanged).
-(BOOL) toplevelIsOccluded;
// Relates the window to another toplevel window of the UI layer that the UI layer chose for it (a window of a raised level
// stays in front of the window it belongs to, a panel or a sheet belongs to its document window); nil makes the window one
// without a parent. For a window system that can only relate windows, not stack them at will (Wayland). The window system
// refuses a parent that is not shown, or whose own parents lead to this window, and may drop the relation when the parent
// is hidden (kCGSToplevelEventParentLost); the window is related again whenever it is shown and when it is asked again.
// The parent is not retained.
-(CGError) setToplevelParent:(CGSWindow*) parent;
// The parent the window system holds the window to, nil for none.
-(CGSWindow*) toplevelParent;
// The UI layer ordered the window in, but keeps it from the window system (a fully transparent window, a window of an
// application that must not take the focus yet): it has no window system objects, but is listed by
// _CGSOrderedToplevelWindowIDs() as a window that is ordered in.
-(CGError) setToplevelHeldBack:(BOOL) heldBack;
// Whether a request for fullscreen or for leaving it is not answered yet: the window system decides the size of the window
// by itself then, and a frame presented before the answer would have the size of the old state. Ends with
// kCGSToplevelEventFullscreenSettled, at the latest a second after the request.
-(BOOL) toplevelFullscreenSettling;

// The window's own pixels. A process that has no GL surface for the window draws into it with
// -drawImage:atPoint: and the window shows them. The contents are kept by the window, so they
// survive the window being covered, hidden and shown again, and can be read back (-copyContentsImage,
// CGWindowListCreateImage() for a window of this process).
// The image replaces (source copy, not blended with what is there) the part of the contents it
// covers; origin is the top left corner in the window's coordinates, y down.
-(CGError) drawImage:(CGImageRef) image atPoint:(CGPoint) origin;
// A snapshot of the contents, or NULL while nothing was drawn. The caller releases it.
-(CGImageRef) copyContentsImage;
// The backends show the contents: called after the part of the contents in rect has changed, and by
// the backend itself when the window system asks for a repaint. The default shows nothing.
-(void) presentRect:(CGRect) rect;
// Sets the style bits (kCGSWindowStyle...). The backends override it to apply them to their
// windows (it may be called before the window is first ordered in, and again later).
-(CGError) setStyle:(uint32_t) styleFlags;
@property (readonly) uint32_t styleFlags;
// The window's level (see CGWindowLevel.h), 0 until set. A window system that stacks windows by
// role rather than by number (Wayland) reads from it what the window is: a menu bar, a menu, a
// floating window. The backends override it to apply the level to their windows (it may be called
// before the window is first ordered in, and again later).
-(CGError) setLevel:(CGWindowLevel) level;
@property (readonly) CGWindowLevel level;
// For the backends, when the window's size is not what the contents have: resizes the contents
// (what was in them stays at the top left, the rest is transparent).
-(void) resizeContentsTo:(CGSize) size;
// For the backends: runs the block with the pixels (BGRA, premultiplied), their row length and
// size, with the contents locked. Not called when there are no contents yet.
-(BOOL) withContents:(void (^)(const void* bytes, size_t rowBytes, CGSize size)) block;

// Used, for example, by CGWindowContextCreate()
-(void*) nativeWindow;
-(CGSSurface*) createSurface;

@property (readonly) CGSWindowID windowId;

-(void) _surfaceInvalidated:(CGSSurfaceID) surfaceId;

@end

// A toplevel window of the application's UI layer on the process' connection to the window system, or
// nil when the window system cannot make one (the window then has to be made by the UI layer itself).
// The window is owned by the connection until the UI layer releases it with CGSReleaseWindow() or
// [CGSConnection destroyWindow:]; the caller retains it for as long as it uses it.
COREGRAPHICS_EXPORT CGSWindow* _CGSNewToplevelWindow(const CGSToplevelAttributes* attributes);
// Whether the window system can show what is behind a toplevel window through its alpha.
COREGRAPHICS_EXPORT BOOL _CGSToplevelWindowsSupportTranslucency(void);
// The toplevel windows of the process' connection that are shown, front to back, as the numbers the UI layer
// gave them (the order CGWindowListCopyWindowInfo() lists them in).
COREGRAPHICS_EXPORT NSArray<NSNumber*>* _CGSOrderedToplevelWindowIDs(void);

#endif
