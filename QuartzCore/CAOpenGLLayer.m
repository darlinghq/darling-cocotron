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
#import <IOSurface/IOSurface.h>
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
    // The layer's frames are composited into its context's native surface. Let a
    // backend that can describe that surface know that this layer needs EDR.
    CGSubWindow *subwindow = [NS_EXTRA(CALayer, self)->_context subwindow];
    if ([subwindow respondsToSelector: @selector(setWantsExtendedDynamicRangeContent:forLayer:)])
        [subwindow setWantsExtendedDynamicRangeContent: val forLayer: self];
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
// context and composited by the hosting context, which samples a texture it
// shares with the drawing context directly, without the surface that any other
// context needs (see -_hostTextureForContext:). Evidence: a requirement of this
// compositor, not an observation of macOS (no tier; maintainer-approved).
// A subclass that returns a context that does not share objects with the
// hosting one still reaches the screen, through IOSurface-backed frames.
// Test: quartzcore-opengl-layer, "default contexts share objects" (with an
// unshared context as the control).
- (CGLContextObj) copyCGLContextForPixelFormat: (CGLPixelFormatObj) pf {
    if (!pf) return NULL;
    CGLContextObj ctx = NULL;
    CGLCreateContext(pf, [NS_EXTRA(CALayer, self)->_context glContext], &ctx);
    return ctx;
}


#define GLX(layer) NS_EXTRA(CAOpenGLLayer, layer)

enum { kFrameSlots = 3 };

// Whether objects made in the two contexts are the same objects.
static BOOL contextsShareObjects(CGLContextObj a, CGLContextObj b) {
    return a != NULL && b != NULL && (a == b || CGLGetShareGroup(a) == CGLGetShareGroup(b));
}

static void setFrameTextureParameters(void) {
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
}

// Makes the texture bound to GL_TEXTURE_2D in the current context use the
// surface as its storage: the texture is the surface's pixels on macOS, and
// here when the driver can import the surface's memory (see OpenGL.c).
static CGLError bindFrameSurface(IOSurfaceRef surface, GLsizei width, GLsizei height) {
    return CGLTexImageIOSurface2D(CGLGetCurrentContext(), GL_TEXTURE_2D, GL_RGBA8, width, height,
                                  GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, surface, 0);
}

static IOSurfaceRef createFrameSurface(GLsizei width, GLsizei height) {
    NSDictionary *properties = @{
        (NSString *) kIOSurfaceWidth : @(width),
        (NSString *) kIOSurfaceHeight : @(height),
        (NSString *) kIOSurfaceBytesPerElement : @4,
        (NSString *) kIOSurfacePixelFormat : @((uint32_t) 'BGRA'),
    };
    return IOSurfaceCreate((CFDictionaryRef) properties);
}

// Called with the layer's context current: makes sure that the slot has a
// texture of width x height pixels, bound to a surface of that size if
// withSurface. Returns NO if it could not.
- (BOOL) _prepareSlot: (int) slot width: (GLsizei) width height: (GLsizei) height withSurface: (BOOL) withSurface {
    BOOL hasSurface = GLX(self)->_slotSurface[slot] != NULL;
    if (GLX(self)->_slotTex[slot] != 0 && GLX(self)->_slotWidth[slot] == width
        && GLX(self)->_slotHeight[slot] == height && (hasSurface || !withSurface))
        return YES;

    IOSurfaceRef surface = NULL;
    if (withSurface) {
        surface = createFrameSurface(width, height);
        if (surface == NULL)
            return NO;
    }

    GLint boundTexture = 0;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &boundTexture);
    if (GLX(self)->_slotTex[slot] == 0)
        glGenTextures(1, &GLX(self)->_slotTex[slot]);
    glBindTexture(GL_TEXTURE_2D, GLX(self)->_slotTex[slot]);
    CGLError error = kCGLNoError;
    if (withSurface) {
        // The texture keeps its name when its surface changes, so that the
        // context drops what it remembers of the old surface.
        error = bindFrameSurface(surface, width, height);
    } else {
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL);
    }
    setFrameTextureParameters();
    glBindTexture(GL_TEXTURE_2D, (GLuint) boundTexture);
    if (error != kCGLNoError) {
        if (surface != NULL)
            CFRelease(surface);
        return NO;
    }

    IOSurfaceRef old = GLX(self)->_slotSurface[slot];
    GLX(self)->_slotSurface[slot] = surface;
    GLX(self)->_slotWidth[slot] = width;
    GLX(self)->_slotHeight[slot] = height;
    if (old != NULL)
        CFRelease(old);
    return YES;
}

