#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>
#import <QuartzCore/CALayer.h>
#import <QuartzCore/CALayerContext.h>
#import <QuartzCore/CAMetalLayer.h>
#import <QuartzCore/CARenderer.h>
#import <QuartzCore/CAOpenGLLayer.h>
#import "CALayerInternal.h"
#import <OpenGL/CGLInternal.h>
#include <math.h>

// The methods of CAMetalLayerInternal used here. Its header is Objective-C++.
@interface CAMetalLayerInternal : CAMetalLayer
- (BOOL) hasQueuedDrawables;
- (void) prepareRender;
@end

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
    _swapInterval = -1;

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
    if (_cglWindow != NULL && _ownsCglWindow)
        CGLDestroyWindow(_cglWindow);
    // The subwindow can outlive the context (it may still be in an
    // autorelease pool); it must not keep covering the window meanwhile.
    [_subwindow hide];
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

// A transparent or hidden root layer still has a native child window.
- (void) setHidden: (BOOL) hidden {
    if (hidden)
        [_subwindow hide];
    else
        [_subwindow show];
}

- (void) setSubwindow: (CGSubWindow*) subwindow
{
    CGSubWindow* oldSubwindow = _subwindow;

    if (_cglWindow && _ownsCglWindow) {
        CGLDestroyWindow(_cglWindow);
    }

    _subwindow = [subwindow retain];
    _cglWindow = CGLGetWindow([_subwindow nativeWindow]);
    _ownsCglWindow = _cglWindow != NULL;
    _swapInterval = -1;

    [_subwindow show];

    // As in -dealloc: a replaced subwindow is no longer drawn into.
    if (oldSubwindow != _subwindow)
        [oldSubwindow hide];
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

static GLint metalLayerSwapInterval(CALayer *layer);

// A tree with Metal layers that covers a borderless window may present in the
// window's own drawable (see -[CGSubWindow sharedCGLWindow]); switch to it, or
// back to the subwindow's, as that changes.
- (void) updateDrawable {
    if (_subwindow == nil)
        return;

    GLint interval = _layer != nil ? metalLayerSwapInterval(_layer) : -1;
    [_subwindow setAllowsParentDrawable: interval >= 0];
    [_subwindow setSyncsToDisplay: interval != 0];
    void *shared = [_subwindow sharedCGLWindow];

    if (shared != NULL ? (_cglWindow == shared && !_ownsCglWindow)
                       : (_cglWindow != NULL && _ownsCglWindow))
        return;

    // Detach from the old drawable before it can be destroyed.
    if (CGLGetCurrentContext() == _glContext)
        CGLSetCurrentContext(NULL);
    if (_cglWindow != NULL && _ownsCglWindow)
        CGLDestroyWindow(_cglWindow);

    if (shared != NULL) {
        _cglWindow = shared;
        _ownsCglWindow = NO;
    } else {
        _cglWindow = CGLGetWindow([_subwindow nativeWindow]);
        _ownsCglWindow = _cglWindow != NULL;
    }
    // The swap interval belongs to the drawable.
    _swapInterval = -1;
}

// The largest drawable dimension, in pixels, that the layer context renders.
#define MAX_DRAWABLE_DIMENSION 16384

// Sizes a drawable of the given size in points: the whole-point size used for
// the projection, and the size in pixels for the viewport. The pixel size is the
// one the subwindow reports for its allocation when it reports one, since
// repeating the multiplication by the scale here could round differently and
// leave an edge of the drawable stale; otherwise it follows from the
// subwindow's backing scale. Returns NO when the size or scale is unusable.
static BOOL drawableSizes(CGSubWindow *subwindow, CGSize size, GLint *width,
                          GLint *height, GLsizei *pixelWidth, GLsizei *pixelHeight)
{
    if (!isfinite(size.width) || !isfinite(size.height) || size.width <= 0 ||
        size.height <= 0 || size.width > MAX_DRAWABLE_DIMENSION ||
        size.height > MAX_DRAWABLE_DIMENSION)
        return NO;

    CGSize pixels = [subwindow drawablePixelSize];
    if (CGSizeEqualToSize(pixels, CGSizeZero)) {
        CGFloat scale = [subwindow backingScaleFactor];
        if (!isfinite(scale) || scale <= 0 ||
            ceil(size.width) * scale > MAX_DRAWABLE_DIMENSION ||
            ceil(size.height) * scale > MAX_DRAWABLE_DIMENSION)
            return NO;
        pixels = CGSizeMake(floor(ceil(size.width) * scale),
                            floor(ceil(size.height) * scale));
    } else if (!isfinite(pixels.width) || !isfinite(pixels.height) ||
               pixels.width < 1 || pixels.height < 1 ||
               pixels.width > MAX_DRAWABLE_DIMENSION ||
               pixels.height > MAX_DRAWABLE_DIMENSION ||
               floor(pixels.width) != pixels.width ||
               floor(pixels.height) != pixels.height) {
        return NO;
    }

    *width = ceil(size.width);
    *height = ceil(size.height);
    *pixelWidth = pixels.width;
    *pixelHeight = pixels.height;
    return YES;
}

- (void) renderLayer: (CALayer *) layer {
    // A backend that presents on its own thread cannot be rendered into from
    // another one.
    if ([_subwindow requiresMainThreadPresentation] && ![NSThread isMainThread])
        return;

    GLint width, height;
    GLsizei pixelWidth, pixelHeight;
    if (!drawableSizes(_subwindow, _frame.size, &width, &height, &pixelWidth,
                       &pixelHeight))
        return;

    // The application's own context is current on this thread when a view
    // displays; give it back afterwards, also when nothing was current or the
    // tree's drawing raises.
    CGLContextObj previous = CGLGetCurrentContext();

    if (CGLContextMakeCurrentAndAttachToWindow(_glContext, _cglWindow) != kCGLNoError)
        return;

    @try {
        // A context's draw and read buffers start out as NONE when it is first
        // made current without a window surface, and a Metal layer does that to
        // create its drawables. Attaching the window later does not change them,
        // so select the window's back buffer, which the flush swaps.
        glDrawBuffer(GL_BACK);
        glReadBuffer(GL_BACK);

        [self _drawLayerTree: layer
                       width: width
                      height: height
                 pixelsWidth: pixelWidth
                pixelsHeight: pixelHeight
                 topRowFirst: NO];
    } @finally {
        if (previous != _glContext)
            CGLSetCurrentContext(previous);
    }
}

- (void) _drawLayerTree: (CALayer *) layer
                  width: (GLint) width
                 height: (GLint) height
            topRowFirst: (BOOL) topRowFirst
{
    [self _drawLayerTree: layer
                   width: width
                  height: height
             pixelsWidth: width
            pixelsHeight: height
             topRowFirst: topRowFirst];
}

// The projection covers width x height points and the viewport the given number
// of pixels, which differs from it on a scaled drawable.
- (void) _drawLayerTree: (CALayer *) layer
                  width: (GLint) width
                 height: (GLint) height
            pixelsWidth: (GLsizei) pixelsWidth
           pixelsHeight: (GLsizei) pixelsHeight
            topRowFirst: (BOOL) topRowFirst
{
    glEnable(GL_DEPTH_TEST);
    glShadeModel(GL_SMOOTH);

    glViewport(0, 0, pixelsWidth, pixelsHeight);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    // Framebuffer row 0 is the bottom of the picture on a window. Pixels read
    // back into memory whose first row is the top are drawn upside down.
    if (topRowFirst)
        glOrtho(0, width, height, 0, -1, 1);
    else
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
    [self updateDrawable];
    // Without a window surface, attaching would leave the context without a
    // drawable and the tree would be drawn into nothing.
    if (_layer == nil || _cglWindow == NULL)
        return;
    [self renderLayer: _layer];
}

static BOOL layerTreeNeedsAnotherFrame(CALayer *layer) {
    if ([[layer animationKeys] count] > 0)
        return YES;
    // A Metal layer's frames arrive as presents from the app rather than as
    // layer-tree mutations, so the tree stays animation-free between them and the
    // animation check alone stops the timer after every present, costing a fresh
    // timer and its first 1/60s delay each time.
    if ([[layer class] isSubclassOfClass: [CAMetalLayerInternal class]] &&
        [(CAMetalLayerInternal*)layer hasQueuedDrawables])
        return YES;
    if ([layer isKindOfClass: [CAOpenGLLayer class]])
        return YES;
    for (CALayer *child in layer.sublayers)
        if (layerTreeNeedsAnotherFrame(child))
            return YES;
    return NO;
}

- (void) timer: (NSTimer *) timer {
    // Consume requests for this frame before callbacks can request another.
    _renderRequested = NO;
    [_renderer beginFrameAtTime: CACurrentMediaTime() timeStamp: NULL];

    [self render];

    [_renderer endFrame];

    // Animation frames aren't part of a view display pass, so present them here.
    [self flush];

    // beginFrameAtTime: drops finished animations. Once none are left, the frame
    // just drawn shows the final values: stop until an animation is added again,
    // or until a Metal layer has another present waiting to be composited,
    // or unless callbacks requested a subsequent frame while rendering or presenting this one.
    if (!_renderRequested && !layerTreeNeedsAnotherFrame(_layer)) {
        [_timer invalidate];
        [_timer release];
        _timer = nil;
    }
}

- (void) startTimerIfNeeded {
    // Metal and OpenGL layers present from arbitrary app threads. A timer scheduled there
    // lands on a run loop that never spins, so the frame is never composited.
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread: @selector(startTimerIfNeeded)
                               withObject: nil
                            waitUntilDone: NO
                                    modes: [NSArray arrayWithObjects: NSDefaultRunLoopMode, NSRunLoopCommonModes, @"NSModalPanelRunLoopMode", nil]];
        return;
    }
    _renderRequested = YES;
    if (_timer == nil) {
        _timer = [[NSTimer timerWithTimeInterval: 1.0 / 60.0
                                          target: self
                                        selector: @selector(timer:)
                                        userInfo: nil
                                         repeats: YES] retain];
        // Common modes keep frames flowing during live resize/drag tracking,
        // and default mode keeps frames flowing during normal event processing.
        [[NSRunLoop mainRunLoop] addTimer: _timer forMode: NSDefaultRunLoopMode];
        [[NSRunLoop mainRunLoop] addTimer: _timer forMode: NSRunLoopCommonModes];
        [[NSRunLoop mainRunLoop] addTimer: _timer forMode: @"NSModalPanelRunLoopMode"];
    }
}

