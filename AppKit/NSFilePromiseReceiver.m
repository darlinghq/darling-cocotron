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

#import "NSFilePromise-Private.h"
#import <AppKit/NSPasteboardItem.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSError.h>
#import <Foundation/NSOperation.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>

@implementation NSFilePromiseReceiver

// macOS 26.7.3 lists the metadata type, the content type and the dynamic
// type it gives the legacy NSFilesPromisePboardType; Darling's pasteboard
// keeps the legacy type under its own name, so that is the name listed here.
+ (NSArray<NSString *> *) readableDraggedTypes {
    return [NSArray arrayWithObjects: NSFilePromiseMetaDataType, NSFilesPromisePboardType,
                                      NSFilePromiseContentTypeType, nil];
}

+ (NSArray<NSPasteboardType> *) readableTypesForPasteboard: (NSPasteboard *) pasteboard {
    return [self readableDraggedTypes];
}

- (instancetype) _initWithPasteboardItem: (NSPasteboardItem *) item {
    self = [super init];
    if (self == nil)
        return nil;

    NSArray *fileTypes = nil;
    id metaData = [item propertyListForType: NSFilePromiseMetaDataType];
    if ([metaData isKindOfClass: [NSDictionary class]]) {
        NSString *type = [metaData objectForKey: NSFilePromiseContentTypeType];
        if ([type isKindOfClass: [NSString class]])
            fileTypes = [NSArray arrayWithObject: type];
    }
    if (fileTypes == nil) {
        NSString *type = [item stringForType: NSFilePromiseContentTypeType];
        if (type != nil)
            fileTypes = [NSArray arrayWithObject: type];
    }
    if (fileTypes == nil) {
        // a legacy promise: the list of the types of its files
        id legacy = [item propertyListForType: NSFilesPromisePboardType];
        if ([legacy isKindOfClass: [NSArray class]])
            fileTypes = legacy;
    }
    if (fileTypes == nil) {
        [self release];
        return nil;
    }

    NS_EXTRA(NSFilePromiseReceiver, self)->_fileTypes = [fileTypes copy];
    NS_EXTRA(NSFilePromiseReceiver, self)->_promiseID = [[item dataForType: NSFilePromiseIDType] copy];
    return self;
}

- (void) dealloc {
    if (NS_EXTRA_ALLOCATED(NSFilePromiseReceiver, self)) {
        [NS_EXTRA(NSFilePromiseReceiver, self)->_fileTypes release];
        [NS_EXTRA(NSFilePromiseReceiver, self)->_fileNames release];
        [NS_EXTRA(NSFilePromiseReceiver, self)->_promiseID release];
    }
    NS_EXTRA_FREE(NSFilePromiseReceiver, self);
    [super dealloc];
}

- (NSArray<NSString *> *) fileTypes {
    return [[NS_EXTRA(NSFilePromiseReceiver, self)->_fileTypes retain] autorelease];
}

// nil until the files are asked for (observed on macOS 26.7.3; the header
// says an empty array)
- (NSArray<NSString *> *) fileNames {
    @synchronized(self) {
        return [[NS_EXTRA(NSFilePromiseReceiver, self)->_fileNames retain] autorelease];
    }
}

static void callReader(NSOperationQueue *queue, void (^reader)(NSURL *, NSError *), NSURL *url, NSError *error) {
    [queue addOperationWithBlock: ^{
        reader(url, error);
    }];
}

- (void) receivePromisedFilesAtDestination: (NSURL *) destinationDir
                                   options: (NSDictionary *) options
                            operationQueue: (NSOperationQueue *) operationQueue
                                    reader: (void (^)(NSURL *fileURL, NSError *errorOrNil)) reader
{
    NSOperationQueue *readerQueue = operationQueue != nil ? operationQueue : [NSOperationQueue mainQueue];
    reader = [[reader copy] autorelease];

    NSFilePromiseProvider *provider =
            [NSFilePromiseProvider _providerWithPromiseID: NS_EXTRA(NSFilePromiseReceiver, self)->_promiseID];
    id<NSFilePromiseProviderDelegate> delegate = [provider delegate];
    if (delegate == nil) {
        // Only a provider of this process can be asked for its file.
        NSError *error = [NSError errorWithDomain: NSCocoaErrorDomain
                                             code: NSFeatureUnsupportedError
                                         userInfo: nil];
        for (NSUInteger i = 0; i < [[self fileTypes] count]; i++)
            callReader(readerQueue, reader, destinationDir, error);
        return;
    }

    NSString *name = [delegate filePromiseProvider: provider fileNameForType: [provider fileType]];
    if (name == nil) {
        callReader(readerQueue, reader, destinationDir,
                   [NSError errorWithDomain: NSCocoaErrorDomain code: NSFileWriteUnknownError userInfo: nil]);
        return;
    }
    @synchronized(self) {
        [NS_EXTRA(NSFilePromiseReceiver, self)->_fileNames release];
        NS_EXTRA(NSFilePromiseReceiver, self)->_fileNames = [[NSArray alloc] initWithObjects: name, nil];
    }

    NSURL *fileURL = [destinationDir URLByAppendingPathComponent: name];
    NSOperationQueue *writeQueue = nil;
    if ([delegate respondsToSelector: @selector(operationQueueForFilePromiseProvider:)])
        writeQueue = [delegate operationQueueForFilePromiseProvider: provider];
    if (writeQueue == nil)
        writeQueue = [NSOperationQueue mainQueue];

    NSFilePromiseProvider *heldProvider = [provider retain];
    [writeQueue addOperationWithBlock: ^{
        [delegate filePromiseProvider: heldProvider
                    writePromiseToURL: fileURL
                    completionHandler: ^(NSError *errorOrNil) {
            callReader(readerQueue, reader, fileURL, errorOrNil);
        }];
        [heldProvider release];
    }];
}

@end
