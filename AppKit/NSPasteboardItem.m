/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

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

#import <AppKit/NSPasteboardItem.h>
#import "NSPasteboardAliases.h"

// Standalone items keep their own data and data providers. Items read off a pasteboard that was
// written some other way ("derived") keep nothing: they are a view of the pasteboard's flat types.

@interface NSPasteboardItem (NSPasteboardPrivate)
- (void) _fulfillType: (NSPasteboardType) type;
- (void) _promiseOwnerCreated;
- (void) _promiseOwnerDestroyed;
- (void) _finishProviders;
@end

// What the pasteboard calls for a type that was promised, not written: asks the item to produce it.
@interface NSPasteboardItemPromiseOwner : NSObject <NSPasteboardTypeOwner> {
    NSPasteboardItem *_item;
}
- (id) initWithItem: (NSPasteboardItem *) item;
@end

// The data provider of a type an NSPasteboardWriting object promised.
@interface NSPasteboardWritingProvider : NSObject <NSPasteboardItemDataProvider> {
    id<NSPasteboardWriting> _object;
}
- (id) initWithObject: (id<NSPasteboardWriting>) object;
@end

static NSData *dataOfPropertyList(id plist) {
    if (plist == nil)
        return nil;
    if ([plist isKindOfClass: [NSData class]])
        return plist;
    if ([plist isKindOfClass: [NSString class]])
        return [(NSString *) plist dataUsingEncoding: NSUTF8StringEncoding];
    NSString *error = nil;
    return [NSPropertyListSerialization dataFromPropertyList: plist
                                                      format: NSPropertyListXMLFormat_v1_0
                                            errorDescription: &error];
}

@implementation NSPasteboardItem

- (id) init {
    if ((self = [super init])) {
        NS_EXTRA(NSPasteboardItem, self)->_orderedTypes = [NSMutableArray new];
        NS_EXTRA(NSPasteboardItem, self)->_data = [NSMutableDictionary new];
        NS_EXTRA(NSPasteboardItem, self)->_providers = [NSMutableDictionary new];
    }
    return self;
}

- (id) _initDerivedFromPasteboard: (NSPasteboard *) pasteboard {
    if ((self = [self init])) {
        NS_EXTRA(NSPasteboardItem, self)->_derived = YES;
        NS_EXTRA(NSPasteboardItem, self)->_pasteboard = pasteboard;
    }
    return self;
}

- (id) _initWithWritingObject: (id<NSPasteboardWriting>) object pasteboard: (NSPasteboard *) pasteboard {
    if ((self = [self init])) {
        NSPasteboardWritingProvider *provider = nil;
        for (NSPasteboardType type in NSPasteboardCanonicalTypes([object writableTypesForPasteboard: pasteboard])) {
            NSPasteboardWritingOptions options = 0;
            if ([object respondsToSelector: @selector(writingOptionsForType:pasteboard:)])
                options = [object writingOptionsForType: type pasteboard: pasteboard];

            if (options & NSPasteboardWritingPromised) {
                if (provider == nil)
                    provider = [[[NSPasteboardWritingProvider alloc] initWithObject: object] autorelease];
                [self setDataProvider: provider forTypes: [NSArray arrayWithObject: type]];
            } else {
                NSData *data = dataOfPropertyList([object pasteboardPropertyListForType: type]);
                if (data != nil)
                    [self setData: data forType: type];
            }
        }
    }
    return self;
}

- (void) dealloc {
    // Providers of a standalone item that was never written, or whose pasteboard owners are all gone.
    if (NS_EXTRA(NSPasteboardItem, self)->_promiseOwners == 0 && !NS_EXTRA(NSPasteboardItem, self)->_derived)
        [self _finishProviders];
    [NS_EXTRA(NSPasteboardItem, self)->_orderedTypes release];
    [NS_EXTRA(NSPasteboardItem, self)->_data release];
    [NS_EXTRA(NSPasteboardItem, self)->_providers release];
    NS_EXTRA_FREE(NSPasteboardItem, self);
    [super dealloc];
}

- (void) _finishProviders {
    if (NS_EXTRA(NSPasteboardItem, self)->_providersFinished)
        return;
    NS_EXTRA(NSPasteboardItem, self)->_providersFinished = YES;
    NSMutableArray *finished = [NSMutableArray array];
    for (id provider in [NS_EXTRA(NSPasteboardItem, self)->_providers allValues]) {
        if ([finished containsObject: provider])
            continue;
        [finished addObject: provider];
        if ([provider respondsToSelector: @selector(pasteboardFinishedWithDataProvider:)])
            [provider pasteboardFinishedWithDataProvider: NS_EXTRA(NSPasteboardItem, self)->_pasteboard];
    }
}

