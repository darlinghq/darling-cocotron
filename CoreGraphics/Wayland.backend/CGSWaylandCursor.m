/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/
#import "CGSWaylandCursor.h"
#import "CGSConnectionWayland.h"
#import "CGSWaylandPointer.h"
#import <CoreGraphics/CGSCursorPrivate.h>
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import "WaylandScale.h"
#include <limits.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

// What the pointer was last given (see -alreadyApplied:key:serial:).
enum { AppliedNothing, AppliedHidden, AppliedShape, AppliedSurface };

// The freedesktop names of the cursor themes and the matching wp_cursor_shape_device_v1.shape.
static uint32_t cursorShapeForName(const char* name)
{
    static const struct { const char *name; uint32_t shape; } shapes[] = {
        {"default", WP_CURSOR_SHAPE_DEFAULT},
        {"grabbing", WP_CURSOR_SHAPE_GRABBING},
        {"crosshair", WP_CURSOR_SHAPE_CROSSHAIR},
        {"text", WP_CURSOR_SHAPE_TEXT},
        {"vertical-text", WP_CURSOR_SHAPE_VERTICAL_TEXT},
        {"zoom-in", WP_CURSOR_SHAPE_ZOOM_IN},
        {"zoom-out", WP_CURSOR_SHAPE_ZOOM_OUT},
        {"grab", WP_CURSOR_SHAPE_GRAB},
        {"pointer", WP_CURSOR_SHAPE_POINTER},
        {"s-resize", WP_CURSOR_SHAPE_S_RESIZE},
        {"w-resize", WP_CURSOR_SHAPE_W_RESIZE},
        {"ew-resize", WP_CURSOR_SHAPE_EW_RESIZE},
        {"e-resize", WP_CURSOR_SHAPE_E_RESIZE},
        {"n-resize", WP_CURSOR_SHAPE_N_RESIZE},
        {"ns-resize", WP_CURSOR_SHAPE_NS_RESIZE},
        {"nw-resize", WP_CURSOR_SHAPE_NW_RESIZE},
        {"ne-resize", WP_CURSOR_SHAPE_NE_RESIZE},
        {"se-resize", WP_CURSOR_SHAPE_SE_RESIZE},
        {"sw-resize", WP_CURSOR_SHAPE_SW_RESIZE},
        {"nwse-resize", WP_CURSOR_SHAPE_NWSE_RESIZE},
        {"nesw-resize", WP_CURSOR_SHAPE_NESW_RESIZE},
    };
    for (size_t i = 0; name != NULL && i < sizeof(shapes) / sizeof(shapes[0]); i++)
        if (strcmp(name, shapes[i].name) == 0)
            return shapes[i].shape;
    return WP_CURSOR_SHAPE_DEFAULT;
}

@implementation CGSWaylandCursor

- (instancetype) initWithConnection: (CGSConnectionWayland *) connection pointer: (CGSWaylandPointer *) pointer {
    if ((self = [super init]) != nil) {
        _connection = connection;
        _pointer = pointer;
    }
    return self;
}

- (void) dealloc {
    [self invalidate];
    [super dealloc];
}

#pragma mark - Objects

- (void) destroyImageBuffer {
    if (_imageBuffer != NULL) {
        union wl_argument none[1] = {{.o = NULL}};
        WaylandMarshal(_imageBuffer, WP_BUFFER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, none);
        _imageBuffer = NULL;
    }
    [_imageCursor release];
    _imageCursor = nil;
}

