/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

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
#ifndef CGSCURSORPRIVATE_H
#define CGSCURSORPRIVATE_H

// The cursor object behind CGSCursorRef (see CGSCursor.h), for the backends of CoreGraphics. Not installed.

#import <Foundation/NSObject.h>
#import <Foundation/NSData.h>
#include <CoreGraphics/CGSCursor.h>
#include <CoreGraphics/CGSServerSPI.h>

@class CGSCursor;

// An internal shape appended after the public shape values so their ABI does not change. It uses the wait/watch
// theme names and remains visible only to the backends and AppKit's standard-cursor table.
enum { kCGSCursorShapeBusy = kCGSCursorShapeCount };

// QUIRK: CGSGetCursorScale/CGSSetCursorScale expose the system-wide pointer-size factor, starting at 1, shared by
// all processes. Not documented. The accepted range and the results are described, with the evidence (black-box on
// macOS 26.7.3, tier 2), at the implementation in CGSCursor.m. The SPI exists because Blender calls the getter.
// Test: coregraphics-cursor-scale.
// The scale is a 4-byte float: the getter on macOS 26.7.3 writes one float, not a CGFloat (tier 2, black-box).
COREGRAPHICS_EXPORT CGError CGSGetCursorScale(CGSConnectionID connection, float *outScale);
COREGRAPHICS_EXPORT CGError CGSSetCursorScale(CGSConnectionID connection, float scale);

// What makes the window system's object of a cursor: the backend's connection. The object belongs to the cursor
// and is destroyed through the same owner when the cursor goes.
@protocol CGSCursorNativeOwner <NSObject>
-(void*) createNativeCursor:(CGSCursor*)cursor scale:(double)scale;
-(void) destroyNativeCursor:(void*)native;
@end

@interface CGSCursor : NSObject {
	// Declared here: the i386 slice has the legacy Objective-C ABI, which has no ivars in the @implementation.
	BOOL _isImage;
	CGSCursorShape _shape;
	CGImageRef _image;
	CGSize _size;
	CGPoint _hotSpot;
	NSData* _pixels;
	double _pixelScale;
	id<CGSCursorNativeOwner> _nativeOwner;
	void* _native;
	double _nativeScale;
}

-(BOOL) isImage;
// The shape, for a cursor that is not an image.
-(CGSCursorShape) shape;
// An image cursor's logical size in whole points and hot spot (points from the top-left corner, inside the image).
-(CGSize) size;
-(CGPoint) hotSpot;
// The names of the shape in the cursor themes (NULL when it has none): freedesktop name and the older one a
// theme may ship it under, X11's name and the spelling a theme may use for it instead.
-(const char*) themeName;
-(const char*) themeFallbackName;
-(const char*) x11Name;
-(const char*) x11AliasName;
// The size in device pixels at a scale (whole pixels, rounded; zero when no window system can have it), and the
// pixels: premultiplied ARGB, 32 bits little-endian per pixel, tightly packed, at the scale (nil for a shape).
-(CGSize) pixelSizeForScale:(double)scale;
-(NSData*) pixelsForScale:(double)scale;
// The backend's object for this cursor at the scale, made once and kept until the scale changes or the cursor goes.
-(void*) nativeCursorFor:(id<CGSCursorNativeOwner>)owner scale:(double)scale;

@end

#endif