- (void) _promiseOwnerCreated {
    NS_EXTRA(NSPasteboardItem, self)->_promiseOwners++;
}

- (void) _promiseOwnerDestroyed {
    // The pasteboard gave up the last promise: the providers are not needed any more.
    if (NS_EXTRA(NSPasteboardItem, self)->_promiseOwners > 0 && --NS_EXTRA(NSPasteboardItem, self)->_promiseOwners == 0)
        [self _finishProviders];
}

- (NSArray *) _orderedTypes {
    return [[NS_EXTRA(NSPasteboardItem, self)->_orderedTypes copy] autorelease];
}

- (NSData *) _storedDataForType: (NSPasteboardType) type {
    return [NS_EXTRA(NSPasteboardItem, self)->_data objectForKey: type];
}

- (id<NSPasteboardTypeOwner>) _promiseOwner {
    return [[[NSPasteboardItemPromiseOwner alloc] initWithItem: self] autorelease];
}

// The item is the first item of a pasteboard (the one whose types are the flat types): values
// set on it afterwards, such as the result of a data provider, go to that pasteboard too, as
// long as nothing else has changed it.
- (void) _attachToPasteboard: (NSPasteboard *) pasteboard {
    NS_EXTRA(NSPasteboardItem, self)->_pasteboard = pasteboard;
    NS_EXTRA(NSPasteboardItem, self)->_attached = YES;
    NS_EXTRA(NSPasteboardItem, self)->_attachedChangeCount = [pasteboard changeCount];
}

- (BOOL) _isAttachedToCurrentContents {
    return NS_EXTRA(NSPasteboardItem, self)->_attached && NS_EXTRA(NSPasteboardItem, self)->_pasteboard != nil && [NS_EXTRA(NSPasteboardItem, self)->_pasteboard changeCount] == NS_EXTRA(NSPasteboardItem, self)->_attachedChangeCount;
}

- (void) _fulfillType: (NSPasteboardType) type {
    if ([NS_EXTRA(NSPasteboardItem, self)->_data objectForKey: type] == nil) {
        id<NSPasteboardItemDataProvider> provider = [NS_EXTRA(NSPasteboardItem, self)->_providers objectForKey: type];
        [provider pasteboard: NS_EXTRA(NSPasteboardItem, self)->_pasteboard item: self provideDataForType: type];
    }
    NSData *data = [NS_EXTRA(NSPasteboardItem, self)->_data objectForKey: type];
    // A provider that only set the value on the item (after the pasteboard was changed again, say)
    // leaves the pasteboard without it; hand it over.
    if (data != nil && [self _isAttachedToCurrentContents])
        [NS_EXTRA(NSPasteboardItem, self)->_pasteboard setData: data forType: type];
}

- (NSArray<NSPasteboardType> *) types {
    if (!NS_EXTRA(NSPasteboardItem, self)->_derived)
        return [[NS_EXTRA(NSPasteboardItem, self)->_orderedTypes copy] autorelease];

    // The flat types of the pasteboard in their UTI spelling. The older file name list and URL
    // types are another spelling of the file URL items, not types of their own.
    NSMutableArray *types = [NSMutableArray array];
    for (NSPasteboardType type in NSPasteboardCanonicalTypes([NS_EXTRA(NSPasteboardItem, self)->_pasteboard types])) {
        if ([type isEqual: NSFilenamesPboardType] || [type isEqual: NSURLPboardType])
            continue;
        [types addObject: type];
    }
    return types;
}

- (NSPasteboardType) availableTypeFromArray: (NSArray<NSPasteboardType> *) types {
    NSArray *have = [self types];
    for (NSPasteboardType type in types) {
        NSPasteboardType canonical = NSPasteboardCanonicalType(type);
        if ([have containsObject: canonical])
            return type;
    }
    for (NSPasteboardType type in types) {
        for (NSPasteboardType itemType in have) {
            if (NSPasteboardTypeConformsTo(itemType, type))
                return itemType;
        }
    }
    return nil;
}

- (BOOL) setDataProvider: (id<NSPasteboardItemDataProvider>) dataProvider
                forTypes: (NSArray<NSPasteboardType> *) types
{
    // A derived item is a view of a pasteboard other code wrote; it has nobody to make the promise
    // to, so only standalone items take providers.
    if (NS_EXTRA(NSPasteboardItem, self)->_derived || dataProvider == nil)
        return NO;
    for (NSPasteboardType type in NSPasteboardCanonicalTypes(types)) {
        if (![NS_EXTRA(NSPasteboardItem, self)->_orderedTypes containsObject: type])
            [NS_EXTRA(NSPasteboardItem, self)->_orderedTypes addObject: type];
        [NS_EXTRA(NSPasteboardItem, self)->_data removeObjectForKey: type];
        [NS_EXTRA(NSPasteboardItem, self)->_providers setObject: dataProvider forKey: type];
    }
    return YES;
}

