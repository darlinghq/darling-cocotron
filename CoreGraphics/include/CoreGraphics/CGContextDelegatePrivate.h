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

#ifndef CGCONTEXTDELEGATEPRIVATE_H
#define CGCONTEXTDELEGATEPRIVATE_H

// Private CoreGraphics interfaces: contexts whose drawing operations are
// handed to client callbacks (a context delegate) and the graphics state those
// callbacks are given. Apple does not document them. The names and signatures
// follow the declarations WebKit (BSD licensed) makes for them in
// Source/WebCore/PAL/pal/spi/cg/CoreGraphicsSPI.h; the numeric values are
// inferred from those declarations and are labelled where they appear.

#include <CoreGraphics/CoreGraphics.h>
#include <CoreGraphics/CGError.h>

__BEGIN_DECLS

typedef struct CGContextDelegate *CGContextDelegateRef;
typedef struct CGRenderingState *CGRenderingStateRef;
// The graphics state a callback is given: the context's current state.
typedef struct CGGState *CGGStateRef;
typedef struct CGStyle *CGStyleRef;

// A callback of any kind, cast to its kind's type below when it is set.
typedef void (*CGContextDelegateCallback)(void);

// The kinds of callback. Inferred values (WebKit's declarations); other values
// may be set but are never called.
typedef CF_ENUM(int32_t, CGContextDelegateCallbackName) {
    deDrawPath = 6,
    deDrawImage = 7,
    deDrawGlyphs = 8,
    deBeginLayer = 17,
    deEndLayer = 18,
};

// The kinds of context CGContextGetType reports. Inferred values (the order of
// WebKit's declaration).
typedef enum {
    kCGContextTypeUnknown,
    kCGContextTypePDF,
    kCGContextTypePostScript,
    kCGContextTypeWindow,
    kCGContextTypeBitmap,
    kCGContextTypeGL,
    kCGContextTypeDisplayList,
    kCGContextTypeKSeparation,
    kCGContextTypeIOSurface,
    kCGContextTypeCount
} CGContextType;

// The callback signatures, by kind. The path given to deDrawPath has the CTM
// applied to it already; the rectangle given to deDrawImage is in user space.
// deDrawGlyphs gets the text matrix and the glyph positions in text space.
typedef CGError (*CGContextDelegateDrawPathCallback)(CGContextDelegateRef delegate,
        CGRenderingStateRef renderingState, CGGStateRef gstate,
        CGPathDrawingMode mode, CGPathRef path);
typedef CGError (*CGContextDelegateDrawImageCallback)(CGContextDelegateRef delegate,
        CGRenderingStateRef renderingState, CGGStateRef gstate, CGRect rect,
        CGImageRef image);
typedef CGError (*CGContextDelegateDrawGlyphsCallback)(CGContextDelegateRef delegate,
        CGRenderingStateRef renderingState, CGGStateRef gstate,
        const CGAffineTransform *textMatrix, const CGGlyph glyphs[],
        const CGPoint positions[], size_t count);
typedef CGContextDelegateRef (*CGContextDelegateBeginLayerCallback)(CGContextDelegateRef delegate,
        CGRenderingStateRef renderingState, CGGStateRef gstate, CGRect rect,
        CFDictionaryRef auxiliaryInfo, CGContextDelegateRef layerDelegate);
typedef CGContextDelegateRef (*CGContextDelegateEndLayerCallback)(CGContextDelegateRef delegate,
        CGRenderingStateRef renderingState, CGGStateRef gstate);

// A new delegate with no callbacks. It is a CF object; release it with
// CGContextDelegateRelease or CFRelease.
extern CGContextDelegateRef CGContextDelegateCreate(void *info);
extern CGContextDelegateRef CGContextDelegateRetain(CGContextDelegateRef delegate);
extern void CGContextDelegateRelease(CGContextDelegateRef delegate);
extern CFTypeID CGContextDelegateGetTypeID(void);
extern void *CGContextDelegateGetInfo(CGContextDelegateRef delegate);
// Sets (or, with NULL, removes) the callback of a kind.
extern void CGContextDelegateSetCallback(CGContextDelegateRef delegate,
        CGContextDelegateCallbackName name, CGContextDelegateCallback callback);

// A context that hands its drawing to the delegate's callbacks and draws
// nothing itself. type is what CGContextGetType reports for it. The graphics
// state, when given, is the context's initial state (it is copied); the
// rendering state is not kept, and callbacks are given NULL for it.
extern CGContextRef CGContextCreateWithDelegate(CGContextDelegateRef delegate,
        CGContextType type, CGRenderingStateRef renderingState, CGGStateRef gstate);
extern CGContextType CGContextGetType(CGContextRef context);

// Graphics state getters. The objects returned are owned by the state.
extern CGFloat CGGStateGetAlpha(CGGStateRef gstate);
extern CGFontRef CGGStateGetFont(CGGStateRef gstate);
extern CGFloat CGGStateGetFontSize(CGGStateRef gstate);
extern const CGAffineTransform *CGGStateGetCTM(CGGStateRef gstate);
extern CGColorRef CGGStateGetFillColor(CGGStateRef gstate);
extern CGColorRef CGGStateGetStrokeColor(CGGStateRef gstate);
extern CGStyleRef CGGStateGetStyle(CGGStateRef gstate);

__END_DECLS

#endif
