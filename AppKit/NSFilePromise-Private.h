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

#import <AppKit/NSFilePromiseProvider.h>
#import <AppKit/NSFilePromiseReceiver.h>

@class NSPasteboardItem;

// The pasteboard types of a file promise item, as a provider on macOS 26.7.3
// writes them.
#define NSFilePromiseMetaDataType @"com.apple.NSFilePromiseItemMetaData"
#define NSFilePromiseFileNameType @"com.apple.pasteboard.promised-file-name"
#define NSFilePromiseSuggestedFileNameType @"com.apple.pasteboard.promised-suggested-file-name"
#define NSFilePromiseContentTypeType @"com.apple.pasteboard.promised-file-content-type"
#define NSFilePromiseIDType @"com.apple.pasteboard.NSFilePromiseID"

@interface NSFilePromiseProvider (NSFilePromisePrivate)
// The provider of this process that wrote the promise, if it is still there.
+ (NSFilePromiseProvider *) _providerWithPromiseID: (NSData *) promiseID;
@end

@interface NSFilePromiseReceiver (NSFilePromisePrivate)
// Read by NSPasteboard instead of -initWithPasteboardPropertyList:ofType:, so
// the receiver sees all of the item and not just one of its types.
- (instancetype) _initWithPasteboardItem: (NSPasteboardItem *) item;
@end
