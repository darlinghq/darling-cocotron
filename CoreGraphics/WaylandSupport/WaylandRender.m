/* Shared client support for Linux dma-buf, explicit synchronization and fifo.

   The protocol details come from the vendored XML in protocols/; no client stubs are used because
   the Darwin and Linux variadic ABIs differ. Every new-object request goes through
   WaylandMarshal() and every event through the backend's dispatcher. */

#import "WaylandRender.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

// Private interface between IOSurface.framework and the GPU APIs that use its memory directly.
// The declaration is local so the backends need no extra header search path; its layout must stay
// in step with src/frameworks/IOSurface/include/IOSurface/IOSurfacePriv.h.
typedef struct {
    uint32_t version;
    int fd;
    uint64_t size;
    uint64_t offset;
    uint32_t bytesPerRow;
} WaylandRenderDMABuf;
extern bool _IOSurfaceGetDMABuf(IOSurfaceRef surface, size_t planeIndex,
                                WaylandRenderDMABuf *buffer);

// The small part of the Linux DRM syncobj ABI used here. The ioctl numbers are encoded locally so
// the backends build even where the DRM headers are absent.
#define WP_DRM_IOC_NRBITS 8
#define WP_DRM_IOC_TYPEBITS 8
#define WP_DRM_IOC_SIZEBITS 14
#define WP_DRM_IOC_DIRBITS 2
#define WP_DRM_IOC_NRSHIFT 0
#define WP_DRM_IOC_TYPESHIFT (WP_DRM_IOC_NRSHIFT + WP_DRM_IOC_NRBITS)
#define WP_DRM_IOC_SIZESHIFT (WP_DRM_IOC_TYPESHIFT + WP_DRM_IOC_TYPEBITS)
#define WP_DRM_IOC_DIRSHIFT (WP_DRM_IOC_SIZESHIFT + WP_DRM_IOC_SIZEBITS)
#define WP_DRM_IOC(dir, type, nr, structure)                                                    \
    ((((size_t)(dir)) << WP_DRM_IOC_DIRSHIFT) | (((size_t)(type)) << WP_DRM_IOC_TYPESHIFT) |    \
     (((size_t)(nr)) << WP_DRM_IOC_NRSHIFT) |                                                  \
     (((size_t) sizeof(structure)) << WP_DRM_IOC_SIZESHIFT))
#define WP_DRM_IOC_READ 2
#define WP_DRM_IOC_WRITE 1
#define WP_DRM_IOWR(type, nr, structure) \
    WP_DRM_IOC(WP_DRM_IOC_READ | WP_DRM_IOC_WRITE, type, nr, structure)

typedef struct {
    uint32_t handle;
    uint32_t flags;
} WaylandRenderSyncobjCreate;
typedef struct {
    uint32_t handle;
    uint32_t flags;
    int32_t fd;
    uint32_t pad;
} WaylandRenderSyncobjHandle;
typedef struct {
    uint64_t handles;
    uint64_t points;
    int64_t timeout_nsec;
    uint32_t count_handles;
    uint32_t flags;
    uint32_t first_signaled;
    uint32_t pad;
    // Newer kernels added a deadline hint; include it so the ioctl size matches their ABI.
    int64_t deadline_nsec;
} WaylandRenderSyncobjWait;
typedef struct {
    uint32_t handle;
    uint32_t pad;
} WaylandRenderSyncobjDestroy;

#define WP_DRM_SYNCOBJ_HANDLE_TO_FD_FLAGS_EXPORT_SYNC_FILE (1u << 0)
#define WP_DRM_SYNCOBJ_CREATE_IOCTL WP_DRM_IOWR(0x64, 0xBF, WaylandRenderSyncobjCreate)
#define WP_DRM_SYNCOBJ_DESTROY_IOCTL WP_DRM_IOWR(0x64, 0xC0, WaylandRenderSyncobjDestroy)
#define WP_DRM_SYNCOBJ_HANDLE_TO_FD_IOCTL WP_DRM_IOWR(0x64, 0xC1, WaylandRenderSyncobjHandle)
#define WP_DRM_SYNCOBJ_TIMELINE_WAIT_IOCTL WP_DRM_IOWR(0x64, 0xCA, WaylandRenderSyncobjWait)

static NSValue *Key(void *pointer) {
    return [NSValue valueWithPointer: pointer];
}

static NSValue *SurfaceKey(struct wl_proxy *surface) {
    return Key(surface);
}

