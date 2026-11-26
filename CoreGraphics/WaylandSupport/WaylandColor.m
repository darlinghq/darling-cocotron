/* Wayland color-management and color-representation client support shared by the
   CoreGraphics and AppKit Wayland backends.

   Permission is hereby granted, free of charge, to any person obtaining a copy of
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

#import "WaylandColor.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import <Foundation/NSData.h>

#include <errno.h>
#include <unistd.h>

static NSValue *Key(struct wl_proxy *proxy) {
    return [NSValue valueWithPointer: proxy];
}

static struct wl_proxy *NewObject(struct wl_proxy *parent, uint32_t opcode,
                                  const struct wl_interface *interface,
                                  uint32_t flags, union wl_argument *args)
{
    return WaylandMarshal(parent, opcode, interface, flags, args);
}

static void SendDestroy(struct wl_proxy *proxy, uint32_t opcode) {
    if (proxy == NULL)
        return;
    WaylandMarshal(proxy, opcode, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
}

// Named color spaces map directly onto the protocol's named primaries and
// transfer functions. A space that has no such pair is described by its ICC
// profile when the compositor supports one.
static BOOL ColorSpaceDescription(CGColorSpaceRef space, uint32_t *primaries, uint32_t *transferFunction) {
    if (space == NULL)
        return NO;
    CFStringRef name = CGColorSpaceGetName(space);
    if (name == NULL)
        return NO;

    if (CFEqual(name, kCGColorSpaceSRGB) || CFEqual(name, kCGColorSpaceGenericRGB) ||
        CFEqual(name, kCGColorSpaceITUR_709) || CFEqual(name, kCGColorSpaceGenericGray)) {
        *primaries = WP_COLOR_PRIMARIES_SRGB;
        *transferFunction = WP_COLOR_TF_SRGB;
        return YES;
    }
    if (CFEqual(name, kCGColorSpaceGenericGrayGamma2_2)) {
        *primaries = WP_COLOR_PRIMARIES_SRGB;
        *transferFunction = WP_COLOR_TF_GAMMA22;
        return YES;
    }
    if (CFEqual(name, kCGColorSpaceExtendedSRGB)) {
        *primaries = WP_COLOR_PRIMARIES_SRGB;
        *transferFunction = WP_COLOR_TF_EXT_SRGB;
        return YES;
    }
    if (CFEqual(name, kCGColorSpaceLinearSRGB) || CFEqual(name, kCGColorSpaceGenericRGBLinear) ||
        CFEqual(name, kCGColorSpaceExtendedLinearSRGB)) {
        *primaries = WP_COLOR_PRIMARIES_SRGB;
        *transferFunction = WP_COLOR_TF_EXT_LINEAR;
        return YES;
    }
    if (CFEqual(name, kCGColorSpaceDisplayP3) || CFEqual(name, kCGColorSpaceExtendedDisplayP3)) {
        *primaries = WP_COLOR_PRIMARIES_DISPLAY_P3;
        *transferFunction = CFEqual(name, kCGColorSpaceExtendedDisplayP3)
                            ? WP_COLOR_TF_EXT_SRGB : WP_COLOR_TF_SRGB;
        return YES;
    }
    if (CFEqual(name, kCGColorSpaceLinearDisplayP3) || CFEqual(name, kCGColorSpaceExtendedLinearDisplayP3)) {
        *primaries = WP_COLOR_PRIMARIES_DISPLAY_P3;
        *transferFunction = WP_COLOR_TF_EXT_LINEAR;
        return YES;
    }
    if (CFEqual(name, kCGColorSpaceDCIP3)) {
        *primaries = WP_COLOR_PRIMARIES_DCI_P3;
        *transferFunction = WP_COLOR_TF_SRGB;
        return YES;
    }
    if (CFEqual(name, kCGColorSpaceAdobeRGB1998)) {
        *primaries = WP_COLOR_PRIMARIES_ADOBE_RGB;
        *transferFunction = WP_COLOR_TF_SRGB;
        return YES;
    }
    if (CFEqual(name, kCGColorSpaceITUR_2020)) {
        *primaries = WP_COLOR_PRIMARIES_BT2020;
        *transferFunction = WP_COLOR_TF_SRGB;
        return YES;
    }
    if (CFEqual(name, kCGColorSpaceExtendedLinearITUR_2020)) {
        *primaries = WP_COLOR_PRIMARIES_BT2020;
        *transferFunction = WP_COLOR_TF_EXT_LINEAR;
        return YES;
    }
    if (CFEqual(name, kCGColorSpaceITUR_2100_PQ)) {
        *primaries = WP_COLOR_PRIMARIES_BT2020;
        *transferFunction = WP_COLOR_TF_ST2084_PQ;
        return YES;
    }
    if (CFEqual(name, kCGColorSpaceITUR_2100_HLG)) {
        *primaries = WP_COLOR_PRIMARIES_BT2020;
        *transferFunction = WP_COLOR_TF_HLG;
        return YES;
    }
    return NO;
}

@implementation WaylandColorManager

- (instancetype) initWithDispatcher: (wl_dispatcher_func_t) dispatcher owner: (id) owner
{
    if ((self = [super init]) == nil)
        return nil;
    _dispatcher = dispatcher;
    _owner = owner;
    _namedTransferFunctions = [NSMutableSet new];
    _namedPrimaries = [NSMutableSet new];
    _outputs = [NSMutableArray new];
    _outputObservers = [NSMutableDictionary new];
    _outputInfos = [NSMutableDictionary new];
    _pendingOutputDescriptions = [NSMutableDictionary new];
    _pendingSurfaceDescriptions = [NSMutableDictionary new];
    _pendingInfos = [NSMutableDictionary new];
    _pendingColorSpaces = [NSMutableDictionary new];
    _colorSurfaces = [NSMutableSet new];
    _representationSurfaces = [NSMutableSet new];
    _pendingRepresentationSurfaces = [NSMutableArray new];
    return self;
}

- (void) dealloc {
    [self shutdown];
    for (NSValue *space in [_pendingColorSpaces allValues]) {
        CGColorSpaceRef colorSpace = (CGColorSpaceRef) [space pointerValue];
        if (colorSpace != NULL)
            CGColorSpaceRelease(colorSpace);
    }
    [_namedTransferFunctions release];
    [_namedPrimaries release];
    [_outputs release];
    [_outputObservers release];
    [_outputInfos release];
    [_pendingOutputDescriptions release];
    [_pendingSurfaceDescriptions release];
    [_pendingInfos release];
    [_pendingColorSpaces release];
    [_colorSurfaces release];
    [_representationSurfaces release];
    [_pendingRepresentationSurfaces release];
    [super dealloc];
}

- (void) shutdown {
    // The per-window surface proxies are owned by the windows; if one is still alive here,
    // sending a request for it would leave the window holding a destroyed proxy. The owner is
    // disconnecting, so dropping the bookkeeping is enough.
    [_colorSurfaces removeAllObjects];
    [_representationSurfaces removeAllObjects];
    // _outputObservers maps an wl_output proxy to the color output object created for it, so the
    // values, not the keys, are the proxies that accept WP_COLOR_OUTPUT_DESTROY.
    for (NSValue *proxy in [_outputObservers allValues])
        SendDestroy((struct wl_proxy *) [proxy pointerValue], WP_COLOR_OUTPUT_DESTROY);
    for (NSValue *proxy in _pendingOutputDescriptions)
        SendDestroy((struct wl_proxy *) [proxy pointerValue], WP_IMAGE_DESCRIPTION_DESTROY);
    for (NSValue *proxy in _pendingSurfaceDescriptions)
        SendDestroy((struct wl_proxy *) [proxy pointerValue], WP_IMAGE_DESCRIPTION_DESTROY);
    for (NSValue *proxy in _pendingInfos)
        WL.wl_proxy_destroy((struct wl_proxy *) [proxy pointerValue]);
    for (NSValue *space in [_pendingColorSpaces allValues]) {
        CGColorSpaceRef colorSpace = (CGColorSpaceRef) [space pointerValue];
        if (colorSpace != NULL)
            CGColorSpaceRelease(colorSpace);
    }
    if (_representationManager != NULL)
        SendDestroy(_representationManager, WP_COLOR_REP_MANAGER_DESTROY);
    if (_colorManager != NULL)
        SendDestroy(_colorManager, WP_COLOR_MANAGER_DESTROY);
    [_outputObservers removeAllObjects];
    [_pendingOutputDescriptions removeAllObjects];
    [_pendingSurfaceDescriptions removeAllObjects];
    [_pendingInfos removeAllObjects];
    [_pendingColorSpaces removeAllObjects];
    [_outputInfos removeAllObjects];
    [_namedTransferFunctions removeAllObjects];
    [_namedPrimaries removeAllObjects];
    [_pendingRepresentationSurfaces removeAllObjects];
    _featuresKnown = _parametricSupported = _iccSupported = NO;
    _representationKnown = NO;
    _alphaModes = 0;
    _colorManager = NULL;
    _colorManagerVersion = _colorManagerName = 0;
    _representationManager = NULL;
    _representationManagerName = 0;
}

- (void) attachDispatcher: (struct wl_proxy *) proxy kind: (WaylandColorObjectKind) kind {
    if (proxy != NULL)
        WL.wl_proxy_add_dispatcher(proxy, _dispatcher, (void *) (uintptr_t) kind, self);
}

#pragma mark - Globals and outputs

- (void) bindColorManager: (struct wl_proxy *) proxy
                  version: (uint32_t) version
                    name: (uint32_t) name
{
    _colorManager = proxy;
    _colorManagerVersion = version;
    _colorManagerName = name;

    // The registry does not promise an order: outputs seen before the global
    // arrived still need their descriptions.
    for (NSValue *output in _outputs)
        [self requestDescriptionForOutput: (struct wl_proxy *) [output pointerValue]];
}

- (void) bindRepresentationManager: (struct wl_proxy *) proxy
                           version: (uint32_t) version
                             name: (uint32_t) name
{
    (void) version;
    _representationManager = proxy;
    _representationManagerName = name;
}

// The color manager global is gone and the compositor has made its child objects inert. The
// output observers and descriptions are ours; the per-window surface proxies stay alive until
// their owners release them through -destroyColorSurface:.
- (void) colorManagerRemoved {
    for (NSValue *observer in [_outputObservers allValues])
        WL.wl_proxy_destroy((struct wl_proxy *) [observer pointerValue]);
    for (NSValue *description in _pendingOutputDescriptions)
        WL.wl_proxy_destroy((struct wl_proxy *) [description pointerValue]);
    for (NSValue *description in _pendingSurfaceDescriptions)
        WL.wl_proxy_destroy((struct wl_proxy *) [description pointerValue]);
    for (NSValue *information in _pendingInfos)
        WL.wl_proxy_destroy((struct wl_proxy *) [information pointerValue]);
    for (NSValue *space in [_pendingColorSpaces allValues]) {
        CGColorSpaceRef colorSpace = (CGColorSpaceRef) [space pointerValue];
        if (colorSpace != NULL)
            CGColorSpaceRelease(colorSpace);
    }
    if (_colorManager != NULL)
        WaylandMarshal(_colorManager, WP_COLOR_MANAGER_DESTROY,
                       NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    [_outputObservers removeAllObjects];
    [_pendingOutputDescriptions removeAllObjects];
    [_pendingSurfaceDescriptions removeAllObjects];
    [_pendingInfos removeAllObjects];
    [_pendingColorSpaces removeAllObjects];
    [_outputInfos removeAllObjects];
    [_colorSurfaces removeAllObjects];
    [_namedTransferFunctions removeAllObjects];
    [_namedPrimaries removeAllObjects];
    _featuresKnown = _parametricSupported = _iccSupported = NO;
    _colorManager = NULL;
    _colorManagerVersion = _colorManagerName = 0;
}

- (void) representationManagerRemoved {
    if (_representationManager != NULL)
        WaylandMarshal(_representationManager, WP_COLOR_REP_MANAGER_DESTROY,
                       NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    [_pendingRepresentationSurfaces removeAllObjects];
    [_representationSurfaces removeAllObjects];
    _representationManager = NULL;
    _representationManagerName = 0;
    _representationKnown = NO;
    _alphaModes = 0;
}

- (void) globalRemoved: (uint32_t) name {
    BOOL colorGone = name != 0 && name == _colorManagerName;
    BOOL representationGone = name != 0 && name == _representationManagerName;
    if (colorGone)
        [self colorManagerRemoved];
    if (representationGone)
        [self representationManagerRemoved];
    if ((colorGone || representationGone) &&
        [_owner respondsToSelector: @selector(waylandColorManagerDidLoseGlobal:)])
        [_owner waylandColorManagerDidLoseGlobal: self];
}

- (void) observeOutput: (struct wl_proxy *) output {
    NSValue *key = Key(output);
    if (output == NULL || [_outputs containsObject: key])
        return;
    [_outputs addObject: key];
    [self requestDescriptionForOutput: output];
}

- (void) requestDescriptionForOutput: (struct wl_proxy *) output {
    NSValue *key = Key(output);
    if (_colorManager == NULL || output == NULL ||
        [_outputObservers objectForKey: key] != nil)
        return;

    union wl_argument getOutput[2] = {{.o = NULL}, {.o = (struct wl_object *) output}};
    struct wl_proxy *managerOutput =
            NewObject(_colorManager, WP_COLOR_MANAGER_GET_OUTPUT,
                      &wp_color_management_output_v1_interface, 0, getOutput);
    if (managerOutput == NULL)
        return;
    [self attachDispatcher: managerOutput kind: WaylandColorObjectOutput];
    [_outputObservers setObject: [NSValue valueWithPointer: managerOutput] forKey: key];

    union wl_argument getDescription[1] = {{.o = NULL}};
    struct wl_proxy *description =
            NewObject(managerOutput, WP_COLOR_OUTPUT_GET_IMAGE_DESCRIPTION,
                      &wp_image_description_v1_interface, 0, getDescription);
    if (description == NULL)
        return;
    [self attachDispatcher: description kind: WaylandColorObjectImageDescription];
    [_pendingOutputDescriptions setObject: key forKey: Key(description)];
}

- (BOOL) hasColorGlobals {
    return _colorManager != NULL || _representationManager != NULL;
}

- (NSDictionary *) infoForOutput: (struct wl_proxy *) output {
    return output == NULL ? nil : [_outputInfos objectForKey: Key(output)];
}

#pragma mark - Surfaces

- (struct wl_proxy *) newColorSurfaceForSurface: (struct wl_proxy *) surface {
    if (_colorManager == NULL || surface == NULL)
        return NULL;
    union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) surface}};
    struct wl_proxy *proxy =
            NewObject(_colorManager, WP_COLOR_MANAGER_GET_SURFACE,
                      &wp_color_management_surface_v1_interface, 0, args);
    if (proxy == NULL)
        return NULL;
    [self attachDispatcher: proxy kind: WaylandColorObjectSurface];
    [_colorSurfaces addObject: Key(proxy)];
    return proxy;
}

- (struct wl_proxy *) newRepresentationSurfaceForSurface: (struct wl_proxy *) surface {
    if (_representationManager == NULL || surface == NULL)
        return NULL;
    union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) surface}};
    struct wl_proxy *proxy =
            NewObject(_representationManager, WP_COLOR_REP_MANAGER_GET_SURFACE,
                      &wp_color_representation_surface_v1_interface, 0, args);
    if (proxy == NULL)
        return NULL;
    [self attachDispatcher: proxy kind: WaylandColorObjectRepresentationSurface];
    NSValue *key = Key(proxy);
    [_representationSurfaces addObject: key];
    if (_representationKnown)
        [self applyRepresentationToSurface: proxy];
    else
        [_pendingRepresentationSurfaces addObject: key];
    return proxy;
}

- (void) destroyColorSurface: (struct wl_proxy *) proxy {
    if (proxy == NULL)
        return;
    NSValue *key = Key(proxy);
    NSValue *pendingSpace = [_pendingColorSpaces objectForKey: key];
    if (pendingSpace != NULL) {
        CGColorSpaceRef colorSpace = (CGColorSpaceRef) [pendingSpace pointerValue];
        if (colorSpace != NULL)
            CGColorSpaceRelease(colorSpace);
    }
    [_pendingColorSpaces removeObjectForKey: key];
    [_colorSurfaces removeObject: key];
    NSMutableArray *descriptions = [NSMutableArray array];
    for (NSValue *description in _pendingSurfaceDescriptions)
        if ([[_pendingSurfaceDescriptions objectForKey: description] isEqual: key]) {
            SendDestroy((struct wl_proxy *) [description pointerValue], WP_IMAGE_DESCRIPTION_DESTROY);
            [descriptions addObject: description];
        }
    [_pendingSurfaceDescriptions removeObjectsForKeys: descriptions];
    // After the manager global goes away the surface is inert; the destroy request would no
    // longer name a live object, so release only the local proxy in that case.
    if (_colorManager != NULL)
        SendDestroy(proxy, WP_COLOR_SURFACE_DESTROY);
    else
        WL.wl_proxy_destroy(proxy);
}

- (void) destroyRepresentationSurface: (struct wl_proxy *) proxy {
    if (proxy == NULL)
        return;
    NSValue *key = Key(proxy);
    [_pendingRepresentationSurfaces removeObject: key];
    [_representationSurfaces removeObject: key];
    if (_representationManager != NULL)
        SendDestroy(proxy, WP_COLOR_REP_SURFACE_DESTROY);
    else
        WL.wl_proxy_destroy(proxy);
}

- (void) setColorSpace: (CGColorSpaceRef) space onSurface: (struct wl_proxy *) surfaceManager {
    if (space == NULL || surfaceManager == NULL || _colorManager == NULL)
        return;
    NSValue *key = Key(surfaceManager);
    if (!_featuresKnown) {
        CGColorSpaceRetain(space);
        [_pendingColorSpaces setObject: [NSValue valueWithPointer: space] forKey: key];
        return;
    }
    [self createDescriptionForSpace: space surface: surfaceManager];
}

- (void) applyRepresentationToSurface: (struct wl_proxy *) proxy {
    // The CPU buffers are premultiplied sRGB values. The protocol's default is
    // premultiplied electrical, so saying so explicitly only matters when the
    // compositor asks the client to choose.
    if ((_alphaModes & (1u << WP_COLOR_ALPHA_PREMULTIPLIED_ELECTRICAL)) != 0) {
        union wl_argument alpha[1] = {{.u = WP_COLOR_ALPHA_PREMULTIPLIED_ELECTRICAL}};
        WaylandMarshal(proxy, WP_COLOR_REP_SURFACE_SET_ALPHA_MODE, NULL, 0, alpha);
    }
    // No coefficients and range are sent: the buffers contain RGB pixels, not
    // subsampled YUV data, and the protocol's defaults describe them correctly.
}

#pragma mark - Image descriptions

- (void) createDescriptionForSpace: (CGColorSpaceRef) space surface: (struct wl_proxy *) surface {
    uint32_t primaries = 0, transferFunction = 0;
    BOOL named = _parametricSupported &&
                 ColorSpaceDescription(space, &primaries, &transferFunction) &&
                 [_namedPrimaries containsObject: [NSNumber numberWithUnsignedInt: primaries]] &&
                 [_namedTransferFunctions containsObject: [NSNumber numberWithUnsignedInt: transferFunction]];

    struct wl_proxy *creator = NULL;
    uint32_t createOpcode = WP_COLOR_PARAMS_CREATE;

    if (named) {
        union wl_argument args[1] = {{.o = NULL}};
        creator = NewObject(_colorManager, WP_COLOR_MANAGER_CREATE_PARAMETRIC_CREATOR,
                            &wp_image_description_creator_params_v1_interface, 0, args);
        if (creator != NULL) {
            union wl_argument value[1] = {{.u = primaries}};
            WaylandMarshal(creator, WP_COLOR_PARAMS_SET_PRIMARIES_NAMED, NULL, 0, value);
            value[0].u = transferFunction;
            WaylandMarshal(creator, WP_COLOR_PARAMS_SET_TF_NAMED, NULL, 0, value);
        }
    } else if (_iccSupported) {
        CFDataRef profile = CGColorSpaceCopyICCProfile(space);
        size_t length = profile != NULL ? CFDataGetLength(profile) : 0;
        int fd = length > 0 ? WaylandCreateAnonymousFile(length) : -1;
        if (fd >= 0) {
            const uint8_t *bytes = CFDataGetBytePtr(profile);
            size_t written = 0;
            while (written < length) {
                ssize_t n = write(fd, bytes + written, length - written);
                if (n < 0 && errno == EINTR)
                    continue;
                if (n <= 0)
                    break;
                written += (size_t) n;
            }
            if (written == length) {
                union wl_argument args[1] = {{.o = NULL}};
                creator = NewObject(_colorManager, WP_COLOR_MANAGER_CREATE_ICC_CREATOR,
                                    &wp_image_description_creator_icc_v1_interface, 0, args);
                if (creator != NULL) {
                    union wl_argument icc[3] = {{.h = fd}, {.u = 0}, {.u = (uint32_t) length}};
                    WaylandMarshal(creator, WP_COLOR_ICC_CREATOR_SET_ICC_FILE, NULL, 0, icc);
                    createOpcode = WP_COLOR_ICC_CREATOR_CREATE;
                }
            }
            close(fd);
        }
        if (profile != NULL)
            CFRelease(profile);
    }
    if (creator == NULL)
        return;

    union wl_argument args[1] = {{.o = NULL}};
    struct wl_proxy *description =
            NewObject(creator, createOpcode, &wp_image_description_v1_interface,
                      WL_MARSHAL_FLAG_DESTROY, args);
    if (description == NULL)
        return;
    [self attachDispatcher: description kind: WaylandColorObjectImageDescription];
    [_pendingSurfaceDescriptions setObject: Key(surface) forKey: Key(description)];
}

- (void) handleReadyDescription: (struct wl_proxy *) description {
    NSValue *key = Key(description);
    NSValue *output = [_pendingOutputDescriptions objectForKey: key];
    NSValue *surface = [_pendingSurfaceDescriptions objectForKey: key];

    if (output != nil) {
        [_pendingOutputDescriptions removeObjectForKey: key];
        union wl_argument args[1] = {{.o = NULL}};
        struct wl_proxy *information =
                NewObject(description, WP_IMAGE_DESCRIPTION_GET_INFORMATION,
                          &wp_image_description_info_v1_interface, 0, args);
        if (information != NULL) {
            [self attachDispatcher: information kind: WaylandColorObjectImageDescriptionInfo];
            [_pendingInfos setObject: output forKey: Key(information)];
        }
        SendDestroy(description, WP_IMAGE_DESCRIPTION_DESTROY);
    } else if (surface != nil) {
        [_pendingSurfaceDescriptions removeObjectForKey: key];
        union wl_argument args[2] = {{.o = (struct wl_object *) description},
                                     {.u = WP_COLOR_RENDER_INTENT_PERCEPTUAL}};
        WaylandMarshal((struct wl_proxy *) [surface pointerValue],
                       WP_COLOR_SURFACE_SET_IMAGE_DESCRIPTION, NULL, 0, args);
        // The compositor copies the description with the request.
        SendDestroy(description, WP_IMAGE_DESCRIPTION_DESTROY);
    }
}

- (void) handleInformation: (uint32_t) opcode
                      args: (union wl_argument *) args
                     proxy: (struct wl_proxy *) proxy
{
    NSValue *output = [_pendingInfos objectForKey: Key(proxy)];
    if (output == nil)
        return;
    NSMutableDictionary *info = [_outputInfos objectForKey: output];
    if (info == nil) {
        info = [NSMutableDictionary dictionary];
        [_outputInfos setObject: info forKey: output];
    }

    switch (opcode) {
    case WP_IMAGE_DESCRIPTION_INFO_EV_PRIMARIES_NAMED:
        [info setObject: [NSNumber numberWithUnsignedInt: args[0].u]
                 forKey: (id) kCGSDisplayColorPrimariesKey];
        break;
    case WP_IMAGE_DESCRIPTION_INFO_EV_TF_NAMED:
        [info setObject: [NSNumber numberWithUnsignedInt: args[0].u]
                 forKey: (id) kCGSDisplayColorTransferFunctionKey];
        break;
    case WP_IMAGE_DESCRIPTION_INFO_EV_LUMINANCES:
        [info setObject: [NSNumber numberWithUnsignedInt: args[0].u]
                 forKey: (id) kCGSDisplayColorMinLuminanceKey];
        [info setObject: [NSNumber numberWithUnsignedInt: args[1].u]
                 forKey: (id) kCGSDisplayColorMaxLuminanceKey];
        [info setObject: [NSNumber numberWithUnsignedInt: args[2].u]
                 forKey: (id) kCGSDisplayColorReferenceLuminanceKey];
        break;
    case WP_IMAGE_DESCRIPTION_INFO_EV_TARGET_LUMINANCE:
        [info setObject: [NSNumber numberWithUnsignedInt: args[0].u]
                 forKey: (id) kCGSDisplayColorTargetMinLuminanceKey];
        [info setObject: [NSNumber numberWithUnsignedInt: args[1].u]
                 forKey: (id) kCGSDisplayColorTargetMaxLuminanceKey];
        break;
    case WP_IMAGE_DESCRIPTION_INFO_EV_ICC_FILE: {
        // The event transfers the fd to the client. Keep the profile so frameworks above
        // CoreGraphics can build a color space even when the description has no named pair.
        const size_t limit = 16 * 1024 * 1024;
        size_t length = args[1].u;
        if (args[0].h >= 0 && length > 0 && length <= limit) {
            NSMutableData *profile = [NSMutableData dataWithLength: length];
            uint8_t *bytes = [profile mutableBytes];
            size_t used = 0;
            while (used < length) {
                ssize_t n = read(args[0].h, bytes + used, length - used);
                if (n < 0 && errno == EINTR)
                    continue;
                if (n <= 0)
                    break;
                used += (size_t) n;
            }
            if (used == length)
                [info setObject: profile forKey: (id) kCGSDisplayColorICCProfileKey];
        }
        if (args[0].h >= 0)
            close(args[0].h);
        break;
    }
    case WP_IMAGE_DESCRIPTION_INFO_EV_DONE:
        [_pendingInfos removeObjectForKey: Key(proxy)];
        // done is a destructor event: the compositor has destroyed this object already.
        WL.wl_proxy_destroy(proxy);
        if ([_owner respondsToSelector: @selector(waylandColorManagerOutputInfoChanged:)])
            [_owner waylandColorManagerOutputInfoChanged: self];
        break;
    default:
        break;
    }
}

- (void) outputDescriptionChanged: (struct wl_proxy *) managerOutput {
    NSValue *observed = nil;
    for (NSValue *output in _outputObservers)
        if ([[_outputObservers objectForKey: output] pointerValue] == managerOutput) {
            observed = output;
            break;
        }
    if (observed == nil)
        return;

    // Drop the old description and its information object before asking again.
    [_outputObservers removeObjectForKey: observed];
    [_outputInfos removeObjectForKey: observed];
    NSMutableArray *staleDescriptions = [NSMutableArray array];
    for (NSValue *description in _pendingOutputDescriptions)
        if ([[_pendingOutputDescriptions objectForKey: description] isEqual: observed]) {
            SendDestroy((struct wl_proxy *) [description pointerValue], WP_IMAGE_DESCRIPTION_DESTROY);
            [staleDescriptions addObject: description];
        }
    [_pendingOutputDescriptions removeObjectsForKeys: staleDescriptions];
    NSMutableArray *staleInfos = [NSMutableArray array];
    for (NSValue *information in _pendingInfos)
        if ([[_pendingInfos objectForKey: information] isEqual: observed])
            [staleInfos addObject: information];
    for (NSValue *information in staleInfos)
        WL.wl_proxy_destroy((struct wl_proxy *) [information pointerValue]);
    [_pendingInfos removeObjectsForKeys: staleInfos];
    SendDestroy(managerOutput, WP_COLOR_OUTPUT_DESTROY);

    if ([_owner respondsToSelector: @selector(waylandColorManagerOutputInfoChanged:)])
        [_owner waylandColorManagerOutputInfoChanged: self];
    [self requestDescriptionForOutput: (struct wl_proxy *) [observed pointerValue]];
}

#pragma mark - Events

- (void) handleEvent: (uint32_t) opcode
                kind: (WaylandColorObjectKind) kind
               proxy: (struct wl_proxy *) proxy
           arguments: (union wl_argument *) args
{
    switch (kind) {
    case WaylandColorObjectManager:
        switch (opcode) {
        case WP_COLOR_MANAGER_EV_SUPPORTED_FEATURE:
            if (args[0].u == WP_COLOR_FEATURE_PARAMETRIC)
                _parametricSupported = YES;
            else if (args[0].u == WP_COLOR_FEATURE_ICC_V2_V4)
                _iccSupported = YES;
            break;
        case WP_COLOR_MANAGER_EV_SUPPORTED_TF_NAMED:
            [_namedTransferFunctions addObject: [NSNumber numberWithUnsignedInt: args[0].u]];
            break;
        case WP_COLOR_MANAGER_EV_SUPPORTED_PRIMARIES_NAMED:
            [_namedPrimaries addObject: [NSNumber numberWithUnsignedInt: args[0].u]];
            break;
        case WP_COLOR_MANAGER_EV_DONE: {
            _featuresKnown = YES;
            for (NSValue *surface in _pendingColorSpaces) {
                CGColorSpaceRef space = (CGColorSpaceRef) [[_pendingColorSpaces objectForKey: surface] pointerValue];
                [self createDescriptionForSpace: space
                                        surface: (struct wl_proxy *) [surface pointerValue]];
                CGColorSpaceRelease(space);
            }
            [_pendingColorSpaces removeAllObjects];
            break;
        }
        default:
            break;
        }
        break;

    case WaylandColorObjectRepresentationManager:
        switch (opcode) {
        case WP_COLOR_REP_MANAGER_EV_SUPPORTED_ALPHA_MODE:
            // A future compositor could advertise a value outside the bits of _alphaModes.
            if (args[0].u < 8 * sizeof(_alphaModes))
                _alphaModes |= 1u << args[0].u;
            break;
        case WP_COLOR_REP_MANAGER_EV_DONE:
            _representationKnown = YES;
            for (NSValue *surface in _pendingRepresentationSurfaces)
                [self applyRepresentationToSurface: (struct wl_proxy *) [surface pointerValue]];
            [_pendingRepresentationSurfaces removeAllObjects];
            break;
        default:
            break;
        }
        break;

    case WaylandColorObjectImageDescription:
        if (opcode == WP_IMAGE_DESCRIPTION_EV_READY || opcode == WP_IMAGE_DESCRIPTION_EV_READY2)
            [self handleReadyDescription: proxy];
        else if (opcode == WP_IMAGE_DESCRIPTION_EV_FAILED) {
            [_pendingOutputDescriptions removeObjectForKey: Key(proxy)];
            [_pendingSurfaceDescriptions removeObjectForKey: Key(proxy)];
            SendDestroy(proxy, WP_IMAGE_DESCRIPTION_DESTROY);
        }
        break;

    case WaylandColorObjectImageDescriptionInfo:
        [self handleInformation: opcode args: args proxy: proxy];
        break;

    case WaylandColorObjectOutput:
        if (opcode == WP_COLOR_OUTPUT_EV_IMAGE_DESCRIPTION_CHANGED)
            [self outputDescriptionChanged: proxy];
        break;

    default:
        break;
    }
}

@end
