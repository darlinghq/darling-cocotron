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
    return NS_EXTRA(CAOpenGLLayer, self)->_asynchronous;
}

- (void) setAsynchronous: (BOOL) async {
    NS_EXTRA(CAOpenGLLayer, self)->_asynchronous = async;
}

- (BOOL) wantsExtendedDynamicRangeContent {
    return NS_EXTRA(CAOpenGLLayer, self)->_wantsExtendedDynamicRangeContent;
}

- (void) setWantsExtendedDynamicRangeContent: (BOOL) val {
    NS_EXTRA(CAOpenGLLayer, self)->_wantsExtendedDynamicRangeContent = val;
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

// QUIRK: the default context shares objects with the context of the window
// the layer tree is hosted in, although the documented default is a context
// without a share context. The layer's frame is drawn into a texture in this
// context and composited by the hosting context, which can only sample a
// texture it shares with the drawing context. Evidence: a requirement of this
// compositor, not an observation of macOS (no tier; maintainer-approved).
// A subclass that returns a context that does not share objects with the
// hosting one still reaches the screen, through a copy of every frame made
// with glReadPixels (see -_copyFrameForHost and -_hostTextureForContext:).
// Test: quartzcore-opengl-layer, "default contexts share objects" (with an
// unshared context as the control).
- (CGLContextObj) copyCGLContextForPixelFormat: (CGLPixelFormatObj) pf {
    if (!pf) return NULL;
    CGLContextObj ctx = NULL;
    CGLCreateContext(pf, [NS_EXTRA(CALayer, self)->_context glContext], &ctx);
    return ctx;
}


#define GLX(layer) NS_EXTRA(CAOpenGLLayer, layer)

// Whether objects made in the two contexts are the same objects.
static BOOL contextsShareObjects(CGLContextObj a, CGLContextObj b) {
    return a != NULL && b != NULL && (a == b || CGLGetShareGroup(a) == CGLGetShareGroup(b));
}

// Called with the layer's context current and its framebuffer bound, after the
// frame has been drawn: keeps a copy of the frame in memory when the context
// that composites the layer cannot sample the framebuffer's texture itself.
- (void) _copyFrameForHost: (CGLContextObj) host width: (int) width height: (int) height {
    if (contextsShareObjects(GLX(self)->_cglContext, host))
        return;

    size_t needed = (size_t) width * (size_t) height * 4;
    @synchronized(self) {
        if (GLX(self)->_pixelsCapacity < needed) {
            GLubyte *grown = realloc(GLX(self)->_pixels, needed);
            if (grown == NULL)
                return;
            GLX(self)->_pixels = grown;
            GLX(self)->_pixelsCapacity = needed;
        }

        GLint packAlignment, packRowLength, packSkipPixels, packSkipRows, packBuffer, readBuffer;
        glGetIntegerv(GL_PACK_ALIGNMENT, &packAlignment);
        glGetIntegerv(GL_PACK_ROW_LENGTH, &packRowLength);
        glGetIntegerv(GL_PACK_SKIP_PIXELS, &packSkipPixels);
        glGetIntegerv(GL_PACK_SKIP_ROWS, &packSkipRows);
        glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &packBuffer);
        glGetIntegerv(GL_READ_BUFFER, &readBuffer);
        glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
        glPixelStorei(GL_PACK_ALIGNMENT, 4);
        glPixelStorei(GL_PACK_ROW_LENGTH, 0);
        glPixelStorei(GL_PACK_SKIP_PIXELS, 0);
        glPixelStorei(GL_PACK_SKIP_ROWS, 0);
        glBindFramebuffer(GL_FRAMEBUFFER, GLX(self)->_fbo);
        glReadBuffer(GL_COLOR_ATTACHMENT0);
        glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, GLX(self)->_pixels);
        glReadBuffer(readBuffer);
        glPixelStorei(GL_PACK_ALIGNMENT, packAlignment);
        glPixelStorei(GL_PACK_ROW_LENGTH, packRowLength);
        glPixelStorei(GL_PACK_SKIP_PIXELS, packSkipPixels);
        glPixelStorei(GL_PACK_SKIP_ROWS, packSkipRows);
        glBindBuffer(GL_PIXEL_PACK_BUFFER, packBuffer);

        GLX(self)->_pixelsWidth = width;
        GLX(self)->_pixelsHeight = height;
        GLX(self)->_pixelsSerial++;
    }
}

