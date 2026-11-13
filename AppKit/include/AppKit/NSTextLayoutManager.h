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

// TextKit 2 layout manager (macOS 12), minimal: layout is done by a TextKit 1
// NSLayoutManager attached to the content storage's NSTextStorage.

#import <AppKit/NSTextContentManager.h>
#import <AppKit/NSTextView.h>

@class NSTextContainer, NSLayoutManager;

@interface NSTextLayoutManager : NSObject {
    NSTextContentManager *_textContentManager; // not retained (it owns us)
    NSTextContainer *_textContainer;
    NSLayoutManager *_layoutManager;
    NSTextContainer *_templateTextContainer;
    BOOL _usesDefaultHyphenation;
}

@property(readonly, assign) NSTextContentManager *textContentManager;
@property(retain) NSTextContainer *textContainer;
@property(readonly) NSArray *textContainers;
@property(readonly) NSRect usageBoundsForTextContainer;
@property(readonly, retain) NSTextRange *documentRange;

- (void) replaceTextContentManager: (NSTextContentManager *) textContentManager;
- (void) ensureLayoutForRange: (NSTextRange *) range;

// Stored only: layout uses textContainer, with no containers made from it.
@property(retain) NSTextContainer *templateTextContainer;
// Stored only (NO by default): there's no hyphenation.
@property BOOL usesDefaultHyphenation;
// Invalidates the TextKit 1 layout of the whole document.
- (void) invalidateLayoutForRange: (NSTextRange *) range;
// The characters laid out in textContainer for index 0 (the whole document
// before layout places any); nil for other indexes.
- (NSTextRange *) rangeForTextContainerAtIndex: (NSUInteger) index;

@end

// Cocotron text views use TextKit 1, for which AppKit reports nil here.
@interface NSTextView (NSTextKit2)
+ (instancetype) textViewUsingTextLayoutManager: (BOOL) usingTextLayoutManager;
@property(readonly) NSTextLayoutManager *textLayoutManager;
@property(readonly) NSTextContentStorage *textContentStorage;
@end
