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
#import <CoreGraphics/CGSCursor.h>
#import <CoreGraphics/CGSCursorPrivate.h>
#import <CoreGraphics/CGSConnection.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <CoreGraphics/CGBitmapContext.h>
#import <CoreGraphics/CGColorSpace.h>
#import <CoreGraphics/CGContext.h>
#import <Foundation/NSData.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

// The names a shape has in the cursor themes: the freedesktop cursor name Wayland compositors and current
// themes use, the older name a theme may still ship under, and the X11 name (with the spelling a theme may
// know it by instead).
static const struct {
	const char* theme;
	const char* themeFallback;
	const char* x11;
	const char* x11Alias;
} kShapeNames[kCGSCursorShapeCount] = {
	[kCGSCursorShapeArrow] = {"default", "left_ptr", "left_ptr", NULL},
	[kCGSCursorShapeIBeam] = {"text", "xterm", "xterm", "text"},
	[kCGSCursorShapeVerticalIBeam] = {"vertical-text", "xterm", "vertical-text", "xterm"},
	[kCGSCursorShapeCrosshair] = {"crosshair", "cross", "crosshair", NULL},
	[kCGSCursorShapeClosedHand] = {"grabbing", "hand3", "hand3", "pointer"},
	[kCGSCursorShapeOpenHand] = {"grab", "fleur", "fleur", "move"},
	[kCGSCursorShapePointingHand] = {"pointer", "hand2", "hand", "pointer"},
	[kCGSCursorShapeZoomIn] = {"zoom-in", "left_ptr", "zoom-in", NULL},
	[kCGSCursorShapeZoomOut] = {"zoom-out", "left_ptr", "zoom-out", NULL},
	[kCGSCursorShapeResizeUp] = {"n-resize", "top_side", "top_side", NULL},
	[kCGSCursorShapeResizeDown] = {"s-resize", "bottom_side", "bottom_side", NULL},
	[kCGSCursorShapeResizeLeft] = {"w-resize", "left_side", "left_side", NULL},
	[kCGSCursorShapeResizeRight] = {"e-resize", "right_side", "right_side", NULL},
	[kCGSCursorShapeResizeLeftRight] = {"ew-resize", "h_double_arrow", "h_double_arrow", NULL},
	[kCGSCursorShapeResizeUpDown] = {"ns-resize", "v_double_arrow", "v_double_arrow", NULL},
	[kCGSCursorShapeResizeNorthWest] = {"nw-resize", "top_left_corner", "top_left_corner", NULL},
	[kCGSCursorShapeResizeNorthEast] = {"ne-resize", "top_right_corner", "top_right_corner", NULL},
	[kCGSCursorShapeResizeSouthEast] = {"se-resize", "bottom_right_corner", "bottom_right_corner", NULL},
	[kCGSCursorShapeResizeSouthWest] = {"sw-resize", "bottom_left_corner", "bottom_left_corner", NULL},
	[kCGSCursorShapeResizeNorthWestSouthEast] = {"nwse-resize", "fd_double_arrow", "fd_double_arrow", NULL},
	[kCGSCursorShapeResizeNorthEastSouthWest] = {"nesw-resize", "bd_double_arrow", "bd_double_arrow", NULL},
};

@implementation CGSCursor

-(instancetype) _initWithShape:(CGSCursorShape)shape
{
	if ((self = [super init]) == nil)
		return nil;
	_shape = shape;
	return self;
}

-(instancetype) _initWithImage:(CGImageRef)image logicalSize:(CGSize)size hotSpot:(CGPoint)hotSpot
{
	if ((self = [super init]) == nil)
		return nil;

	// The shm pool size and stride of Wayland, and Xcursor, take signed 32-bit and 15-bit sizes, so the size of
	// a cursor is whole points of a bounded size.
	double width = ceil(size.width), height = ceil(size.height);
	if (image == NULL || !isfinite(width) || !isfinite(height) || width < 1 || height < 1 ||
		width > 0x7FFF / 8 || height > 0x7FFF / 8 || !isfinite(hotSpot.x) || !isfinite(hotSpot.y))
	{
		[self release];
		return nil;
	}
	_isImage = YES;
	_size = CGSizeMake(width, height);
	_hotSpot = CGPointMake(fmax(0, fmin(floor(hotSpot.x), width - 1)), fmax(0, fmin(floor(hotSpot.y), height - 1)));
	_image = CGImageRetain(image);
	return self;
}

-(void) dealloc
{
	if (_nativeOwner != nil)
	{
		[_nativeOwner destroyNativeCursor: _native];
		[_nativeOwner release];
	}
	CGImageRelease(_image);
	[_pixels release];
	[super dealloc];
}