- (void) invalidate {
    [self destroyImageBuffer];
    if (_shapeDevice != NULL) {
        WaylandMarshal(_shapeDevice, WP_CURSOR_SHAPE_DEVICE_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        _shapeDevice = NULL;
    }
    if (_fractionalScale != NULL) {
        WaylandMarshal(_fractionalScale, WP_FRACTIONAL_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        _fractionalScale = NULL;
    }
    if (_surface != NULL) {
        WL.wl_proxy_destroy(_surface);
        _surface = NULL;
    }
    if (_theme != NULL) {
        WL.wl_cursor_theme_destroy(_theme);
        _theme = NULL;
    }
}

// The cursor surface needs only the compositor and wl_shm, not a cursor theme.
- (void) ensureSurface {
    if (_surface == NULL && _connection->_compositor != NULL) {
        union wl_argument args[1] = {{.o = NULL}};
        _surface = [_connection createObject: _connection->_compositor
                                      opcode: WP_COMPOSITOR_CREATE_SURFACE
                                   interface: &wl_surface_interface
                                   arguments: args
                                        kind: CGSWaylandObjectNone
                                      object: nil];
    }
    struct wl_proxy *manager = [_connection fractionalScaleManager];
    if (_surface != NULL && _fractionalScale == NULL && manager != NULL) {
        union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _surface}};
        _fractionalScale = [_connection createObject: manager
                                              opcode: WP_FRACTIONAL_MANAGER_GET_SCALE
                                           interface: &wp_fractional_scale_v1_interface
                                           arguments: args
                                                kind: CGSWaylandObjectCursorScale
                                              object: self];
    }
}

- (void) objectsChanged {
    struct wl_proxy *pointer = [_pointer pointerProxy], *manager = [_connection cursorShapeManager];

    [self ensureSurface];
    _appliedKind = AppliedNothing;
    if (manager != NULL && pointer != NULL && _shapeDevice == NULL) {
        union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) pointer}};
        _shapeDevice = [_connection createObject: manager
                                          opcode: WP_CURSOR_SHAPE_MANAGER_GET_POINTER
                                       interface: &wp_cursor_shape_device_v1_interface
                                       arguments: args
                                            kind: CGSWaylandObjectNone
                                          object: nil];
    } else if ((manager == NULL || pointer == NULL) && _shapeDevice != NULL) {
        // A device whose pointer went away is inert; there is nothing to send it.
        WaylandMarshal(_shapeDevice, WP_CURSOR_SHAPE_DEVICE_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        _shapeDevice = NULL;
    }
    [self setNeedsApply];
}

#pragma mark - Scale

// The compositor sends the preferred scale of the cursor surface while the surface is the pointer's cursor; while it is
// not (a shape the compositor draws, a hidden cursor), the scale of the outputs is what the next image is made for.
// The output scale must be applied exactly once. wl_surface.set_buffer_scale is the one mechanism every compositor
// applies to a cursor surface; a wp_viewport destination is not (Hyprland derives the logical size from buffer size
// / buffer scale and ignores it, wlroots honours it). A raster pinned to buffer_scale 1 and cropped by a viewport
// therefore shows 2x too large on a 2x Hyprland. So the raster is made at the next whole scale and tagged with it;
// the compositor scales it down to a fractional output. Without a fractional-scale manager, or without
// set_buffer_scale, the compositor owns the scaling: hand over a 1x raster.
- (uint32_t) renderScale120 {
    // set_buffer_scale needs wl_surface v3.
    if (_fractionalScale == NULL || WL.wl_proxy_get_version(_connection->_compositor) < 3)
        return 120;
    return WaylandCursorBufferScale120(_preferredScale120 ?: [_connection maximumOutputScale120]);
}

- (void) preferredScaleChanged: (uint32_t) scale120 {
    if (_fractionalScale == NULL || scale120 == 0 || scale120 == _preferredScale120)
        return;
    _preferredScale120 = scale120;
    [self setNeedsApply];
}

#pragma mark - Buffers

