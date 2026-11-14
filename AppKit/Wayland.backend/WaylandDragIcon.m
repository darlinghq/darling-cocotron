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

#import "WaylandDragIcon.h"
#import "WaylandCursor.h"
#import "WaylandScale.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import <AppKit/NSImage.h>
#include <math.h>

@implementation WaylandDragIcon
- (id) initWithImage: (NSImage *) image display: (WaylandDisplay *) display
              scale120: (uint32_t) scale120 fallbackScale: (int32_t) fallbackScale offset: (NSPoint) offset {
    if ((self = [super init]) == nil) return nil;
    _display = [display retain];
    NSSize size = [image size];
    // Bound raster allocation before invoking any image drawing callbacks.
    if (!isfinite(size.width) || !isfinite(size.height) || size.width < 1 || size.height < 1 ||
        ceil(size.width) * ceil(size.height) > 4 * 1024 * 1024 ||
        !isfinite(offset.x) || !isfinite(offset.y) ||
        fabs(offset.x) > INT32_MAX || fabs(offset.y) > INT32_MAX) {
        [self release]; return nil;
    }
    _offset = NSMakePoint(floor(offset.x), floor(offset.y));
    _outputs = [NSMutableSet new];
    _initialScale120 = scale120; _initialBufferScale = fallbackScale;
    @try {
        union wl_argument args[1] = {{.o = NULL}};
        _surface = WaylandCreateObject(display->_compositor, WP_COMPOSITOR_CREATE_SURFACE,
                &wl_surface_interface, args, WaylandObjectSurface, self);
        _fractionalScale = [display newFractionalScaleForSurface: _surface owner: (id)self];
        if (_fractionalScale) {
            union wl_argument viewport[] = {{.o = NULL}, {.o = (struct wl_object *)_surface}};
            _viewport = WaylandCreateObject(display->_viewporter, WP_VIEWPORTER_GET_VIEWPORT,
                &wp_viewport_interface, viewport, 0, nil);
        }
        // WaylandCursor eagerly draws at 1x. Refuse an already over-cap target
        // scale before that first application callback as well as before retries.
        int32_t width, height;
        uint32_t effective = [self effectiveScale120];
        if (!WaylandScaleExtent((int32_t)ceil(size.width), effective, 4 * 1024 * 1024, &width) ||
            !WaylandScaleExtent((int32_t)ceil(size.height), effective, 4 * 1024 * 1024, &height) ||
            (uint64_t)width * height > 4 * 1024 * 1024) { [self release]; return nil; }
        _image = [[WaylandCursor alloc] initWithImage: image hotSpot: NSZeroPoint];
        if (_image == nil) {
            [self release]; return nil;
        }
        // If the first rasterization cannot produce a buffer, keep the valid
        // icon surface and request a bounded asynchronous retry; show() also
        // retries when no buffer is available.
        if (![self prepareScale120: [self effectiveScale120]]) [self scheduleScaleUpdate];
    } @catch (id exception) { [self release]; @throw; }
    return self;
}
- (BOOL) prepareScale120: (uint32_t) scale120 {
    if (_rendering) { _scaleDirty = YES; return NO; }
    _rendering = YES;
    @try { return [self renderScale120: scale120]; }
    @finally {
        _rendering = NO;
        if (_scaleDirty) { _scaleDirty = NO; [self scheduleScaleUpdate]; }
    }
}
- (BOOL) renderScale120: (uint32_t) scale120 {
    NSSize pixelsSize = [_image pixelSizeForScale120: scale120];
    // Check the rounded allocation cap before invoking application image code.
    if (pixelsSize.width < 1 || pixelsSize.height < 1 || pixelsSize.width * pixelsSize.height > 4 * 1024 * 1024) return NO;
    WaylandDisplay *display = _display;
    NSData *pixels = [_image pixelsForScale120: scale120];
    // Image drawing can cancel this drag through application callbacks.
    if (!_display || _display != display || !_surface || _scaleDirty || scale120 != [self effectiveScale120]) return NO;
    struct wl_proxy *buffer = [_display newARGBBuffer: pixels
            pixelSize: pixelsSize];
    if (!buffer) return NO;
    struct wl_proxy *old = _buffer;
    _buffer = buffer; _scale120 = scale120;
    if (_shown) [self show];
    if (old) WaylandMarshal(old, WP_BUFFER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    return YES;
}
- (struct wl_proxy *) surface { return _surface; }
- (void) show {
    if (!_display || !_surface) return;
    _shown = YES;
    if (!_buffer) { [self scheduleScaleUpdate]; return; }
    if (_display->_compositorVersion >= 3) {
        union wl_argument scale[1] = {{.i = _fractionalScale ? 1 : (int32_t)(_scale120 / 120)}};
        WaylandMarshal(_surface, WP_SURFACE_SET_BUFFER_SCALE, NULL, 0, scale);
    }
    if (_viewport) {
        NSSize size = [_image size];
        union wl_argument destination[] = {{.i = (int32_t)size.width}, {.i = (int32_t)size.height}};
        WaylandMarshal(_viewport, WP_VIEWPORT_SET_DESTINATION, NULL, 0, destination);
    }
    // Backend binds compositor<=4: attach carries a relative content offset.
    // Apply it only once; repeating it on scale changes would move the icon.
    union wl_argument attach[3] = {{.o = (struct wl_object *) _buffer},
            {.i = _positioned ? 0 : (int32_t) _offset.x},
            {.i = _positioned ? 0 : (int32_t) _offset.y}};
    WaylandMarshal(_surface, WP_SURFACE_ATTACH, NULL, 0, attach);
    NSSize size = [_image size];
    union wl_argument damage[4] = {{.i = 0}, {.i = 0},
            {.i = (int32_t) size.width}, {.i = (int32_t) size.height}};
    WaylandMarshal(_surface, WP_SURFACE_DAMAGE, NULL, 0, damage);
    WaylandMarshal(_surface, WP_SURFACE_COMMIT, NULL, 0, NULL);
    _positioned = YES;
}
- (uint32_t) effectiveScale120 {
    if (_fractionalScale && _preferredScale120) return _preferredScale120;
    if ([_outputs count] == 0) return _fractionalScale ? _initialScale120
        : (uint32_t)MIN((uint64_t)(_display->_compositorVersion >= 3 ? MAX(1, _initialBufferScale) : 1) * 120, UINT32_MAX);
    int32_t scale = 1;
    if (_display->_compositorVersion >= 3)
        for (NSValue *output in _outputs) scale = MAX(scale, [_display scaleForOutput: [output pointerValue]]);
    return (uint32_t)MIN((uint64_t)scale * 120, UINT32_MAX);
}
- (void) preferredScaleChanged: (uint32_t) scale120 {
    if (!_fractionalScale || !scale120 || scale120 == _preferredScale120) return;
    _preferredScale120 = scale120;
    [self scheduleScaleUpdate];
}
- (void) updateScale {
    if (!_display || !_shown) return;
    uint32_t scale120 = [self effectiveScale120];
    if (scale120 != _scale120 || !_buffer) [self prepareScale120: scale120];
}
- (void) scheduleScaleUpdate {
    if (!_display) return;
    if (_rendering) { _scaleDirty = YES; return; }
    if (_scaleQueued) return;
    _scaleQueued = YES;
    [_display performAfterDispatch: ^{ _scaleQueued = NO; [self updateScale]; }];
}
- (void) outputRemoved: (struct wl_proxy *) output {
    [_outputs removeObject: [NSValue valueWithPointer: output]];
    [self scheduleScaleUpdate];
}
- (void) handleEvent: (uint32_t) opcode kind: (WaylandObjectKind) kind
              proxy: (struct wl_proxy *) proxy arguments: (union wl_argument *) args {
    if (!_display || proxy != _surface) return;
    if (opcode != WP_SURFACE_EV_ENTER && opcode != WP_SURFACE_EV_LEAVE) return;
    NSValue *output = [NSValue valueWithPointer: args[0].o];
    if (opcode == WP_SURFACE_EV_ENTER) [_outputs addObject: output];
    else [_outputs removeObject: output];
    // Rasterization can call application image code; never do it in native dispatch.
    [self scheduleScaleUpdate];
}
- (void) invalidate {
    if (_fractionalScale) WaylandMarshal(_fractionalScale, WP_FRACTIONAL_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    if (_viewport) WaylandMarshal(_viewport, WP_VIEWPORT_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    _fractionalScale = _viewport = NULL;
    if (_surface) WaylandMarshal(_surface, WP_SURFACE_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    if (_buffer) WaylandMarshal(_buffer, WP_BUFFER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    _surface = _buffer = NULL;
    WaylandDisplay *display = _display; _display = nil; [display release];
}
- (void) dealloc {
    [self invalidate]; [_image release]; [_outputs release]; [super dealloc];
}
@end
