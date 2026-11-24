/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSOpenGLContext.h>
#import <AppKit/NSOpenGLPixelFormat.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow-Private.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <OpenGL/CGLInternal.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <CoreFoundation/CFNotificationCenter.h>
#import <objc/runtime.h>

@interface NSOpenGLContext (private)
- (void) _clearCurrentContext;
- (void) _startObservingView;
- (void) _stopObservingView;
- (void) _applyPendingViewportReset;
@end

@interface _NSOpenGLViewContextEntry : NSObject {
@public
    id _context;
}
@end

@implementation _NSOpenGLViewContextEntry
- (void) dealloc {
    objc_storeWeak(&_context, nil);
    [super dealloc];
}
@end

@implementation NSOpenGLContext

// The contexts that have a view, so that AppKit can find the ones attached to
// the views of a window (see +_updateContextsAttachedToWindow:). Each entry
// refers to its context through a zeroing weak reference: a context removes
// itself when its view is cleared and in dealloc, and a context that is
// already deallocating on another thread reads back as nil, so it is never
// retained again while it is being destroyed.
static NSMutableArray *_viewContexts;

static void _registerViewContext(NSOpenGLContext *context, BOOL attached) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _viewContexts = [[NSMutableArray alloc] init];
    });
    @synchronized(_viewContexts) {
        // Drop this context's entry and any entry whose context is gone.
        for (NSUInteger i = [_viewContexts count]; i > 0; i--) {
            _NSOpenGLViewContextEntry *entry = [_viewContexts objectAtIndex: i - 1];
            id existing = objc_loadWeak(&entry->_context);
            if (existing == nil || existing == context)
                [_viewContexts removeObjectAtIndex: i - 1];
        }
        if (attached) {
            _NSOpenGLViewContextEntry *entry = [[_NSOpenGLViewContextEntry alloc] init];
            objc_storeWeak(&entry->_context, context);
            [_viewContexts addObject: entry];
            [entry release];
        }
    }
}

// Sends -update to each context attached to a view of the window. It goes
// through normal dispatch, so a subclass that overrides -update sees the call.
// The contexts are retained through their weak references, which fail for one
// that is being deallocated.
+ (void) _updateContextsAttachedToWindow: (NSWindow *) window {
    if (_viewContexts == nil)
        return;
    NSMutableArray *contexts = [NSMutableArray array];
    @synchronized(_viewContexts) {
        for (_NSOpenGLViewContextEntry *entry in _viewContexts) {
            NSOpenGLContext *context = objc_loadWeak(&entry->_context);
            if (context != nil)
                [contexts addObject: context];
        }
    }
    for (NSOpenGLContext *context in contexts) {
        if ([[context view] window] == window)
            [context update];
    }
}

static inline NSOpenGLContext *_currentContext() {
    return (NSOpenGLContext *) NSThreadSharedInstanceDoNotCreate(
            @"NSOpenGLContext");
}

static void _setCurrentContext(NSOpenGLContext *context) {
    [NSCurrentThread() setSharedObject: context
                          forClassName: @"NSOpenGLContext"];
}

static inline void _clearCurrentContext() {
    [_currentContext() _clearCurrentContext];
    _setCurrentContext(nil);
}

+ (NSOpenGLContext *) currentContext {
    return _currentContext();
}

+ (void) clearCurrentContext {
    _clearCurrentContext();
}

- initWithFormat: (NSOpenGLPixelFormat *) pixelFormat
        shareContext: (NSOpenGLContext *) shareContext
{
    CGLError error;

    if (_pixelFormat != nil) {
        // Cocoa's NSOpenGLContext can withstand a double init and I know of at
        // least one app that does it Maybe Cocoa just leaks, we don't
        [_pixelFormat release];
        _pixelFormat = nil;
        CGLReleaseContext(_glContext);
        _glContext = NULL;
    }

    _pixelFormat = [pixelFormat retain];
    if ((error = CGLCreateContext(
                 [_pixelFormat CGLPixelFormatObj], [shareContext CGLContextObj],
                 (CGLContextObj *) &_glContext)) != kCGLNoError)
        NSLog(@"CGLCreateContext failed with %d in %s %d", error, __FILE__,
              __LINE__);

    return self;
}

