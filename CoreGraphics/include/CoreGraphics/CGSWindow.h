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