// Forgets the texture made in a hosting context for a copied frame.
- (void) _releaseHostTexture {
    if (GLX(self)->_hostTexContext == NULL)
        return;

    CGLContextObj previous = CGLGetCurrentContext();
    CGLLockContext(GLX(self)->_hostTexContext);
    if (CGLSetCurrentContext(GLX(self)->_hostTexContext) == kCGLNoError) {
        if (GLX(self)->_hostTex)
            glDeleteTextures(1, &GLX(self)->_hostTex);
        CGLSetCurrentContext(previous);
    }
    CGLUnlockContext(GLX(self)->_hostTexContext);
    GLX(self)->_hostTex = 0;
    GLX(self)->_hostTexSize = CGSizeZero;
    CGLReleaseContext(GLX(self)->_hostTexContext);
    GLX(self)->_hostTexContext = NULL;
}

// The texture to composite in the context that is current (the hosting
// context), holding the last frame: the framebuffer's own texture when the
// current context shares objects with the layer's, otherwise a texture made
// here from the copy of the frame. 0 when there is no frame.
- (GLuint) _hostTextureForContext: (CGLContextObj) host {
    if (contextsShareObjects(GLX(self)->_cglContext, host))
        return GLX(self)->_colorTex;

    @synchronized(self) {
        if (GLX(self)->_pixels == NULL || GLX(self)->_pixelsSerial == 0)
            return 0;

        if (GLX(self)->_hostTexContext != NULL && !contextsShareObjects(GLX(self)->_hostTexContext, host))
            [self _releaseHostTexture];

        BOOL created = NO;
        if (GLX(self)->_hostTex == 0) {
            glGenTextures(1, &GLX(self)->_hostTex);
            GLX(self)->_hostTexContext = CGLRetainContext(host);
            GLX(self)->_uploadedSerial = 0;
            created = YES;
        }
        glBindTexture(GL_TEXTURE_2D, GLX(self)->_hostTex);
        if (created) {
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        }
        if (GLX(self)->_uploadedSerial != GLX(self)->_pixelsSerial) {
            GLint unpackAlignment, unpackRowLength, unpackSkipPixels, unpackSkipRows, unpackBuffer;
            glGetIntegerv(GL_UNPACK_ALIGNMENT, &unpackAlignment);
            glGetIntegerv(GL_UNPACK_ROW_LENGTH, &unpackRowLength);
            glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &unpackSkipPixels);
            glGetIntegerv(GL_UNPACK_SKIP_ROWS, &unpackSkipRows);
            glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &unpackBuffer);
            glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
            glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
            glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
            glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);
            glPixelStorei(GL_UNPACK_SKIP_ROWS, 0);
            if (GLX(self)->_hostTexSize.width == GLX(self)->_pixelsWidth &&
                GLX(self)->_hostTexSize.height == GLX(self)->_pixelsHeight) {
                glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, GLX(self)->_pixelsWidth, GLX(self)->_pixelsHeight,
                                GL_RGBA, GL_UNSIGNED_BYTE, GLX(self)->_pixels);
            } else {
                glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, GLX(self)->_pixelsWidth, GLX(self)->_pixelsHeight, 0,
                             GL_RGBA, GL_UNSIGNED_BYTE, GLX(self)->_pixels);
                GLX(self)->_hostTexSize = CGSizeMake(GLX(self)->_pixelsWidth, GLX(self)->_pixelsHeight);
            }
            glPixelStorei(GL_UNPACK_ALIGNMENT, unpackAlignment);
            glPixelStorei(GL_UNPACK_ROW_LENGTH, unpackRowLength);
            glPixelStorei(GL_UNPACK_SKIP_PIXELS, unpackSkipPixels);
            glPixelStorei(GL_UNPACK_SKIP_ROWS, unpackSkipRows);
            glBindBuffer(GL_PIXEL_UNPACK_BUFFER, unpackBuffer);
            GLX(self)->_uploadedSerial = GLX(self)->_pixelsSerial;
        }
        return GLX(self)->_hostTex;
    }
}

