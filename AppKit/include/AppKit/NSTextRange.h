/*
 This file is part of Darling.

 Copyright (C) 2026 Darling developers

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

// TextKit 2 text locations and ranges (macOS 12).

#import <AppKit/AppKitExport.h>
#import <Foundation/Foundation.h>

@protocol NSTextLocation <NSObject>
- (NSComparisonResult) compare: (id<NSTextLocation>) location;
@end

@interface NSTextRange : NSObject <NSCopying> {
    id<NSTextLocation> _location;
    id<NSTextLocation> _endLocation;
}

// Returns nil if endLocation precedes location. A nil endLocation makes an
// empty range at location.
- (instancetype) initWithLocation: (id<NSTextLocation>) location
                      endLocation: (id<NSTextLocation>) endLocation;
- (instancetype) initWithLocation: (id<NSTextLocation>) location;

@property(readonly, retain) id<NSTextLocation> location;
@property(readonly, retain) id<NSTextLocation> endLocation;
@property(readonly, getter=isEmpty) BOOL empty;

- (BOOL) isEqualToTextRange: (NSTextRange *) textRange;
- (BOOL) containsLocation: (id<NSTextLocation>) location;
- (BOOL) containsRange: (NSTextRange *) textRange;
- (BOOL) intersectsWithTextRange: (NSTextRange *) textRange;
- (NSTextRange *) textRangeByIntersectingWithTextRange:
        (NSTextRange *) textRange;
- (NSTextRange *) textRangeByFormingUnionWithTextRange:
        (NSTextRange *) textRange;

@end
