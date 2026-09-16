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
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSStringDrawing.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSRunLoop.h>
#import <Onyx2D/O2Context_builtin_FT.h>
#import <Onyx2D/O2Surface.h>
#include <errno.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <limits.h>
#include <math.h>

// NSView replaces the user CTM whenever it locks focus. Keep scaling in the
// device transform, alongside Onyx2D's bottom-left to top-left conversion.
@interface WaylandDrawingContext : O2Context_builtin_FT
- (id) initWithSurface: (O2Surface *) surface scale: (int32_t) scale border: (CGFloat) border;
@end

@implementation WaylandDrawingContext
- (id) initWithSurface: (O2Surface *) surface scale: (int32_t) scale border: (CGFloat) border {
    if ((self = [super initWithSurface: surface flipped: NO]) != nil) {
        _userToDeviceTransform = O2AffineTransformMake(scale, 0, 0, -scale, border * scale,
                                                       O2SurfaceGetHeight(surface) - border * scale);
        O2ContextSetCTM(self, O2AffineTransformIdentity);
    }
    return self;
}
@end

@implementation WaylandWindow

static const CGFloat WaylandTitleHeight = 28;
static const CGFloat WaylandBorder = 6;

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
    _surfaceOutputs = [NSMutableSet new];
    _bufferScale = 1;
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
    [_surfaceOutputs release];
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

- (BOOL) isPopup { return _popup != NULL; }
- (WaylandWindow *) popupParent { return _popupParent; }
- (uint32_t) popupGrabSerial { return _popupGrabSerial; }
- (struct wl_proxy *) xdgSurface { return _xdgSurface; }

#pragma mark - Mapping

- (void) ensureMapped {
    if (_mapped || _display == nil)
        return;
    _surfaceGeneration++;
    _configureUpdatePending = NO;
    BOOL forceClient = getenv("DARLING_WAYLAND_DECORATIONS") != NULL &&
            strcmp(getenv("DARLING_WAYLAND_DECORATIONS"), "client") == 0;
    _pendingClientDecorated = _display->_decorationManager == NULL || forceClient;

    union wl_argument args[4];

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

    BOOL menu = [_delegate isKindOfClass: NSClassFromString(@"NSMenuWindow")] ||
                [_delegate isKindOfClass: NSClassFromString(@"NSPopUpWindow")];
    WaylandWindow *parent = menu ? [_display popupParentForWindow: self] : nil;
    if (parent != nil && parent->_configured) {
        _popupParent = [parent retain];
        [self createPopupRole];
    } else {
        args[0].o = NULL;
        _toplevel = WaylandCreateObject(_xdgSurface, WP_XDG_SURFACE_GET_TOPLEVEL,
                                    &xdg_toplevel_interface, args,
                                    WaylandObjectToplevel, self);

        [self updateTitle];
        args[0].s = [[[NSProcessInfo processInfo] processName] UTF8String];
        if (args[0].s != NULL)
            WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_APP_ID, NULL, 0, args);
        [self updateSizeLimits];

        if (_display->_decorationManager != NULL && (_styleMask & NSWindowStyleMaskTitled)) {
            args[0].o = NULL;
            args[1].o = (struct wl_object *) _toplevel;
            _decoration = WaylandCreateObject(
                    _display->_decorationManager,
                    WP_DECORATION_MANAGER_GET_TOPLEVEL_DECORATION,
                    &zxdg_toplevel_decoration_v1_interface, args,
                    WaylandObjectDecoration, self);
            args[0].u = forceClient ? WP_TOPLEVEL_DECORATION_MODE_CLIENT_SIDE
                                     : WP_TOPLEVEL_DECORATION_MODE_SERVER_SIDE;
            WaylandMarshal(_decoration, WP_TOPLEVEL_DECORATION_SET_MODE, NULL, 0, args);
        }
    }

    _pendingWidth = _pendingHeight = 0;
    _pendingActivated = NO;
    // The initial commit has no buffer; content follows the first configure.
    sendRequest(_surface, WP_SURFACE_COMMIT, 0);
    _mapped = YES;
    _configured = NO;
    _needsPresent = _context != nil;
    [_display flush];
}

