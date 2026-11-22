/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/

#import "WaylandToplevelIcon.h"
#import "WaylandDisplay.h"
#import "WaylandWindow.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import "../private-include/AppKit/DarlingDisplay.h"
#include <sys/mman.h>
#include <unistd.h>

// Used when the compositor names no sizes.
static const int DefaultSizes[] = {16, 32, 48, 64, 128, 256};
// Sizes the compositor names are taken at face value up to this edge length in pixels (after scaling), and
// at most this many of them.
enum { MaxPixelSide = 1024, MaxSizes = 16 };

// A buffer must not go away before the icon that uses it.
static void destroyIcon(struct wl_proxy *icon, NSArray *buffers) {
    union wl_argument none[1] = {{.o = NULL}};
    if (icon != NULL)
        WaylandMarshal(icon, WP_ICON_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, none);
    for (NSValue *buffer in buffers)
        WaylandMarshal([buffer pointerValue], WP_BUFFER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, none);
}

@implementation WaylandToplevelIcons

- (instancetype) initWithDisplay: (WaylandDisplay *) display {
    if ((self = [super init]) != nil) {
        _display = display;
        _sizes = [NSMutableArray new];
        _pendingSizes = [NSMutableArray new];
    }
    return self;
}

- (void) setManager: (struct wl_proxy *) manager name: (uint32_t) name {
    _manager = manager;
    _name = name;
}

- (uint32_t) name {
    return _name;
}

- (void) dealloc {
    // Disconnecting does not free proxies, so they are released while the connection is still up.
    destroyIcon(_icon, _buffers);
    [_buffers release];
    if (_manager != NULL)
        WL.wl_proxy_destroy(_manager);
    [_sizes release];
    [_pendingSizes release];
    [super dealloc];
}

- (void) handleEvent: (uint32_t) opcode arguments: (union wl_argument *) args {
    if (opcode == WP_ICON_MANAGER_EV_ICON_SIZE) {
        int32_t size = args[0].i;
        if (size >= 1 && size <= MaxPixelSide && [_pendingSizes count] < MaxSizes &&
            ![_pendingSizes containsObject: @(size)])
            [_pendingSizes addObject: @(size)];
    } else if (opcode == WP_ICON_MANAGER_EV_DONE) {
        BOOL changed = ![_pendingSizes isEqualToArray: _sizes];
        [_sizes setArray: _pendingSizes];
        [_pendingSizes removeAllObjects];
        if (changed && _built)
            [self applicationIconChanged];
    }
}

// Renders the icon at the sizes in use and creates the icon object. _icon stays NULL when the application
// has no icon or the memory for the pixels cannot be had.
- (void) build {
    _built = YES;
    NSMutableArray *sides = [NSMutableArray array]; // the edge lengths (in points) and scales
    if ([_sizes count] == 0) {
        for (size_t i = 0; i < sizeof(DefaultSizes) / sizeof(DefaultSizes[0]); i++)
            [sides addObject: @(DefaultSizes[i])];
    } else {
        [sides setArray: _sizes];
    }
    NSMutableArray *entries = [NSMutableArray array];
    for (NSNumber *size in sides)
        [entries addObject: @[ size, @1 ]];
    // The same sizes at scale 2, for outputs with a scale factor.
    for (NSNumber *size in sides)
        if ([size intValue] * 2 <= MaxPixelSide)
            [entries addObject: @[ size, @2 ]];

    NSMutableArray *pixelData = [NSMutableArray array];
    size_t total = 0;
    for (NSArray *entry in entries) {
        int side = [entry[0] intValue] * [entry[1] intValue];
        NSData *pixels = [_display applicationIconPixelsOfSide: side];
        if (pixels == nil)
            return; // no application icon
        [pixelData addObject: pixels];
        total += [pixels length];
    }
    if (total == 0 || total > INT32_MAX)
        return;

    int fd = WaylandCreateAnonymousFile(total);
    if (fd < 0)
        return;
    void *memory = mmap(NULL, total, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (memory == MAP_FAILED) {
        close(fd);
        return;
    }
    size_t offset = 0;
    for (NSData *pixels in pixelData) {
        memcpy((uint8_t *) memory + offset, [pixels bytes], [pixels length]);
        offset += [pixels length];
    }
    munmap(memory, total);

    // libwayland duplicates the descriptor when it marshals the request.
    union wl_argument poolArgs[3] = {{.o = NULL}, {.h = fd}, {.i = (int32_t) total}};
    struct wl_proxy *pool = WaylandCreateObject(_display->_shm, WP_SHM_CREATE_POOL, &wl_shm_pool_interface,
                                                poolArgs, 0, nil);
    close(fd);

    union wl_argument noArgs[1] = {{.o = NULL}};
    _icon = WaylandCreateObject(_manager, WP_ICON_MANAGER_CREATE_ICON, &xdg_toplevel_icon_v1_interface,
                                noArgs, 0, nil);
    _buffers = [NSMutableArray new];
    offset = 0;
    for (NSUInteger i = 0; i < [entries count]; i++) {
        int32_t scale = [entries[i][1] intValue];
        int32_t side = [entries[i][0] intValue] * scale;
        union wl_argument bufferArgs[6] = {{.o = NULL}, {.i = (int32_t) offset}, {.i = side}, {.i = side},
                                           {.i = side * 4}, {.u = WP_SHM_FORMAT_ARGB8888}};
        struct wl_proxy *buffer = WaylandCreateObject(pool, WP_SHM_POOL_CREATE_BUFFER, &wl_buffer_interface,
                                                      bufferArgs, 0, nil);
        [_buffers addObject: [NSValue valueWithPointer: buffer]];
        union wl_argument addArgs[2] = {{.o = (struct wl_object *) buffer}, {.i = scale}};
        WaylandMarshal(_icon, WP_ICON_ADD_BUFFER, NULL, 0, addArgs);
        offset += [pixelData[i] length];
    }
    WaylandMarshal(pool, WP_SHM_POOL_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, noArgs);
}

- (void) applicationIconChanged {
    if (_manager == NULL)
        return;
    // The windows are given the new icon first: the old one is released when none uses it any more.
    struct wl_proxy *oldIcon = _icon;
    NSMutableArray *oldBuffers = _buffers;
    _icon = NULL;
    _buffers = nil;
    [self build];
    [_display updateWindowIcons];
    destroyIcon(oldIcon, oldBuffers);
    [oldBuffers release];
    [_display flush];
}

- (BOOL) applyToToplevel: (struct wl_proxy *) toplevel hadIcon: (BOOL *) hadIcon {
    if (_manager == NULL)
        return NO;
    if (!_built)
        [self build];
    if (_icon == NULL && !*hadIcon)
        return NO;
    union wl_argument args[2] = {{.o = (struct wl_object *) toplevel}, {.o = (struct wl_object *) _icon}};
    WaylandMarshal(_manager, WP_ICON_MANAGER_SET_ICON, NULL, 0, args);
    *hadIcon = _icon != NULL;
    return YES;
}

- (void) managerRemoved {
    destroyIcon(_icon, _buffers);
    _icon = NULL;
    [_buffers release];
    _buffers = nil;
    _built = NO;
    union wl_argument none[1] = {{.o = NULL}};
    if (_manager != NULL)
        WaylandMarshal(_manager, WP_ICON_MANAGER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, none);
    _manager = NULL;
}

@end
