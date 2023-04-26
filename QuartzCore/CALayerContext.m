#import <Foundation/NSString.h>
#import <QuartzCore/CALayer.h>
#import <QuartzCore/CALayerContext.h>
#import <QuartzCore/CARenderer.h>
#import "CALayerInternal.h"
#import <OpenGL/CGLInternal.h>

@class CAMetalLayerInternal;

@implementation CALayerContext

@synthesize glContext = _glContext;

- initWithFrame: (CGRect) rect {
    CGLError error;

    CGLPixelFormatAttribute attributes[1] = {
            0,
    };
    GLint numberOfVirtualScreens;

    CGLChoosePixelFormat(attributes, &_pixelFormat, &numberOfVirtualScreens);

    if ((error = CGLCreateContext(_pixelFormat, NULL, &_glContext)) !=
        kCGLNoError)
        NSLog(@"CGLCreateContext failed with %d in %s %d", error, __FILE__,
              __LINE__);

    _frame = rect;

    _renderer = [[CARenderer rendererWithCGLContext: _glContext
                                            options: nil] retain];

    return self;
}

- (void) dealloc {
    [_timer invalidate];
    [_timer release];
    [_renderer release];
    CGLReleaseContext(_glContext);
    CGLDestroyWindow(_cglWindow);
    [_subwindow release];
    [_layer release];
    [super dealloc];
}

- (void) setFrame: (CGRect) rect {
    _frame = rect;
    [_subwindow setFrame: _frame];
}

- (void) setLayer: (CALayer *) layer {
    layer = [layer retain];
    [_layer release];
    _layer = layer;

    [_layer _setContext: self];
    [_renderer setLayer: layer];
}

- (void) setSubwindow: (CGSubWindow*) subwindow
{
    CGSubWindow* oldSubwindow = _subwindow;

    if (_cglWindow) {
        CGLDestroyWindow(_cglWindow);
    }

    _subwindow = [subwindow retain];
    _cglWindow = CGLGetWindow([_subwindow nativeWindow]);

    [_subwindow show];

    [oldSubwindow release];

    [_subwindow setFrame: _frame];
}

- (void) invalidate {
}

- (void) assignTextureIdsToLayerTree: (CALayer *) layer {

    if ([layer _textureId] == nil) {
        GLuint texture;

        glGenTextures(1, &texture);
        [layer _setTextureId: [NSNumber numberWithUnsignedInt: texture]];
    }

    for (CALayer *child in layer.sublayers)
        [self assignTextureIdsToLayerTree: child];
}

- (void) renderLayer: (CALayer *) layer {
    CGLContextMakeCurrentAndAttachToWindow(_glContext, _cglWindow);

    glEnable(GL_DEPTH_TEST);
    glShadeModel(GL_SMOOTH);

    GLint width = _frame.size.width;
    GLint height = _frame.size.height;

    glViewport(0, 0, width, height);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0, width, 0, height, -1, 1);

    GLsizei i = 0;
    GLuint deleteIds[[_deleteTextureIds count]];

    for (NSNumber *number in _deleteTextureIds)
        deleteIds[i++] = [number unsignedIntValue];

    if (i > 0)
        glDeleteTextures(i, deleteIds);

    [_deleteTextureIds removeAllObjects];

    [self assignTextureIdsToLayerTree: layer];

    // this is where the Metal layer renders to an internal texture for us to use
    if ([[layer class] isSubclassOfClass: [CAMetalLayerInternal class]]) {
        CAMetalLayerInternal* mtl = (CAMetalLayerInternal*)layer;
        [mtl prepareRender];
    }

    [_renderer render];
}

- (void) render {
    [self renderLayer: _layer];
}

- (void) timer: (NSTimer *) timer {
    [_renderer beginFrameAtTime: CACurrentMediaTime() timeStamp: NULL];

    [self render];

    [_renderer endFrame];
}

- (void) startTimerIfNeeded {
    if (_timer == nil)
        _timer = [[NSTimer scheduledTimerWithTimeInterval: 1.0 / 60.0
                                                   target: self
                                                 selector: @selector(timer:)
                                                 userInfo: nil
                                                  repeats: YES] retain];
}

- (void) deleteTextureId: (NSNumber *) textureId {
    [_deleteTextureIds addObject: textureId];
}

- (void) flush {
    CGLFlushDrawable(_glContext);
}

@end
