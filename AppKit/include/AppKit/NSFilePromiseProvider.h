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

#import <Foundation/NSObject.h>
#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSPasteboard.h>

@class NSError, NSOperationQueue, NSString, NSURL;
@protocol NSFilePromiseProviderDelegate;

// Writes the promise of a file to a pasteboard; the delegate writes the file
// when a receiver asks for it. The receiver has to be in the same process:
// there is no service that would carry the request to another one.
@interface NSFilePromiseProvider : NSObject <NSPasteboardWriting> {
    NS_LEGACY_IVAR_PAD(_NSFilePromiseProviderReserved, 36)
    NS_EXTRA_IVARS_BEGIN(NSFilePromiseProvider)
        NSString *_fileType;
        id<NSFilePromiseProviderDelegate> _delegate;
        id _userInfo;
        unsigned long long _promiseID;
    NS_EXTRA_IVARS_END(NSFilePromiseProvider)
}

@property(copy) NSString *fileType;
// not retained
@property(assign) id<NSFilePromiseProviderDelegate> delegate;
@property(retain) id userInfo;

- (instancetype) initWithFileType: (NSString *) fileType
                         delegate: (id<NSFilePromiseProviderDelegate>) delegate;

@end

@protocol NSFilePromiseProviderDelegate <NSObject>
@required
- (NSString *) filePromiseProvider: (NSFilePromiseProvider *) filePromiseProvider
                   fileNameForType: (NSString *) fileType;
- (void) filePromiseProvider: (NSFilePromiseProvider *) filePromiseProvider
           writePromiseToURL: (NSURL *) url
           completionHandler: (void (^)(NSError *errorOrNil)) completionHandler;
@optional
- (NSOperationQueue *) operationQueueForFilePromiseProvider: (NSFilePromiseProvider *) filePromiseProvider;
@end