// The caller declares the layout of the IOSurface it will attach. Only the formats whose byte
// order matches that layout are offered; an advertised format in the other order would display
// its channels swapped.
static BOOL WaylandRenderFormatUsable(uint32_t candidate, BOOL needsAlpha,
                                      WaylandRenderPixelFormat pixelFormat) {
    if (pixelFormat == WaylandRenderPixelFormatFloat16) {
        if (needsAlpha)
            return candidate == WP_DRM_FORMAT_ARGB16161616F;
        return candidate == WP_DRM_FORMAT_XRGB16161616F ||
               candidate == WP_DRM_FORMAT_ARGB16161616F;
    }
    if (needsAlpha)
        return candidate == WP_DRM_FORMAT_ARGB8888;
    return candidate == WP_DRM_FORMAT_XRGB8888 || candidate == WP_DRM_FORMAT_ARGB8888;
}

static size_t WaylandRenderCandidates(BOOL needsAlpha, WaylandRenderPixelFormat pixelFormat,
                                      uint32_t candidates[2]) {
    size_t count = 0;
    if (pixelFormat == WaylandRenderPixelFormatFloat16) {
        if (needsAlpha)
            candidates[count++] = WP_DRM_FORMAT_ARGB16161616F;
        else {
            candidates[count++] = WP_DRM_FORMAT_XRGB16161616F;
            candidates[count++] = WP_DRM_FORMAT_ARGB16161616F;
        }
    } else {
        if (needsAlpha)
            candidates[count++] = WP_DRM_FORMAT_ARGB8888;
        else {
            candidates[count++] = WP_DRM_FORMAT_XRGB8888;
            candidates[count++] = WP_DRM_FORMAT_ARGB8888;
        }
    }
    return count;
}

// A format table entry, packed as the protocol defines it: 32-bit DRM format, 32 bits of
// padding, then a 64-bit modifier. The padding is part of the 16-byte entry.
typedef struct __attribute__((packed)) {
    uint32_t format;
    uint32_t padding;
    uint64_t modifier;
} WaylandRenderTableEntry;

@interface WaylandRenderFeedback : NSObject {
@public
    NSData *_table;
    NSMutableArray *_tranches;       // arrays of NSNumber table indices, in preference order
    NSMutableArray *_currentTranche;
    BOOL _done;
}
@end

@implementation WaylandRenderFeedback

- (instancetype) init {
    if ((self = [super init]) != nil) {
        _tranches = [NSMutableArray new];
        _currentTranche = [NSMutableArray new];
    }
    return self;
}

- (void) dealloc {
    [_table release];
    [_tranches release];
    [_currentTranche release];
    [super dealloc];
}

- (WaylandRenderFormat) entryAtIndex: (uint16_t) index {
    WaylandRenderFormat result = {0, WP_DRM_FORMAT_MOD_INVALID};
    if (_table == nil || index >= [_table length] / sizeof(WaylandRenderTableEntry))
        return result;
    WaylandRenderTableEntry entry;
    memcpy(&entry, (const uint8_t *) [_table bytes] + (size_t) index * sizeof(entry), sizeof(entry));
    result.format = entry.format;
    result.modifier = entry.modifier;
    return result;
}

@end

// The fifo and explicit-synchronization objects belong to a wl_surface. The syncobj surface must
// be destroyed before a buffer without explicit synchronization can be committed to that surface.
@interface WaylandRenderSurface : NSObject {
@public
    struct wl_proxy *_feedback;
    struct wl_proxy *_fifo;
    struct wl_proxy *_syncobjSurface;
    BOOL _barrierActive;
}
@end

@implementation WaylandRenderSurface

- (void) dealloc {
    if (_feedback != NULL)
        WL.wl_proxy_destroy(_feedback);
    if (_fifo != NULL)
        WL.wl_proxy_destroy(_fifo);
    if (_syncobjSurface != NULL)
        WL.wl_proxy_destroy(_syncobjSurface);
    [super dealloc];
}

@end

// The protocol strongly recommends a separate timeline for each buffer: release points on one
// timeline may be signalled out of order when several buffers use it.
@interface WaylandRenderBuffer : NSObject {
@public
    struct wl_proxy *_timeline;
    int _deviceFD;
    int _timelineFD;
    uint32_t _handle;
    uint64_t _acquirePoint;
    uint64_t _releasePoint;
    BOOL _failed;
}
@end

@implementation WaylandRenderBuffer

- (instancetype) init {
    if ((self = [super init]) != nil)
        _deviceFD = _timelineFD = -1;
    return self;
}

- (void) dealloc {
    if (_timeline != NULL)
        WL.wl_proxy_destroy(_timeline);
    if (_timelineFD >= 0)
        close(_timelineFD);
    if (_handle != 0 && _deviceFD >= 0) {
        WaylandRenderSyncobjDestroy destroy = {_handle, 0};
        ioctl(_deviceFD, WP_DRM_SYNCOBJ_DESTROY_IOCTL, &destroy);
    }
    if (_deviceFD >= 0)
        close(_deviceFD);
    [super dealloc];
}

@end

