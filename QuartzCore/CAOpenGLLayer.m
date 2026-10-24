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

#import <QuartzCore/CAOpenGLLayer.h>

@implementation CAOpenGLLayer

- (BOOL) isAsynchronous {
    return _asynchronous;
}

- (void) setAsynchronous: (BOOL) async {
    _asynchronous = async;
}

- (BOOL) wantsExtendedDynamicRangeContent {
    return _wantsExtendedDynamicRangeContent;
}

- (void) setWantsExtendedDynamicRangeContent: (BOOL) val {
    _wantsExtendedDynamicRangeContent = val;
}

- (BOOL) canDrawInCGLContext: (CGLContextObj) ctx pixelFormat: (CGLPixelFormatObj) pf forLayerTime: (CFTimeInterval) t displayTime: (const CVTimeStamp *) ts {
    return YES;
}

- (void) drawInCGLContext: (CGLContextObj) ctx pixelFormat: (CGLPixelFormatObj) pf forLayerTime: (CFTimeInterval) t displayTime: (const CVTimeStamp *) ts {
    // Subclasses override
}

- (CGLPixelFormatObj) copyCGLPixelFormatForDisplayMask: (uint32_t) mask {
    CGLPixelFormatAttribute attribs[] = {
        kCGLPFAAccelerated,
        kCGLPFADoubleBuffer,
        kCGLPFAColorSize, (CGLPixelFormatAttribute)24,
        kCGLPFAAlphaSize, (CGLPixelFormatAttribute)8,
        kCGLPFADepthSize, (CGLPixelFormatAttribute)24,
        (CGLPixelFormatAttribute)0
    };
    CGLPixelFormatObj pixelFormat = NULL;
    GLint numScreens = 0;
    CGLChoosePixelFormat(attribs, &pixelFormat, &numScreens);
    return pixelFormat;
}

- (CGLPixelFormatObj) copyCGLPixelFormatForPixelFormat: (CGLPixelFormatObj) pf {
    return pf ? CGLRetainPixelFormat(pf) : NULL;
}

- (CGLContextObj) copyCGLContextForPixelFormat: (CGLPixelFormatObj) pf {
    if (!pf) return NULL;
    CGLContextObj ctx = NULL;
    CGLCreateContext(pf, NULL, &ctx);
    return ctx;
}

- (void) display {
    @synchronized(self) {
        if (!_pixelFormat) {
            if ([self respondsToSelector: @selector(copyCGLPixelFormatForDisplayMask:)]) {
                _pixelFormat = [(id)self copyCGLPixelFormatForDisplayMask: 0];
            }
        }
        if (!_cglContext) {
            if ([self respondsToSelector: @selector(copyCGLContextForPixelFormat:)]) {
                _cglContext = [self copyCGLContextForPixelFormat: _pixelFormat];
            }
        }
    }

    if (_cglContext) {
        CGLContextObj prevCtx = CGLGetCurrentContext();
        CGLSetCurrentContext(_cglContext);
        CVTimeStamp ts;
        memset(&ts, 0, sizeof(ts));
        if ([self canDrawInCGLContext: _cglContext pixelFormat: _pixelFormat forLayerTime: 0.0 displayTime: &ts]) {
            [self drawInCGLContext: _cglContext pixelFormat: _pixelFormat forLayerTime: 0.0 displayTime: &ts];
            CGLFlushDrawable(_cglContext);
        }
        if (prevCtx != _cglContext) {
            CGLSetCurrentContext(prevCtx);
        }
    }
}

- (void) releaseCGLPixelFormat: (CGLPixelFormatObj) pf {
    if (pf) CGLReleasePixelFormat(pf);
}

- (void) releaseCGLContext: (CGLContextObj) ctx {
    if (ctx) CGLReleaseContext(ctx);
}

- (void) dealloc {
    if (_pixelFormat) [self releaseCGLPixelFormat: _pixelFormat];
    if (_cglContext) [self releaseCGLContext: _cglContext];
    [super dealloc];
}

@end
