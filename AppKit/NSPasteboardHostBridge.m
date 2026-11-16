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

#import "NSPasteboardHostBridge.h"
#import "NSPasteboardAliases.h"
#import <CoreFoundation/CFPasteboard_Private.h>
#import <dispatch/dispatch.h>

NSPasteboardType const NSPasteboardHostBridgeOriginType = @"com.apple.darling.pasteboard-origin";

@interface NSPasteboardHostBridge : NSObject <NSPasteboardTypeOwner> {
    NSPasteboard<NSPasteboardHostClipboard> *_clipboard;
    CFPasteboardRef _general;
    BOOL _exportPending;
}
- (id) initWithClipboard: (NSPasteboard<NSPasteboardHostClipboard> *) clipboard;
- (void) scheduleExport;
- (NSData *) hostDataForType: (NSPasteboardType) type;
@end

static NSPasteboardHostBridge *hostBridge;

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
    [(NSPasteboardHostBridge *) info scheduleExport];
}

// A flavor of a host selection imported without its data: fetched now.
static CFDataRef bridgeCopyData(CFStringRef name, CFIndex itemIndex, CFStringRef flavor, void *info) {
    if (itemIndex != 0)
        return NULL;
    __block NSData *data = nil;
    @autoreleasepool {
        onMainThread(^{
          data = [[(NSPasteboardHostBridge *) info hostDataForType: (NSPasteboardType) flavor] retain];
        });
    }
    return (CFDataRef) data;
}

@implementation NSPasteboardHostBridge

- (id) initWithClipboard: (NSPasteboard<NSPasteboardHostClipboard> *) clipboard {
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

        __block NSPasteboardHostBridge *bridge = self;
        [_clipboard setHostClipboardChangeHandler: ^{
          [bridge hostClipboardChanged];
        }];
    }
    return self;
}

- (NSData *) hostDataForType: (NSPasteboardType) type {
    return [_clipboard dataForType: type];
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
        if (count < 1 && [_clipboard ownsHostClipboard])
            [_clipboard clearContents];
        return;
    }
    NSMutableArray *types = [NSMutableArray arrayWithArray: NSPasteboardCanonicalTypes((NSArray *) flavors)];
    CFRelease(flavors);
    [types removeObject: NSPasteboardHostBridgeOriginType];
    [types addObject: NSPasteboardHostBridgeOriginType];
    [_clipboard declareTypes: types owner: self];
}

// The host clipboard has another owner: the general pasteboard becomes its contents.
- (void) hostClipboardChanged {
    if ([_clipboard ownsHostClipboard])
        return;
    NSArray *types = NSPasteboardCanonicalTypes([_clipboard types]);
    // A selection that another Darling process published is the general pasteboard already.
    if ([types count] == 0 || [types containsObject: NSPasteboardHostBridgeOriginType])
        return;

    NSMutableDictionary *flavors = [NSMutableDictionary dictionary];
    for (NSPasteboardType type in types) {
        // Text is taken at once, so that it outlives the program that copied it; everything else when it is read.
        NSData *data = [type isEqual: NSPasteboardTypeString] ? [_clipboard dataForType: type] : nil;
        [flavors setObject: data != nil ? (id) data : (id) [NSNull null] forKey: type];
    }
    CFPasteboardHostBridgeReplaceContents(kCFPasteboardGeneral, (CFArrayRef) [NSArray arrayWithObject: flavors]);
}

#pragma mark NSPasteboardTypeOwner

// A host program asks for a type that was offered.
- (void) pasteboard: (NSPasteboard *) sender provideDataForType: (NSPasteboardType) type {
    if ([type isEqual: NSPasteboardHostBridgeOriginType]) {
        [sender setData: [NSData data] forType: type];
        return;
    }
    CFIndex count = 0;
    CFPasteboardItemID item;
    CFDataRef data = NULL;
    if (_general != NULL && CFPasteboardGetItemCount(_general, &count) == kCFPasteboardSuccess && count > 0 &&
        CFPasteboardGetItemAtIndex(_general, 0, &item) == kCFPasteboardSuccess &&
        CFPasteboardCopyData(_general, item, (CFStringRef) type, &data) == kCFPasteboardSuccess && data != NULL) {
        [sender setData: (NSData *) data forType: type];
        CFRelease(data);
    }
}

- (void) pasteboardChangedOwner: (NSPasteboard *) sender {
}

@end

void NSPasteboardRegisterHostClipboard(NSPasteboard<NSPasteboardHostClipboard> *clipboard) {
    @synchronized([NSPasteboardHostBridge class]) {
        if (hostBridge == nil)
            hostBridge = [[NSPasteboardHostBridge alloc] initWithClipboard: clipboard];
    }
}
