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

#import <AppKit/NSMenuItemBadge.h>
#import <Foundation/NSString.h>

@implementation NSMenuItemBadge

@synthesize itemCount = _itemCount;
@synthesize type = _type;
@synthesize stringValue = _stringValue;

+ (instancetype) updatesWithCount: (NSInteger) itemCount {
    return [[[self alloc] initWithCount: itemCount
                                   type: NSMenuItemBadgeTypeUpdates]
            autorelease];
}

+ (instancetype) newItemsWithCount: (NSInteger) itemCount {
    return [[self alloc] initWithCount: itemCount
                                  type: NSMenuItemBadgeTypeNewItems];
}

+ (instancetype) alertsWithCount: (NSInteger) itemCount {
    return [[[self alloc] initWithCount: itemCount
                                   type: NSMenuItemBadgeTypeAlerts]
            autorelease];
}

- (instancetype) initWithCount: (NSInteger) itemCount
                          type: (NSMenuItemBadgeType) type
{
    self = [super init];
    if (self == nil)
        return nil;

    _itemCount = itemCount;
    _type = type;
    return self;
}

- (instancetype) initWithCount: (NSInteger) itemCount {
    return [self initWithCount: itemCount type: NSMenuItemBadgeTypeNone];
}

- (instancetype) initWithString: (NSString *) string {
    self = [self initWithCount: 0 type: NSMenuItemBadgeTypeNone];
    if (self == nil)
        return nil;

    _stringValue = [string copy];
    return self;
}

- (void) dealloc {
    [_stringValue release];
    [super dealloc];
}

- (NSString *) description {
    return [NSString stringWithFormat: @"<%@[%p] type: %ld count: %ld string: %@>",
                                       [self class], self, (long) _type,
                                       (long) _itemCount, _stringValue];
}

@end