- (void) display {
    @synchronized(self) {
        if (!NS_EXTRA(CAOpenGLLayer, self)->_pixelFormat) {
            if ([self respondsToSelector: @selector(copyCGLPixelFormatForDisplayMask:)]) {
                NS_EXTRA(CAOpenGLLayer, self)->_pixelFormat = [(id)self copyCGLPixelFormatForDisplayMask: 0];
            }
        }
        if (!NS_EXTRA(CAOpenGLLayer, self)->_cglContext) {
            if ([self respondsToSelector: @selector(copyCGLContextForPixelFormat:)]) {
                NS_EXTRA(CAOpenGLLayer, self)->_cglContext = [self copyCGLContextForPixelFormat: NS_EXTRA(CAOpenGLLayer, self)->_pixelFormat];
            }
        }
    }

    if (NS_EXTRA(CAOpenGLLayer, self)->_cglContext) {
        CGRect bounds = [self bounds];
        CGFloat scale = [self contentsScale];
        if (scale <= 0.0) scale = 1.0;
        int width = (int)ceil(bounds.size.width * scale);
        int height = (int)ceil(bounds.size.height * scale);

        if (width <= 0 || height <= 0)
            return;

        CGLContextObj prevCtx = CGLGetCurrentContext();
        // The context that composites the layer: the one of the window the
        // layer is hosted in, else the one that asked for the frame.
        CGLContextObj hostContext = [NS_EXTRA(CALayer, self)->_context glContext];
        if (hostContext == NULL)
            hostContext = prevCtx;
        BOOL needBind = (prevCtx != NS_EXTRA(CAOpenGLLayer, self)->_cglContext);
        if (needBind) {
            CGLLockContext(NS_EXTRA(CAOpenGLLayer, self)->_cglContext);
            CGLSetCurrentContext(NS_EXTRA(CAOpenGLLayer, self)->_cglContext);
        }

        if (NS_EXTRA(CAOpenGLLayer, self)->_fbo == 0 || NS_EXTRA(CAOpenGLLayer, self)->_allocatedSize.width != width || NS_EXTRA(CAOpenGLLayer, self)->_allocatedSize.height != height) {
            if (NS_EXTRA(CAOpenGLLayer, self)->_colorTex != 0) { glDeleteTextures(1, &NS_EXTRA(CAOpenGLLayer, self)->_colorTex); NS_EXTRA(CAOpenGLLayer, self)->_colorTex = 0; }
            if (NS_EXTRA(CAOpenGLLayer, self)->_depthRb != 0) { glDeleteRenderbuffers(1, &NS_EXTRA(CAOpenGLLayer, self)->_depthRb); NS_EXTRA(CAOpenGLLayer, self)->_depthRb = 0; }
            if (NS_EXTRA(CAOpenGLLayer, self)->_fbo != 0) { glDeleteFramebuffers(1, &NS_EXTRA(CAOpenGLLayer, self)->_fbo); NS_EXTRA(CAOpenGLLayer, self)->_fbo = 0; }

            glGenTextures(1, &NS_EXTRA(CAOpenGLLayer, self)->_colorTex);
            glBindTexture(GL_TEXTURE_2D, NS_EXTRA(CAOpenGLLayer, self)->_colorTex);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, width, height, 0, GL_RGB, GL_UNSIGNED_BYTE, NULL);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

            glGenRenderbuffers(1, &NS_EXTRA(CAOpenGLLayer, self)->_depthRb);
            glBindRenderbuffer(GL_RENDERBUFFER, NS_EXTRA(CAOpenGLLayer, self)->_depthRb);
            glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, width, height);

            glGenFramebuffers(1, &NS_EXTRA(CAOpenGLLayer, self)->_fbo);
            glBindFramebuffer(GL_FRAMEBUFFER, NS_EXTRA(CAOpenGLLayer, self)->_fbo);
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, NS_EXTRA(CAOpenGLLayer, self)->_colorTex, 0);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, NS_EXTRA(CAOpenGLLayer, self)->_depthRb);

            GLenum fboStatus = glCheckFramebufferStatus(GL_FRAMEBUFFER);
            if (fboStatus != GL_FRAMEBUFFER_COMPLETE) {
                NSLog(@"CAOpenGLLayer: FBO incomplete (0x%x)", fboStatus);
                glBindFramebuffer(GL_FRAMEBUFFER, 0);
                if (NS_EXTRA(CAOpenGLLayer, self)->_colorTex != 0) { glDeleteTextures(1, &NS_EXTRA(CAOpenGLLayer, self)->_colorTex); NS_EXTRA(CAOpenGLLayer, self)->_colorTex = 0; }
                if (NS_EXTRA(CAOpenGLLayer, self)->_depthRb != 0) { glDeleteRenderbuffers(1, &NS_EXTRA(CAOpenGLLayer, self)->_depthRb); NS_EXTRA(CAOpenGLLayer, self)->_depthRb = 0; }
                if (NS_EXTRA(CAOpenGLLayer, self)->_fbo != 0) { glDeleteFramebuffers(1, &NS_EXTRA(CAOpenGLLayer, self)->_fbo); NS_EXTRA(CAOpenGLLayer, self)->_fbo = 0; }
                NS_EXTRA(CAOpenGLLayer, self)->_allocatedSize = CGSizeZero;
                if (needBind) {
                    CGLSetCurrentContext(prevCtx);
                    CGLUnlockContext(NS_EXTRA(CAOpenGLLayer, self)->_cglContext);
                }
                return;
            }

            NS_EXTRA(CAOpenGLLayer, self)->_allocatedSize = CGSizeMake(width, height);
        } else {
            glBindFramebuffer(GL_FRAMEBUFFER, NS_EXTRA(CAOpenGLLayer, self)->_fbo);
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

        if ([self canDrawInCGLContext: NS_EXTRA(CAOpenGLLayer, self)->_cglContext pixelFormat: NS_EXTRA(CAOpenGLLayer, self)->_pixelFormat forLayerTime: layerTime displayTime: &ts]) {
            [self drawInCGLContext: NS_EXTRA(CAOpenGLLayer, self)->_cglContext pixelFormat: NS_EXTRA(CAOpenGLLayer, self)->_pixelFormat forLayerTime: layerTime displayTime: &ts];
        }

        glFlush();
        [self _copyFrameForHost: hostContext width: width height: height];
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(prevViewport[0], prevViewport[1], prevViewport[2], prevViewport[3]);

        if (needBind) {
            CGLSetCurrentContext(prevCtx);
            CGLUnlockContext(NS_EXTRA(CAOpenGLLayer, self)->_cglContext);
        }

        [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
    }
}