// Wraps a context created with the CGL API. The wrapper owns one reference of
// the CGL context, which dealloc gives back.
- (instancetype) initWithCGLContextObj: (CGLContextObj) context {
    if (context == NULL) {
        [self release];
        return nil;
    }

    if (_glContext != NULL) {
        CGLReleaseContext(_glContext);
        _glContext = NULL;
    }
    [_pixelFormat release];
    _pixelFormat = nil;
    _glContext = CGLRetainContext(context);
    return self;
}

- (void) dealloc {
    _registerViewContext(self, NO);
    [self _stopObservingView];
    // FIXME: this doesn't actually work because if we are the current context
    // we're retained by the thread shared object dict
    if (_currentContext() == self)
        _clearCurrentContext();
    [_pixelFormat release];

    [self _stopObservingPresentation];
    if (NS_EXTRA(NSOpenGLContext, self)->_cglWindow != NULL) {
        CGLDestroyWindow(NS_EXTRA(NSOpenGLContext, self)->_cglWindow);
    }
    if (NS_EXTRA(NSOpenGLContext, self)->_surfaceID != 0)
        _CGSRemoveWindowSurface(NS_EXTRA(NSOpenGLContext, self)->_surfaceID);
    [NS_EXTRA(NSOpenGLContext, self)->_subwindow release];
    NS_EXTRA(NSOpenGLContext, self)->_view = nil;

    CGLReleaseContext(_glContext);
    NS_EXTRA_FREE(NSOpenGLContext, self);
    [super dealloc];
}

- (NSView *) view {
    return NS_EXTRA(NSOpenGLContext, self)->_view;
}

- (NSOpenGLPixelBuffer *) pixelBuffer {
    NSUnimplementedMethod();
    return nil;
}

- (unsigned long) pixelBufferCubeMapFace {
    NSUnimplementedMethod();
    return 0;
}

- (long) pixelBufferMipMapLevel {
    NSUnimplementedMethod();
    return 0;
}

- (void *) CGLContextObj {
    return _glContext;
}

- (void) getValues: (GLint *) vals
        forParameter: (NSOpenGLContextParameter) parameter
{
    CGLGetParameter(_glContext, parameter, vals);
}

- (void) setValues: (const GLint *) vals
        forParameter: (NSOpenGLContextParameter) parameter
{
    CGLSetParameter(_glContext, parameter, vals);
}

// A client that swaps through CGLFlushDrawable() directly (not -flushBuffer)
// is presented by the window backend after the swap too: OpenGL posts a
// notification for the window's native handle when it swaps a surface, and
// the subwindow's -flush is what the backend does after a swap. Only backends
// that do something there need it.
static void _swapNotification(CFNotificationCenterRef center, void *observer, CFNotificationName name,
                              const void *object, CFDictionaryRef userInfo) {
    CGSubWindow *subwindow = [(NSOpenGLContext *) observer _presentationSubwindow];
    [subwindow flush];
}

- (CGSubWindow *) _presentationSubwindow {
    return NS_EXTRA(NSOpenGLContext, self)->_subwindow;
}

- (void) _startObservingPresentation {
    CGSubWindow *subwindow = NS_EXTRA(NSOpenGLContext, self)->_subwindow;
    if (NS_EXTRA(NSOpenGLContext, self)->_presentObserved || subwindow == nil ||
        [subwindow methodForSelector: @selector(flush)] == [CGSubWindow instanceMethodForSelector: @selector(flush)])
        return;
    CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), self, _swapNotification,
        kCGLWindowDidSwapNotification, [subwindow nativeWindow], CFNotificationSuspensionBehaviorDeliverImmediately);
    NS_EXTRA(NSOpenGLContext, self)->_presentObserved = YES;
}

