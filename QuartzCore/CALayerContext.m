#import <Foundation/NSArray.h>
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
    self = [super init];
    if (self == nil)
        return nil;

    CGLError error;

    CGLPixelFormatAttribute attributes[1] = {
            0,
    };
    GLint numberOfVirtualScreens;

    error = CGLChoosePixelFormat(attributes, &_pixelFormat, &numberOfVirtualScreens);
    if (error != kCGLNoError) {
        NSLog(@"CGLChoosePixelFormat failed with %d", error);
        [self release];
        return nil;
    }

    if ((error = CGLCreateContext(_pixelFormat, NULL, &_glContext)) !=
        kCGLNoError) {
        NSLog(@"CGLCreateContext failed with %d in %s %d", error, __FILE__,
              __LINE__);
        [self release];
        return nil;
    }

    _frame = rect;
    _deleteTextureIds = [[NSMutableArray alloc] init];

    _renderer = [[CARenderer rendererWithCGLContext: _glContext
                                            options: nil] retain];

    return self;
}

- (void) dealloc {
    [_timer invalidate];
    [_timer release];
    // Layers can outlive their context. Clear the borrowed pointer while the
    // context can still receive texture-cleanup requests from _setContext:.
    if ([_layer _context] == self)
        [_layer _setContext: nil];
    [_renderer release];
    [_deleteTextureIds release];
    CGLReleaseContext(_glContext);
    CGLReleasePixelFormat(_pixelFormat);
    if (_cglWindow != NULL)
        CGLDestroyWindow(_cglWindow);
    [_subwindow release];
    [_layer release];
    [super dealloc];
}

- (void) setFrame: (CGRect) rect {
    _frame = rect;
    [_subwindow setFrame: _frame];

    // The tree may have been set up before there was anything to draw it on.
    if (_layer != nil && _cglWindow != NULL)
        [self startTimerIfNeeded];
}

- (void) setLayer: (CALayer *) layer {
    layer = [layer retain];
    // Keep self-assignment intact, and do not detach a root that has already
    // been rebound to another context while this one still retains it.
    if (_layer != layer && [_layer _context] == self)
        [_layer _setContext: nil];
    [_layer release];
    _layer = layer;

    [_layer _setContext: self];
    [_renderer setLayer: layer];
    // Show the new tree even if nothing in it changes afterwards.
    if (_layer != nil)
        [self startTimerIfNeeded];
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
    [_timer invalidate];
    [_timer release];
    _timer = nil;
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

// A Metal layer is usually installed as some view's layer, and every view below
// the topmost layer-backed one in a window contributes a sublayer, so the Metal
// layer is rarely the context's root. Preparing only the root left a nested one
// with whatever _setContext: allocated, whose contents glTextureStorage2D leaves
// undefined, which the self-draw hook then composited verbatim.
//
// Only a CAMetalLayerInternal needs this, and for one with an empty queue
// -prepareRender is a lock and an @synchronized, no GL work. The drawable pool
// and its fd export live in -recreateDrawables, which only the property setters
// call, so walking the tree cannot repeat that per frame.
- (void) prepareMetalLayersInLayerTree: (CALayer *) layer {

    if ([[layer class] isSubclassOfClass: [CAMetalLayerInternal class]]) {
        CAMetalLayerInternal* mtl = (CAMetalLayerInternal*)layer;
        [mtl prepareRender];
    }

    for (CALayer *child in layer.sublayers)
        [self prepareMetalLayersInLayerTree: child];
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

    [self prepareMetalLayersInLayerTree: layer];

    [_renderer render];
}

- (void) render {
    // Without a window surface, attaching would leave the context without a
    // drawable and the tree would be drawn into nothing.
    if (_layer == nil || _cglWindow == NULL)
        return;
    [self renderLayer: _layer];
}

static BOOL layerTreeHasAnimations(CALayer *layer) {
    if ([[layer animationKeys] count] > 0)
        return YES;
    for (CALayer *child in layer.sublayers)
        if (layerTreeHasAnimations(child))
            return YES;
    return NO;
}

- (void) timer: (NSTimer *) timer {
    [_renderer beginFrameAtTime: CACurrentMediaTime() timeStamp: NULL];

    [self render];

    [_renderer endFrame];

    // Animation frames aren't part of a view display pass, so present them here.
    [self flush];

    // beginFrameAtTime: drops finished animations. Once none are left, the frame
    // just drawn shows the final values: stop until an animation is added again.
    if (!layerTreeHasAnimations(_layer)) {
        [_timer invalidate];
        [_timer release];
        _timer = nil;
    }
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
    if (textureId != nil)
        [_deleteTextureIds addObject: textureId];
}

- (void) flush {
    if (_cglWindow == NULL)
        return;

    // The swap applies to the current context's surface. Code run during the
    // frame, such as a Metal layer's present, may have made another context
    // current, so make this one current on its window first.
    CGLContextObj previous = CGLGetCurrentContext();
    if (CGLContextMakeCurrentAndAttachToWindow(_glContext, _cglWindow) != kCGLNoError)
        return;
    CGLFlushDrawable(_glContext);
    if (previous != _glContext)
        CGLSetCurrentContext(previous);
}

@end
