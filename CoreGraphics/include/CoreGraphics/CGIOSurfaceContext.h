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

#ifndef CGIOSURFACECONTEXT_H
#define CGIOSURFACECONTEXT_H

// Private CoreGraphics interfaces: bitmap contexts that draw into the memory
// of an IOSurface. Apple does not document them; the names and signatures
// follow WebKit's (BSD licensed) declarations in
// Source/WebCore/PAL/pal/spi/cg/CoreGraphicsSPI.h.

#include <CoreGraphics/CoreGraphics.h>
#include <IOSurface/IOSurfaceRef.h>

__BEGIN_DECLS

// A context drawing into the surface's memory, whose rows are the surface's
// bytes per row. The size must fit in the surface and the pixel format
// (bitsPerComponent, bitsPerPixel, colour space and bitmap info) must be one a
// bitmap context supports with bitsPerPixel bits per pixel; NULL otherwise.
// The context keeps the surface. CGContextGetType reports
// kCGContextTypeIOSurface for it, and the CGBitmapContext getters work on it.
extern CGContextRef CGIOSurfaceContextCreate(IOSurfaceRef surface, size_t width,
        size_t height, size_t bitsPerComponent, size_t bitsPerPixel,
        CGColorSpaceRef colorSpace, CGBitmapInfo bitmapInfo);
// An image of what the context holds now; later drawing does not change it.
// NULL for a context that is not an IOSurface context.
extern CGImageRef CGIOSurfaceContextCreateImage(CGContextRef context);
// Like CGIOSurfaceContextCreateImage (the image is a copy here too).
extern CGImageRef CGIOSurfaceContextCreateImageReference(CGContextRef context);
// The context's colour space (owned by the context) and bitmap info; NULL and 0
// for a context that is not an IOSurface context.
extern CGColorSpaceRef CGIOSurfaceContextGetColorSpace(CGContextRef context);
extern size_t CGIOSurfaceContextGetBitmapInfo(CGContextRef context);
// The surface the context draws into (owned by the context), or NULL.
extern IOSurfaceRef CGIOSurfaceContextGetSurface(CGContextRef context);
// Which displays the context's content is meant for. Kept, it has no effect.
extern void CGIOSurfaceContextSetDisplayMask(CGContextRef context, uint32_t mask);
// Tells the context the surface's memory was changed by someone else. The
// context reads the memory directly, so there is nothing to invalidate.
extern void CGIOSurfaceContextInvalidateSurface(CGContextRef context);

__END_DECLS

#endif