- (void) _stopObservingPresentation {
    if (!NS_EXTRA(NSOpenGLContext, self)->_presentObserved)
        return;
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetLocalCenter(), self,
        kCGLWindowDidSwapNotification, [NS_EXTRA(NSOpenGLContext, self)->_subwindow nativeWindow]);
    NS_EXTRA(NSOpenGLContext, self)->_presentObserved = NO;
}

// Makes the view's window the drawable of the CGL context without changing
// which context is current on this thread: a context that the application
// makes current later with CGLSetCurrentContext() (not -makeCurrentContext)
// then draws to and presents on the view, as it does on macOS once -setView:
// has been called.
- (void) _attachDrawable {
    CGLWindowRef window = NS_EXTRA(NSOpenGLContext, self)->_cglWindow;
    if (window == NULL)
        return;
    CGLContextObj previous = CGLGetCurrentContext();
    if (CGLContextMakeCurrentAndAttachToWindow(_glContext, window) == kCGLNoError && previous != _glContext)
        CGLSetCurrentContext(previous);
}

- (void) updateViewParameters {
    [self _updateViewParametersAttaching: YES];
}

// -makeCurrentContext attaches the drawable itself, on the calling thread, so
// it does not need the extra attach (which would bind the context to the main
// thread while another thread may be holding it).
- (void) _updateViewParametersForMakeCurrent {
    [self _updateViewParametersAttaching: NO];
}

- (void) _updateViewParametersAttaching: (BOOL) attach {
    if (NS_EXTRA(NSOpenGLContext, self)->_view == nil || [NS_EXTRA(NSOpenGLContext, self)->_view window] == nil) return;
    NSRect rect = [NS_EXTRA(NSOpenGLContext, self)->_view bounds];

    if ([NS_EXTRA(NSOpenGLContext, self)->_view window] != nil)
        rect = [NS_EXTRA(NSOpenGLContext, self)->_view convertRect: rect toView: nil];
    if (NS_EXTRA(NSOpenGLContext, self)->_subwindow == nil) {
        NS_EXTRA(NSOpenGLContext, self)->_subwindow = [[[NS_EXTRA(NSOpenGLContext, self)->_view window] _createSubWindowWithFrame: rect] retain];
        NS_EXTRA(NSOpenGLContext, self)->_cglWindow = CGLGetWindowForContext(_glContext, [NS_EXTRA(NSOpenGLContext, self)->_subwindow nativeWindow]);
        // Record the drawable as a surface of the view's window, so that CGLGetSurface() and
        // the window server calls (CGSGetSurfaceBounds()) can find it.
        NS_EXTRA(NSOpenGLContext, self)->_surfaceID = _CGSAddWindowSurface(
            (CGSWindowID) [[NS_EXTRA(NSOpenGLContext, self)->_view window] windowNumber],
            [NS_EXTRA(NSOpenGLContext, self)->_subwindow nativeWindow], rect.size);
        [self _startObservingPresentation];
        if (attach)
            [self _attachDrawable];
    } else {
        [NS_EXTRA(NSOpenGLContext, self)->_subwindow setFrame: rect];
        _CGSSetWindowSurfaceSize(NS_EXTRA(NSOpenGLContext, self)->_surfaceID, rect.size);
    }

    if ([NS_EXTRA(NSOpenGLContext, self)->_view isHidden]) {
        [NS_EXTRA(NSOpenGLContext, self)->_subwindow hide];
    } else {
        [NS_EXTRA(NSOpenGLContext, self)->_subwindow show];
    }
}

