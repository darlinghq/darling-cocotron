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

#import "WaylandSubWindow.h"
#import "WaylandWindow.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#include <math.h>

static void request(struct wl_proxy *proxy, uint32_t opcode, uint32_t flags) {
    union wl_argument args[] = {{.o = NULL}};
    WaylandMarshal(proxy, opcode, NULL, flags, args);
}
static BOOL validFrame(CGRect frame) {
    return isfinite(frame.origin.x) && isfinite(frame.origin.y) &&
        fabs(frame.origin.x) <= INT32_MAX / 2 && fabs(frame.origin.y) <= INT32_MAX / 2 &&
        isfinite(frame.size.width) && isfinite(frame.size.height) &&
        frame.size.width > 0 && frame.size.height > 0 &&
        frame.size.width <= 16384 && frame.size.height <= 16384;
}

@implementation WaylandSubWindow
- (id) initWithParentWindow: (WaylandWindow *) parent frame: (CGRect) frame {
    if (!(self = [super init])) return nil;
    if (!validFrame(frame)) { [self release]; return nil; }
    _parent = [parent retain]; _frame = frame; _visible = YES;
    WaylandDisplay *display = [parent waylandDisplay];
    union wl_argument args[2] = {{.o = NULL}};
    _surface = WaylandCreateObject(display->_compositor, WP_COMPOSITOR_CREATE_SURFACE,
                                  &wl_surface_interface, args, 0, nil);
    if (display->_viewporter) {
        args[0].o = NULL; args[1].o = (struct wl_object *)_surface;
        _viewport = WaylandCreateObject(display->_viewporter, WP_VIEWPORTER_GET_VIEWPORT,
                                       &wp_viewport_interface, args, 0, nil);
    }
    // Let AppKit hit-test child views using the parent's input coordinates.
    args[0].o = NULL;
    struct wl_proxy *region = WaylandCreateObject(display->_compositor, WP_COMPOSITOR_CREATE_REGION,
                                                  &wl_region_interface, args, 0, nil);
    args[0].o = (struct wl_object *) region;
    WaylandMarshal(_surface, WP_SURFACE_SET_INPUT_REGION, NULL, 0, args);
    request(region, WP_REGION_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    _eglWindow = WL.wl_egl_window_create((struct wl_surface *) _surface, 1, 1);
    if (!_eglWindow) { [self release]; return nil; }
    _drawablePixelSize = CGSizeMake(1, 1);
    [parent addSubwindow: self];
    [self updateGeometry];
    return self;
}
- (void) removeRole {
    if (_subsurface) {
        request(_subsurface, WP_SUBSURFACE_DESTROY, WL_MARSHAL_FLAG_DESTROY);
        _subsurface = NULL;
    }
}
- (void) dealloc {
    [_parent removeSubwindow: self];
    if (_eglWindow) WL.wl_egl_window_destroy(_eglWindow);
    [self removeRole];
    if (_viewport) request(_viewport, WP_VIEWPORT_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    if (_surface) request(_surface, WP_SURFACE_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    [[_parent waylandDisplay] flush];
    [_parent release];
    [super dealloc];
}
- (void *) nativeWindow { return _eglWindow; }
- (CGFloat) backingScaleFactor { return [_parent bufferScale]; }
- (CGSize) drawablePixelSize { return _drawablePixelSize; }
- (void) updateGeometry {
    if (!_eglWindow) return;
    NSPoint offset = [_parent contentOffset];
    CGRect bounds = CGRectMake(offset.x, offset.y, [_parent frame].size.width, [_parent frame].size.height);
    CGRect full = CGRectMake(floor(_frame.origin.x + offset.x),
        floor([_parent frame].size.height - CGRectGetMaxY(_frame) + offset.y),
        ceil(_frame.size.width), ceil(_frame.size.height));
    // Surface extents and crop dimensions are integral logical pixels.
    bounds.size.width = floor(bounds.size.width); bounds.size.height = floor(bounds.size.height);
    CGRect crop = CGRectIntersection(full, bounds);
    int scale = [_parent bufferScale];
    _clipped = CGRectIsEmpty(crop) || full.size.width * scale > 16384 || full.size.height * scale > 16384;
    // Without viewporter, suppress partial children instead of drawing beyond
    // the parent's content/decorations. Fully contained children still work.
    if (!_viewport && !CGRectContainsRect(bounds, full)) _clipped = YES;
    if (_clipped || !CGRectContainsRect(bounds, _presentedRect)) [self removeRole];
    if (_clipped) { [[_parent waylandDisplay] flush]; return; }
    _pendingRect = crop;
    if (_viewport) {
        union wl_argument source[] = {
            {.f = wl_fixed_from_int((int)(crop.origin.x - full.origin.x))},
            {.f = wl_fixed_from_int((int)(crop.origin.y - full.origin.y))},
            {.f = wl_fixed_from_int((int)crop.size.width)},
            {.f = wl_fixed_from_int((int)crop.size.height)}};
        WaylandMarshal(_viewport, WP_VIEWPORT_SET_SOURCE, NULL, 0, source);
    }
    if ([_parent waylandDisplay]->_compositorVersion >= 3) {
        union wl_argument scaling[] = {{.i = scale}};
        WaylandMarshal(_surface, WP_SURFACE_SET_BUFFER_SCALE, NULL, 0, scaling);
    }
    _drawablePixelSize = CGSizeMake((int)full.size.width * scale,
                                    (int)full.size.height * scale);
    WL.wl_egl_window_resize(_eglWindow, (int)_drawablePixelSize.width,
                            (int)_drawablePixelSize.height, 0, 0);
    // No child commit here: crop/scale must apply with the matching EGL buffer.
    // No parent commit either: position changes belong to the post-swap flush.
}
- (void) setFrame: (CGRect) frame {
    if (!validFrame(frame)) return;
    _frame = frame; [self updateGeometry];
}
- (void) hide {
    _visible = NO;
    [self removeRole];
    [[_parent waylandDisplay] flush];
}
- (void) show { _visible = YES; [self updateGeometry]; }
- (struct wl_proxy *) presentedSurface { return _subsurface ? _surface : NULL; }
- (void) placeAboveSurface: (struct wl_proxy *) surface {
    union wl_argument args[] = {{.o = (struct wl_object *)surface}};
    WaylandMarshal(_subsurface, WP_SUBSURFACE_PLACE_ABOVE, NULL, 0, args);
}
- (BOOL) requiresMainThreadPresentation { return YES; }
- (void) flush {
    if (![NSThread isMainThread]) return;
    if (!_visible || _clipped || !_eglWindow || [_parent isInvalidated]) return;
    struct wl_proxy *parentSurface = [_parent ensureSurface];
    if (!parentSurface) return;
    if (!_subsurface) {
        union wl_argument args[] = {{.o = NULL}, {.o = (struct wl_object *)_surface},
                                    {.o = (struct wl_object *)parentSurface}};
        _subsurface = WaylandCreateObject([_parent waylandDisplay]->_subcompositor,
            WP_SUBCOMPOSITOR_GET_SUBSURFACE, &wl_subsurface_interface, args, 0, nil);
        // Default synchronized mode: the parent commit presents the cached
        // EGL buffer, viewport crop, scale and position as one transaction.
    }
    union wl_argument position[] = {{.i = (int)_pendingRect.origin.x}, {.i = (int)_pendingRect.origin.y}};
    WaylandMarshal(_subsurface, WP_SUBSURFACE_SET_POSITION, NULL, 0, position);
    [_parent stackSubwindows];
    request(parentSurface, WP_SURFACE_COMMIT, 0);
    _presentedRect = _pendingRect;
    [[_parent waylandDisplay] flush];
}
@end
