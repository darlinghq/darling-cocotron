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

#import <CoreGraphics/CGSSelection.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <CoreGraphics/CGSConnection.h>
#import <CoreGraphics/CGSServerSPI.h>
#import <CoreGraphics/DarlingFileURIList.h>
#import <CoreFoundation/CFPasteboard_Private.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <unistd.h>

const NSUInteger CGSSelectionTransferLimit = 16 * 1024 * 1024;
static const NSTimeInterval CGSSelectionWriteTimeout = 5;

// The UTI spellings of the types the window systems have their own names for.
static NSString *const kTypeString = @"public.utf8-plain-text";
static NSString *const kTypeHTML = @"public.html";
static NSString *const kTypePNG = @"public.png";
static NSString *const kTypeTIFF = @"public.tiff";
static NSString *const kTypeRTF = @"public.rtf";
// The AppKit type of a list of file names (a property list), which has no counterpart in the window systems.
static NSString *const kTypeFilenames = @"NSFilenamesPboardType";
// Older spellings of the image types that are not aliases of the UTI types in AppKit's table.
static NSString *const kLegacyTypeTIFF = @"NeXT TIFF v4.0 pasteboard type";
static NSString *const kLegacyTypePNG = @"NSPNGPPboardType";

NSString *const CGSHostClipboardOriginType = @"com.apple.darling.pasteboard-origin";

#pragma mark - Type names

NSString *_CGSSelectionMimeTypeForType(NSString *type) {
    if ([type isEqual: kTypeHTML])
        return @"text/html";
    if ([type isEqual: kTypePNG])
        return @"image/png";
    if ([type isEqual: kTypeTIFF])
        return @"image/tiff";
    if ([type isEqual: kTypeRTF])
        return @"text/rtf";
    return nil;
}

NSArray<NSString *> *_CGSSelectionTargetsForType(NSString *type) {
    if ([type isEqual: kTypeString])
        return @[ @"UTF8_STRING", @"STRING", @"TEXT", @"text/plain", @"text/plain;charset=utf-8" ];
    NSString *mime = _CGSSelectionMimeTypeForType(type);
    if (mime != nil)
        return @[ mime, type ];
    return @[ type ];
}

NSString *_CGSSelectionTypeForTarget(NSString *target) {
    if ([target isEqual: @"STRING"] || [target isEqual: @"TEXT"] || [target isEqual: @"text/plain"] ||
        [target isEqual: @"text/plain;charset=utf-8"] || [target isEqual: @"UTF8_STRING"])
        return kTypeString;
    for (NSString *type in @[ kTypeHTML, kTypePNG, kTypeTIFF, kTypeRTF ]) {
        if ([target isEqual: _CGSSelectionMimeTypeForType(type)])
            return type;
    }
    return target;
}

NSArray<NSString *> *_CGSSelectionMimeTypesForType(NSString *type) {
    if ([type isEqual: kTypeFilenames])
        return @[ @"text/uri-list" ];
    if ([type isEqual: kTypeString])
        return @[ @"text/plain;charset=utf-8", @"text/plain", @"UTF8_STRING" ];
    if ([type isEqual: kTypeHTML])
        return @[ @"text/html" ];
    if ([type isEqual: kTypeRTF])
        return @[ @"text/rtf" ];
    if ([type isEqual: kTypePNG] || [type isEqual: kLegacyTypePNG])
        return @[ @"image/png" ];
    if ([type isEqual: kTypeTIFF] || [type isEqual: kLegacyTypeTIFF])
        return @[ @"image/tiff" ];
    return @[ type ];
}

static NSString *typeForMime(NSString *mime) {
    if ([mime isEqual: @"text/plain;charset=utf-8"] || [mime isEqual: @"text/plain"] || [mime isEqual: @"UTF8_STRING"])
        return kTypeString;
    if ([mime isEqual: @"text/html"])
        return kTypeHTML;
    if ([mime isEqual: @"text/rtf"])
        return kTypeRTF;
    if ([mime isEqual: @"image/png"])
        return kTypePNG;
    if ([mime isEqual: @"image/tiff"])
        return kTypeTIFF;
    return mime;
}

NSArray<NSString *> *_CGSSelectionTypesForMime(NSString *mime) {
    // The native bytes stay available alongside the converted Cocoa representation.
    if ([mime isEqual: @"text/uri-list"])
        return @[ mime, kTypeFilenames ];
    return @[ typeForMime(mime) ];
}

NSData *_CGSSelectionEncodeData(NSData *data, NSString *type) {
    if (data == nil || [data length] > CGSSelectionTransferLimit)
        return nil;
    if (![type isEqual: kTypeFilenames])
        return data;
    id files = [NSPropertyListSerialization propertyListFromData: data
                                                mutabilityOption: NSPropertyListImmutable
                                                          format: NULL
                                                errorDescription: NULL];
    return DarlingURIListFromFilenames(files);
}

