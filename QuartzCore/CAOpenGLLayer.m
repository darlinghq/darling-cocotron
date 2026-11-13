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

#define GL_GLEXT_PROTOTYPES 1
#import <QuartzCore/CAOpenGLLayer.h>
#import <QuartzCore/CALayerContext.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>
#import "CALayerInternal.h"

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

// The documented default is a context with no share context. The layer's
// frame is drawn into a texture in this context and composited by the
// context of the window the layer tree is hosted in, which can only sample a
// texture it shares with the drawing context, so the default context shares
// with the hosting one when there is one. A subclass that returns its own
// context has to share with it too for its output to reach the screen.
- (CGLContextObj) copyCGLContextForPixelFormat: (CGLPixelFormatObj) pf {
    if (!pf) return NULL;
    CGLContextObj ctx = NULL;
    CGLCreateContext(pf, [_context glContext], &ctx);
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
        CGRect bounds = [self bounds];
        CGFloat scale = [self contentsScale];
        if (scale <= 0.0) scale = 1.0;
        int width = (int)ceil(bounds.size.width * scale);
        int height = (int)ceil(bounds.size.height * scale);

        if (width <= 0 || height <= 0)
            return;

        CGLContextObj prevCtx = CGLGetCurrentContext();
        BOOL needBind = (prevCtx != _cglContext);
        if (needBind) {
            CGLLockContext(_cglContext);
            CGLSetCurrentContext(_cglContext);
        }

        if (_fbo == 0 || _allocatedSize.width != width || _allocatedSize.height != height) {
            if (_colorTex != 0) { glDeleteTextures(1, &_colorTex); _colorTex = 0; }
            if (_depthRb != 0) { glDeleteRenderbuffers(1, &_depthRb); _depthRb = 0; }
            if (_fbo != 0) { glDeleteFramebuffers(1, &_fbo); _fbo = 0; }

            glGenTextures(1, &_colorTex);
            glBindTexture(GL_TEXTURE_2D, _colorTex);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, width, height, 0, GL_RGB, GL_UNSIGNED_BYTE, NULL);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

            glGenRenderbuffers(1, &_depthRb);
            glBindRenderbuffer(GL_RENDERBUFFER, _depthRb);
            glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, width, height);

            glGenFramebuffers(1, &_fbo);
            glBindFramebuffer(GL_FRAMEBUFFER, _fbo);
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, _colorTex, 0);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, _depthRb);

            GLenum fboStatus = glCheckFramebufferStatus(GL_FRAMEBUFFER);
            if (fboStatus != GL_FRAMEBUFFER_COMPLETE) {
                NSLog(@"CAOpenGLLayer: FBO incomplete (0x%x)", fboStatus);
                glBindFramebuffer(GL_FRAMEBUFFER, 0);
                if (_colorTex != 0) { glDeleteTextures(1, &_colorTex); _colorTex = 0; }
                if (_depthRb != 0) { glDeleteRenderbuffers(1, &_depthRb); _depthRb = 0; }
                if (_fbo != 0) { glDeleteFramebuffers(1, &_fbo); _fbo = 0; }
                _allocatedSize = CGSizeZero;
                if (needBind) {
                    CGLSetCurrentContext(prevCtx);
                    CGLUnlockContext(_cglContext);
                }
                return;
            }

            _allocatedSize = CGSizeMake(width, height);
        } else {
            glBindFramebuffer(GL_FRAMEBUFFER, _fbo);
        }

        GLint prevViewport[4];
        glGetIntegerv(GL_VIEWPORT, prevViewport);
        glViewport(0, 0, width, height);

        CFTimeInterval currentTime = CACurrentMediaTime();
        CFTimeInterval layerTime = currentTime;
        CVTimeStamp ts;
        memset(&ts, 0, sizeof(ts));
        ts.version = 0;
        ts.videoTime = (int64_t)(currentTime * 1000000000.0);
        ts.videoTimeScale = 1000000000;
        ts.flags = kCVTimeStampVideoTimeValid;

        if ([self canDrawInCGLContext: _cglContext pixelFormat: _pixelFormat forLayerTime: layerTime displayTime: &ts]) {
            [self drawInCGLContext: _cglContext pixelFormat: _pixelFormat forLayerTime: layerTime displayTime: &ts];
        }

        glFlush();
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(prevViewport[0], prevViewport[1], prevViewport[2], prevViewport[3]);

        if (needBind) {
            CGLSetCurrentContext(prevCtx);
            CGLUnlockContext(_cglContext);
        }

        [_context startTimerIfNeeded];
    }
}

// An asynchronous layer redraws with every frame, a synchronous one only
// after -setNeedsDisplay.
- (void) displayIfNeeded {
    if (_asynchronous) {
        _needsDisplay = NO;
        [self display];
    } else {
        [super displayIfNeeded];
    }
}

- (BOOL) _drawLayerContents: (CGRect) bounds opacity: (CGFloat) opacity {
    if (_colorTex == 0)
        return NO;

    GLint prevPrgm = 0;
    glGetIntegerv(GL_CURRENT_PROGRAM, &prevPrgm);
    if (prevPrgm != 0) glUseProgram(0);

    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);

    GLboolean blendWasEnabled = glIsEnabled(GL_BLEND);
    glDisable(GL_BLEND);

    glEnable(GL_TEXTURE_2D);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glEnableClientState(GL_VERTEX_ARRAY);
    glBindTexture(GL_TEXTURE_2D, _colorTex);

    const GLfloat uprightTexture[4 * 2] = {0, 0, 1, 0, 0, 1, 1, 1};
    const GLfloat vertices[4 * 2] = {
        0, 0,
        (GLfloat) bounds.size.width, 0,
        0, (GLfloat) bounds.size.height,
        (GLfloat) bounds.size.width, (GLfloat) bounds.size.height
    };

    glTexCoordPointer(2, GL_FLOAT, 0, uprightTexture);
    glVertexPointer(2, GL_FLOAT, 0, vertices);
    glColor4f(opacity, opacity, opacity, opacity);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

    glDisableClientState(GL_VERTEX_ARRAY);
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisable(GL_TEXTURE_2D);

    if (blendWasEnabled) glEnable(GL_BLEND);
    if (prevPrgm != 0) glUseProgram(prevPrgm);

    return YES;
}

- (void) releaseCGLPixelFormat: (CGLPixelFormatObj) pf {
    if (pf) CGLReleasePixelFormat(pf);
}

- (void) releaseCGLContext: (CGLContextObj) ctx {
    if (ctx) CGLReleaseContext(ctx);
}

- (void) dealloc {
    if (_cglContext) {
        if (CGLLockContext(_cglContext) == kCGLNoError) {
            CGLContextObj prevCtx = CGLGetCurrentContext();
            if (CGLSetCurrentContext(_cglContext) == kCGLNoError) {
                if (_colorTex) glDeleteTextures(1, &_colorTex);
                if (_depthRb) glDeleteRenderbuffers(1, &_depthRb);
                if (_fbo) glDeleteFramebuffers(1, &_fbo);
                if (prevCtx != _cglContext) CGLSetCurrentContext(prevCtx);
            }
            CGLUnlockContext(_cglContext);
        }
    }
    if (_pixelFormat) [self releaseCGLPixelFormat: _pixelFormat];
    if (_cglContext) [self releaseCGLContext: _cglContext];
    [super dealloc];
}

@end