- (struct wl_proxy *) imageBufferForCursor: (CGSCursor *) cursor scale120: (uint32_t) scale120 {
    if (_imageBuffer != NULL && (_imageCursor != cursor || _imageScale120 != scale120))
        [self destroyImageBuffer];
    if (_imageBuffer != NULL)
        return _imageBuffer;
    double scale = scale120 / 120.0;
    NSData *pixels = [cursor pixelsForScale: scale];
    CGSize size = [cursor pixelSizeForScale: scale];
    if (pixels == nil)
        return NULL;
    _imageBuffer = WaylandCreateARGBBuffer(_connection->_shm, [pixels bytes], [pixels length],
                                         (int32_t) size.width, (int32_t) size.height);
    if (_imageBuffer != NULL) {
        _imageCursor = [cursor retain];
        _imageScale120 = scale120;
    }
    return _imageBuffer;
}

// The cursor theme at the nominal size times the scale.
- (BOOL) loadThemeForScale120: (uint32_t) scale120 {
    if (!WL.hasCursor)
        return NO;
    if (_theme != NULL && _themeScale120 == scale120)
        return YES;
    const char *sizeString = getenv("XCURSOR_SIZE");
    long nominal = sizeString ? strtol(sizeString, NULL, 10) : 24;
    if (nominal <= 0 || nominal > INT32_MAX)
        nominal = 24;
    int32_t requested;
    struct wl_cursor_theme *theme = WaylandScaleExtent((int32_t) nominal, scale120, INT32_MAX, &requested)
        ? WL.wl_cursor_theme_load(getenv("XCURSOR_THEME"), requested, (struct wl_shm *) _connection->_shm) : NULL;
    if (theme == NULL)
        return _theme != NULL;
    if (_theme != NULL)
        WL.wl_cursor_theme_destroy(_theme);
    _theme = theme;
    _themeScale120 = scale120;
    return YES;
}

#pragma mark - The cursor of the pointer

- (void) setNeedsApply {
    if (_applyQueued)
        return;
    _applyQueued = YES;
    [_connection performAfterDispatch: ^{
        self->_applyQueued = NO;
        [self apply];
    }];
}

- (void) setPointerCursorSurface: (struct wl_proxy *) surface serial: (uint32_t) serial hotX: (int32_t) x hotY: (int32_t) y {
    union wl_argument args[4] = {{.u = serial}, {.o = (struct wl_object *) surface}, {.i = x}, {.i = y}};
    WaylandMarshal([_pointer pointerProxy], WP_POINTER_SET_CURSOR, NULL, 0, args);
    [_connection flush];
}

// Whether the pointer already has this cursor for this enter; if not, it is remembered as given.
- (BOOL) alreadyApplied: (int) kind key: (uintptr_t) key serial: (uint32_t) serial {
    if (serial == _appliedSerial && kind == _appliedKind && key == _appliedKey)
        return YES;
    _appliedSerial = serial;
    _appliedKind = kind;
    _appliedKey = key;
    return NO;
}

