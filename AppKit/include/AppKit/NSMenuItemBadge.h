/* Copyright (c) 2026 Darling Developers

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/AppKitExport.h>
#import <Foundation/NSObject.h>

@class NSString;

typedef NS_ENUM(NSInteger, NSMenuItemBadgeType) {
    NSMenuItemBadgeTypeNone = 0,
    NSMenuItemBadgeTypeUpdates,
    NSMenuItemBadgeTypeNewItems,
    NSMenuItemBadgeTypeAlerts,
};

// A count or a short string shown at the trailing edge of a menu item.

APPKIT_EXPORT
@interface NSMenuItemBadge : NSObject {
    NSInteger _itemCount;
    NSMenuItemBadgeType _type;
    NSString *_stringValue;
}

+ (instancetype) updatesWithCount: (NSInteger) itemCount;
// Like any method in the "new" family, this returns an object the caller
// owns.
+ (instancetype) newItemsWithCount: (NSInteger) itemCount;
+ (instancetype) alertsWithCount: (NSInteger) itemCount;

- (instancetype) initWithCount: (NSInteger) itemCount
                          type: (NSMenuItemBadgeType) type;
- (instancetype) initWithCount: (NSInteger) itemCount;
- (instancetype) initWithString: (NSString *) string;

@property(readonly) NSInteger itemCount;
@property(readonly) NSMenuItemBadgeType type;
@property(readonly, copy) NSString *stringValue;

@end