// A view that has a context attached posts NSViewGlobalFrameDidChangeNotification
// when its frame changes; applications observe it to call -update when the
// view is resized. Plain views do not post it. The notification is queued for
// when the run loop is idle and coalesced per view: on macOS it is posted from
// inside -setFrame:, but a thread that is waiting for this thread (an
// application's drawing thread holding its lock) must not be able to block the
// callout that changed the frame, because a context can be current on one
// thread at a time here and the main thread has to get to its run loop to
// hand its context over (see CGLSetCurrentContext).
- (void) _viewFrameDidChange: (NSNotification *) note {
    [[NSNotificationQueue defaultQueue]
            enqueueNotification: [NSNotification notificationWithName: NSViewGlobalFrameDidChangeNotification
                                                               object: NS_EXTRA(NSOpenGLContext, self)->_view]
                   postingStyle: NSPostWhenIdle
                   coalesceMask: NSNotificationCoalescingOnName | NSNotificationCoalescingOnSender
                       forModes: nil];
}

- (void) _startObservingView {
    if (NS_EXTRA(NSOpenGLContext, self)->_view != nil)
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(_viewFrameDidChange:)
                                                     name: NSViewFrameDidChangeNotification
                                                   object: NS_EXTRA(NSOpenGLContext, self)->_view];
}

- (void) _stopObservingView {
    if (NS_EXTRA(NSOpenGLContext, self)->_view != nil)
        [[NSNotificationCenter defaultCenter] removeObserver: self
                                                        name: NSViewFrameDidChangeNotification
                                                      object: NS_EXTRA(NSOpenGLContext, self)->_view];
}

- (void) setView: (NSView *) view {
    if (NS_EXTRA(NSOpenGLContext, self)->_view == view)
        return;

    // Detach before native-window destruction; EGL can defer destroying a
    // drawable that remains current. Keep self alive across the thread release.
    [self retain];
    if (CGLGetCurrentContext() == _glContext) {
        if (CGLSetCurrentContext(NULL) != kCGLNoError) { [self release]; return; }
        if (_currentContext() == self) _setCurrentContext(nil);
    }
    NS_EXTRA(NSOpenGLContext, self)->_hasPrepared = NO;
    NS_EXTRA(NSOpenGLContext, self)->_drawableAttachmentSucceeded = NO;
    [self _stopObservingView];
    NS_EXTRA(NSOpenGLContext, self)->_view = view;
    [self _startObservingView];
    _registerViewContext(self, view != nil);

    [self _stopObservingPresentation];
    if (NS_EXTRA(NSOpenGLContext, self)->_cglWindow != NULL) {
        CGLDestroyWindow(NS_EXTRA(NSOpenGLContext, self)->_cglWindow);
        NS_EXTRA(NSOpenGLContext, self)->_cglWindow = NULL;
    }
    if (NS_EXTRA(NSOpenGLContext, self)->_surfaceID != 0) {
        _CGSRemoveWindowSurface(NS_EXTRA(NSOpenGLContext, self)->_surfaceID);
        NS_EXTRA(NSOpenGLContext, self)->_surfaceID = 0;
    }
    [NS_EXTRA(NSOpenGLContext, self)->_subwindow release];
    NS_EXTRA(NSOpenGLContext, self)->_subwindow = nil;

    [self updateViewParameters];
    [self release];
}

