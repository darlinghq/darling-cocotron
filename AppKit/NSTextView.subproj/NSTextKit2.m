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

// NSTextView's TextKit 2 accessors. TextKit 2 itself (NSTextRange,
// NSTextContentManager, NSTextContentStorage, NSTextLayoutManager) is in
// UIFoundation; text views here use TextKit 1 only.

#import <AppKit/NSTextContentManager.h>
#import <AppKit/NSTextLayoutManager.h>
#import <AppKit/NSTextView.h>

@implementation NSTextView (NSTextKit2)

+ (instancetype) textViewUsingTextLayoutManager: (BOOL) usingTextLayoutManager {
    // Only TextKit 1 text views exist here.
    return [[[self alloc] initWithFrame: NSZeroRect] autorelease];
}

- (NSTextLayoutManager *) textLayoutManager {
    return nil;
}

- (NSTextContentStorage *) textContentStorage {
    return nil;
}

@end
