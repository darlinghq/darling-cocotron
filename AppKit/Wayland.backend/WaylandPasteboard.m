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

#import "WaylandPasteboard.h"
#import "WaylandFileURLs.h"
#import "WaylandDropSession.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <errno.h>

static const NSUInteger TransferLimit = 16 * 1024 * 1024;
static const NSTimeInterval TransferTimeout = 5;

static void destroyProxy(struct wl_proxy *proxy, uint32_t opcode) {
    if (proxy != NULL) {
        union wl_argument args[1] = {{.o = NULL}};
        WaylandMarshal(proxy, opcode, NULL, WL_MARSHAL_FLAG_DESTROY, args);
    }
}

// A dedicated, bounded writer keeps a slow reader off the AppKit thread.
// SIGPIPE is blocked only on this short-lived thread, never process-wide.
@interface WaylandClipboardWriter : NSObject {
    NSData *_data;
    int _fd;
}
- (id) initWithData: (NSData *) data descriptor: (int) fd;
- (void) writeData: (id) unused;
@end
@implementation WaylandClipboardWriter
- (id) initWithData: (NSData *) data descriptor: (int) fd {
    if ((self = [super init])) { _data = [data copy]; _fd = fd; }
    return self;
}
- (void) dealloc {
    if (_fd >= 0) close(_fd);
    [_data release];
    [super dealloc];
}
- (void) writeData: (id) unused {
    @autoreleasepool {
        sigset_t signals;
        sigemptyset(&signals);
        sigaddset(&signals, SIGPIPE);
        if (pthread_sigmask(SIG_BLOCK, &signals, NULL) != 0) return;
        int flags = fcntl(_fd, F_GETFL);
        if (flags < 0 || fcntl(_fd, F_SETFL, flags | O_NONBLOCK) < 0) return;
        NSUInteger offset = 0;
        NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + TransferTimeout;
        while (offset < [_data length] && [NSDate timeIntervalSinceReferenceDate] < deadline) {
            ssize_t count = write(_fd, (const char *) [_data bytes] + offset, [_data length] - offset);
            if (count > 0) { offset += count; continue; }
            if (count < 0 && errno == EINTR) continue;
            if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                struct pollfd ready = {.fd = _fd, .events = POLLOUT};
                poll(&ready, 1, 20);
                continue;
            }
            break;
        }
        close(_fd);
        _fd = -1;
    }
}
@end

void WaylandSendData(WaylandDisplay *display, NSData *data, int fd) {
    if (data == nil) { close(fd); return; }
    WaylandClipboardWriter *writer = [[[WaylandClipboardWriter alloc]
            initWithData: data descriptor: fd] autorelease];
    [display performAfterDispatch: ^{
        [NSThread detachNewThreadSelector: @selector(writeData:)
                                toTarget: writer withObject: nil];
    }];
}

@implementation WaylandPasteboard
- (struct wl_proxy *) dataDevice { return _device; }


