/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

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

#import <AppKit/NSVisualEffectView.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphics.h>

@implementation NSVisualEffectView

@synthesize material = _material;
@synthesize blendingMode = _blendingMode;
@synthesize state = _state;

- (instancetype) initWithFrame: (NSRect) frame {
    self = [super initWithFrame: frame];
    if (self) {
        _material = NSVisualEffectMaterialWindowBackground;
        _blendingMode = NSVisualEffectBlendingModeBehindWindow;
        _state = NSVisualEffectStateFollowsWindowActiveState;
    }
    return self;
}

- (BOOL) isOpaque {
    return YES;
}

- (void) drawRect: (NSRect) rect {
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(rect);
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [super methodSignatureForSelector: aSelector];
}

@end
