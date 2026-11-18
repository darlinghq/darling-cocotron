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
#import "WaylandScale.h"

static void request(struct wl_proxy *proxy, uint32_t opcode, uint32_t flags) {
    union wl_argument args[] = {{.o = NULL}};
    WaylandMarshal(proxy, opcode, NULL, flags, args);
}
static void unsetViewportSource(struct wl_proxy *viewport) {
    int32_t unset = wl_fixed_from_int(-1);
    union wl_argument source[] = {{.f = unset}, {.f = unset}, {.f = unset}, {.f = unset}};
    WaylandMarshal(viewport, WP_VIEWPORT_SET_SOURCE, NULL, 0, source);
}
// The largest subwindow dimension, in points and in allocated pixels, that is accepted. It
// matches the layer context's drawable bound (MAX_DRAWABLE_DIMENSION in QuartzCore) so a
// bogus frame is refused instead of reaching wl_egl_window_resize.
static const int32_t WaylandMaxSubWindowDimension = 16384;

static BOOL validFrame(CGRect frame) {
    return isfinite(frame.origin.x) && isfinite(frame.origin.y) &&
        fabs(frame.origin.x) <= INT32_MAX / 2 && fabs(frame.origin.y) <= INT32_MAX / 2 &&
        isfinite(frame.size.width) && isfinite(frame.size.height) &&
        frame.size.width > 0 && frame.size.height > 0 &&
        frame.size.width <= WaylandMaxSubWindowDimension &&
        frame.size.height <= WaylandMaxSubWindowDimension;
}

