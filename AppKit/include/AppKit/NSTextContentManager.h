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

// TextKit 2 content managers (macOS 12), minimal: NSTextContentStorage keeps its
// content in an NSTextStorage, and locations are character offsets into it.

#import <AppKit/NSTextRange.h>

@class NSTextLayoutManager, NSTextStorage;

APPKIT_EXPORT NSString *const NSTextContentStorageUnsupportedAttributeAddedNotification;

@interface NSTextContentManager : NSObject {
    NSMutableArray *_textLayoutManagers;
    NSTextLayoutManager *_primaryTextLayoutManager; // one of _textLayoutManagers
    BOOL _automaticallySynchronizesTextLayoutManagers;
    BOOL _automaticallySynchronizesToBackingStore;
    NSInteger _editingTransactionDepth;
    BOOL _includesTextListMarkers;
}

@property(readonly, copy) NSArray *textLayoutManagers;
@property(assign) NSTextLayoutManager *primaryTextLayoutManager;
@property BOOL automaticallySynchronizesTextLayoutManagers;
@property BOOL automaticallySynchronizesToBackingStore;
@property(readonly) BOOL hasEditingTransaction;
@property(readonly, retain) NSTextRange *documentRange;
// Stored only: there are no text list elements.
@property BOOL includesTextListMarkers;

- (void) addTextLayoutManager: (NSTextLayoutManager *) textLayoutManager;
- (void) removeTextLayoutManager: (NSTextLayoutManager *) textLayoutManager;

- (id<NSTextLocation>) locationFromLocation: (id<NSTextLocation>) location
                                 withOffset: (NSInteger) offset;
- (NSInteger) offsetFromLocation: (id<NSTextLocation>) from
                      toLocation: (id<NSTextLocation>) to;

- (void) performEditingTransactionUsingBlock: (void (^)(void)) transaction;

@end

@interface NSTextContentStorage : NSTextContentManager {
    NSTextStorage *_textStorage;
}

@property(retain) NSTextStorage *textStorage;
@property(copy) NSAttributedString *attributedString;

@end
