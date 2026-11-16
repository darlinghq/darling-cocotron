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

#import <Foundation/NSObject.h>
#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSPasteboard.h>

@protocol NSPasteboardItemDataProvider;

// One item of a pasteboard: the data of one thing, offered in one or more types (UTIs).
@interface NSPasteboardItem : NSObject <NSPasteboardWriting, NSPasteboardReading> {
    NS_LEGACY_IVAR_PAD(_NSPasteboardItemReserved, 16)
    NS_EXTRA_IVARS_BEGIN(NSPasteboardItem)
    NSMutableArray *_orderedTypes;
    NSMutableDictionary *_data;
    NSMutableDictionary *_providers;
    NSPasteboard *_pasteboard;
    NSInteger _attachedChangeCount;
    BOOL _derived;
    BOOL _attached;
    BOOL _providersFinished;
    NSUInteger _promiseOwners;
    NS_EXTRA_IVARS_END(NSPasteboardItem)
}

@property(readonly, copy) NSArray<NSPasteboardType> *types;
- (NSPasteboardType) availableTypeFromArray: (NSArray<NSPasteboardType> *) types;

- (BOOL) setDataProvider: (id<NSPasteboardItemDataProvider>) dataProvider
                forTypes: (NSArray<NSPasteboardType> *) types;
- (BOOL) setData: (NSData *) data forType: (NSPasteboardType) type;
- (BOOL) setString: (NSString *) string forType: (NSPasteboardType) type;
- (BOOL) setPropertyList: (id) propertyList forType: (NSPasteboardType) type;

- (NSData *) dataForType: (NSPasteboardType) type;
- (NSString *) stringForType: (NSPasteboardType) type;
- (id) propertyListForType: (NSPasteboardType) type;

@end

@protocol NSPasteboardItemDataProvider <NSObject>
@required
- (void) pasteboard: (NSPasteboard *) pasteboard
                item: (NSPasteboardItem *) item
  provideDataForType: (NSPasteboardType) type;
@optional
- (void) pasteboardFinishedWithDataProvider: (NSPasteboard *) pasteboard;
@end
