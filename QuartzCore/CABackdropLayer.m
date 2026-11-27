/*
 This file is part of Darling.

 Copyright (C) 2026 Darling Developers

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

#import "CABackdropLayer.h"

@implementation CABackdropLayer

NS_EXTRA_SYNTHESIZE_ASSIGN(CABackdropLayer, windowServerAware, _windowServerAware, BOOL, windowServerAware, setWindowServerAware:)
NS_EXTRA_SYNTHESIZE_ASSIGN(CABackdropLayer, scale, _scale, CGFloat, scale, setScale:)
NS_EXTRA_SYNTHESIZE_ASSIGN(CABackdropLayer, allowsInPlaceFiltering, _allowsInPlaceFiltering, BOOL, allowsInPlaceFiltering, setAllowsInPlaceFiltering:)
NS_EXTRA_SYNTHESIZE_COPY(CABackdropLayer, groupName, _groupName, NSString *, groupName, setGroupName:)

// windowServerAware starts as NO, and initWithLayer: does not take it from
// the layer copied: observed on macOS 26.7.3 and 10.14.4 (black-box, through
// the property and KVC). Set here because the i386 extra storage is not
// zeroed. Test: tests/quartzcore-backdrop-layer-presentation-modifier.m
- init {
    self = [super init];
    if (self != nil) {
        NS_EXTRA(CABackdropLayer, self)->_windowServerAware = NO;
        NS_EXTRA(CABackdropLayer, self)->_scale = 1.0;
        NS_EXTRA(CABackdropLayer, self)->_allowsInPlaceFiltering = NO;
        NS_EXTRA(CABackdropLayer, self)->_groupName = nil;
    }
    return self;
}

- initWithLayer: (id) layer {
    self = [super initWithLayer: layer];
    if (self != nil) {
        // Like -[CALayer initWithLayer:], the copy starts in the default state.
        NS_EXTRA(CABackdropLayer, self)->_windowServerAware = NO;
        NS_EXTRA(CABackdropLayer, self)->_scale = 1.0;
        NS_EXTRA(CABackdropLayer, self)->_allowsInPlaceFiltering = NO;
        NS_EXTRA(CABackdropLayer, self)->_groupName = nil;
    }
    return self;
}

- (void) dealloc {
    if (NS_EXTRA_ALLOCATED(CABackdropLayer, self)) {
        [NS_EXTRA(CABackdropLayer, self)->_groupName release];
    }
    NS_EXTRA_FREE(CABackdropLayer, self);
    [super dealloc];
}

@end
