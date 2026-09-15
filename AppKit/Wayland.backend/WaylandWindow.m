/* Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

#import "WaylandWindow.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSRunLoop.h>
#import <Onyx2D/O2Context_builtin_FT.h>
#import <Onyx2D/O2Surface.h>
#include <errno.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

@implementation WaylandWindow

static void sendRequest(struct wl_proxy *proxy, uint32_t opcode, uint32_t flags) {
    union wl_argument args[1] = {{.o = NULL}};
    WaylandMarshal(proxy, opcode, NULL, flags, args);
}

- (instancetype) initWithDelegate: (NSWindow *) delegate {
    if ((self = [super init]) == nil)
        return nil;

    _delegate = delegate;
    _level = [delegate level];
    _styleMask = [delegate styleMask];
    _backingType = (CGSBackingStoreType) [delegate backingType];
    _isOpaque = [delegate isOpaque];
    _deviceDictionary = [NSMutableDictionary new];
    _display = (WaylandDisplay *) [NSDisplay currentDisplay];

    _frame = [delegate frame];
    _frame.size.width = MAX(_frame.size.width, 1.0);
    _frame.size.height = MAX(_frame.size.height, 1.0);

    [_display windowCreated: self];
    return self;
}

- (void) dealloc {
    [self invalidate];
    [_deviceDictionary release];
    [_title release];
    [super dealloc];
}

- (void) invalidate {
    // Like X11Window, this can run several times.
    [_context release];
    _context = nil;

    [_delegate platformWindowDidInvalidateCGContext: self];
    _delegate = nil;

    [self unmap];
    if (_display != nil) {
        [_display windowDestroyed: self];
        _display = nil;
    }
}

- (void) setDelegate: (id) delegate {
    _delegate = delegate;
}

- (id) delegate {
    return _delegate;
}

- (void) syncDelegateProperties {
}

- (struct wl_proxy *) surface {
    return _surface;
}

- (BOOL) isMapped {
    return _mapped;
}

#pragma mark - Mapping

- (void) ensureMapped {
    if (_mapped || _display == nil)
        return;

    union wl_argument args[2];

    args[0].o = NULL;
    _surface = WaylandCreateObject(_display->_compositor,
                                   WP_COMPOSITOR_CREATE_SURFACE,
                                   &wl_surface_interface, args,
                                   WaylandObjectSurface, self);

    args[0].o = NULL;
    args[1].o = (struct wl_object *) _surface;
    _xdgSurface = WaylandCreateObject(_display->_wmBase,
                                      WP_WM_BASE_GET_XDG_SURFACE,
                                      &xdg_surface_interface, args,
                                      WaylandObjectXdgSurface, self);

    args[0].o = NULL;
    _toplevel = WaylandCreateObject(_xdgSurface, WP_XDG_SURFACE_GET_TOPLEVEL,
                                    &xdg_toplevel_interface, args,
                                    WaylandObjectToplevel, self);

    [self updateTitle];
    args[0].s = [[[NSProcessInfo processInfo] processName] UTF8String];
    if (args[0].s != NULL)
        WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_APP_ID, NULL, 0, args);
    [self updateSizeLimits];

    if (_display->_decorationManager != NULL) {
        args[0].o = NULL;
        args[1].o = (struct wl_object *) _toplevel;
        _decoration = WaylandCreateObject(
                _display->_decorationManager,
                WP_DECORATION_MANAGER_GET_TOPLEVEL_DECORATION,
                &zxdg_toplevel_decoration_v1_interface, args,
                WaylandObjectDecoration, self);
        args[0].u = WP_TOPLEVEL_DECORATION_MODE_SERVER_SIDE;
        WaylandMarshal(_decoration, WP_TOPLEVEL_DECORATION_SET_MODE, NULL, 0, args);
    }

    // The initial commit has no buffer; content follows the first configure.
    sendRequest(_surface, WP_SURFACE_COMMIT, 0);
    _mapped = YES;
    _configured = NO;
    _needsPresent = _context != nil;
    [_display flush];
}

- (void) destroyBuffers {
    for (int i = 0; i < 2; i++) {
        struct WaylandBuffer *buffer = &_buffers[i];
        if (buffer->buffer != NULL)
            sendRequest(buffer->buffer, WP_BUFFER_DESTROY, WL_MARSHAL_FLAG_DESTROY);
        if (buffer->data != NULL)
            munmap(buffer->data, buffer->size);
        memset(buffer, 0, sizeof(*buffer));
    }
}

// Unmapping an xdg surface requires a new configure sequence before it can be
// shown again, so the role objects are destroyed and created again on show.
- (void) unmap {
    if (!_mapped)
        return;

    if (_frameCallback != NULL) {
        WL.wl_proxy_destroy(_frameCallback);
        _frameCallback = NULL;
    }
    if (_decoration != NULL) {
        sendRequest(_decoration, WP_TOPLEVEL_DECORATION_DESTROY,
                    WL_MARSHAL_FLAG_DESTROY);
        _decoration = NULL;
    }
    sendRequest(_toplevel, WP_TOPLEVEL_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    sendRequest(_xdgSurface, WP_XDG_SURFACE_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    sendRequest(_surface, WP_SURFACE_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    _toplevel = _xdgSurface = _surface = NULL;
    [self destroyBuffers];

    _mapped = NO;
    _configured = NO;
    _activated = NO;
    [_display windowUnmapped: self];
    [_display flush];
}

- (void) showWindowWithoutActivation {
    [self ensureMapped];
}

- (void) showWindowForAppActivation: (NSRect) frame {
    [self ensureMapped];
}

- (void) hideWindowForAppDeactivation: (NSRect) frame {
}

- (void) hideWindow {
    [self unmap];
}

- (void) sheetOrderFrontFromFrame: (NSRect) frame
                      aboveWindow: (CGWindow *) aboveWindow
{
    [self setFrame: frame];
    [self ensureMapped];
}

- (void) sheetOrderOutToFrame: (NSRect) frame {
    [self unmap];
}

// Clients can't restack or focus toplevels; the compositor decides.
- (void) placeAboveWindow: (NSInteger) otherNumber {
    [self ensureMapped];
}

- (void) placeBelowWindow: (NSInteger) otherNumber {
    [self ensureMapped];
}

- (void) makeKey {
    [self ensureMapped];
}

- (void) makeMain {
}

- (void) captureEvents {
}

- (void) miniaturize {
    if (_toplevel != NULL) {
        sendRequest(_toplevel, WP_TOPLEVEL_SET_MINIMIZED, 0);
        [_display flush];
    }
}

- (void) deminiaturize {
    [self ensureMapped];
}

- (BOOL) isMiniaturized {
    // xdg-shell doesn't report whether a toplevel is minimized.
    return NO;
}

- (void) flashWindow {
}

#pragma mark - Properties

- (NSUInteger) styleMask {
    return _styleMask;
}

- (void) setStyleMask: (NSUInteger) mask {
    _styleMask = mask;
    [self updateSizeLimits];
}

- (void) setLevel: (int) value {
    _level = value;
}

- (void) updateTitle {
    if (_toplevel == NULL)
        return;
    const char *title = [_title UTF8String];
    union wl_argument args[1] = {{.s = title ? title : ""}};
    WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_TITLE, NULL, 0, args);
}

- (void) setTitle: (NSString *) title {
    [_title release];
    _title = [title copy];
    [self updateTitle];
    [_display flush];
}

- (void) updateSizeLimits {
    if (_toplevel == NULL)
        return;

    union wl_argument args[2] = {{.i = 0}, {.i = 0}};
    if (!(_styleMask & NSWindowStyleMaskResizable)) {
        args[0].i = (int32_t) _frame.size.width;
        args[1].i = (int32_t) _frame.size.height;
    }
    WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_MIN_SIZE, NULL, 0, args);
    WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_MAX_SIZE, NULL, 0, args);
}

- (void) setOpaque: (BOOL) value {
    _isOpaque = value;
}

- (void) setAlphaValue: (CGFloat) value {
    // No client-side opacity on Wayland without an extra protocol.
}

- (void) setHasShadow: (BOOL) value {
    _hasShadow = value;
}

- (CGLContextObj) cglContext {
    return NULL;
}

- (void) addEntriesToDeviceDictionary: (NSDictionary *) entries {
    [_deviceDictionary addEntriesFromDictionary: entries];
}

- (CGSubWindow *) createSubWindowWithFrame: (CGRect) frame {
    // OpenGL subwindows aren't supported yet.
    return nil;
}

#pragma mark - Geometry

- (O2Rect) frame {
    return _frame;
}

- (void) setFrame: (O2Rect) frame {
    frame.size.width = MAX(frame.size.width, 1.0);
    frame.size.height = MAX(frame.size.height, 1.0);

    BOOL sized = !NSEqualSizes(frame.size, _frame.size);
    [self invalidateContextWithNewSize: frame.size];
    _frame = frame;
    if (sized) {
        [self updateSizeLimits];
        [_display flush];
    }
}

- (NSPoint) transformPoint: (CGPoint) surfacePoint {
    return NSMakePoint(surfacePoint.x, _frame.size.height - surfacePoint.y);
}

- (void) setLastKnownCursorPosition: (CGPoint) point {
    _lastMotionPos = point;
}

- (NSPoint) mouseLocationOutsideOfEventStream {
    return _lastMotionPos;
}

#pragma mark - Drawing

- (O2Context *) createCGContextIfNeeded {
    if (_context == nil) {
        O2ColorSpaceRef colorSpace = O2ColorSpaceCreateDeviceRGB();
        O2Surface *surface = [[O2Surface alloc]
                   initWithBytes: NULL
                           width: _frame.size.width
                          height: _frame.size.height
                bitsPerComponent: 8
                     bytesPerRow: 0
                      colorSpace: colorSpace
                      bitmapInfo: kO2ImageAlphaPremultipliedFirst |
                                  kO2BitmapByteOrder32Little];
        O2ColorSpaceRelease(colorSpace);
        _context = [[O2Context_builtin_FT alloc] initWithSurface: surface
                                                         flipped: NO];
        [surface release];
    }
    return _context;
}

- (O2Context *) cgContext {
    return [self createCGContextIfNeeded];
}

- (void) invalidateContextWithNewSize: (NSSize) size {
    if (!NSEqualSizes(_frame.size, size)) {
        _frame.size = size;
        if (![_context resizeWithNewSize: size]) {
            [_context release];
            _context = nil;
            [_delegate platformWindowDidInvalidateCGContext: self];
        }
    }
}

- (void) flushBuffer {
    if (_context == nil)
        return;
    O2ContextFlush(_context);
    _needsPresent = YES;
    [self presentIfPossible];
}

- (struct WaylandBuffer *) bufferWithWidth: (int32_t) width
                                    height: (int32_t) height
                                    format: (uint32_t) format
{
    struct WaylandBuffer *reusable = NULL;

    for (int i = 0; i < 2; i++) {
        struct WaylandBuffer *buffer = &_buffers[i];
        if (buffer->busy)
            continue;
        if (buffer->buffer != NULL && buffer->width == width &&
            buffer->height == height && buffer->format == format)
            return buffer;
        if (reusable == NULL)
            reusable = buffer;
    }
    // Both buffers are still in use: present again when one is released.
    if (reusable == NULL)
        return NULL;

    if (reusable->buffer != NULL)
        sendRequest(reusable->buffer, WP_BUFFER_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    if (reusable->data != NULL)
        munmap(reusable->data, reusable->size);
    memset(reusable, 0, sizeof(*reusable));

    int32_t stride = width * 4;
    size_t size = (size_t) stride * (size_t) height;
    int fd = WaylandCreateAnonymousFile(size);
    if (fd < 0) {
        NSLog(@"Wayland backend: cannot allocate a %dx%d window buffer", width,
              height);
        return NULL;
    }

    void *data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (data == MAP_FAILED) {
        NSLog(@"Wayland backend: cannot map a %dx%d window buffer: %s", width,
              height, strerror(errno));
        close(fd);
        return NULL;
    }

    // libwayland duplicates the descriptor when it marshals the request.
    union wl_argument poolArgs[3] = {{.o = NULL}, {.h = fd}, {.i = (int32_t) size}};
    struct wl_proxy *pool = WaylandCreateObject(_display->_shm, WP_SHM_CREATE_POOL,
                                                &wl_shm_pool_interface, poolArgs,
                                                0, nil);
    close(fd);

    union wl_argument bufferArgs[6] = {{.o = NULL},    {.i = 0},
                                       {.i = width},   {.i = height},
                                       {.i = stride},  {.u = format}};
    struct wl_proxy *proxy = WaylandCreateObject(pool, WP_SHM_POOL_CREATE_BUFFER,
                                                 &wl_buffer_interface, bufferArgs,
                                                 WaylandObjectBuffer, self);
    sendRequest(pool, WP_SHM_POOL_DESTROY, WL_MARSHAL_FLAG_DESTROY);

    reusable->buffer = proxy;
    reusable->data = data;
    reusable->size = size;
    reusable->width = width;
    reusable->height = height;
    reusable->format = format;
    return reusable;
}

// Copies the current content into a shm buffer and commits it, at most once
// per frame callback.
- (void) presentIfPossible {
    if (!_needsPresent || !_mapped || !_configured || _frameCallback != NULL ||
        _context == nil)
        return;

    O2Surface *surface = [_context surface];
    size_t width = O2SurfaceGetWidth(surface);
    size_t height = O2SurfaceGetHeight(surface);
    size_t sourceStride = O2SurfaceGetBytesPerRow(surface);
    const uint8_t *pixels = O2SurfaceGetPixelBytes(surface);
    if (pixels == NULL || width == 0 || height == 0 || sourceStride < width * 4)
        return;

    // Onyx2D's premultiplied, little-endian ARGB is wl_shm's ARGB8888.
    uint32_t format = _isOpaque ? WP_SHM_FORMAT_XRGB8888 : WP_SHM_FORMAT_ARGB8888;
    struct WaylandBuffer *buffer = [self bufferWithWidth: (int32_t) width
                                                  height: (int32_t) height
                                                  format: format];
    if (buffer == NULL)
        return;

    // Both start with the top row.
    for (size_t row = 0; row < height; row++)
        memcpy((uint8_t *) buffer->data + row * width * 4,
               pixels + row * sourceStride, width * 4);

    union wl_argument args[4] = {{.o = (struct wl_object *) buffer->buffer},
                                 {.i = 0},
                                 {.i = 0}};
    WaylandMarshal(_surface, WP_SURFACE_ATTACH, NULL, 0, args);

    args[0].i = 0;
    args[1].i = 0;
    args[2].i = (int32_t) width;
    args[3].i = (int32_t) height;
    WaylandMarshal(_surface,
                   _display->_compositorVersion >= 4 ? WP_SURFACE_DAMAGE_BUFFER
                                                     : WP_SURFACE_DAMAGE,
                   NULL, 0, args);

    args[0].o = NULL;
    _frameCallback = WaylandCreateObject(_surface, WP_SURFACE_FRAME,
                                         &wl_callback_interface, args,
                                         WaylandObjectFrameCallback, self);

    sendRequest(_surface, WP_SURFACE_COMMIT, 0);
    buffer->busy = YES;
    _needsPresent = NO;
    [_display flush];
}

#pragma mark - Events

- (void) handleEvent: (uint32_t) opcode
                kind: (WaylandObjectKind) kind
               proxy: (struct wl_proxy *) proxy
           arguments: (union wl_argument *) args
{
    switch (kind) {
    case WaylandObjectXdgSurface:
        if (opcode == WP_XDG_SURFACE_EV_CONFIGURE)
            [self configure: args[0].u];
        break;

    case WaylandObjectToplevel:
        if (opcode == WP_TOPLEVEL_EV_CONFIGURE) {
            _pendingWidth = args[0].i;
            _pendingHeight = args[1].i;
            _pendingActivated = NO;
            struct wl_array *states = args[2].a;
            uint32_t *state;
            wl_array_for_each (state, states)
                if (*state == WP_TOPLEVEL_STATE_ACTIVATED)
                    _pendingActivated = YES;
        } else if (opcode == WP_TOPLEVEL_EV_CLOSE) {
            [self closeRequested];
        }
        break;

    case WaylandObjectFrameCallback:
        if (proxy == _frameCallback) {
            WL.wl_proxy_destroy(_frameCallback);
            _frameCallback = NULL;
            [self presentIfPossible];
        }
        break;

    case WaylandObjectBuffer:
        for (int i = 0; i < 2; i++)
            if (_buffers[i].buffer == proxy)
                _buffers[i].busy = NO;
        [self presentIfPossible];
        break;

    default:
        break;
    }
}

// xdg_surface.configure ends a configure sequence: apply the toplevel state.
- (void) configure: (uint32_t) serial {
    union wl_argument args[1] = {{.u = serial}};
    WaylandMarshal(_xdgSurface, WP_XDG_SURFACE_ACK_CONFIGURE, NULL, 0, args);

    BOOL firstConfigure = !_configured;
    _configured = YES;

    BOOL sized = NO;
    if (_pendingWidth > 0 && _pendingHeight > 0 &&
        (_pendingWidth != (int32_t) _frame.size.width ||
         _pendingHeight != (int32_t) _frame.size.height))
    {
        // Keep the top edge where it was, as the compositor does on screen.
        O2Rect frame = _frame;
        frame.origin.y += frame.size.height - _pendingHeight;
        frame.size = NSMakeSize(_pendingWidth, _pendingHeight);
        [self invalidateContextWithNewSize: frame.size];
        _frame = frame;
        sized = YES;
    }

    BOOL activationChanged = _pendingActivated != _activated;
    BOOL activated = _pendingActivated;
    _activated = activated;

    if (firstConfigure || sized || activationChanged) {
        [_display performAfterDispatch: ^{
          NSWindow *delegate = self->_delegate;
          if (delegate == nil)
              return;
          if (sized)
              [delegate platformWindow: self
                          frameChanged: self->_frame
                               didSize: YES];
          if (firstConfigure || sized)
              [delegate platformWindowExposed: self
                                       inRect: NSMakeRect(0, 0,
                                                          self->_frame.size.width,
                                                          self->_frame.size.height)];
          if (activationChanged && activated) {
              [self->_display windowActivated: self];
              if ([delegate attachedSheet] != nil)
                  [[delegate attachedSheet] makeKeyAndOrderFront: delegate];
              else
                  [delegate platformWindowActivated: self displayIfNeeded: YES];
          } else if (activationChanged) {
              [delegate platformWindowDeactivated: self
                          checkForAppDeactivation: NO];
          }
        }];
    }

    [self presentIfPossible];
}

- (void) closeRequested {
    [[NSRunLoop currentRunLoop]
            cancelPerformSelector: @selector(platformWindowWillClose:)
                           target: _delegate
                         argument: self];
    [[NSRunLoop currentRunLoop]
            performSelector: @selector(platformWindowWillClose:)
                     target: _delegate
                   argument: self
                      order: 0
                      modes: @[
                          NSDefaultRunLoopMode, NSModalPanelRunLoopMode,
                          NSEventTrackingRunLoopMode
                      ]];
}

@end