// Forgets the textures made in a compositing context for the frames.
- (void) _releaseHostTexture {
    if (GLX(self)->_hostTexContext == NULL)
        return;

    CGLContextObj previous = CGLGetCurrentContext();
    CGLLockContext(GLX(self)->_hostTexContext);
    if (CGLSetCurrentContext(GLX(self)->_hostTexContext) == kCGLNoError) {
        glDeleteTextures(kFrameSlots, GLX(self)->_hostTex);
        CGLSetCurrentContext(previous);
    }
    CGLUnlockContext(GLX(self)->_hostTexContext);
    memset(GLX(self)->_hostTex, 0, sizeof GLX(self)->_hostTex);
    memset(GLX(self)->_hostBoundSerial, 0, sizeof GLX(self)->_hostBoundSerial);
    CGLReleaseContext(GLX(self)->_hostTexContext);
    GLX(self)->_hostTexContext = NULL;
}

// The texture to composite in the context that is current (the compositing
// context), holding the last finished frame, or 0 when there is none. A
// context that shares objects with the layer's samples the slot's texture
// itself. Another one binds a texture of its own to the slot's surface: the
// surface is the layer's storage, so there is no copy of the pixels beyond
// what OpenGL.c makes for a driver that cannot import them.
- (GLuint) _hostTextureForContext: (CGLContextObj) host {
    IOSurfaceRef surface = NULL;
    GLuint texture = 0;
    int slot;
    unsigned long serial;
    GLsizei width, height;
    BOOL shared = contextsShareObjects(GLX(self)->_cglContext, host);

    @synchronized(self) {
        slot = GLX(self)->_frontSlot;
        if (slot == 0)
            return 0;
        // The layer does not draw into this slot until the compositor has
        // moved on to a later frame.
        GLX(self)->_hostSlot = slot;
        slot--;
        serial = GLX(self)->_frameSerial;
        width = GLX(self)->_slotWidth[slot];
        height = GLX(self)->_slotHeight[slot];
        if (shared) {
            texture = GLX(self)->_slotTex[slot];
        } else if (GLX(self)->_slotSurface[slot] != NULL) {
            surface = (IOSurfaceRef) CFRetain(GLX(self)->_slotSurface[slot]);
        } else {
            // The frame was drawn for a compositing context that shares
            // objects with the layer's, and this one does not: draw the
            // next frames into surfaces.
            GLX(self)->_wantsSurface = YES;
            texture = 0;
        }
    }
    if (shared)
        return texture;
    if (surface == NULL) {
        [self setNeedsDisplay];
        return 0;
    }

    if (GLX(self)->_hostTexContext != NULL && !contextsShareObjects(GLX(self)->_hostTexContext, host))
        [self _releaseHostTexture];
    if (GLX(self)->_hostTexContext == NULL)
        GLX(self)->_hostTexContext = CGLRetainContext(host);

    GLuint hostTexture = GLX(self)->_hostTex[slot];
    if (hostTexture != 0 && GLX(self)->_hostBoundSerial[slot] == serial) {
        CFRelease(surface);
        return hostTexture;
    }

    if (hostTexture == 0) {
        glGenTextures(1, &hostTexture);
        GLX(self)->_hostTex[slot] = hostTexture;
        glBindTexture(GL_TEXTURE_2D, hostTexture);
        setFrameTextureParameters();
    } else {
        glBindTexture(GL_TEXTURE_2D, hostTexture);
    }
    // Where the driver imports the surface's memory, binding it again to the
    // texture that already uses it changes nothing (the texture is the
    // surface); elsewhere this copies the new frame in.
    if (bindFrameSurface(surface, width, height) == kCGLNoError)
        GLX(self)->_hostBoundSerial[slot] = serial;
    else
        hostTexture = 0;
    CFRelease(surface);
    return hostTexture;
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
        CGLContextObj layerContext = NS_EXTRA(CAOpenGLLayer, self)->_cglContext;
        // The context that composites the layer: the one of the window the
        // layer is hosted in, else the one that asked for the frame.
        CGLContextObj hostContext = [NS_EXTRA(CALayer, self)->_context glContext];
        if (hostContext == NULL)
            hostContext = prevCtx;
        BOOL needBind = (prevCtx != layerContext);
        if (needBind) {
            CGLLockContext(layerContext);
            CGLSetCurrentContext(layerContext);
        }

        // Draw into a slot that is neither the latest frame nor the one the
        // compositor sampled last.
        int slot = 0;
        @synchronized(self) {
            while (slot + 1 == GLX(self)->_frontSlot || slot + 1 == GLX(self)->_hostSlot)
                slot++;
        }

        // A compositing context that shares objects with the layer's samples
        // the slot's texture itself; any other one needs a surface.
        BOOL withSurface = GLX(self)->_wantsSurface || !contextsShareObjects(layerContext, hostContext);
        BOOL ready = [self _prepareSlot: slot width: width height: height withSurface: withSurface];
        if (ready) {
            if (GLX(self)->_fbo == 0)
                glGenFramebuffers(1, &GLX(self)->_fbo);
            if (GLX(self)->_depthRb == 0)
                glGenRenderbuffers(1, &GLX(self)->_depthRb);
            glBindFramebuffer(GL_FRAMEBUFFER, GLX(self)->_fbo);
            if (GLX(self)->_allocatedSize.width != width || GLX(self)->_allocatedSize.height != height) {
                GLint boundRenderbuffer = 0;
                glGetIntegerv(GL_RENDERBUFFER_BINDING, &boundRenderbuffer);
                glBindRenderbuffer(GL_RENDERBUFFER, GLX(self)->_depthRb);
                glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, width, height);
                glBindRenderbuffer(GL_RENDERBUFFER, (GLuint) boundRenderbuffer);
                glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, GLX(self)->_depthRb);
                GLX(self)->_allocatedSize = CGSizeMake(width, height);
            }
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, GLX(self)->_slotTex[slot], 0);

            GLenum fboStatus = glCheckFramebufferStatus(GL_FRAMEBUFFER);
            if (fboStatus != GL_FRAMEBUFFER_COMPLETE) {
                NSLog(@"CAOpenGLLayer: FBO incomplete (0x%x)", fboStatus);
                ready = NO;
            }
        }
        if (!ready) {
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            if (needBind) {
                CGLSetCurrentContext(prevCtx);
                CGLUnlockContext(layerContext);
            }
            return;
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

        if ([self canDrawInCGLContext: layerContext pixelFormat: NS_EXTRA(CAOpenGLLayer, self)->_pixelFormat forLayerTime: layerTime displayTime: &ts]) {
            [self drawInCGLContext: layerContext pixelFormat: NS_EXTRA(CAOpenGLLayer, self)->_pixelFormat forLayerTime: layerTime displayTime: &ts];
        }

        // Another context of the same share group sees the frame after a
        // flush. One that shares nothing sees it through the surface, which
        // holds the frame once the work on it is finished (OpenGL.c copies a
        // texture that is only a copy of its surface into it at the same
        // point).
        if (withSurface)
            glFinish();
        else
            glFlush();
        @synchronized(self) {
            GLX(self)->_frontSlot = slot + 1;
            GLX(self)->_frameSerial++;
        }
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(prevViewport[0], prevViewport[1], prevViewport[2], prevViewport[3]);

        if (needBind) {
            CGLSetCurrentContext(prevCtx);
            CGLUnlockContext(layerContext);
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
    GLuint frameTexture = [self _hostTextureForContext: CGLGetCurrentContext()];
    if (frameTexture == 0)
        return NO;

    GLint prevPrgm = 0;
    glGetIntegerv(GL_CURRENT_PROGRAM, &prevPrgm);
    if (prevPrgm != 0) glUseProgram(0);

    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);

    // The frame has an alpha channel and is premultiplied, as the contents of
    // a layer are. An opaque layer says that its frame is completely opaque,
    // so its alpha channel is not looked at, whatever the frame holds there
    // (a frame that was cleared to alpha 0 shows its colour). The layer covers
    // what it is drawn over, so the destination's alpha is raised to 1 (to the
    // layer's opacity) in a pass of its own: where the destination is the
    // surface of a native subwindow, a compositor reads that alpha, and a
    // colour with alpha 0 is not a valid premultiplied pixel.
    BOOL opaque = [self isOpaque];
    GLboolean blendWasEnabled = glIsEnabled(GL_BLEND);
    GLboolean alphaTestWasEnabled = glIsEnabled(GL_ALPHA_TEST);
    GLint blendSrcRGB, blendDstRGB, blendSrcAlpha, blendDstAlpha;
    GLboolean colorMask[4];
    GLfloat blendColor[4];
    glGetIntegerv(GL_BLEND_SRC_RGB, &blendSrcRGB);
    glGetIntegerv(GL_BLEND_DST_RGB, &blendDstRGB);
    glGetIntegerv(GL_BLEND_SRC_ALPHA, &blendSrcAlpha);
    glGetIntegerv(GL_BLEND_DST_ALPHA, &blendDstAlpha);
    glGetBooleanv(GL_COLOR_WRITEMASK, colorMask);
    glGetFloatv(GL_BLEND_COLOR, blendColor);
    GLfloat modulate = opacity;
    if (!opaque) {
        glEnable(GL_BLEND);
        glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    } else {
        glDisable(GL_ALPHA_TEST);
        glColorMask(colorMask[0], colorMask[1], colorMask[2], GL_FALSE);
        if (opacity < 1) {
            glEnable(GL_BLEND);
            glBlendColor(0, 0, 0, opacity);
            glBlendFunc(GL_CONSTANT_ALPHA, GL_ONE_MINUS_CONSTANT_ALPHA);
            modulate = 1;
        } else {
            glDisable(GL_BLEND);
        }
    }

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
    glColor4f(modulate, modulate, modulate, modulate);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

    if (opaque && colorMask[3]) {
        // The blend function set up above (none, or the constant alpha one)
        // applies to alpha as well, with a source alpha of 1.
        glDisable(GL_TEXTURE_2D);
        glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_TRUE);
        glColor4f(1, 1, 1, 1);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    }

    glDisableClientState(GL_VERTEX_ARRAY);
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisable(GL_TEXTURE_2D);

    glBlendFuncSeparate(blendSrcRGB, blendDstRGB, blendSrcAlpha, blendDstAlpha);
    glBlendColor(blendColor[0], blendColor[1], blendColor[2], blendColor[3]);
    glColorMask(colorMask[0], colorMask[1], colorMask[2], colorMask[3]);
    if (blendWasEnabled) glEnable(GL_BLEND); else glDisable(GL_BLEND);
    if (alphaTestWasEnabled) glEnable(GL_ALPHA_TEST); else glDisable(GL_ALPHA_TEST);
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
    if (GLX(self)->_cglContext) {
        if (CGLLockContext(GLX(self)->_cglContext) == kCGLNoError) {
            CGLContextObj prevCtx = CGLGetCurrentContext();
            if (CGLSetCurrentContext(GLX(self)->_cglContext) == kCGLNoError) {
                glDeleteTextures(kFrameSlots, GLX(self)->_slotTex);
                if (GLX(self)->_depthRb) glDeleteRenderbuffers(1, &GLX(self)->_depthRb);
                if (GLX(self)->_fbo) glDeleteFramebuffers(1, &GLX(self)->_fbo);
                if (prevCtx != GLX(self)->_cglContext) CGLSetCurrentContext(prevCtx);
            }
            CGLUnlockContext(GLX(self)->_cglContext);
        }
    }
    [self _releaseHostTexture];
    for (int i = 0; i < kFrameSlots; i++) {
        if (GLX(self)->_slotSurface[i] != NULL)
            CFRelease(GLX(self)->_slotSurface[i]);
    }
    if (GLX(self)->_pixelFormat) [self releaseCGLPixelFormat: GLX(self)->_pixelFormat];
    if (GLX(self)->_cglContext) [self releaseCGLContext: GLX(self)->_cglContext];
    NS_EXTRA_FREE(CAOpenGLLayer, self);
    [super dealloc];
}

@end
