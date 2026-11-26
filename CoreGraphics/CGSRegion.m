/*
 This file is part of Darling.

 Copyright (C) 2020 Lubos Dolezel

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
#include <CoreGraphics/CoreGraphicsPrivate.h>
#import <Foundation/NSObject.h>

@interface CGSRegion : NSObject {
    CGRect _rect;
}
@property CGRect rect;
@end

@implementation CGSRegion
@synthesize rect = _rect;
@end

CGError CGSNewRegionWithRect(const CGRect *rect, CGSRegionRef *newRegion) {
    if (rect == NULL || newRegion == NULL)
        return kCGErrorIllegalArgument;
    CGSRegion *reg = [CGSRegion new];
    reg.rect = *rect;
    *newRegion = (CGSRegionRef) reg;
    return kCGSErrorSuccess;
}

void CGSRegionRelease(CGSRegionRef reg) {
    CGSRegion *r = (CGSRegion *) reg;
    [r release];
}

void CGSRegionRetain(CGSRegionRef reg) {
    CGSRegion *r = (CGSRegion *) reg;
    [r retain];
}

// This is non-standard. We should support non-rectangular regions instead
void CGSRegionToRect(CGSRegionRef reg, CGRect *rect) {
    CGSRegion *r = (CGSRegion *) reg;
    *rect = r.rect;
}

bool CGSRegionIsRectangular(CGSRegionRef reg) {
    return TRUE;
}

CGRegionRef CGRegionCreateWithRect(CGRect rect) {
    CGSRegionRef region;
    CGSNewRegionWithRect(&rect, &region);
    return region;
}

void CGRegionRelease(CGRegionRef region) {
    CGSRegionRelease(region);
}

// CGSRegionRelease under the name WebKit uses; there is nothing to fail.
CGError CGSReleaseRegion(const CGSRegionRef region) {
    if (region != NULL)
        CGSRegionRelease(region);
    return kCGErrorSuccess;
}

// The regions here are single rectangles, so an enumerator holds at most one
// rectangle; an empty region has none.
struct CGSRegionEnumeratorObject {
    CGRect rects[1];
    size_t count;
    size_t next;
};

CGSRegionEnumeratorObj CGSRegionEnumerator(CGSRegionRef region) {
    if (region == NULL)
        return NULL;
    CGSRegionEnumeratorObj enumerator = calloc(1, sizeof(struct CGSRegionEnumeratorObject));
    if (enumerator == NULL)
        return NULL;
    CGRect rect;
    CGSRegionToRect(region, &rect);
    if (!CGRectIsEmpty(rect))
        enumerator->rects[enumerator->count++] = CGRectStandardize(rect);
    return enumerator;
}

CGRect *CGSNextRect(const CGSRegionEnumeratorObj enumerator) {
    if (enumerator == NULL || enumerator->next >= enumerator->count)
        return NULL;
    return &enumerator->rects[enumerator->next++];
}

CGError CGSReleaseRegionEnumerator(const CGSRegionEnumeratorObj enumerator) {
    free(enumerator);
    return kCGErrorSuccess;
}