-(BOOL) isImage { return _isImage; }
-(CGSCursorShape) shape { return _shape; }
-(CGSize) size { return _size; }
-(CGPoint) hotSpot { return _hotSpot; }

-(const char*) themeName { return kShapeNames[_shape].theme; }
-(const char*) themeFallbackName { return kShapeNames[_shape].themeFallback; }
-(const char*) x11Name { return kShapeNames[_shape].x11; }
-(const char*) x11AliasName { return kShapeNames[_shape].x11Alias; }

// The window system's object for this cursor, made by the backend and kept for as long as the cursor lives.
// It is made for one scale (an image cursor is rasterised for it), so a different scale makes it again.
-(void*) nativeCursorFor:(id<CGSCursorNativeOwner>)owner scale:(double)scale
{
	if (_nativeOwner == owner && _nativeScale == scale)
		return _native;
	if (_nativeOwner != nil)
	{
		[_nativeOwner destroyNativeCursor: _native];
		[_nativeOwner release];
		_nativeOwner = nil;
		_native = NULL;
	}
	_native = [owner createNativeCursor: self scale: scale];
	_nativeScale = scale;
	if (_native != NULL)
		_nativeOwner = [owner retain];
	return _native;
}

// The pixel extent of a logical extent at a scale, or 0 when it is not a size the window system can have.
static int32_t scaledExtent(double logical, double scale, int32_t limit)
{
	double value = floor(logical * scale + 0.5);
	if (!(value >= 1.0))
		value = 1.0;
	return value > limit ? 0 : (int32_t) value;
}

-(CGSize) pixelSizeForScale:(double)scale
{
	if (!(scale >= 1.0) || !isfinite(scale))
		scale = 1.0;
	int32_t width = scaledExtent(_size.width, scale, INT32_MAX / 4);
	if (width < 1)
		return CGSizeZero;
	int32_t height = scaledExtent(_size.height, scale, INT32_MAX / (width * 4));
	return height < 1 ? CGSizeZero : CGSizeMake(width, height);
}

// Premultiplied ARGB, 32 bits little-endian per pixel, rows packed, at the scale. The data is cached for the
// last scale asked for.
-(NSData*) pixelsForScale:(double)scale
{
	if (!_isImage)
		return nil;
	if (!(scale >= 1.0) || !isfinite(scale))
		scale = 1.0;
	if (_pixels != nil && _pixelScale == scale)
		return _pixels;
	CGSize pixelSize = [self pixelSizeForScale: scale];
	size_t width = (size_t) pixelSize.width, height = (size_t) pixelSize.height;
	if (width < 1 || height < 1)
		return nil;

	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, space,
		kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
	CGColorSpaceRelease(space);
	if (context == NULL)
		return nil;
	CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
	CGContextDrawImage(context, CGRectMake(0, 0, width, height), _image);

	size_t stride = width * 4;
	NSMutableData* pixels = [NSMutableData dataWithLength: stride * height];
	const uint8_t* source = CGBitmapContextGetData(context);
	size_t sourceStride = CGBitmapContextGetBytesPerRow(context);
	for (size_t row = 0; row < height; row++)
		memcpy((uint8_t*) [pixels mutableBytes] + row * stride, source + row * sourceStride, stride);
	CGContextRelease(context);

	[_pixels release];
	_pixels = [pixels copy];
	_pixelScale = scale;
	return _pixels;
}

@end

CGSCursorRef CGSCursorCreateWithShape(CGSCursorShape shape)
{
	if ((int) shape < 0 || shape >= kCGSCursorShapeCount)
		shape = kCGSCursorShapeArrow;
	return (CGSCursorRef) [[CGSCursor alloc] _initWithShape: shape];
}

CGSCursorRef CGSCursorCreateWithImage(CGImageRef image, CGSize logicalSize, CGPoint hotSpot)
{
	return (CGSCursorRef) [[CGSCursor alloc] _initWithImage: image logicalSize: logicalSize hotSpot: hotSpot];
}

CGSCursorRef CGSCursorRetain(CGSCursorRef cursor)
{
	return (CGSCursorRef) [(CGSCursor*) cursor retain];
}

void CGSCursorRelease(CGSCursorRef cursor)
{
	[(CGSCursor*) cursor release];
}

CGError CGSCursorSetCurrent(CGSCursorRef cursor)
{
	CGSConnectionID connectionID = CGSMainConnectionID();
	if (connectionID == 0)
		return kCGErrorCannotComplete;
	[_CGSConnectionForID(connectionID) setCursor: (CGSCursor*) cursor];
	return kCGErrorSuccess;
}