- (void) makeCurrentContext {
    CGLError error;
    NS_EXTRA(NSOpenGLContext, self)->_drawableAttachmentSucceeded = NO;

    // Viewless contexts have no window geometry to update. In particular,
    // background resource uploads must not wait for a main-thread run loop.
    if (NS_EXTRA(NSOpenGLContext, self)->_subwindow == nil && NS_EXTRA(NSOpenGLContext, self)->_view != nil) {
        if ([NSThread isMainThread]) {
            [self _updateViewParametersForMakeCurrent];
        } else {
            [self performSelectorOnMainThread: @selector(_updateViewParametersForMakeCurrent)
                                   withObject: nil
                                waitUntilDone: YES];
        }
    }

    if ([NS_EXTRA(NSOpenGLContext, self)->_subwindow respondsToSelector: @selector(requiresMainThreadPresentation)] &&
        [NS_EXTRA(NSOpenGLContext, self)->_subwindow requiresMainThreadPresentation] && ![NSThread isMainThread]) {
        NSLog(@"This window backend requires OpenGL rendering on the main thread");
        return;
    }
    if (NS_EXTRA(NSOpenGLContext, self)->_cglWindow != NULL) {
        if ((error = CGLContextMakeCurrentAndAttachToWindow(
                     _glContext, NS_EXTRA(NSOpenGLContext, self)->_cglWindow)) != kCGLNoError) {
            NSLog(@"CGLSetCurrentContext failed with %d in %s %d", error, __FILE__,
                  __LINE__);
            // A swap-interval error may occur after EGL successfully switched.
            if (CGLGetCurrentContext() == _glContext) _setCurrentContext(self);
            return;
        }
    } else {
        if ((error = CGLSetCurrentContext(_glContext)) != kCGLNoError) {
            NSLog(@"CGLSetCurrentContext without window failed with %d in %s %d", error, __FILE__, __LINE__);
            return;
        }
    }

    _setCurrentContext(self);
    NS_EXTRA(NSOpenGLContext, self)->_drawableAttachmentSucceeded = YES;
    [self _applyPendingViewportReset];

    if (!NS_EXTRA(NSOpenGLContext, self)->_hasPrepared) {
        NS_EXTRA(NSOpenGLContext, self)->_hasPrepared = YES;

        // NSOpenGLContext will call prepareOpenGL on any view, not just
        // NSOpenGLView
        if ([NS_EXTRA(NSOpenGLContext, self)->_view respondsToSelector: @selector(prepareOpenGL)])
            [NS_EXTRA(NSOpenGLContext, self)->_view performSelector: @selector(prepareOpenGL)];
    }
}

- (void) _clearCurrentContext {
    CGLError error;

    if ((error = CGLSetCurrentContext(NULL)) != kCGLNoError)
        NSLog(@"CGLSetCurrentContext failed with %d in %s %d", error, __FILE__,
              __LINE__);
}

- (int) currentVirtualScreen {
    NSUnimplementedMethod();
    return 0;
}

- (void) setCurrentVirtualScreen: (int) screen {
    NSUnimplementedMethod();
}

- (void) setFullScreen {
    if (NS_EXTRA(NSOpenGLContext, self)->_view != nil)
        NSLog(@"NSOpenGLContext has view, full-screen not allowed");

    NSUnimplementedMethod();
}

- (void) setOffscreen: (void *) bytes
                width: (long) width
               height: (long) height
             rowbytes: (long) rowbytes
{
    NSUnimplementedMethod();
}

- (void) setPixelBuffer: (NSOpenGLPixelBuffer *) pixelBuffer
                 cubeMapFace: (unsigned long) cubeMapFace
                  mipMapLeve: (long) mipMapLevel
        currentVirtualScreen: (int) screen
{
    NSUnimplementedMethod();
}

- (void) setTextureImageToPixelBuffer: (NSOpenGLPixelBuffer *) pixelBuffer
                          colorBuffer: (unsigned long) source
{
    NSUnimplementedMethod();
}

- (BOOL) _drawableAttachmentSucceeded {
    return NS_EXTRA(NSOpenGLContext, self)->_drawableAttachmentSucceeded;
}

// Do not create a drawable just to answer a backing-coordinate query.
- (NSSize) _drawablePixelSize {
    return [NS_EXTRA(NSOpenGLContext, self)->_subwindow respondsToSelector: @selector(drawablePixelSize)]
        ? [NS_EXTRA(NSOpenGLContext, self)->_subwindow drawablePixelSize] : NSZeroSize;
}