- (BOOL) setData: (NSData *) data forType: (NSPasteboardType) type {
    type = NSPasteboardCanonicalType(type);
    if (data == nil || type == nil)
        return NO;
    if (NS_EXTRA(NSPasteboardItem, self)->_derived)
        return [NS_EXTRA(NSPasteboardItem, self)->_pasteboard setData: data forType: type];

    if (![NS_EXTRA(NSPasteboardItem, self)->_orderedTypes containsObject: type])
        [NS_EXTRA(NSPasteboardItem, self)->_orderedTypes addObject: type];
    [NS_EXTRA(NSPasteboardItem, self)->_data setObject: [[data copy] autorelease] forKey: type];
    if ([self _isAttachedToCurrentContents])
        [NS_EXTRA(NSPasteboardItem, self)->_pasteboard setData: data forType: type];
    return YES;
}

- (BOOL) setString: (NSString *) string forType: (NSPasteboardType) type {
    return [self setData: [string dataUsingEncoding: NSUTF8StringEncoding] forType: type];
}

- (BOOL) setPropertyList: (id) propertyList forType: (NSPasteboardType) type {
    return [self setData: dataOfPropertyList(propertyList) forType: type];
}

- (NSData *) dataForType: (NSPasteboardType) type {
    type = NSPasteboardCanonicalType(type);
    if (NS_EXTRA(NSPasteboardItem, self)->_derived)
        return [NS_EXTRA(NSPasteboardItem, self)->_pasteboard dataForType: type];

    if ([NS_EXTRA(NSPasteboardItem, self)->_data objectForKey: type] == nil && [NS_EXTRA(NSPasteboardItem, self)->_providers objectForKey: type] != nil)
        [self _fulfillType: type];
    return [[[NS_EXTRA(NSPasteboardItem, self)->_data objectForKey: type] retain] autorelease];
}

- (NSString *) stringForType: (NSPasteboardType) type {
    NSData *data = [self dataForType: type];
    if (data == nil)
        return nil;
    NSString *string = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
    if (string == nil && [type rangeOfString: @"utf16"].location != NSNotFound)
        string = [[[NSString alloc] initWithData: data encoding: NSUnicodeStringEncoding] autorelease];
    return string;
}

- (id) propertyListForType: (NSPasteboardType) type {
    NSData *data = [self dataForType: type];
    if (data == nil)
        return nil;
    NSString *error = nil;
    id plist = [NSPropertyListSerialization propertyListFromData: data
                                                mutabilityOption: NSPropertyListImmutable
                                                          format: NULL
                                                errorDescription: &error];
    return error == nil ? plist : nil;
}

#pragma mark NSPasteboardWriting

- (NSArray<NSPasteboardType> *) writableTypesForPasteboard: (NSPasteboard *) pasteboard {
    return [self types];
}

- (id) pasteboardPropertyListForType: (NSPasteboardType) type {
    return [self dataForType: type];
}

#pragma mark NSPasteboardReading

+ (NSArray<NSPasteboardType> *) readableTypesForPasteboard: (NSPasteboard *) pasteboard {
    return NSPasteboardCanonicalTypes([pasteboard types]);
}

+ (NSPasteboardReadingOptions) readingOptionsForType: (NSPasteboardType) type pasteboard: (NSPasteboard *) pasteboard {
    return NSPasteboardReadingAsData;
}

- (id) initWithPasteboardPropertyList: (id) propertyList ofType: (NSPasteboardType) type {
    if ((self = [self init]))
        [self setData: dataOfPropertyList(propertyList) forType: type];
    return self;
}

@end

@implementation NSPasteboardItemPromiseOwner

- (id) initWithItem: (NSPasteboardItem *) item {
    if ((self = [super init])) {
        _item = [item retain];
        [_item _promiseOwnerCreated];
    }
    return self;
}

- (void) dealloc {
    [_item _promiseOwnerDestroyed];
    [_item release];
    [super dealloc];
}

- (void) pasteboard: (NSPasteboard *) sender provideDataForType: (NSPasteboardType) type {
    [_item _fulfillType: NSPasteboardCanonicalType(type)];
}

@end

@implementation NSPasteboardWritingProvider

- (id) initWithObject: (id<NSPasteboardWriting>) object {
    if ((self = [super init]))
        _object = [(id) object retain];
    return self;
}

- (void) dealloc {
    [(id) _object release];
    [super dealloc];
}

- (void) pasteboard: (NSPasteboard *) pasteboard
                item: (NSPasteboardItem *) item
  provideDataForType: (NSPasteboardType) type
{
    NSData *data = dataOfPropertyList([_object pasteboardPropertyListForType: type]);
    if (data != nil)
        [item setData: data forType: type];
}

@end