- (void) apply {
    struct wl_proxy *pointer = [_pointer pointerProxy];
    uint32_t serial = [_pointer enterSerial];

    if (pointer == NULL || serial == 0)
        return;
    // A hidden cursor gives the pointer no image; it is the selected one that is shown again.
    if (![_connection cursorIsVisible]) {
        _preferredScale120 = 0;
        if (![self alreadyApplied: AppliedHidden key: 0 serial: serial])
            [self setPointerCursorSurface: NULL serial: serial hotX: 0 hotY: 0];
        return;
    }

    CGSCursor *cursor = [_connection cursor];
    BOOL image = [cursor isImage];
    // A shape needs neither a cursor surface nor a theme when the compositor draws it. The protocol requires the
    // latest wl_pointer.enter serial, which is the one the surface cursor uses too.
    if (!image && _shapeDevice != NULL) {
        _preferredScale120 = 0;
        uint32_t shape = cursor != nil ? cursorShapeForName([cursor themeName]) : WP_CURSOR_SHAPE_DEFAULT;
        if ([self alreadyApplied: AppliedShape key: shape serial: serial])
            return;
        union wl_argument args[2] = {{.u = serial}, {.u = shape}};
        WaylandMarshal(_shapeDevice, WP_CURSOR_SHAPE_DEVICE_SET_SHAPE, NULL, 0, args);
        [_connection flush];
        return;
    }
    [self ensureSurface];
    if (_surface == NULL)
        return;

    uint32_t scale120 = [self renderScale120];
    int32_t wireScale = (int32_t) (scale120 / 120);
    struct wl_proxy *buffer = NULL;
    CGSize logical = CGSizeZero;
    CGPoint hotSpot = CGPointZero;
    if (image) {
        buffer = [self imageBufferForCursor: cursor scale120: scale120];
        logical = [cursor size];
        hotSpot = [cursor hotSpot];
    }
    if (buffer == NULL) {
        // A shape from the theme (or the arrow when the image could not be made).
        if (![self loadThemeForScale120: scale120] || _theme == NULL)
            return;
        static const char *const arrowNames[] = {"default", "left_ptr", NULL};
        const char *shapeNames[3] = {NULL, NULL, NULL};
        const char *const *names = arrowNames;
        if (cursor != nil && !image) {
            shapeNames[0] = [cursor themeName];
            shapeNames[1] = [cursor themeFallbackName];
            names = shapeNames;
        }
        struct wl_cursor *themed = NULL;
        for (int i = 0; themed == NULL && names[i] != NULL; i++)
            themed = WL.wl_cursor_theme_get_cursor(_theme, names[i]);
        for (int i = 0; themed == NULL && arrowNames[i] != NULL; i++)
            themed = WL.wl_cursor_theme_get_cursor(_theme, arrowNames[i]);
        if (themed == NULL || themed->image_count == 0)
            return;

        struct wl_cursor_image *themedImage = themed->images[0];
        buffer = (struct wl_proxy *) WL.wl_cursor_image_get_buffer(themedImage);
        if (buffer == NULL || !themedImage->width || !themedImage->height || themedImage->width > INT32_MAX ||
            themedImage->height > INT32_MAX)
            return;
        // The theme was loaded at the nominal size times the whole scale: the surface is tagged with that scale, so
        // the logical size and the hot spot are the image's divided by it. A theme without that exact size hands
        // back its nearest one, which the scale may not divide.
        wireScale = WaylandCursorWireScale((int32_t) themedImage->width, (int32_t) themedImage->height,
                                           (int32_t) (_themeScale120 / 120));
        logical = CGSizeMake(themedImage->width / wireScale, themedImage->height / wireScale);
        hotSpot = CGPointMake(themedImage->hotspot_x / wireScale, themedImage->hotspot_y / wireScale);
    }

    // The image cursor is kept alive by its buffer, so its address names it; a shape is named by its theme name.
    if ([self alreadyApplied: AppliedSurface
                         key: (image ? (uintptr_t) cursor : (uintptr_t) (cursor != nil ? [cursor themeName] : "")) ^ scale120
                      serial: serial])
        return;
    if (WL.wl_proxy_get_version(_connection->_compositor) >= 3) {
        union wl_argument scaleArgs[1] = {{.i = wireScale}};
        WaylandMarshal(_surface, WP_SURFACE_SET_BUFFER_SCALE, NULL, 0, scaleArgs);
    }
    union wl_argument attach[3] = {{.o = (struct wl_object *) buffer}, {.i = 0}, {.i = 0}};
    WaylandMarshal(_surface, WP_SURFACE_ATTACH, NULL, 0, attach);
    union wl_argument damage[4] = {{.i = 0}, {.i = 0}, {.i = (int32_t) logical.width}, {.i = (int32_t) logical.height}};
    WaylandMarshal(_surface, WP_SURFACE_DAMAGE, NULL, 0, damage);
    union wl_argument none[1] = {{.o = NULL}};
    WaylandMarshal(_surface, WP_SURFACE_COMMIT, NULL, 0, none);
    [self setPointerCursorSurface: _surface serial: serial hotX: (int32_t) hotSpot.x hotY: (int32_t) hotSpot.y];
}

@end
