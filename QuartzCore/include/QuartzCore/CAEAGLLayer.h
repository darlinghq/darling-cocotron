/*
 This file is part of Darling.

 Copyright (C) 2026 Darling Team

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
*/

#import <QuartzCore/CALayer.h>
#import <Foundation/Foundation.h>

/* OpenGLES's EAGLDrawable.h declares the same protocol. */
#ifndef EAGL_DRAWABLE_PROTOCOL
#define EAGL_DRAWABLE_PROTOCOL
@protocol EAGLDrawable
@property (copy) NSDictionary *drawableProperties;
@end
#endif

/*
 * iOS's OpenGL ES layer. An EAGLContext sizes a renderbuffer to it, and
 * presenting the renderbuffer makes its pixels the layer's contents.
 */
@interface CAEAGLLayer : CALayer <EAGLDrawable> {
    NSDictionary *_drawableProperties;
    BOOL _presentsWithTransaction;
}

@property (copy) NSDictionary *drawableProperties;
@property BOOL presentsWithTransaction;

@end
