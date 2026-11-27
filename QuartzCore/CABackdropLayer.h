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

#import <QuartzCore/CALayer.h>
#import <QuartzCore/LegacyIvarLayout.h>

// Private SPI, kept out of the public headers as on macOS: clients declare
// CABackdropLayer themselves. A layer whose filters apply to the content
// behind it. Darling's renderer does not sample the backdrop for such a layer
// yet, so it draws as a plain CALayer; its properties are kept.
// The state lives in side storage so the instance size stays CALayer's on the
// legacy ABI (Apple's size for this class is not known).
#define _NS_SIDE_CABackdropLayer 0, 1,
@interface CABackdropLayer : CALayer {
    NS_EXTRA_IVARS_BEGIN(CABackdropLayer)
        BOOL _windowServerAware;
        CGFloat _scale;
        BOOL _allowsInPlaceFiltering;
        NSString *_groupName;
    NS_SIDE_IVARS_END(CABackdropLayer)
}

// Whether the window server content behind the window is part of the backdrop.
@property BOOL windowServerAware;
@property (nonatomic) CGFloat scale;
@property (nonatomic) BOOL allowsInPlaceFiltering;
@property (nonatomic, copy) NSString *groupName;

@end