NSData *_CGSSelectionDecodeData(NSData *data, NSString *type, NSString *mime) {
    if (data == nil || [data length] > CGSSelectionTransferLimit)
        return nil;
    if (![type isEqual: kTypeFilenames] || ![mime isEqual: @"text/uri-list"])
        return data;
    NSArray *files = DarlingFilenamesFromURIList(data);
    if (files == nil)
        return nil;
    NSData *plist = [NSPropertyListSerialization dataFromPropertyList: files
                                                               format: NSPropertyListXMLFormat_v1_0
                                                     errorDescription: NULL];
    return [plist length] <= CGSSelectionTransferLimit ? plist : nil;
}

#pragma mark - Sending data to a descriptor

// A dedicated, bounded writer keeps a slow reader off the calling thread. SIGPIPE is blocked only on this
// short-lived thread, never process-wide.
@interface CGSSelectionWriter : NSObject {
    NSData *_data;
    int _fd;
}
- (id) initWithData: (NSData *) data descriptor: (int) fd;
- (void) writeData: (id) unused;
@end

@implementation CGSSelectionWriter
- (id) initWithData: (NSData *) data descriptor: (int) fd {
    if ((self = [super init])) {
        _data = [data copy];
        _fd = fd;
    }
    return self;
}

- (void) dealloc {
    if (_fd >= 0)
        close(_fd);
    [_data release];
    [super dealloc];
}

