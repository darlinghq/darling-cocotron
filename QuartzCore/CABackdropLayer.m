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

// windowServerAware starts as NO, and initWithLayer: does not take it from
// the layer copied: observed on macOS 26.7.3 and 10.14.4 (black-box, through
// the property and KVC). Set here because the i386 extra storage is not
// zeroed. Test: tests/quartzcore-backdrop-layer-presentation-modifier.m
- init {
    self = [super init];
    if (self != nil)
        NS_EXTRA(CABackdropLayer, self)->_windowServerAware = NO;
    return self;
}

- initWithLayer: (id) layer {
    self = [super initWithLayer: layer];
    if (self != nil)
        NS_EXTRA(CABackdropLayer, self)->_windowServerAware = NO;
    return self;
}

@end
