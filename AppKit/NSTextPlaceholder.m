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

#import <AppKit/NSTextPlaceholder.h>
#import <Foundation/NSArray.h>

// Observed on macOS 26.7.3: both classes descend directly from NSObject, and a placeholder made
// with -init has no rects. Test: tests/appkit-text-placeholder.m.

@implementation NSTextSelectionRect

- (NSRect)rect
{
    return NSZeroRect;
}

- (NSWritingDirection)writingDirection
{
    return NSWritingDirectionNatural;
}

- (BOOL)isVertical
{
    return NO;
}

- (NSAffineTransform *)transform
{
    return nil;
}

- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSTextSelectionRect class]])
        return NO;
    NSTextSelectionRect *rect = other;
    return NSEqualRects([self rect], [rect rect]) && [self writingDirection] == [rect writingDirection]
        && [self isVertical] == [rect isVertical];
}

- (NSUInteger)hash
{
    NSRect rect = [self rect];
    return (NSUInteger) (rect.origin.x * 31 + rect.origin.y * 17 + rect.size.width * 7 + rect.size.height);
}

@end

@implementation NSTextPlaceholder

@synthesize placeholderRange = _placeholderRange;

- (void)dealloc
{
    [_rects release];
    [super dealloc];
}

- (NSArray *)rects
{
    return _rects;
}

- (void)setRects:(NSArray *)rects
{
    if (rects == _rects)
        return;
    [_rects release];
    _rects = [rects copy];
}

@end