- (void) writeData: (id) unused {
    @autoreleasepool {
        sigset_t signals;
        sigemptyset(&signals);
        sigaddset(&signals, SIGPIPE);
        if (pthread_sigmask(SIG_BLOCK, &signals, NULL) != 0)
            return;
        int flags = fcntl(_fd, F_GETFL);
        if (flags < 0 || fcntl(_fd, F_SETFL, flags | O_NONBLOCK) < 0)
            return;
        NSUInteger offset = 0;
        NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + CGSSelectionWriteTimeout;
        while (offset < [_data length] && [NSDate timeIntervalSinceReferenceDate] < deadline) {
            ssize_t count = write(_fd, (const char *) [_data bytes] + offset, [_data length] - offset);
            if (count > 0) {
                offset += count;
                continue;
            }
            if (count < 0 && errno == EINTR)
                continue;
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

void _CGSSelectionSendData(NSData *data, int fd) {
    if (data == nil) {
        close(fd);
        return;
    }
    CGSSelectionWriter *writer = [[[CGSSelectionWriter alloc] initWithData: data descriptor: fd] autorelease];
    [NSThread detachNewThreadSelector: @selector(writeData:) toTarget: writer withObject: nil];
}

#pragma mark - Endpoints of the connection

// The connection creates its endpoints; a backend that has none leaves the base class' answer.
@interface CGSConnection (CGSSelectionEndpoints)
- (id) newSelectionEndpointNamed: (NSString *) name;
@end

id<CGSSelectionEndpoint> _CGSNativeConnectionNewSelection(NSString *name) {
    CGSConnectionID connId = CGSMainConnectionID();
    CGSConnection *connection = connId != 0 ? _CGSConnectionForID(connId) : nil;
    if (![connection respondsToSelector: @selector(newSelectionEndpointNamed:)])
        return nil;
    return [connection newSelectionEndpointNamed: name];
}

#pragma mark - The host clipboard and the general pasteboard

// Offers the general pasteboard of CoreFoundation to the host and imports what the host copies. The general
// pasteboard lives in CoreFoundation's pasteboard (shared by every process of the user): the bridge is told
// when it changed and exports it; a change of the host's selection is imported into it, text at once and the
// other types when they are read.
@interface CGSHostClipboardBridge : NSObject <CGSSelectionSource> {
    id<CGSSelectionEndpoint> _clipboard;
    CFPasteboardRef _general;
    BOOL _exportPending;
}
- (id) initWithClipboard: (id<CGSSelectionEndpoint>) clipboard;
- (void) scheduleExport;
- (void) export;
- (void) hostClipboardChanged;
- (NSData *) hostDataForType: (NSString *) type;
@end

static CGSHostClipboardBridge *hostBridge;

static void onMainThread(void (^block)(void)) {
    if ([NSThread isMainThread])
        block();
    else
        dispatch_sync(dispatch_get_main_queue(), block);
}

// The general pasteboard changed (here or in another process): publish it to the host.
static void bridgeBoardChanged(CFStringRef name, CFPasteboardRef pasteboard, void *info) {
    // Drags go through the window system's own drag protocol, not through a selection.
    if (!CFEqual(name, kCFPasteboardGeneral))
        return;
    [(CGSHostClipboardBridge *) info scheduleExport];
}

// A flavor of a host selection imported without its data: fetched now.
static CFDataRef bridgeCopyData(CFStringRef name, CFIndex itemIndex, CFStringRef flavor, void *info) {
    if (itemIndex != 0)
        return NULL;
    __block NSData *data = nil;
    @autoreleasepool {
        onMainThread(^{
          data = [[(CGSHostClipboardBridge *) info hostDataForType: (NSString *) flavor] retain];
        });
    }
    return (CFDataRef) data;
}

@implementation CGSHostClipboardBridge

- (id) initWithClipboard: (id<CGSSelectionEndpoint>) clipboard {
    if ((self = [super init])) {
        _clipboard = [clipboard retain];
        CFPasteboardHostBridgeCallbacks callbacks = {0, bridgeBoardChanged, bridgeCopyData, self};
        if (!CFPasteboardRegisterHostBridge(&callbacks)) {
            [self release];
            return nil;
        }
        // The bridge only hears about boards it created after registering. Having the general
        // pasteboard from the start means a change made by any process is seen even if this one never
        // uses NSPasteboard.
        _general = CFPasteboardCreate(NULL, kCFPasteboardGeneral);

        [_clipboard setSource: self];
        __block CGSHostClipboardBridge *bridge = self;
        [_clipboard setHostChangeHandler: ^{
          [bridge hostClipboardChanged];
        }];
    }
    return self;
}

- (NSData *) hostDataForType: (NSString *) type {
    return [_clipboard remoteDataForType: type];
}

- (void) scheduleExport {
    @synchronized(self) {
        if (_exportPending)
            return;
        _exportPending = YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      @synchronized(self) {
          _exportPending = NO;
      }
      [self export];
    });
}

// Offers the general pasteboard to the host: its types are declared and the data is fetched from
// CoreFoundation when a host program asks for it.
- (void) export {
    if (_general == NULL)
        return;
    CFIndex count = 0;
    CFPasteboardItemID item;
    CFArrayRef flavors = NULL;
    if (CFPasteboardGetItemCount(_general, &count) != kCFPasteboardSuccess || count < 1 ||
        CFPasteboardGetItemAtIndex(_general, 0, &item) != kCFPasteboardSuccess ||
        CFPasteboardCopyFlavorsForItem(_general, item, &flavors) != kCFPasteboardSuccess) {
        // Nothing to offer (a cleared pasteboard): stop offering what was offered before.
        if (count < 1 && [_clipboard ownsSelection]) {
            [_clipboard acquire];
            [_clipboard setLocalTypes: @[]];
            [_clipboard bumpChangeCount];
        }
        return;
    }
    NSMutableArray *types = [NSMutableArray array];
    for (NSString *flavor in (NSArray *) flavors) {
        if (![types containsObject: flavor])
            [types addObject: flavor];
    }
    CFRelease(flavors);
    [types removeObject: CGSHostClipboardOriginType];
    [types addObject: CGSHostClipboardOriginType];
    [_clipboard acquire];
    [_clipboard setLocalTypes: types];
    [_clipboard bumpChangeCount];
}

// The host clipboard has another owner: the general pasteboard becomes its contents.
- (void) hostClipboardChanged {
    if ([_clipboard ownsSelection])
        return;
    // A change of the pasteboard that is waiting to be exported is newer than the host selection that is
    // noticed now (the process copied before the host's first selection was looked at): it is not replaced.
    @synchronized(self) {
        if (_exportPending)
            return;
    }
    NSArray *types = [_clipboard remoteTypes];
    // A selection that another Darling process published is the general pasteboard already.
    if ([types count] == 0 || [types containsObject: CGSHostClipboardOriginType])
        return;

    NSMutableDictionary *flavors = [NSMutableDictionary dictionary];
    for (NSString *type in types) {
        // Text is taken at once, so that it outlives the program that copied it; everything else when it is read.
        NSData *data = [type isEqual: kTypeString] ? [_clipboard remoteDataForType: type] : nil;
        [flavors setObject: data != nil ? (id) data : (id) [NSNull null] forKey: type];
    }
    CFPasteboardHostBridgeReplaceContents(kCFPasteboardGeneral, (CFArrayRef) [NSArray arrayWithObject: flavors]);
}

#pragma mark CGSSelectionSource

// A host program asks for a type that was offered.
- (NSData *) selectionDataForType: (NSString *) type {
    if ([type isEqual: CGSHostClipboardOriginType])
        return [NSData data];
    CFIndex count = 0;
    CFPasteboardItemID item;
    CFDataRef data = NULL;
    if (_general != NULL && CFPasteboardGetItemCount(_general, &count) == kCFPasteboardSuccess && count > 0 &&
        CFPasteboardGetItemAtIndex(_general, 0, &item) == kCFPasteboardSuccess &&
        CFPasteboardCopyData(_general, item, (CFStringRef) type, &data) == kCFPasteboardSuccess && data != NULL)
        return [(NSData *) data autorelease];
    return nil;
}

- (void) selectionLost {
}

@end

void _CGSHostClipboardStart(id<CGSSelectionEndpoint> clipboard) {
    @synchronized([CGSHostClipboardBridge class]) {
        if (hostBridge == nil)
            hostBridge = [[CGSHostClipboardBridge alloc] initWithClipboard: clipboard];
    }
}
