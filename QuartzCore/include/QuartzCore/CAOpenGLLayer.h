/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

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

#import <QuartzCore/CALayer.h>
#import <QuartzCore/LegacyIvarLayout.h>
#import <OpenGL/OpenGL.h>
#import <CoreVideo/CVBase.h>
#import <IOSurface/IOSurfaceRef.h>

@interface CAOpenGLLayer : CALayer {
    NS_EXTRA_IVARS_BEGIN(CAOpenGLLayer)
        BOOL _asynchronous;
        CGLPixelFormatObj _pixelFormat;
        CGLContextObj _cglContext;
        BOOL _wantsExtendedDynamicRangeContent;
        GLuint _fbo;
        GLuint _depthRb;
        CGSize _allocatedSize;
        // The frames the layer draws go into one of three slots at a time,
        // so that the compositor never samples the slot being drawn.
        // _frontSlot and _hostSlot are slot numbers plus one (0 for none): the
        // latest finished frame, and the one the compositor sampled last (it
        // may still be reading it). A slot's texture is a plain one, or, for
        // a compositing context that shares no objects with the layer's,
        // bound to the IOSurface in _slotSurface.
        IOSurfaceRef _slotSurface[3];
        GLuint _slotTex[3];
        GLsizei _slotWidth[3];
        GLsizei _slotHeight[3];
        int _frontSlot;
        int _hostSlot;
        unsigned long _frameSerial;
        BOOL _wantsSurface;
        // The textures of a compositing context that shares no objects with
        // the layer's context, one for each slot, bound to the slot's surface
        // and to the frame they last showed.
        GLuint _hostTex[3];
        CGLContextObj _hostTexContext;
        unsigned long _hostBoundSerial[3];
    NS_EXTRA_IVARS_END(CAOpenGLLayer)
}

@property(getter=isAsynchronous) BOOL asynchronous;
@property BOOL wantsExtendedDynamicRangeContent;

- (BOOL) canDrawInCGLContext: (CGLContextObj) ctx pixelFormat: (CGLPixelFormatObj) pf forLayerTime: (CFTimeInterval) t displayTime: (const CVTimeStamp *) ts;
- (void) drawInCGLContext: (CGLContextObj) ctx pixelFormat: (CGLPixelFormatObj) pf forLayerTime: (CFTimeInterval) t displayTime: (const CVTimeStamp *) ts;
- (CGLPixelFormatObj) copyCGLPixelFormatForDisplayMask: (uint32_t) mask;
- (CGLContextObj) copyCGLContextForPixelFormat: (CGLPixelFormatObj) pf;
- (void) releaseCGLPixelFormat: (CGLPixelFormatObj) pf;
- (void) releaseCGLContext: (CGLContextObj) ctx;

@end