// Opens the first available DRM render node and exports a timeline syncobj. Returns NO on a host
// without a render node or without syncobj support; the caller then uses implicit synchronization.
static BOOL CreateTimeline(int *deviceFD, int *timelineFD, uint32_t *handle) {
    *deviceFD = *timelineFD = -1;
    *handle = 0;
    int fd = -1;
    for (int n = 128; n < 256; n++) {
        char path[64];
        snprintf(path, sizeof(path), "/dev/dri/renderD%d", n);
        fd = open(path, O_RDWR | O_CLOEXEC);
        if (fd >= 0)
            break;
    }
    if (fd < 0)
        return NO;

    WaylandRenderSyncobjCreate create = {0, 0};
    if (ioctl(fd, WP_DRM_SYNCOBJ_CREATE_IOCTL, &create) != 0 || create.handle == 0) {
        close(fd);
        return NO;
    }
    WaylandRenderSyncobjHandle export = {create.handle,
                                         WP_DRM_SYNCOBJ_HANDLE_TO_FD_FLAGS_EXPORT_SYNC_FILE,
                                         -1, 0};
    if (ioctl(fd, WP_DRM_SYNCOBJ_HANDLE_TO_FD_IOCTL, &export) != 0 || export.fd < 0) {
        WaylandRenderSyncobjDestroy destroy = {create.handle, 0};
        ioctl(fd, WP_DRM_SYNCOBJ_DESTROY_IOCTL, &destroy);
        close(fd);
        return NO;
    }
    fcntl(export.fd, F_SETFD, FD_CLOEXEC);
    *deviceFD = fd;
    *timelineFD = export.fd;
    *handle = create.handle;
    return YES;
}

@implementation WaylandRenderManager

- (instancetype) initWithDispatcher: (wl_dispatcher_func_t) dispatcher {
    if ((self = [super init]) != nil) {
        _dispatcher = dispatcher;
        _feedbacks = [NSMutableDictionary new];
        _feedbackOwners = [NSMutableDictionary new];
        _legacyFormats = [NSMutableArray new];
        _legacyModifiers = [NSMutableArray new];
        _surfaceObjects = [NSMutableDictionary new];
        _buffers = [NSMutableDictionary new];
        _params = [NSMutableDictionary new];
    }
    return self;
}

- (void) dealloc {
    [self shutdown];
    [_feedbacks release];
    [_feedbackOwners release];
    [_legacyFormats release];
    [_legacyModifiers release];
    [_surfaceObjects release];
    [_buffers release];
    [_params release];
    [super dealloc];
}