- (struct wl_proxy *) newPopupPositioner {
    union wl_argument args[4] = {{.o = NULL}};
    struct wl_proxy *positioner = WaylandCreateObject(_display->_wmBase,
            WP_WM_BASE_CREATE_POSITIONER, &xdg_positioner_interface, args, 0, nil);
    args[0].i = MAX(1, (int32_t) ceil(_frame.size.width));
    args[1].i = MAX(1, (int32_t) ceil(_frame.size.height));
    WaylandMarshal(positioner, WP_POSITIONER_SET_SIZE, NULL, 0, args);
    NSRect parent = [_popupParent frame];
    NSPoint offset = [_popupParent contentOffset];
    int32_t x = (int32_t) floor(_frame.origin.x - parent.origin.x + offset.x);
    int32_t y = (int32_t) floor(NSMaxY(parent) - NSMaxY(_frame) + offset.y);
    // A submenu can start beyond its parent edge. Keep the anchor inside the
    // parent geometry, expressing the remaining displacement as an offset.
    int32_t anchorX = MAX(0, MIN(x, (int32_t) ceil(parent.size.width + 2 * offset.x) - 1));
    int32_t anchorY = MAX(0, MIN(y, (int32_t) ceil(parent.size.height + offset.x + offset.y) - 1));
    args[0].i = anchorX;
    args[1].i = anchorY;
    args[2].i = args[3].i = 1;
    WaylandMarshal(positioner, WP_POSITIONER_SET_ANCHOR_RECT, NULL, 0, args);
    args[0].i = x - anchorX;
    args[1].i = y - anchorY;
    WaylandMarshal(positioner, WP_POSITIONER_SET_OFFSET, NULL, 0, args);
    args[0].u = WP_POSITIONER_ANCHOR_TOP_LEFT;
    WaylandMarshal(positioner, WP_POSITIONER_SET_ANCHOR, NULL, 0, args);
    args[0].u = WP_POSITIONER_GRAVITY_BOTTOM_RIGHT;
    WaylandMarshal(positioner, WP_POSITIONER_SET_GRAVITY, NULL, 0, args);
    args[0].u = WP_POSITIONER_SLIDE_X | WP_POSITIONER_SLIDE_Y |
                WP_POSITIONER_FLIP_X | WP_POSITIONER_FLIP_Y;
    WaylandMarshal(positioner, WP_POSITIONER_SET_CONSTRAINT_ADJUSTMENT, NULL, 0, args);
    return positioner;
}