+ (NSArray *) mimeTypesForType: (NSString *) type {
    if ([type isEqual:NSFilenamesPboardType]) return @[@"text/uri-list"];
    if ([type isEqual: NSStringPboardType])
        return @[@"text/plain;charset=utf-8", @"text/plain", @"UTF8_STRING"];
    return @[type];
}
+ (NSString *) typeForMime: (NSString *) mime {
    if ([mime isEqual: @"text/plain;charset=utf-8"] || [mime isEqual: @"text/plain"] ||
        [mime isEqual: @"UTF8_STRING"])
        return NSStringPboardType;
    return mime;
}
// Keep the native bytes available alongside the converted Cocoa representation.
+ (NSArray *) typesForMime: (NSString *) mime {
    if ([mime isEqual:@"text/uri-list"]) return @[mime, NSFilenamesPboardType];
    return @[[self typeForMime:mime]];
}
+ (NSData *) encodeData: (NSData *) data forType: (NSString *) type {
    if (!data || [data length] > TransferLimit) return nil;
    if (![type isEqual:NSFilenamesPboardType]) return data;
    id files = [NSPropertyListSerialization propertyListFromData:data
            mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:NULL];
    return WaylandURIListFromFilenames(files);
}
+ (NSData *) decodeData: (NSData *) data forType: (NSString *) type mime: (NSString *) mime {
    if (!data || [data length] > TransferLimit) return nil;
    if (![type isEqual:NSFilenamesPboardType] || ![mime isEqual:@"text/uri-list"]) return data;
    NSArray *files = WaylandFilenamesFromURIList(data);
    if (!files) return nil;
    NSData *plist = [NSPropertyListSerialization dataFromPropertyList:files
            format:NSPropertyListXMLFormat_v1_0 errorDescription:NULL];
    return [plist length] <= TransferLimit ? plist : nil;
}
- (id) initWithName: (NSString *) name display: (WaylandDisplay *) display
           manager: (struct wl_proxy *) manager seat: (struct wl_proxy *) seat {
    if ((self = [super init])) {
        _display = display;
        _name = [name copy];
        _manager = manager;
        _offers = [NSMutableDictionary new];
        _offerActions = [NSMutableDictionary new];
        _types = [NSMutableArray new];
        _data = [NSMutableDictionary new];
        _owners = [NSMutableDictionary new];
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
    destroyProxy(_source, WP_DATA_SOURCE_DESTROY);
    _source = NULL;
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
    [_name release]; [_offers release]; [_offerActions release]; [_types release];
    [_data release]; [_owners release]; [_sourceData release];
    [super dealloc];
}
- (NSString *) name { return _name; }
- (NSInteger) changeCount {
    [_display processPendingEvents];
    return _changeCount;
}
- (void) notifyOwners {
    NSSet *owners = [NSSet setWithArray: [_owners allValues]];
    [_owners removeAllObjects];
    for (id owner in owners)
        if ([owner respondsToSelector: @selector(pasteboardChangedOwner:)])
            [owner pasteboardChangedOwner: self];
}
- (void) inputAvailable {
    if (!_needsPublish || _publishQueued || _publishing || !_device) return;
    _publishQueued = YES;
    [_display performAfterDispatch: ^{
        self->_publishQueued = NO;
        [self publishSelection];
    }];
}
- (void) changed {
    _owned = YES;
    if (_publishing) return;
    _needsPublish = YES;
    [self inputAvailable];
}
- (NSInteger) clearContents {
    [self notifyOwners];
    [_types removeAllObjects]; [_data removeAllObjects];
    _changeCount++;
    [self changed];
    return _changeCount;
}
- (NSInteger) declareTypes: (NSArray *) types owner: (id) owner {
    [self clearContents];
    return [self addTypes: types owner: owner];
}
- (NSInteger) addTypes: (NSArray *) types owner: (id) owner {
    for (NSString *type in types) {
        if (![_types containsObject: type]) [_types addObject: type];
        [_data removeObjectForKey: type];
        if (owner) [_owners setObject: owner forKey: type];
        else [_owners removeObjectForKey: type];
    }
    [self changed];
    return _changeCount;
}
- (BOOL) setData: (NSData *) data forType: (NSString *) type {
    if (data == nil || type == nil || [data length] > TransferLimit) return NO;
    if (![_types containsObject: type]) [_types addObject: type];
    [_data setObject: [[data copy] autorelease] forKey: type];
    [_owners removeObjectForKey: type];
    [self changed];
    return YES;
}
- (BOOL) setString: (NSString *) string forType: (NSString *) type {
    return [self setData: [string dataUsingEncoding:
            [type isEqual: NSStringPboardType] ? NSUTF8StringEncoding : NSUnicodeStringEncoding]
                 forType: type];
}
- (NSString *) stringForType: (NSString *) type {
    NSData *data = [self dataForType: type];
    return data ? [[[NSString alloc] initWithData: data encoding:
            [type isEqual: NSStringPboardType] ? NSUTF8StringEncoding : NSUnicodeStringEncoding] autorelease] : nil;
}
- (NSArray *) types {
    [_display processPendingEvents];
    if (_owned || !_device) return [[_types copy] autorelease];
    NSMutableArray *types = [NSMutableArray array];
    for (NSString *mime in [_offers objectForKey: [NSValue valueWithPointer: _selection]]) {
        for (NSString *type in [WaylandPasteboard typesForMime:mime])
            if (![types containsObject:type]) [types addObject:type];
    }
    return types;
}
- (NSData *) localDataForType: (NSString *) type {
    id owner = [[[_owners objectForKey: type] retain] autorelease];
    if (owner && [owner respondsToSelector: @selector(pasteboard:provideDataForType:)])
        [owner pasteboard: self provideDataForType: type];
    return [_data objectForKey: type];
}
- (void) publishSelection {
    uint32_t serial = [_display clipboardSerial];
    if (!_needsPublish || !_device || !serial || !_owned) return;
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    _publishing = YES;
    @try {
        for (NSString *type in [[_types copy] autorelease]) {
            NSData *data = [WaylandPasteboard encodeData:[self localDataForType:type] forType:type];
            if (data && [data length] <= TransferLimit)
                for (NSString *mime in [WaylandPasteboard mimeTypesForType: type])
                    if ([type isEqual:mime] || ![snapshot objectForKey:mime])
                        [snapshot setObject:data forKey:mime];
        }
    } @finally { _publishing = NO; }
    union wl_argument args[2] = {{.o = NULL}};
    struct wl_proxy *source = NULL;
    if ([snapshot count]) {
        source = WaylandCreateObject(_manager, WP_DATA_MANAGER_CREATE_SOURCE,
                &wl_data_source_interface, args, WaylandObjectDataSource, self);
        for (NSString *mime in snapshot) {
            args[0].s = [mime UTF8String];
            WaylandMarshal(source, WP_DATA_SOURCE_OFFER, NULL, 0, args);
        }
    }
    args[0].o = (struct wl_object *) source; args[1].u = serial;
    WaylandMarshal(_device, WP_DATA_DEVICE_SET_SELECTION, NULL, 0, args);
    destroyProxy(_source, WP_DATA_SOURCE_DESTROY);
    _source = source;
    [_sourceData release]; _sourceData = [snapshot copy];
    _needsPublish = NO;
    [_display flush];
}
- (NSData *) dataForType: (NSString *) type {
    [_display processPendingEvents];
    if (_owned || !_device) return [self localDataForType: type];
    NSString *mime = nil;
    NSArray *offered = [_offers objectForKey: [NSValue valueWithPointer: _selection]];
    for (NSString *candidate in [WaylandPasteboard mimeTypesForType: type])
        if ([offered containsObject: candidate]) { mime = candidate; break; }
    if (!mime || !_selection) return nil;
    int fds[2];
    if (pipe(fds) != 0) return nil;
    fcntl(fds[0], F_SETFD, FD_CLOEXEC); fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    int flags = fcntl(fds[0], F_GETFL);
    if (flags < 0 || fcntl(fds[0], F_SETFL, flags | O_NONBLOCK) < 0) {
        close(fds[0]); close(fds[1]); return nil;
    }
    union wl_argument args[2] = {{.s = [mime UTF8String]}, {.h = fds[1]}};
    WaylandMarshal(_selection, WP_DATA_OFFER_RECEIVE, NULL, 0, args);
    close(fds[1]); [_display flush];
    NSUInteger generation = _selectionGeneration;
    NSMutableData *data = [NSMutableData data];
    BOOL complete = NO;
    NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + TransferTimeout;
    @try {
        while ([NSDate timeIntervalSinceReferenceDate] < deadline && generation == _selectionGeneration) {
            char bytes[16384];
            ssize_t count = read(fds[0], bytes, sizeof(bytes));
            if (count == 0) { complete = YES; break; }
            if (count > 0) {
                if ([data length] + count > TransferLimit) {
                    NSLog(@"Wayland clipboard: incoming transfer exceeds 16 MiB");
                    break;
                }
                [data appendBytes: bytes length: count];
                continue;
            }
            if (errno == EINTR) continue;
            if (errno != EAGAIN && errno != EWOULDBLOCK) break;
            // Service the compositor while the synchronous pasteboard API waits.
            [_display processPendingEvents];
            struct pollfd ready = {.fd = fds[0], .events = POLLIN};
            poll(&ready, 1, 20);
        }
    } @finally { close(fds[0]); }
    return complete && generation == _selectionGeneration
            ? [WaylandPasteboard decodeData:data forType:type mime:mime] : nil;
}
- (oneway void) releaseGlobally { [self clearContents]; }

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
            struct wl_proxy *offer = (struct wl_proxy *) args[0].o;
            if (_selection != offer) [self removeOffer: _selection];
            _selection = offer;
            // Clearing publishes a NULL source, which can never be cancelled.
            // A later external offer must still replace that empty local state.
            if (offer != NULL && _source == NULL && !_needsPublish)
                _owned = NO;
            _selectionGeneration++;
            _changeCount++;
            // A local source may receive its own offer. Cancellation tells us
            // when ownership actually changes; NULL on focus loss is not loss.
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
    } else if (kind == WaylandObjectDataSource) {
        if (opcode == WP_DATA_SOURCE_EV_SEND) {
            int fd = args[1].h;
            NSString *mime = args[0].s ? [NSString stringWithUTF8String: args[0].s] : nil;
            NSData *data = mime ? [_sourceData objectForKey: mime] : nil;
            if (!data || proxy != _source) { close(fd); return; }
            WaylandSendData(_display, data, fd);
        } else if (opcode == WP_DATA_SOURCE_EV_CANCELLED && proxy == _source) {
            destroyProxy(_source, WP_DATA_SOURCE_DESTROY); _source = NULL;
            [_sourceData release]; _sourceData = nil;
            _owned = NO; _needsPublish = NO;
            _changeCount++;
            NSSet *owners = [NSSet setWithArray: [_owners allValues]];
            [_owners removeAllObjects]; [_types removeAllObjects]; [_data removeAllObjects];
            [_display performAfterDispatch: ^{
                for (id owner in owners)
                    if ([owner respondsToSelector: @selector(pasteboardChangedOwner:)])
                        [owner pasteboardChangedOwner: self];
            }];
        }
    }
}
@end
