/*
 This file is part of Darling.

 Copyright (C) 2021 Lubos Dolezel

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

#import <AppKit/AppKitExport.h>
#import <AppKit/AppKitIvarLayout.h>
#import <Foundation/Foundation.h>

// The instance variables fill 22 of the 60 bytes Apple's legacy (i386) layout has
@interface NSCollectionViewLayoutInvalidationContext : NSObject {
    NSMutableSet *_invalidatedItemIndexPaths;
    NSPoint _contentOffsetAdjustment;
    NSSize _contentSizeAdjustment;
    BOOL _invalidateEverything;
    BOOL _invalidateDataSourceCounts;
    NS_LEGACY_IVAR_PAD(_NSCollectionViewLayoutInvalidationContextReserved, 38)
}

@property(readonly) BOOL invalidateEverything;
@property(readonly) BOOL invalidateDataSourceCounts;
- (void) invalidateItemsAtIndexPaths: (NSSet<NSIndexPath *> *) indexPaths;
@property(readonly) NSSet<NSIndexPath *> *invalidatedItemIndexPaths;
@property NSPoint contentOffsetAdjustment;
@property NSSize contentSizeAdjustment;

@end
