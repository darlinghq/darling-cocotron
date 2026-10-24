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
#import <OpenGL/OpenGL.h>
#import <CoreVideo/CVBase.h>

@interface CAOpenGLLayer : CALayer {
    BOOL _asynchronous;
    CGLPixelFormatObj _pixelFormat;
    CGLContextObj _cglContext;
    BOOL _wantsExtendedDynamicRangeContent;
}

@property(getter=isAsynchronous) BOOL asynchronous;
@property BOOL wantsExtendedDynamicRangeContent;

- (BOOL) canDrawInCGLContext: (CGLContextObj) ctx pixelFormat: (CGLPixelFormatObj) pf forLayerTime: (CFTimeInterval) t displayTime: (const CVTimeStamp *) ts;
- (void) drawInCGLContext: (CGLContextObj) ctx pixelFormat: (CGLPixelFormatObj) pf forLayerTime: (CFTimeInterval) t displayTime: (const CVTimeStamp *) ts;
- (CGLPixelFormatObj) copyCGLPixelFormatForDisplayMask: (uint32_t) mask;
- (CGLPixelFormatObj) copyCGLPixelFormatForPixelFormat: (CGLPixelFormatObj) pf;
- (CGLContextObj) copyCGLContextForPixelFormat: (CGLPixelFormatObj) pf;
- (void) releaseCGLPixelFormat: (CGLPixelFormatObj) pf;
- (void) releaseCGLContext: (CGLContextObj) ctx;

@end
