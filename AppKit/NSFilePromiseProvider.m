/*
 This file is part of Darling.

 Copyright (C) 2025 Darling Developers

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

#import "NSFilePromise-Private.h"
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>
#include <unistd.h>

// The providers of this process by promise ID, not retained: a provider
// leaves when it is deallocated.
static NSMutableDictionary *providers;
static unsigned long long lastPromise;

// An ID names the process too, so a receiver in another process can tell the
// promise is not one it can reach.
static unsigned long long newPromiseID(void) {
    return ((unsigned long long) getpid() << 32) | (unsigned long long) ++lastPromise;
}

@implementation NSFilePromiseProvider

NS_EXTRA_SYNTHESIZE_COPY(NSFilePromiseProvider, fileType, _fileType, NSString *, fileType, setFileType:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSFilePromiseProvider, delegate, _delegate,
                           id<NSFilePromiseProviderDelegate>, delegate, setDelegate:)
NS_EXTRA_SYNTHESIZE_RETAIN(NSFilePromiseProvider, userInfo, _userInfo, id, userInfo, setUserInfo:)

- (instancetype) init {
    self = [super init];
    if (self == nil)
        return nil;
    @synchronized([NSFilePromiseProvider class]) {
        if (providers == nil)
            providers = [[NSMutableDictionary alloc] init];
        unsigned long long promiseID = newPromiseID();
        NS_EXTRA(NSFilePromiseProvider, self)->_promiseID = promiseID;
        [providers setObject: [NSValue valueWithNonretainedObject: self]
                      forKey: [NSNumber numberWithUnsignedLongLong: promiseID]];
    }
    return self;
}

- (instancetype) initWithFileType: (NSString *) fileType
                         delegate: (id<NSFilePromiseProviderDelegate>) delegate
{
    self = [self init];
    if (self != nil) {
        [self setFileType: fileType];
        [self setDelegate: delegate];
    }
    return self;
}

- (void) dealloc {
    @synchronized([NSFilePromiseProvider class]) {
        [providers removeObjectForKey:
                [NSNumber numberWithUnsignedLongLong: NS_EXTRA(NSFilePromiseProvider, self)->_promiseID]];
    }
    if (NS_EXTRA_ALLOCATED(NSFilePromiseProvider, self)) {
        [NS_EXTRA(NSFilePromiseProvider, self)->_fileType release];
        [NS_EXTRA(NSFilePromiseProvider, self)->_userInfo release];
    }
    NS_EXTRA_FREE(NSFilePromiseProvider, self);
    [super dealloc];
}

+ (NSFilePromiseProvider *) _providerWithPromiseID: (NSData *) data {
    unsigned long long promiseID;
    if ([data length] != sizeof(promiseID))
        return nil;
    [data getBytes: &promiseID length: sizeof(promiseID)];
    @synchronized([NSFilePromiseProvider class]) {
        NSValue *value = [providers objectForKey: [NSNumber numberWithUnsignedLongLong: promiseID]];
        return [[[value nonretainedObjectValue] retain] autorelease];
    }
}

#pragma mark NSPasteboardWriting

// The types and the promised ones among them as observed on macOS 26.7.3.
- (NSArray<NSPasteboardType> *) writableTypesForPasteboard: (NSPasteboard *) pasteboard {
    return [NSArray arrayWithObjects: NSFilePromiseMetaDataType, NSFilePromiseFileNameType,
                                      NSFilePromiseSuggestedFileNameType, NSFilePromiseContentTypeType,
                                      NSFilePromiseIDType, nil];
}

- (NSPasteboardWritingOptions) writingOptionsForType: (NSPasteboardType) type
                                          pasteboard: (NSPasteboard *) pasteboard
{
    if ([type isEqualToString: NSFilePromiseFileNameType] ||
        [type isEqualToString: NSFilePromiseSuggestedFileNameType])
        return NSPasteboardWritingPromised;
    return 0;
}

- (id) pasteboardPropertyListForType: (NSPasteboardType) type {
    NSString *fileType = [self fileType];
    if ([type isEqualToString: NSFilePromiseMetaDataType])
        return fileType != nil ? [NSDictionary dictionaryWithObject: fileType forKey: NSFilePromiseContentTypeType]
                               : [NSDictionary dictionary];
    if ([type isEqualToString: NSFilePromiseContentTypeType])
        return fileType;
    if ([type isEqualToString: NSFilePromiseSuggestedFileNameType])
        return [[self delegate] filePromiseProvider: self fileNameForType: fileType];
    if ([type isEqualToString: NSFilePromiseIDType]) {
        unsigned long long promiseID = NS_EXTRA(NSFilePromiseProvider, self)->_promiseID;
        return [NSData dataWithBytes: &promiseID length: sizeof(promiseID)];
    }
    // The name of the written file, which the receiver learns when it is written.
    return nil;
}

@end
