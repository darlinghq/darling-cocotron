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

#import "WaylandDataDevice.h"
#import <CoreGraphics/CGSSelection.h>
#import "WaylandDropSession.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#include <unistd.h>

static void destroyProxy(struct wl_proxy *proxy, uint32_t opcode) {
    if (proxy != NULL) {
        union wl_argument args[1] = {{.o = NULL}};
        WaylandMarshal(proxy, opcode, NULL, WL_MARSHAL_FLAG_DESTROY, args);
    }
}

void WaylandSendData(WaylandDisplay *display, NSData *data, int fd) {
    if (data == nil) { close(fd); return; }
    [display performAfterDispatch: ^{
        _CGSSelectionSendData(data, fd);
    }];
}

@implementation WaylandDataDevice
- (struct wl_proxy *) dataDevice { return _device; }

- (id) initWithDisplay: (WaylandDisplay *) display
               manager: (struct wl_proxy *) manager seat: (struct wl_proxy *) seat {
    if ((self = [super init])) {
        _display = display;
        _manager = manager;
        _offers = [NSMutableDictionary new];
        _offerActions = [NSMutableDictionary new];
        if (manager && seat) {
            union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) seat}};
            _device = WaylandCreateObject(manager, WP_DATA_MANAGER_GET_DEVICE,
                    &wl_data_device_interface, args, WaylandObjectDataDevice, self);
        }
    }
    return self;
}
- (void) invalidate {
    [_dragSession invalidate]; [_dragSession release]; _dragSession = nil;
    for (NSValue *key in _offers)
        destroyProxy([key pointerValue], WP_DATA_OFFER_DESTROY);
    [_offers removeAllObjects];
    _selection = _dragOffer = NULL;
    if (_device) {
        if (WL.wl_proxy_get_version(_device) >= 2)
            destroyProxy(_device, WP_DATA_DEVICE_RELEASE);
        else
            WL.wl_proxy_destroy(_device);
    }
    _device = _manager = NULL;
    _display = nil;
}
- (void) dealloc {
    [self invalidate];
    [_offers release]; [_offerActions release];
    [super dealloc];
}

- (void) removeOffer: (struct wl_proxy *) offer {
    if (!offer) return;
    [_offers removeObjectForKey: [NSValue valueWithPointer: offer]];
    [_offerActions removeObjectForKey: [NSValue valueWithPointer: offer]];
    destroyProxy(offer, WP_DATA_OFFER_DESTROY);
}
- (void) handleEvent: (uint32_t) opcode kind: (WaylandObjectKind) kind
              proxy: (struct wl_proxy *) proxy arguments: (union wl_argument *) args {
    if (kind == WaylandObjectDataDevice) {
        if (opcode == WP_DATA_DEVICE_EV_OFFER) {
            struct wl_proxy *offer = (struct wl_proxy *) args[0].o;
            [_offers setObject: [NSMutableArray array] forKey: [NSValue valueWithPointer: offer]];
            WL.wl_proxy_add_dispatcher(offer, WaylandDispatch,
                    (void *) (uintptr_t) WaylandObjectDataOffer, self);
        } else if (opcode == WP_DATA_DEVICE_EV_SELECTION) {
            // The compositor's clipboard is CoreGraphics' business; the offer is of no use here.
            struct wl_proxy *offer = (struct wl_proxy *) args[0].o;
            if (_selection != offer) [self removeOffer: _selection];
            _selection = offer;
        } else if (opcode == WP_DATA_DEVICE_EV_ENTER) {
            WaylandDropSession *old = _dragSession;
            [old willLeave];
            if (old) [_display performAfterDispatch: ^{ [old leave]; }];
            _dragOffer = (struct wl_proxy *) args[4].o;
            NSValue *key = [NSValue valueWithPointer: _dragOffer];
            _dragSession = [[WaylandDropSession alloc] initWithOffer: _dragOffer
                types: [_offers objectForKey: key] display: _display
                window: [_display windowForSurface: (struct wl_proxy *) args[1].o]
                serial: args[0].u sourceActions: [[_offerActions objectForKey: key] unsignedIntValue]];
            // Session now owns the drag offer; clipboard offers stay independent.
            [_offers removeObjectForKey: key]; [_offerActions removeObjectForKey: key];
            [old release];
            WaylandDropSession *session = _dragSession;
            CGPoint point = CGPointMake(wl_fixed_to_double(args[2].f), wl_fixed_to_double(args[3].f));
            [_display performAfterDispatch: ^{ [session motion: point]; }];
        } else if (opcode == WP_DATA_DEVICE_EV_MOTION) {
            WaylandDropSession *session = _dragSession;
            CGPoint point = CGPointMake(wl_fixed_to_double(args[1].f), wl_fixed_to_double(args[2].f));
            [_display performAfterDispatch: ^{ [session motion: point]; }];
        } else if (opcode == WP_DATA_DEVICE_EV_DROP) {
            WaylandDropSession *session = _dragSession;
            [session markDropped];
            [_display performAfterDispatch: ^{ [session drop]; }];
        } else if (opcode == WP_DATA_DEVICE_EV_LEAVE) {
            WaylandDropSession *session = _dragSession;
            [session willLeave];
            [_display performAfterDispatch: ^{ [session leave]; }];
            [_dragSession release]; _dragSession = nil; _dragOffer = NULL;
        }
    } else if (kind == WaylandObjectDataOffer && opcode == WP_DATA_OFFER_EV_SOURCE_ACTIONS) {
        if (proxy == _dragOffer) [_dragSession sourceActions: args[0].u];
        else [_offerActions setObject: [NSNumber numberWithUnsignedInt: args[0].u]
                               forKey: [NSValue valueWithPointer: proxy]];
    } else if (kind == WaylandObjectDataOffer && opcode == WP_DATA_OFFER_EV_ACTION) {
        if (proxy == _dragOffer) [_dragSession selectedAction: args[0].u];
    } else if (kind == WaylandObjectDataOffer && opcode == WP_DATA_OFFER_EV_OFFER) {
        if (args[0].s) {
            NSString *mime = [NSString stringWithUTF8String: args[0].s];
            if (mime) [[_offers objectForKey: [NSValue valueWithPointer: proxy]] addObject: mime];
        }
    }
}
@end