// An asynchronous layer redraws with every frame, a synchronous one only
// after -setNeedsDisplay.
- (void) displayIfNeeded {
    if (NS_EXTRA(CAOpenGLLayer, self)->_asynchronous) {
        NS_EXTRA(CALayer, self)->_needsDisplay = NO;
        [self display];
    } else {
        [super displayIfNeeded];
    }
}

- (BOOL) _drawLayerContents: (CGRect) bounds opacity: (CGFloat) opacity {
    if (NS_EXTRA(CAOpenGLLayer, self)->_colorTex == 0)
        return NO;

    GLuint frameTexture = [self _hostTextureForContext: CGLGetCurrentContext()];
    if (frameTexture == 0)
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
    glBindTexture(GL_TEXTURE_2D, frameTexture);

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
    if (NS_EXTRA(CAOpenGLLayer, self)->_cglContext) {
        if (CGLLockContext(NS_EXTRA(CAOpenGLLayer, self)->_cglContext) == kCGLNoError) {
            CGLContextObj prevCtx = CGLGetCurrentContext();
            if (CGLSetCurrentContext(NS_EXTRA(CAOpenGLLayer, self)->_cglContext) == kCGLNoError) {
                if (NS_EXTRA(CAOpenGLLayer, self)->_colorTex) glDeleteTextures(1, &NS_EXTRA(CAOpenGLLayer, self)->_colorTex);
                if (NS_EXTRA(CAOpenGLLayer, self)->_depthRb) glDeleteRenderbuffers(1, &NS_EXTRA(CAOpenGLLayer, self)->_depthRb);
                if (NS_EXTRA(CAOpenGLLayer, self)->_fbo) glDeleteFramebuffers(1, &NS_EXTRA(CAOpenGLLayer, self)->_fbo);
                if (prevCtx != NS_EXTRA(CAOpenGLLayer, self)->_cglContext) CGLSetCurrentContext(prevCtx);
            }
            CGLUnlockContext(NS_EXTRA(CAOpenGLLayer, self)->_cglContext);
        }
    }
    [self _releaseHostTexture];
    free(NS_EXTRA(CAOpenGLLayer, self)->_pixels);
    if (NS_EXTRA(CAOpenGLLayer, self)->_pixelFormat) [self releaseCGLPixelFormat: NS_EXTRA(CAOpenGLLayer, self)->_pixelFormat];
    if (NS_EXTRA(CAOpenGLLayer, self)->_cglContext) [self releaseCGLContext: NS_EXTRA(CAOpenGLLayer, self)->_cglContext];
    NS_EXTRA_FREE(CAOpenGLLayer, self);
    [super dealloc];
}

@end