// The Wayland objects of one Metal layer's surface.
@interface WaylandMetalSurface : NSObject {
@public
    struct wl_proxy *surface, *subsurface, *viewport;
    CAMetalLayer *layer; // not retained
    CGRect frame;
    NSUInteger sequence; // creation order, for layers that are not in one tree
}
@end
@implementation WaylandMetalSurface
@end

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
    if (_viewport) _fractionalScale = [display newFractionalScaleForSurface: _surface owner: (id)self];
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
    for (CAMetalLayer *layer in [[_metalSurfaces keyEnumerator] allObjects])
        [self destroyMetalSurfaceForLayer: layer];
    [_metalSurfaces release];
    [_parent removeSubwindow: self];
    if (_eglWindow) WL.wl_egl_window_destroy(_eglWindow);
    [self removeRole];
    if (_fractionalScale) request(_fractionalScale, WP_FRACTIONAL_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    if (_viewport) request(_viewport, WP_VIEWPORT_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    if (_surface) request(_surface, WP_SURFACE_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    [[_parent waylandDisplay] flush];
    [_parent release];
    [super dealloc];
}
- (void *) nativeWindow { return _eglWindow; }
- (uint32_t) renderScale120 {
    return _fractionalScale ? (_preferredScale120 ? WaylandIntegralScale120(_preferredScale120) : [_parent renderScale120])
        : (uint32_t)MIN((uint64_t)[_parent bufferScale] * 120, UINT32_MAX);
}
- (CGFloat) backingScaleFactor { return [self renderScale120] / 120.0; }
- (void) preferredScaleChanged: (uint32_t) scale120 {
    if (!_fractionalScale || !scale120 || scale120 == _preferredScale120) return;
    _preferredScale120 = scale120; _needsScaleRedraw = YES; _scaleRedrawRequested = NO;
    if (_scaleUpdatePending) return;
    _scaleUpdatePending = YES;
    [[_parent waylandDisplay] performAfterDispatch: ^{
        self->_scaleUpdatePending = NO;
        if (![self->_parent isInvalidated]) [self updateGeometry];
    }];
}
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
    int32_t width, height;
    BOOL allocatedSizeValid = WaylandScaleExtent((int32_t)full.size.width, [self renderScale120], WaylandMaxSubWindowDimension, &width) &&
        WaylandScaleExtent((int32_t)full.size.height, [self renderScale120], WaylandMaxSubWindowDimension, &height);
    _clipped = CGRectIsEmpty(crop) || !allocatedSizeValid;
    // Without viewporter, suppress partial children instead of drawing beyond
    // the parent's content/decorations. Fully contained children still work.
    if (!_viewport && !CGRectContainsRect(bounds, full)) _clipped = YES;
    if (_clipped || !CGRectContainsRect(bounds, _presentedRect)) [self removeRole];
    if (_clipped) { _scaleRedrawRequested = NO; [[_parent waylandDisplay] flush]; return; }
    _fullRect = full;
    _pendingRect = crop;
    if (_viewport) {
        // EGL can swap a backbuffer allocated before this resize. Clear the old
        // crop before its implicit commit, then crop the actual buffer in flush.
        unsetViewportSource(_viewport);
    }
    if ([_parent waylandDisplay]->_compositorVersion >= 3) {
        union wl_argument scaling[] = {{.i = _viewport ? 1 : scale}};
        WaylandMarshal(_surface, WP_SURFACE_SET_BUFFER_SCALE, NULL, 0, scaling);
    }
    CGSize pixels = CGSizeMake(width, height);
    if (!CGSizeEqualToSize(pixels, _drawablePixelSize)) {
        _needsScaleRedraw = YES; _scaleRedrawRequested = NO;
    }
    _drawablePixelSize = pixels;
    WL.wl_egl_window_resize(_eglWindow, (int)_drawablePixelSize.width,
                            (int)_drawablePixelSize.height, 0, 0);
    if (_needsScaleRedraw && _visible && !_scaleRedrawRequested) {
        _scaleRedrawRequested = YES;
        [_parent scheduleSubwindowRedraw];
    }
    // No child commit here: crop/scale must apply with the matching EGL buffer.
    // No parent commit either: position changes belong to the post-swap flush.
}
- (void) setFrame: (CGRect) frame {
    if (!validFrame(frame)) return;
    _frame = frame; [self updateGeometry];
}
- (void) hide {
    _visible = NO;
    _scaleRedrawRequested = NO;
    [self removeRole];
    [self detachMetalSubsurfaces];
    [[_parent waylandDisplay] flush];
}
- (void) show {
    _visible = YES;
    [self updateGeometry];
    [self attachMetalSubsurfaces];
}
- (struct wl_proxy *) presentedSurface { return _subsurface ? _surface : NULL; }
- (void) placeAboveSurface: (struct wl_proxy *) surface {
    union wl_argument args[] = {{.o = (struct wl_object *)surface}};
    WaylandMarshal(_subsurface, WP_SUBSURFACE_PLACE_ABOVE, NULL, 0, args);
}
- (BOOL) requiresMainThreadPresentation { return NO; }
- (uint32_t) refreshMillihertz { return [_parent refreshMillihertz]; }
// Rendering and swapping the EGL surface may happen on any thread, as on the other
// backends: the EGL platform has its own event queue for the surface, and the
// wl_egl_window is only resized by updateGeometry (main thread), which EGL picks up at the
// next swap. What follows a swap (crop, position, stacking, the parent's commit) uses
// state owned by the main thread, so a swap on another thread asks the main thread to do it.
// Requests made before the main thread gets to it are merged; it presents the latest
// geometry, and the parent's commit applies the newest cached buffer.
- (void) flush {
    if (![NSThread isMainThread]) {
        if (__atomic_exchange_n(&_flushPending, 1, __ATOMIC_ACQ_REL)) return;
        [self retain];
        [self performSelectorOnMainThread: @selector(flushOnMainThread) withObject: nil waitUntilDone: NO
                                    modes: [NSArray arrayWithObject: (NSString *) kCFRunLoopCommonModes]];
        return;
    }
    if (!_visible || _clipped || !_eglWindow || [_parent isInvalidated]) return;
    if (_viewport) {
        int width, height;
        WL.wl_egl_window_get_attached_size(_eglWindow, &width, &height);
        int32_t x, y, w, h;
        if (!WaylandScaleCrop((int32_t)_fullRect.size.width, width,
                (int32_t)(_pendingRect.origin.x - _fullRect.origin.x),
                (int32_t)(CGRectGetMaxX(_pendingRect) - _fullRect.origin.x), &x, &w) ||
            !WaylandScaleCrop((int32_t)_fullRect.size.height, height,
                (int32_t)(_pendingRect.origin.y - _fullRect.origin.y),
                (int32_t)(CGRectGetMaxY(_pendingRect) - _fullRect.origin.y), &y, &h)) {
            NSLog(@"Cannot crop Wayland drawable with attached size %dx%d", width, height);
            [self removeRole];
            return;
        }
        union wl_argument source[] = {{.f = x}, {.f = y}, {.f = w}, {.f = h}};
        WaylandMarshal(_viewport, WP_VIEWPORT_SET_SOURCE, NULL, 0, source);
        union wl_argument destination[] = {{.i = (int)_pendingRect.size.width},
                                          {.i = (int)_pendingRect.size.height}};
        WaylandMarshal(_viewport, WP_VIEWPORT_SET_DESTINATION, NULL, 0, destination);
        request(_surface, WP_SURFACE_COMMIT, 0);
    }
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
    // A later swap may attach the resized backbuffer without another geometry
    // update. Leave source unset pending for that implicit child commit.
    if (_viewport) unsetViewportSource(_viewport);
    // The caller invokes flush only after a successful drawable swap. A queued
    // preference still needs its geometry/redraw pass; don't consume it here.
    if (!_scaleUpdatePending) _needsScaleRedraw = NO;
    _scaleRedrawRequested = NO;
    [[_parent waylandDisplay] flush];
}

- (void) flushOnMainThread {
    __atomic_store_n(&_flushPending, 0, __ATOMIC_RELEASE);
    [self flush];
    [self release];
}

// A Metal layer's surface is a desynchronized subsurface of the parent window, above this
// window's own subsurface, where the layer is in the tree. Its buffers come from the
// Vulkan swapchain; only the place and size are set here.

- (CGSize) pixelSizeForMetalSurfaceFrame: (CGRect) frame {
    int32_t width, height;
    uint32_t scale = [self renderScale120];
    if (!WaylandScaleExtent((int32_t) ceil(frame.size.width), scale, WaylandMaxSubWindowDimension, &width) ||
        !WaylandScaleExtent((int32_t) ceil(frame.size.height), scale, WaylandMaxSubWindowDimension, &height))
        return CGSizeMake(1, 1);
    return CGSizeMake(width, height);
}

- (void) placeMetalSurface: (WaylandMetalSurface *) metal frame: (CGRect) frame {
    metal->frame = frame;
    if (metal->subsurface) {
        NSPoint offset = [_parent contentOffset];
        CGRect inParent = CGRectOffset(frame, _frame.origin.x, _frame.origin.y);
        int32_t x = (int32_t) floor(inParent.origin.x + offset.x);
        int32_t y = (int32_t) floor([_parent frame].size.height - CGRectGetMaxY(inParent) + offset.y);
        union wl_argument position[] = {{.i = x}, {.i = y}};
        WaylandMarshal(metal->subsurface, WP_SUBSURFACE_SET_POSITION, NULL, 0, position);
    }

    WaylandDisplay *display = [_parent waylandDisplay];
    if (metal->viewport) {
        union wl_argument destination[] = {{.i = (int32_t) ceil(frame.size.width)},
                                          {.i = (int32_t) ceil(frame.size.height)}};
        WaylandMarshal(metal->viewport, WP_VIEWPORT_SET_DESTINATION, NULL, 0, destination);
    }
    if (display->_compositorVersion >= 3) {
        union wl_argument scaling[] = {{.i = metal->viewport ? 1 : [_parent bufferScale]}};
        WaylandMarshal(metal->surface, WP_SURFACE_SET_BUFFER_SCALE, NULL, 0, scaling);
    }
    // the position and the stacking apply with the parent's commit
    [_parent stackSubwindows];
    struct wl_proxy *parentSurface = [_parent ensureSurface];
    if (parentSurface)
        request(parentSurface, WP_SURFACE_COMMIT, 0);
    [display flush];
}

- (void) describeMetalSurface: (WaylandMetalSurface *) metal
                        frame: (CGRect) frame
                      surface: (CANativeSurface *) surface {
    surface->kind = CANativeSurfaceKindWayland;
    surface->display = [_parent waylandDisplay]->_wlDisplay;
    surface->window = 0;
    surface->surface = metal->surface;
    surface->pixelSize = [self pixelSizeForMetalSurfaceFrame: frame];
}

// The role of a Metal layer's surface: a desynchronized subsurface of the parent window, which
// is destroyed (unmapping the surface) while this subwindow is hidden. The surface keeps the
// last frame it was given, so showing the subwindow again shows it.
- (void) attachSubsurfaceOfMetalSurface: (WaylandMetalSurface *) metal {
    struct wl_proxy *parentSurface = [_parent ensureSurface];
    WaylandDisplay *display = [_parent waylandDisplay];
    if (metal->subsurface || !parentSurface || !display->_subcompositor)
        return;
    union wl_argument sub[] = {{.o = NULL}, {.o = (struct wl_object *) metal->surface},
                               {.o = (struct wl_object *) parentSurface}};
    metal->subsurface = WaylandCreateObject(display->_subcompositor, WP_SUBCOMPOSITOR_GET_SUBSURFACE,
                                            &wl_subsurface_interface, sub, 0, nil);
    // frames are shown as the swapchain presents them, not with the parent's commits
    request(metal->subsurface, WP_SUBSURFACE_SET_DESYNC, 0);
}

- (void) detachMetalSubsurfaces {
    BOOL any = NO;
    for (CAMetalLayer *layer in [[_metalSurfaces keyEnumerator] allObjects]) {
        WaylandMetalSurface *metal = [_metalSurfaces objectForKey: layer];
        if (metal->subsurface) {
            request(metal->subsurface, WP_SUBSURFACE_DESTROY, WL_MARSHAL_FLAG_DESTROY);
            metal->subsurface = NULL;
            any = YES;
        }
    }
    struct wl_proxy *parentSurface = [_parent ensureSurface];
    if (any && parentSurface && ![_parent isInvalidated])
        request(parentSurface, WP_SURFACE_COMMIT, 0);
    [[_parent waylandDisplay] flush];
}

- (void) attachMetalSubsurfaces {
    for (CAMetalLayer *layer in [[_metalSurfaces keyEnumerator] allObjects]) {
        WaylandMetalSurface *metal = [_metalSurfaces objectForKey: layer];
        [self attachSubsurfaceOfMetalSurface: metal];
        [self placeMetalSurface: metal frame: metal->frame];
    }
}

// The layers' order in the layer tree: the one that is earlier among its siblings, or the
// ancestor, is below.
static NSArray *layerPath(id layer) {
    NSMutableArray *path = [NSMutableArray array];
    for (; layer != nil; layer = [layer superlayer])
        [path insertObject: layer atIndex: 0];
    return path;
}

static NSComparisonResult compareLayerOrder(WaylandMetalSurface *a, WaylandMetalSurface *b, void *unused) {
    NSArray *pathA = layerPath((id) a->layer), *pathB = layerPath((id) b->layer);
    NSUInteger i = 0;
    while (i < [pathA count] && i < [pathB count] && [pathA objectAtIndex: i] == [pathB objectAtIndex: i])
        i++;
    if (i == [pathA count] || i == [pathB count])
        return i == [pathA count] ? (i == [pathB count] ? NSOrderedSame : NSOrderedAscending) : NSOrderedDescending;
    if (i == 0)
        return a->sequence < b->sequence ? NSOrderedAscending : NSOrderedDescending;
    NSArray *siblings = [[pathA objectAtIndex: i - 1] sublayers];
    NSUInteger indexA = [siblings indexOfObjectIdenticalTo: [pathA objectAtIndex: i]];
    NSUInteger indexB = [siblings indexOfObjectIdenticalTo: [pathB objectAtIndex: i]];
    return indexA < indexB ? NSOrderedAscending : (indexA > indexB ? NSOrderedDescending : NSOrderedSame);
}

// Places the Metal layers' surfaces above `below`, in the order of the layers in the tree, and
// returns the topmost surface.
- (struct wl_proxy *) stackMetalSurfacesAbove: (struct wl_proxy *) below {
    NSMutableArray *surfaces = [NSMutableArray array];
    for (CAMetalLayer *layer in [[_metalSurfaces keyEnumerator] allObjects]) {
        WaylandMetalSurface *metal = [_metalSurfaces objectForKey: layer];
        if (metal->subsurface)
            [surfaces addObject: metal];
    }
    [surfaces sortUsingFunction: (NSInteger (*)(id, id, void *)) compareLayerOrder context: NULL];
    for (WaylandMetalSurface *metal in surfaces) {
        union wl_argument args[] = {{.o = (struct wl_object *) below}};
        WaylandMarshal(metal->subsurface, WP_SUBSURFACE_PLACE_ABOVE, NULL, 0, args);
        below = metal->surface;
    }
    return below;
}

- (BOOL) createMetalSurface: (CANativeSurface *) surface
                   forLayer: (CAMetalLayer *) layer
                      frame: (CGRect) frame {
    if (_metalSurfaces == nil)
        _metalSurfaces = [[NSMapTable mapTableWithWeakToStrongObjects] retain];
    WaylandMetalSurface *existing = [_metalSurfaces objectForKey: layer];
    if (existing != nil)
        return [self updateMetalSurface: surface forLayer: layer frame: frame];
    if (!validFrame(frame) || [_parent isInvalidated])
        return NO;
    WaylandDisplay *display = [_parent waylandDisplay];
    struct wl_proxy *parentSurface = [_parent ensureSurface];
    if (!parentSurface || !display->_subcompositor)
        return NO;

    WaylandMetalSurface *metal = [[[WaylandMetalSurface alloc] init] autorelease];
    union wl_argument args[3] = {{.o = NULL}};
    metal->surface = WaylandCreateObject(display->_compositor, WP_COMPOSITOR_CREATE_SURFACE,
                                         &wl_surface_interface, args, 0, nil);
    if (display->_viewporter) {
        args[0].o = NULL; args[1].o = (struct wl_object *) metal->surface;
        metal->viewport = WaylandCreateObject(display->_viewporter, WP_VIEWPORTER_GET_VIEWPORT,
                                              &wp_viewport_interface, args, 0, nil);
    }
    // the layer's pixels do not take input of their own: the parent's hit-testing applies
    args[0].o = NULL;
    struct wl_proxy *region = WaylandCreateObject(display->_compositor, WP_COMPOSITOR_CREATE_REGION,
                                                  &wl_region_interface, args, 0, nil);
    args[0].o = (struct wl_object *) region;
    WaylandMarshal(metal->surface, WP_SURFACE_SET_INPUT_REGION, NULL, 0, args);
    request(region, WP_REGION_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    metal->layer = layer;
    static NSUInteger sequence;
    metal->sequence = ++sequence;
    if (_visible)
        [self attachSubsurfaceOfMetalSurface: metal];

    [_metalSurfaces setObject: metal forKey: layer];
    [self placeMetalSurface: metal frame: frame];
    [self describeMetalSurface: metal frame: frame surface: surface];
    return YES;
}

- (BOOL) updateMetalSurface: (CANativeSurface *) surface
                   forLayer: (CAMetalLayer *) layer
                      frame: (CGRect) frame {
    WaylandMetalSurface *metal = [_metalSurfaces objectForKey: layer];
    if (metal == nil || !validFrame(frame))
        return NO;
    [self placeMetalSurface: metal frame: frame];
    [self describeMetalSurface: metal frame: frame surface: surface];
    return YES;
}

- (void) destroyMetalSurfaceForLayer: (CAMetalLayer *) layer {
    WaylandMetalSurface *metal = [[_metalSurfaces objectForKey: layer] retain];
    if (metal == nil)
        return;
    [_metalSurfaces removeObjectForKey: layer];
    if (metal->viewport) request(metal->viewport, WP_VIEWPORT_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    if (metal->subsurface) request(metal->subsurface, WP_SUBSURFACE_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    request(metal->surface, WP_SURFACE_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    struct wl_proxy *parentSurface = [_parent ensureSurface];
    if (parentSurface && ![_parent isInvalidated])
        request(parentSurface, WP_SURFACE_COMMIT, 0);
    [[_parent waylandDisplay] flush];
    [metal release];
}

@end
