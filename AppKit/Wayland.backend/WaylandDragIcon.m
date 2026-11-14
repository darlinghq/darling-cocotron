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
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import <AppKit/NSImage.h>
#include <math.h>

@implementation WaylandDragIcon
- (id) initWithImage: (NSImage *) image display: (WaylandDisplay *) display
              scale: (int32_t) scale offset: (NSPoint) offset {
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
    @try {
        _image = [[WaylandCursor alloc] initWithImage: image hotSpot: NSZeroPoint];
        if (_image == nil || ![self prepareScale: scale]) { [self release]; return nil; }
        union wl_argument args[1] = {{.o = NULL}};
        _surface = WaylandCreateObject(display->_compositor, WP_COMPOSITOR_CREATE_SURFACE,
                &wl_surface_interface, args, WaylandObjectSurface, self);
    } @catch (id exception) { [self release]; @throw; }
    return self;
}
- (BOOL) prepareScale: (int32_t) scale {
    if (_rendering) { _scaleDirty = YES; return NO; }
    _rendering = YES;
    @try { return [self renderScale: scale]; }
    @finally {
        _rendering = NO;
        if (_scaleDirty) { _scaleDirty = NO; [self scheduleScaleUpdate]; }
    }
}
- (BOOL) renderScale: (int32_t) scale {
    if (_display->_compositorVersion < 3) scale = 1;
    NSSize size = [_image size];
    if (scale < 1 || size.width * size.height * scale * scale > 4 * 1024 * 1024) return NO;
    WaylandDisplay *display = _display;
    NSData *pixels = [_image pixelsForScale: scale];
    // Image drawing can cancel this drag through application callbacks.
    if (!_display || _display != display || (_shown && !_surface)) return NO;
    struct wl_proxy *buffer = [_display newARGBBuffer: pixels
            pixelSize: NSMakeSize(size.width * scale, size.height * scale)];
    if (!buffer) return NO;
    struct wl_proxy *old = _buffer;
    _buffer = buffer; _scale = scale;
    if (_shown) [self show];
    if (old) WaylandMarshal(old, WP_BUFFER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    return YES;
}
- (struct wl_proxy *) surface { return _surface; }
- (void) show {
    if (!_display || !_surface || !_buffer) return;
    _shown = YES;
    if (_display->_compositorVersion >= 3) {
        union wl_argument scale[1] = {{.i = _scale}};
        WaylandMarshal(_surface, WP_SURFACE_SET_BUFFER_SCALE, NULL, 0, scale);
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
- (void) updateScale {
    if (!_display || !_shown) return;
    int32_t scale = 1;
    for (NSValue *output in _outputs)
        scale = MAX(scale, [_display scaleForOutput: [output pointerValue]]);
    if (scale != _scale) [self prepareScale: scale];
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
    if (_surface) WaylandMarshal(_surface, WP_SURFACE_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    if (_buffer) WaylandMarshal(_buffer, WP_BUFFER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    _surface = _buffer = NULL;
    WaylandDisplay *display = _display; _display = nil; [display release];
}
- (void) dealloc {
    [self invalidate]; [_image release]; [_outputs release]; [super dealloc];
}
@end