- (void) createPopupRole {
    struct wl_proxy *positioner = [self newPopupPositioner];
    union wl_argument args[3];
    args[0].o = NULL;
    args[1].o = (struct wl_object *) [_popupParent xdgSurface];
    args[2].o = (struct wl_object *) positioner;
    _popup = WaylandCreateObject(_xdgSurface, WP_XDG_SURFACE_GET_POPUP,
            &xdg_popup_interface, args, WaylandObjectPopup, self);
    sendRequest(positioner, WP_POSITIONER_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    _popupGrabSerial = [_display popupGrabSerialForParent: _popupParent];
    if (_popupGrabSerial != 0 && [_display seat] != NULL) {
        args[0].o = (struct wl_object *) [_display seat];
        args[1].u = _popupGrabSerial;
        WaylandMarshal(_popup, WP_POPUP_GRAB, NULL, 0, args);
    }
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

    [_display unmapPopupsForParent: self];

    if (_frameCallback != NULL) {
        WL.wl_proxy_destroy(_frameCallback);
        _frameCallback = NULL;
    }
    if (_decoration != NULL) {
        sendRequest(_decoration, WP_TOPLEVEL_DECORATION_DESTROY,
                    WL_MARSHAL_FLAG_DESTROY);
        _decoration = NULL;
    }
    if (_popup != NULL) {
        sendRequest(_popup, WP_POPUP_DESTROY, WL_MARSHAL_FLAG_DESTROY);
        _popup = NULL;
        [_popupParent release];
        _popupParent = nil;
        _popupGrabSerial = 0;
    }
    if (_toplevel != NULL)
        sendRequest(_toplevel, WP_TOPLEVEL_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    sendRequest(_xdgSurface, WP_XDG_SURFACE_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    sendRequest(_surface, WP_SURFACE_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    _toplevel = _xdgSurface = _surface = NULL;
    [_surfaceOutputs removeAllObjects];
    [self destroyBuffers];

    _mapped = NO;
    _configureUpdatePending = NO;
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
    if (_clientDecorated)
        [self flushBuffer];
    [_display flush];
}

- (void) updateSizeLimits {
    if (_toplevel == NULL)
        return;

    union wl_argument args[2] = {{.i = 0}, {.i = 0}};
    if (!(_styleMask & NSWindowStyleMaskResizable)) {
        args[0].i = (int32_t) _frame.size.width + (_clientDecorated ? 2 * WaylandBorder : 0);
        args[1].i = (int32_t) _frame.size.height + (_clientDecorated ? 2 * WaylandBorder + WaylandTitleHeight : 0);
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

    BOOL moved = !NSEqualPoints(frame.origin, _frame.origin);
    BOOL sized = !NSEqualSizes(frame.size, _frame.size);
    [self invalidateContextWithNewSize: frame.size];
    _frame = frame;
    if (_popup != NULL && (moved || sized) && WL.wl_proxy_get_version(_popup) >= 3) {
        struct wl_proxy *positioner = [self newPopupPositioner];
        union wl_argument args[2] = {{.o = (struct wl_object *) positioner},
                                     {.u = ++_repositionToken}};
        WaylandMarshal(_popup, WP_POPUP_REPOSITION, NULL, 0, args);
        sendRequest(positioner, WP_POSITIONER_DESTROY, WL_MARSHAL_FLAG_DESTROY);
        [_display flush];
    }
    if (sized) {
        [self updateSizeLimits];
        [_display flush];
    }
}

- (NSPoint) transformPoint: (CGPoint) surfacePoint {
    NSPoint offset = [self contentOffset];
    return NSMakePoint(surfacePoint.x - offset.x, _frame.size.height - surfacePoint.y + offset.y);
}

- (NSPoint) contentOffset {
    return _clientDecorated ? NSMakePoint(WaylandBorder, WaylandBorder + WaylandTitleHeight) : NSZeroPoint;
}

- (BOOL) isDecorationPoint: (CGPoint) point {
    if (!_clientDecorated)
        return NO;
    NSPoint offset = [self contentOffset];
    return point.x < offset.x || point.y < offset.y ||
           point.x >= offset.x + _frame.size.width || point.y >= offset.y + _frame.size.height;
}

- (BOOL) decorationButton: (uint32_t) button pressed: (BOOL) pressed
                   serial: (uint32_t) serial atPoint: (CGPoint) point
{
    if (![self isDecorationPoint: point])
        return NO;
    if (!pressed || button != WP_BTN_LEFT || _toplevel == NULL || [_display seat] == NULL)
        return YES;
    CGFloat width = _frame.size.width + 2 * WaylandBorder;
    CGFloat height = _frame.size.height + 2 * WaylandBorder + WaylandTitleHeight;
    uint32_t edge = 0;
    if (point.y < WaylandBorder) edge |= 1;
    if (point.y >= height - WaylandBorder) edge |= 2;
    if (point.x < WaylandBorder) edge |= 4;
    if (point.x >= width - WaylandBorder) edge |= 8;
    union wl_argument args[3] = {{.o = (struct wl_object *) [_display seat]},
                                 {.u = serial}, {.u = edge}};
    if (edge != 0) {
        if (_styleMask & NSWindowStyleMaskResizable)
            WaylandMarshal(_toplevel, WP_TOPLEVEL_RESIZE, NULL, 0, args);
    } else if (point.y < WaylandBorder + WaylandTitleHeight) {
        CGFloat x = point.x - WaylandBorder;
        if (x >= 4 && x < 22 && (_styleMask & NSWindowStyleMaskClosable))
            [self closeRequested];
        else if (x >= 24 && x < 42 && (_styleMask & NSWindowStyleMaskMiniaturizable))
            [self miniaturize];
        else if (x >= 44 && x < 62 && (_styleMask & NSWindowStyleMaskResizable))
            sendRequest(_toplevel, _maximized ? WP_TOPLEVEL_UNSET_MAXIMIZED : WP_TOPLEVEL_SET_MAXIMIZED, 0);
        else
            WaylandMarshal(_toplevel, WP_TOPLEVEL_MOVE, NULL, 0, args);
    }
    [_display flush];
    return YES;
}

- (void) setLastKnownCursorPosition: (CGPoint) point {
    _lastMotionPos = point;
}

- (NSPoint) mouseLocationOutsideOfEventStream {
    return _lastMotionPos;
}

#pragma mark - Drawing

- (int32_t) bufferScale { return _bufferScale; }

- (void) outputRemoved: (struct wl_proxy *) output {
    [_surfaceOutputs removeObject: [NSValue valueWithPointer: output]];
    [self scheduleScaleUpdate];
}

- (void) scheduleScaleUpdate {
    if (_scaleUpdatePending)
        return;
    _scaleUpdatePending = YES;
    [_display performAfterDispatch: ^{
        self->_scaleUpdatePending = NO;
        if (!self->_mapped || self->_delegate == nil)
            return;
        int32_t scale = 1;
        if (self->_display->_compositorVersion >= 3)
            for (NSValue *output in self->_surfaceOutputs)
                scale = MAX(scale, [self->_display scaleForOutput: [output pointerValue]]);
        if (scale == self->_bufferScale)
            return;
        self->_bufferScale = scale;
        [self->_context release];
        self->_context = nil;
        self->_needsPresent = NO;
        [self->_delegate platformWindowDidInvalidateCGContext: self];
        [self->_delegate platformWindowExposed: self
                                      inRect: NSMakeRect(0, 0, self->_frame.size.width,
                                                         self->_frame.size.height)];
        // Expose only posts a notification in Cocotron. A new backing surface
        // needs a full redraw, even when no view has invalidated its contents.
        [self->_delegate display];
        [self->_display windowScaleChanged: self];
    }];
}

- (O2Context *) createCGContextIfNeeded {
    if (_context == nil) {
        double width = (ceil(_frame.size.width) + (_clientDecorated ? 2 * WaylandBorder : 0)) * _bufferScale;
        double height = (ceil(_frame.size.height) + (_clientDecorated ? 2 * WaylandBorder + WaylandTitleHeight : 0)) * _bufferScale;
        if (!isfinite(width) || !isfinite(height) || width < 1 || height < 1 ||
            width > INT32_MAX / 4 || height > INT32_MAX / (width * 4)) {
            NSLog(@"Wayland backend: window buffer dimensions exceed wl_shm limits");
            return nil;
        }
        O2ColorSpaceRef colorSpace = O2ColorSpaceCreateDeviceRGB();
        O2Surface *surface = [[O2Surface alloc]
                   initWithBytes: NULL
                           width: width
                          height: height
                bitsPerComponent: 8
                     bytesPerRow: 0
                      colorSpace: colorSpace
                      bitmapInfo: kO2ImageAlphaPremultipliedFirst |
                                  kO2BitmapByteOrder32Little];
        O2ColorSpaceRelease(colorSpace);
        _context = [[WaylandDrawingContext alloc] initWithSurface: surface scale: _bufferScale
                                                          border: _clientDecorated ? WaylandBorder : 0];
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
        [_context release];
        _context = nil;
        [_delegate platformWindowDidInvalidateCGContext: self];
    }
}

- (void) drawDecorations {
    if (!_clientDecorated || _context == nil)
        return;
    [NSGraphicsContext saveGraphicsState];
    O2ContextSaveGState(_context);
    @try {
        [NSGraphicsContext setCurrentContext:
            [NSGraphicsContext graphicsContextWithGraphicsPort: (CGContextRef) _context flipped: NO]];
        O2ContextResetClip(_context);
        O2ContextSetCTM(_context, O2AffineTransformIdentity);
        CGFloat w = _frame.size.width, h = _frame.size.height;
        [[NSColor colorWithCalibratedWhite: _activated ? 0.82 : 0.92 alpha: 1] set];
        NSRectFill(NSMakeRect(-WaylandBorder, h, w + 2 * WaylandBorder,
                              WaylandTitleHeight + WaylandBorder));
        NSRectFill(NSMakeRect(-WaylandBorder, -WaylandBorder, w + 2 * WaylandBorder, WaylandBorder));
        NSRectFill(NSMakeRect(-WaylandBorder, 0, WaylandBorder, h));
        NSRectFill(NSMakeRect(w, 0, WaylandBorder, h));
        NSUInteger masks[] = {NSWindowStyleMaskClosable, NSWindowStyleMaskMiniaturizable,
                               NSWindowStyleMaskResizable};
        NSColor *colors[] = {[NSColor redColor], [NSColor yellowColor], [NSColor greenColor]};
        for (int i = 0; i < 3; ++i) {
            [(_styleMask & masks[i] ? colors[i] : [NSColor grayColor]) set];
            [[NSBezierPath bezierPathWithOvalInRect: NSMakeRect(7 + i * 20, h + 8, 12, 12)] fill];
        }
        [_title drawInRect: NSMakeRect(76, h + 6, MAX(0, w - 90), 18)
           withAttributes: @{NSFontAttributeName: [NSFont systemFontOfSize: 12],
                             NSForegroundColorAttributeName: [NSColor blackColor]}];
    } @finally {
        O2ContextRestoreGState(_context);
        [NSGraphicsContext restoreGraphicsState];
    }
}

- (void) flushBuffer {
    if (_context == nil)
        return;
    [self drawDecorations];
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

    if (width < 1 || height < 1 || width > INT32_MAX / 4 ||
        height > INT32_MAX / (width * 4))
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
    if (!_needsPresent || !_mapped || !_configured || _configureUpdatePending || _frameCallback != NULL ||
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
    if (_display->_compositorVersion >= 3) {
        union wl_argument scale[1] = {{.i = _bufferScale}};
        WaylandMarshal(_surface, WP_SURFACE_SET_BUFFER_SCALE, NULL, 0, scale);
    }
    WaylandMarshal(_surface, WP_SURFACE_ATTACH, NULL, 0, args);

    args[0].i = 0;
    args[1].i = 0;
    args[2].i = (int32_t) width / (_display->_compositorVersion >= 4 ? 1 : _bufferScale);
    args[3].i = (int32_t) height / (_display->_compositorVersion >= 4 ? 1 : _bufferScale);
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
    case WaylandObjectSurface:
        if (opcode == WP_SURFACE_EV_ENTER) {
            [_surfaceOutputs addObject: [NSValue valueWithPointer: args[0].o]];
            [self scheduleScaleUpdate];
        } else if (opcode == WP_SURFACE_EV_LEAVE) {
            [self outputRemoved: (struct wl_proxy *) args[0].o];
        }
        break;
    case WaylandObjectXdgSurface:
        if (opcode == WP_XDG_SURFACE_EV_CONFIGURE)
            [self configure: args[0].u];
        break;

    case WaylandObjectToplevel:
        if (opcode == WP_TOPLEVEL_EV_CONFIGURE) {
            _pendingWidth = args[0].i;
            _pendingHeight = args[1].i;
            _pendingActivated = NO;
            _pendingMaximized = NO;
            struct wl_array *states = args[2].a;
            uint32_t *state;
            wl_array_for_each (state, states) {
                if (*state == WP_TOPLEVEL_STATE_ACTIVATED)
                    _pendingActivated = YES;
                if (*state == WP_TOPLEVEL_STATE_MAXIMIZED)
                    _pendingMaximized = YES;
            }
        } else if (opcode == WP_TOPLEVEL_EV_CLOSE) {
            [self closeRequested];
        }
        break;

    case WaylandObjectDecoration:
        if (opcode == WP_TOPLEVEL_DECORATION_EV_CONFIGURE)
            _pendingClientDecorated = args[0].u != WP_TOPLEVEL_DECORATION_MODE_SERVER_SIDE;
        break;

    case WaylandObjectPopup:
        if (opcode == WP_POPUP_EV_CONFIGURE) {
            _pendingPopupX = args[0].i;
            _pendingPopupY = args[1].i;
            _pendingWidth = args[2].i;
            _pendingHeight = args[3].i;
        } else if (opcode == WP_POPUP_EV_DONE) {
            NSUInteger generation = _surfaceGeneration;
            [_display performAfterDispatch: ^{
                if (self->_mapped && self->_surfaceGeneration == generation)
                    [self->_display cancelPopupMenus];
            }];
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

    if (_configureUpdatePending)
        return;
    _configureUpdatePending = YES;
    NSUInteger generation = _surfaceGeneration;
    [_display performAfterDispatch: ^{
        if (!self->_mapped || self->_surfaceGeneration != generation)
            return;
        self->_configureUpdatePending = NO;
        [self applyConfigure];
    }];
}

- (void) applyConfigure {
    BOOL clientDecorated = _toplevel != NULL && (_styleMask & NSWindowStyleMaskTitled) && _pendingClientDecorated;
    BOOL decorationChanged = clientDecorated != _clientDecorated;
    _clientDecorated = clientDecorated;
    _maximized = _pendingMaximized;
    if (decorationChanged) {
        [_context release];
        _context = nil;
        _needsPresent = NO;
        [_delegate platformWindowDidInvalidateCGContext: self];
        [self updateSizeLimits];
    }
    int32_t width = _pendingWidth - (_clientDecorated ? 2 * WaylandBorder : 0);
    int32_t height = _pendingHeight - (_clientDecorated ? 2 * WaylandBorder + WaylandTitleHeight : 0);
    BOOL firstConfigure = !_configured;
    _configured = YES;

    BOOL sized = NO;
    BOOL moved = NO;
    if (_popupParent != nil) {
        NSRect parent = [_popupParent frame];
        NSPoint offset = [_popupParent contentOffset];
        NSPoint origin = NSMakePoint(parent.origin.x + _pendingPopupX - offset.x,
                NSMaxY(parent) - _pendingPopupY + offset.y - _pendingHeight);
        moved = !NSEqualPoints(_frame.origin, origin);
        _frame.origin = origin;
    }
    if (width > 0 && height > 0 &&
        (width != (int32_t) _frame.size.width ||
         height != (int32_t) _frame.size.height))
    {
        // Keep the top edge where it was, as the compositor does on screen.
        O2Rect frame = _frame;
        if (_popupParent == nil)
            frame.origin.y += frame.size.height - height;
        frame.size = NSMakeSize(width, height);
        [self invalidateContextWithNewSize: frame.size];
        _frame = frame;
        sized = YES;
    }

    BOOL activationChanged = _pendingActivated != _activated;
    BOOL activated = _pendingActivated;
    _activated = activated;

    if (firstConfigure || sized || moved || activationChanged || decorationChanged) {
        [_display performAfterDispatch: ^{
          NSWindow *delegate = self->_delegate;
          if (delegate == nil)
              return;
          if (sized || moved)
              [delegate platformWindow: self
                          frameChanged: self->_frame
                               didSize: sized];
          if (firstConfigure || sized)
              [delegate platformWindowExposed: self
                                       inRect: NSMakeRect(0, 0,
                                                          self->_frame.size.width,
                                                          self->_frame.size.height)];
          if (firstConfigure || sized || decorationChanged)
              [delegate display];
          else if (activationChanged)
              [self flushBuffer];
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