- (void) deleteTextureId: (NSNumber *) textureId {
    if (textureId != nil)
        [_deleteTextureIds addObject: textureId];
}

// The swap interval the Metal layers in a tree ask for: 1 if any of them has
// displaySyncEnabled set, 0 if none has, and -1 for a tree without Metal layers.
static GLint metalLayerSwapInterval(CALayer *layer) {
    GLint interval = -1;
    if ([[layer class] isSubclassOfClass: [CAMetalLayerInternal class]])
        interval = [(CAMetalLayer *) layer displaySyncEnabled] ? 1 : 0;
    for (CALayer *child in layer.sublayers) {
        GLint childInterval = metalLayerSwapInterval(child);
        if (childInterval > interval)
            interval = childInterval;
    }
    return interval;
}

- (void) flush {
    if (_cglWindow == NULL)
        return;

    // See -renderLayer:.
    if ([_subwindow requiresMainThreadPresentation] && ![NSThread isMainThread])
        return;

    // The swap applies to the current context's surface. Code run during the
    // frame, such as a Metal layer's present, may have made another context
    // current, so make this one current on its window first.
    CGLContextObj previous = CGLGetCurrentContext();
    if (CGLContextMakeCurrentAndAttachToWindow(_glContext, _cglWindow) != kCGLNoError)
        return;

    // A Metal layer's frames are synchronized with the display refresh unless
    // its displaySyncEnabled is NO, and they reach the screen through this
    // swap. Other trees keep the context's own setting.
    GLint interval = metalLayerSwapInterval(_layer);
    if (interval >= 0 && interval != _swapInterval &&
        CGLSetParameter(_glContext, kCGLCPSwapInterval, &interval) == kCGLNoError)
        _swapInterval = interval;

    // The swap and whatever the backend does to present it happen together on
    // the thread the backend requires.
    if (CGLFlushDrawable(_glContext) == kCGLNoError)
        [_subwindow flush];
    if (previous != _glContext)
        CGLSetCurrentContext(previous);
}

@end
