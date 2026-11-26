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

#import <Foundation/NSObject.h>
#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSPasteboard.h>

@class NSArray, NSData, NSDictionary, NSError, NSOperationQueue, NSString, NSURL;

// A file promise read from a pasteboard. Its class has no instance variables
// on the legacy ABI, where Apple's layout is not known.
#define _NS_SIDE_NSFilePromiseReceiver 0, 1,
@interface NSFilePromiseReceiver : NSObject <NSPasteboardReading> {
    NS_EXTRA_IVARS_BEGIN(NSFilePromiseReceiver)
        NSArray *_fileTypes;
        NSArray *_fileNames;
        NSData *_promiseID;
    NS_SIDE_IVARS_END(NSFilePromiseReceiver)
}

// The types to register a destination for to be offered promises.
@property(class, readonly, copy) NSArray<NSString *> *readableDraggedTypes;

@property(copy, readonly) NSArray<NSString *> *fileTypes;
// nil until the files are received
@property(copy, readonly) NSArray<NSString *> *fileNames;

// Has the files written into the directory; the reader is called on the queue
// for each, with an error when it could not be written.
- (void) receivePromisedFilesAtDestination: (NSURL *) destinationDir
                                   options: (NSDictionary *) options
                            operationQueue: (NSOperationQueue *) operationQueue
                                    reader: (void (^)(NSURL *fileURL, NSError *errorOrNil)) reader;

@end