// QUIRK: when the view the context is attached to has
// wantsBestResolutionOpenGLSurface set (YES by default for programs linked
// against SDK 10.15 or later, see -[NSView wantsBestResolutionOpenGLSurface]),
// -update also sets the current viewport to (0, 0, width, height) of the
// drawable's new pixel size, replacing a viewport the application set with
// glViewport; the scissor box is not changed. The NSOpenGLView.h comment on the
// property only says that glViewport is called before update and reshape for
// such views. Evidence: that header comment (tier 1) and black-box
// observation (tier 2): macOS 26.7.3 x86_64 resets on update when the property
// is YES (its default for a new SDK) and not when it is NO; a binary linked
// against SDK 10.14 resets only if the property is set to YES; Mac OS X
// 10.14.4 (x86_64, i386) resets on update when the property is set to YES, its
// default is NO. It applies to a plain NSView as well as to an NSOpenGLView;
// CGLUpdateContext alone does not reset; the property is read when update is
// called.
// Test: tests/appkit-opengl-update-viewport.m (test_quirk_update_resets_viewport).
//
// The viewport belongs to the GL context, which has to be current on the
// calling thread to change it; a context another thread holds gets the reset
// when a thread next makes it current.
- (void) _resetViewportToDrawable {
    NSView *view = NS_EXTRA(NSOpenGLContext, self)->_view;
    if (view == nil || ![view wantsBestResolutionOpenGLSurface]) return;
    __atomic_store_n(&NS_EXTRA(NSOpenGLContext, self)->_viewportResetPending, 1, __ATOMIC_RELEASE);
    if (CGLGetCurrentContext() == _glContext)
        [self _applyPendingViewportReset];
}

// Sets the viewport of the context current on this thread, if an update asked
// for it since.
- (void) _applyPendingViewportReset {
    if (!__atomic_load_n(&NS_EXTRA(NSOpenGLContext, self)->_viewportResetPending, __ATOMIC_ACQUIRE)) return;
    NSSize pixels = [self _drawablePixelSize];
    // No drawable (yet): nothing to follow; the first bind sets the viewport.
    if (pixels.width < 1 || pixels.height < 1) return;
    if (!__atomic_exchange_n(&NS_EXTRA(NSOpenGLContext, self)->_viewportResetPending, 0, __ATOMIC_ACQ_REL)) return;
    glViewport(0, 0, (GLsizei) pixels.width, (GLsizei) pixels.height);
}

- (void) update {
    [self updateViewParameters];
    [self _resetViewportToDrawable];
}

- (void) clearDrawable {
    [self setView: nil];
}

- (void) copyAttributesFromContext: (NSOpenGLContext *) context
                          withMask: (unsigned long) mask
{
    NSUnimplementedMethod();
}

- (void) createTexture: (unsigned long) identifier
              fromView: (NSView *) view
        internalFormat: (unsigned long) internalFormat
{
    NSUnimplementedMethod();
}

- (void) flushBuffer {
    // A backend that presents on its own thread cannot be swapped from another.
    if ([NS_EXTRA(NSOpenGLContext, self)->_subwindow requiresMainThreadPresentation] && ![NSThread isMainThread])
        return;

    // Pace swaps to the refresh rate of the output the window is on; 0 means unknown.
    CGLSetDrawableRefreshRate(_glContext,
        [NS_EXTRA(NSOpenGLContext, self)->_subwindow respondsToSelector: @selector(refreshMillihertz)]
        ? [NS_EXTRA(NSOpenGLContext, self)->_subwindow refreshMillihertz] : 0);
    // With the notification observer registered CGLFlushDrawable() has already
    // had the subwindow present the frame.
    if (CGLFlushDrawable(_glContext) == kCGLNoError && !NS_EXTRA(NSOpenGLContext, self)->_presentObserved)
        [NS_EXTRA(NSOpenGLContext, self)->_subwindow flush];
}

@end