- (void) shutdown {
    for (NSValue *key in [_buffers allKeys]) {
        WaylandRenderBuffer *buffer = [_buffers objectForKey: key];
        if (buffer->_timeline != NULL) {
            if (_syncobjManager != NULL)
                WaylandMarshal(buffer->_timeline, WP_SYNCOBJ_TIMELINE_DESTROY,
                               NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
            buffer->_timeline = NULL;
        }
        [_buffers removeObjectForKey: key];
    }

    for (NSValue *key in _surfaceObjects) {
        WaylandRenderSurface *state = [_surfaceObjects objectForKey: key];
        if (state->_feedback != NULL) {
            if (_dmabuf != NULL)
                WaylandMarshal(state->_feedback, WP_DMABUF_FEEDBACK_DESTROY,
                               NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
            state->_feedback = NULL;
        }
        if (state->_fifo != NULL) {
            if (_fifoManager != NULL)
                WaylandMarshal(state->_fifo, WP_FIFO_DESTROY,
                               NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
            state->_fifo = NULL;
        }
        if (state->_syncobjSurface != NULL) {
            if (_syncobjManager != NULL)
                WaylandMarshal(state->_syncobjSurface, WP_SYNCOBJ_SURFACE_DESTROY,
                               NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
            state->_syncobjSurface = NULL;
        }
    }
    [_surfaceObjects removeAllObjects];

    if (_defaultFeedback != NULL) {
        if (_dmabuf != NULL)
            WaylandMarshal(_defaultFeedback, WP_DMABUF_FEEDBACK_DESTROY,
                           NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        _defaultFeedback = NULL;
    }
    [_feedbacks removeAllObjects];
    [_feedbackOwners removeAllObjects];
    [_legacyFormats removeAllObjects];
    [_legacyModifiers removeAllObjects];
    // create_immed has no success event, so params objects are kept until failure or teardown.
    NSArray *paramsKeys = [[_params allKeys] copy];
    for (NSValue *key in paramsKeys)
        [self destroyParams: (struct wl_proxy *) [key pointerValue]];
    [paramsKeys release];
    if (_dmabuf != NULL)
        WaylandMarshal(_dmabuf, WP_DMABUF_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    if (_syncobjManager != NULL)
        WaylandMarshal(_syncobjManager, WP_SYNCOBJ_MANAGER_DESTROY, NULL,
                       WL_MARSHAL_FLAG_DESTROY, NULL);
    if (_fifoManager != NULL)
        WaylandMarshal(_fifoManager, WP_FIFO_MANAGER_DESTROY, NULL,
                       WL_MARSHAL_FLAG_DESTROY, NULL);
    _dmabuf = _syncobjManager = _fifoManager = NULL;
    _dmabufVersion = _dmabufName = _syncobjManagerName = _fifoManagerName = 0;
}

// Releases a params object and forgets the buffer it was creating. The protocol lets the object
// stay alive after create_immed; keeping it lets the failure event still reach its dispatcher.
- (void) destroyParams: (struct wl_proxy *) params {
    if (params == NULL)
        return;
    [_params removeObjectForKey: Key(params)];
    if (_dmabuf != NULL)
        WaylandMarshal(params, WP_DMABUF_PARAMS_DESTROY, NULL,
                       WL_MARSHAL_FLAG_DESTROY, NULL);
    else
        WL.wl_proxy_destroy(params);
}

- (void) bindDMABuf: (struct wl_proxy *) proxy version: (uint32_t) version name: (uint32_t) name {
    _dmabuf = proxy;
    _dmabufVersion = version;
    _dmabufName = name;
    WL.wl_proxy_add_dispatcher(_dmabuf, _dispatcher,
                               (void *) (uintptr_t) WaylandRenderObjectManager, self);
    if (version >= 4) {
        union wl_argument args[1] = {{.o = NULL}};
        _defaultFeedback =
                WaylandMarshal(_dmabuf, WP_DMABUF_GET_DEFAULT_FEEDBACK,
                               &zwp_linux_dmabuf_feedback_v1_interface, 0, args);
        if (_defaultFeedback != NULL) {
            id owner = [NSNull null];
            [_feedbackOwners setObject: owner forKey: Key(_defaultFeedback)];
            WL.wl_proxy_add_dispatcher(_defaultFeedback, _dispatcher,
                                       (void *) (uintptr_t) WaylandRenderObjectFeedback, self);
        }
    }
}

- (void) bindSyncobjManager: (struct wl_proxy *) proxy name: (uint32_t) name {
    _syncobjManager = proxy;
    _syncobjManagerName = name;
}

- (void) bindFifoManager: (struct wl_proxy *) proxy name: (uint32_t) name {
    _fifoManager = proxy;
    _fifoManagerName = name;
}

- (void) globalRemoved: (uint32_t) name {
    if (name == 0)
        return;
    if (name == _dmabufName) {
        _dmabuf = NULL;
        _dmabufName = _dmabufVersion = 0;
        if (_defaultFeedback != NULL)
            WL.wl_proxy_destroy(_defaultFeedback);
        _defaultFeedback = NULL;
        // The global already destroyed its children; release our proxies without further requests.
        NSArray *paramsKeys = [[_params allKeys] copy];
        for (NSValue *key in paramsKeys)
            [self destroyParams: (struct wl_proxy *) [key pointerValue]];
        [paramsKeys release];
        [_feedbacks removeAllObjects];
        [_feedbackOwners removeAllObjects];
        [_legacyFormats removeAllObjects];
        [_legacyModifiers removeAllObjects];
        // Existing dma-buf buffers can no longer be checked against a format table.
        for (NSValue *key in [_buffers allKeys]) {
            WaylandRenderBuffer *buffer = [_buffers objectForKey: key];
            buffer->_failed = YES;
        }
        for (NSValue *key in _surfaceObjects) {
            WaylandRenderSurface *state = [_surfaceObjects objectForKey: key];
            if (state->_feedback != NULL)
                WL.wl_proxy_destroy(state->_feedback);
            state->_feedback = NULL;
        }
    }
    if (name == _syncobjManagerName) {
        _syncobjManager = NULL;
        _syncobjManagerName = 0;
        for (NSValue *key in _surfaceObjects) {
            WaylandRenderSurface *state = [_surfaceObjects objectForKey: key];
            if (state->_syncobjSurface != NULL)
                WL.wl_proxy_destroy(state->_syncobjSurface);
            state->_syncobjSurface = NULL;
        }
        for (NSValue *key in [_buffers allKeys]) {
            WaylandRenderBuffer *buffer = [_buffers objectForKey: key];
            if (buffer->_timeline != NULL)
                WL.wl_proxy_destroy(buffer->_timeline);
            buffer->_timeline = NULL;
            // Without a timeline there is no release notification for a dma-buf buffer.
            buffer->_failed = YES;
        }
    }
    if (name == _fifoManagerName) {
        _fifoManager = NULL;
        _fifoManagerName = 0;
        for (NSValue *key in _surfaceObjects) {
            WaylandRenderSurface *state = [_surfaceObjects objectForKey: key];
            if (state->_fifo != NULL)
                WL.wl_proxy_destroy(state->_fifo);
            state->_fifo = NULL;
            state->_barrierActive = NO;
        }
    }
}

- (WaylandRenderSurface *) stateForSurface: (struct wl_proxy *) surface create: (BOOL) create {
    if (surface == NULL)
        return nil;
    NSValue *key = SurfaceKey(surface);
    WaylandRenderSurface *state = [_surfaceObjects objectForKey: key];
    if (state == nil && create) {
        state = [WaylandRenderSurface new];
        [_surfaceObjects setObject: state forKey: key];
        [state release];
    }
    return state;
}

- (void) observeSurface: (struct wl_proxy *) surface {
    WaylandRenderSurface *state = [self stateForSurface: surface create: YES];
    if (state == nil || state->_feedback != NULL || _dmabuf == NULL || _dmabufVersion < 4)
        return;
    union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) surface}};
    struct wl_proxy *feedback =
            WaylandMarshal(_dmabuf, WP_DMABUF_GET_SURFACE_FEEDBACK,
                           &zwp_linux_dmabuf_feedback_v1_interface, 0, args);
    if (feedback == NULL)
        return;
    NSValue *owner = SurfaceKey(surface);
    [_feedbackOwners setObject: owner forKey: Key(feedback)];
    WL.wl_proxy_add_dispatcher(feedback, _dispatcher,
                               (void *) (uintptr_t) WaylandRenderObjectFeedback, self);
    state->_feedback = feedback;
}

- (void) destroySurface: (struct wl_proxy *) surface {
    if (surface == NULL)
        return;
    NSValue *key = SurfaceKey(surface);
    WaylandRenderSurface *state = [_surfaceObjects objectForKey: key];
    if (state != nil) {
        if (state->_feedback != NULL) {
            [_feedbackOwners removeObjectForKey: Key(state->_feedback)];
            if (_dmabuf != NULL)
                WaylandMarshal(state->_feedback, WP_DMABUF_FEEDBACK_DESTROY,
                               NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
            state->_feedback = NULL;
        }
        if (state->_fifo != NULL) {
            if (_fifoManager != NULL)
                WaylandMarshal(state->_fifo, WP_FIFO_DESTROY,
                               NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
            state->_fifo = NULL;
        }
        if (state->_syncobjSurface != NULL) {
            if (_syncobjManager != NULL)
                WaylandMarshal(state->_syncobjSurface, WP_SYNCOBJ_SURFACE_DESTROY,
                               NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
            state->_syncobjSurface = NULL;
        }
    }
    [_feedbacks removeObjectForKey: key];
    [_surfaceObjects removeObjectForKey: key];
}

- (WaylandRenderFeedback *) completedFeedbackForSurface: (struct wl_proxy *) surface {
    WaylandRenderFeedback *feedback = [_feedbacks objectForKey: SurfaceKey(surface)];
    if (feedback != nil && feedback->_done)
        return feedback;
    feedback = [_feedbacks objectForKey: [NSNull null]];
    return feedback != nil && feedback->_done ? feedback : nil;
}

- (BOOL) supportsFormat: (uint32_t) format modifier: (uint64_t) modifier
              forSurface: (struct wl_proxy *) surface
{
    if (format == 0)
        return NO;
    WaylandRenderFeedback *feedback = [self completedFeedbackForSurface: surface];
    if (feedback == nil) {
        // Without a completed v4 feedback, only the legacy format events describe what the
        // compositor accepts. No events at all means the compositor has no dma-buf support.
        if (_dmabufVersion >= 4 || [_legacyFormats count] == 0)
            return NO;
        BOOL formatKnown = [_legacyFormats count] == 0;
        for (NSNumber *value in _legacyFormats)
            if ([value unsignedIntValue] == format)
                formatKnown = YES;
        BOOL modifierKnown = [_legacyModifiers count] == 0;
        for (NSNumber *value in _legacyModifiers) {
            uint64_t reported = [value unsignedLongLongValue];
            if (reported == modifier || reported == WP_DRM_FORMAT_MOD_INVALID)
                modifierKnown = YES;
        }
        return formatKnown && modifierKnown;
    }

    for (NSArray *tranche in feedback->_tranches) {
        for (NSNumber *index in tranche) {
            WaylandRenderFormat pair = [feedback entryAtIndex: [index unsignedShortValue]];
            if (pair.format == format &&
                (pair.modifier == modifier || pair.modifier == WP_DRM_FORMAT_MOD_INVALID))
                return YES;
        }
    }
    return NO;
}

- (BOOL) preferredFormat: (uint32_t *) format modifier: (uint64_t *) modifier
              forSurface: (struct wl_proxy *) surface
              needsAlpha: (BOOL) needsAlpha
             pixelFormat: (WaylandRenderPixelFormat) pixelFormat
{
    WaylandRenderFeedback *feedback = [self completedFeedbackForSurface: surface];
    if (feedback != nil) {
        for (NSArray *tranche in feedback->_tranches) {
            for (NSNumber *index in tranche) {
                WaylandRenderFormat pair = [feedback entryAtIndex: [index unsignedShortValue]];
                if (WaylandRenderFormatUsable(pair.format, needsAlpha, pixelFormat) &&
                    (pair.modifier == WP_DRM_FORMAT_MOD_LINEAR ||
                     pair.modifier == WP_DRM_FORMAT_MOD_INVALID)) {
                    *format = pair.format;
                    *modifier = WP_DRM_FORMAT_MOD_LINEAR;
                    return YES;
                }
            }
        }
        return NO;
    }
    uint32_t candidates[2];
    size_t count = WaylandRenderCandidates(needsAlpha, pixelFormat, candidates);
    for (size_t i = 0; i < count; i++)
        if (WaylandRenderFormatUsable(candidates[i], needsAlpha, pixelFormat) &&
            [self supportsFormat: candidates[i] modifier: WP_DRM_FORMAT_MOD_LINEAR
                      forSurface: surface]) {
            *format = candidates[i];
            *modifier = WP_DRM_FORMAT_MOD_LINEAR;
            return YES;
        }
    return NO;
}

- (struct wl_proxy *) newBufferForIOSurface: (IOSurfaceRef) surface
                                     format: (uint32_t) format
                                   modifier: (uint64_t) modifier
                                  forSurface: (struct wl_proxy *) target
                                      width: (int32_t) width
                                     height: (int32_t) height
                                     offset: (uint32_t) offset
                                     stride: (uint32_t) stride
{
    if (_dmabuf == NULL || surface == NULL || width <= 0 || height <= 0 || stride == 0)
        return NULL;
    // create_immed, added in version 4, returns the wl_buffer with the request. Older versions
    // answer asynchronously with a created event; callers fall back to shm instead.
    if (_dmabufVersion < 4 || ![self supportsFormat: format modifier: modifier forSurface: target])
        return NULL;

    WaylandRenderDMABuf dmabuf = {.version = 1};
    if (!_IOSurfaceGetDMABuf(surface, 0, &dmabuf) || dmabuf.fd < 0)
        return NULL;
    // The descriptor belongs to the IOSurface. libwayland duplicates descriptors it marshals, so
    // pass a private copy and leave the surface's descriptor alone.
    int fd = dup(dmabuf.fd);
    if (fd < 0)
        return NULL;

    union wl_argument args[1] = {{.o = NULL}};
    struct wl_proxy *params = WaylandMarshal(_dmabuf, WP_DMABUF_CREATE_PARAMS,
                                             &zwp_linux_buffer_params_v1_interface, 0, args);
    if (params == NULL) {
        close(fd);
        return NULL;
    }
    WL.wl_proxy_add_dispatcher(params, _dispatcher,
                               (void *) (uintptr_t) WaylandRenderObjectParams, self);
    // IOSurface can round the row stride up; the compositor must get the stride of the exported
    // memory, not the tight stride of the CPU copy.
    uint32_t rowStride = dmabuf.bytesPerRow != 0 ? dmabuf.bytesPerRow : stride;
    union wl_argument plane[6] = {
        {.h = fd}, {.u = 0}, {.u = (uint32_t) (dmabuf.offset + offset)},
        {.u = rowStride}, {.u = (uint32_t) (modifier >> 32)}, {.u = (uint32_t) modifier},
    };
    WaylandMarshal(params, WP_DMABUF_PARAMS_ADD, NULL, 0, plane);
    close(fd);

    union wl_argument create[5] = {
        {.o = NULL}, {.i = width}, {.i = height}, {.u = format}, {.u = 0},
    };
    struct wl_proxy *buffer =
            WaylandMarshal(params, WP_DMABUF_PARAMS_CREATE_IMMED, &wl_buffer_interface, 0, create);
    if (buffer == NULL) {
        [self destroyParams: params];
        return NULL;
    }

    WaylandRenderBuffer *state = [WaylandRenderBuffer new];
    if (state == nil) {
        WL.wl_proxy_destroy(buffer);
        [self destroyParams: params];
        return NULL;
    }
    state->_releasePoint = 1;
    [_buffers setObject: state forKey: Key(buffer)];
    [state release];
    // create_immed has no success event; the params object stays alive so its failed event can
    // still be delivered. It is released on failure or when the manager shuts down.
    [_params setObject: Key(buffer) forKey: Key(params)];
    return buffer;
}

- (void) bufferDestroyed: (struct wl_proxy *) buffer {
    if (buffer == NULL)
        return;
    NSValue *key = Key(buffer);
    WaylandRenderBuffer *state = [_buffers objectForKey: key];
    if (state == nil)
        return;
    if (state->_timeline != NULL) {
        if (_syncobjManager != NULL)
            WaylandMarshal(state->_timeline, WP_SYNCOBJ_TIMELINE_DESTROY,
                           NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        state->_timeline = NULL;
    }
    [_buffers removeObjectForKey: key];
    NSArray *paramsKeys = [[_params allKeys] copy];
    for (NSValue *paramsKey in paramsKeys)
        if ([[_params objectForKey: paramsKey] isEqual: key])
            [self destroyParams: (struct wl_proxy *) [paramsKey pointerValue]];
    [paramsKeys release];
}

- (BOOL) bufferCreationFailed: (struct wl_proxy *) buffer {
    if (buffer == NULL)
        return NO;
    WaylandRenderBuffer *state = [_buffers objectForKey: Key(buffer)];
    return state != nil && state->_failed;
}

- (BOOL) ensureTimelineForBuffer: (WaylandRenderBuffer *) buffer {
    if (buffer->_timeline != NULL)
        return YES;
    if (_syncobjManager == NULL)
        return NO;
    int deviceFD = -1, timelineFD = -1;
    uint32_t handle = 0;
    if (!CreateTimeline(&deviceFD, &timelineFD, &handle))
        return NO;
    union wl_argument args[1] = {{.h = timelineFD}};
    struct wl_proxy *timeline =
            WaylandMarshal(_syncobjManager, WP_SYNCOBJ_MANAGER_IMPORT_TIMELINE,
                           &wp_linux_drm_syncobj_timeline_v1_interface, 0, args);
    if (timeline == NULL) {
        WaylandRenderSyncobjDestroy destroy = {handle, 0};
        ioctl(deviceFD, WP_DRM_SYNCOBJ_DESTROY_IOCTL, &destroy);
        close(timelineFD);
        close(deviceFD);
        return NO;
    }
    buffer->_timeline = timeline;
    buffer->_deviceFD = deviceFD;
    buffer->_timelineFD = timelineFD;
    buffer->_handle = handle;
    return YES;
}

- (BOOL) beginFrameForSurface: (struct wl_proxy *) surface buffer: (struct wl_proxy *) buffer {
    WaylandRenderSurface *state = [self stateForSurface: surface create: YES];
    if (state == nil)
        return NO;

    if (state->_fifo == NULL && _fifoManager != NULL) {
        union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) surface}};
        state->_fifo = WaylandMarshal(_fifoManager, WP_FIFO_MANAGER_GET_FIFO,
                                      &wp_fifo_v1_interface, 0, args);
    }
    if (state->_fifo != NULL) {
        if (state->_barrierActive)
            WaylandMarshal(state->_fifo, WP_FIFO_WAIT_BARRIER, NULL, 0, NULL);
        WaylandMarshal(state->_fifo, WP_FIFO_SET_BARRIER, NULL, 0, NULL);
        state->_barrierActive = YES;
    }

    WaylandRenderBuffer *bufferState = [_buffers objectForKey: Key(buffer)];
    if (bufferState == nil || bufferState->_failed ||
        ![self ensureTimelineForBuffer: bufferState]) {
        // Explicit synchronization only applies to buffers that have a timeline. A syncobj surface
        // left alive would make later implicit-synchronization commits invalid.
        if (state->_syncobjSurface != NULL) {
            WaylandMarshal(state->_syncobjSurface, WP_SYNCOBJ_SURFACE_DESTROY,
                           NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
            state->_syncobjSurface = NULL;
        }
        return NO;
    }
    if (state->_syncobjSurface == NULL) {
        union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) surface}};
        state->_syncobjSurface =
                WaylandMarshal(_syncobjManager, WP_SYNCOBJ_MANAGER_GET_SURFACE,
                               &wp_linux_drm_syncobj_surface_v1_interface, 0, args);
    }
    if (state->_syncobjSurface == NULL)
        return NO;

    // The buffer's contents are ready before the commit, so acquire its previous release point;
    // the compositor signals the next point when it is done with this commit's buffer.
    union wl_argument acquire[3] = {
        {.o = (struct wl_object *) bufferState->_timeline},
        {.u = (uint32_t) (bufferState->_acquirePoint >> 32)},
        {.u = (uint32_t) bufferState->_acquirePoint},
    };
    WaylandMarshal(state->_syncobjSurface, WP_SYNCOBJ_SURFACE_SET_ACQUIRE_POINT, NULL, 0, acquire);
    bufferState->_releasePoint++;
    union wl_argument release[3] = {
        {.o = (struct wl_object *) bufferState->_timeline},
        {.u = (uint32_t) (bufferState->_releasePoint >> 32)},
        {.u = (uint32_t) bufferState->_releasePoint},
    };
    WaylandMarshal(state->_syncobjSurface, WP_SYNCOBJ_SURFACE_SET_RELEASE_POINT, NULL, 0, release);
    bufferState->_acquirePoint = bufferState->_releasePoint;
    return YES;
}

- (BOOL) releasePointSignalledForBuffer: (struct wl_proxy *) buffer {
    WaylandRenderBuffer *state = [_buffers objectForKey: Key(buffer)];
    if (state == nil || state->_failed || state->_timelineFD < 0 ||
        state->_deviceFD < 0 || state->_handle == 0)
        return NO;
    WaylandRenderSyncobjWait wait = {
        .handles = state->_handle,
        .points = state->_releasePoint,
        .count_handles = 1,
    };
    return ioctl(state->_deviceFD, WP_DRM_SYNCOBJ_TIMELINE_WAIT_IOCTL, &wait) == 0;
}

#pragma mark - Events

- (void) handleEvent: (uint32_t) opcode
                kind: (WaylandRenderObjectKind) kind
               proxy: (struct wl_proxy *) proxy
           arguments: (union wl_argument *) args
{
    if (kind == WaylandRenderObjectManager) {
        if (opcode == WP_DMABUF_EV_FORMAT)
            [_legacyFormats addObject: [NSNumber numberWithUnsignedInt: args[0].u]];
        else if (opcode == WP_DMABUF_EV_MODIFIER) {
            uint64_t modifier = ((uint64_t) args[0].u << 32) | args[1].u;
            [_legacyModifiers addObject: [NSNumber numberWithUnsignedLongLong: modifier]];
        }
        return;
    }
    if (kind == WaylandRenderObjectParams) {
        if (opcode == WP_DMABUF_PARAMS_EV_FAILED) {
            NSValue *bufferKey = [_params objectForKey: Key(proxy)];
            if (bufferKey != nil) {
                WaylandRenderBuffer *state = [_buffers objectForKey: bufferKey];
                if (state != nil)
                    state->_failed = YES;
            }
            [self destroyParams: proxy];
        }
        return;
    }
    if (kind != WaylandRenderObjectFeedback)
        return;

    NSValue *owner = [_feedbackOwners objectForKey: Key(proxy)];
    if (owner == nil)
        return;
    WaylandRenderFeedback *feedback = [_feedbacks objectForKey: owner];
    if (feedback == nil) {
        feedback = [WaylandRenderFeedback new];
        [_feedbacks setObject: feedback forKey: owner];
        [feedback release];
    }

    switch (opcode) {
    case WP_DMABUF_FEEDBACK_EV_FORMAT_TABLE: {
        int fd = args[0].h;
        uint32_t size = args[1].u;
        if (fd >= 0 && size >= sizeof(WaylandRenderTableEntry) &&
            size <= 4 * 1024 * 1024 && size % sizeof(WaylandRenderTableEntry) == 0) {
            void *data = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
            if (data != MAP_FAILED) {
                [feedback->_table release];
                feedback->_table = [[NSData alloc] initWithBytes: data length: size];
                munmap(data, size);
            }
        }
        if (fd >= 0)
            close(fd);
        break;
    }
    case WP_DMABUF_FEEDBACK_EV_MAIN_DEVICE:
    case WP_DMABUF_FEEDBACK_EV_TRANCHE_TARGET_DEVICE:
        // The device is a hint about which allocation device to use. IOSurface's DMA-BUF export
        // goes through the host allocator, which cannot select one; the fd still belongs to us.
        if (args[0].h >= 0)
            close(args[0].h);
        if (opcode == WP_DMABUF_FEEDBACK_EV_TRANCHE_TARGET_DEVICE)
            [feedback->_currentTranche removeAllObjects];
        break;
    case WP_DMABUF_FEEDBACK_EV_TRANCHE_FORMATS: {
        struct wl_array *indices = args[0].a;
        if (indices != NULL) {
            const uint8_t *bytes = (const uint8_t *) indices->data;
            // wl_array data is not guaranteed to be aligned for uint16_t, so copy each index.
            for (size_t i = 0; i + sizeof(uint16_t) <= indices->size; i += sizeof(uint16_t)) {
                uint16_t index;
                memcpy(&index, bytes + i, sizeof(index));
                [feedback->_currentTranche addObject: [NSNumber numberWithUnsignedShort: index]];
            }
        }
        break;
    }
    case WP_DMABUF_FEEDBACK_EV_TRANCHE_FLAGS:
        // Scan-out and sampling flags only rank tranches; this client can use every tranche.
        break;
    case WP_DMABUF_FEEDBACK_EV_TRANCHE_DONE:
        if ([feedback->_currentTranche count] > 0)
            [feedback->_tranches addObject: [NSArray arrayWithArray: feedback->_currentTranche]];
        [feedback->_currentTranche removeAllObjects];
        break;
    case WP_DMABUF_FEEDBACK_EV_DONE:
        feedback->_done = YES;
        break;
    default:
        break;
    }
}

@end
