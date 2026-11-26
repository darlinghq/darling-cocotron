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
} CGSToplevelEventKind;

typedef struct {
	CGSToplevelEventKind kind;
	CGRect rect;       // see the kinds; CGRectNull for the others
	bool resized;      // kCGSToplevelEventFrameChanged
	CGFloat oldScale;  // kCGSToplevelEventBackingScaleChanged
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

#endif
