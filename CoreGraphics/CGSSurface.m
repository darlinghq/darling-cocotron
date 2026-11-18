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
#import <CoreGraphics/CGSSurface.h>
#import <CoreGraphics/CGSWindow.h>
#import <Foundation/NSRaise.h>

@implementation CGSSurface
@synthesize surfaceId = _surfaceId;

- (instancetype) initWithWindow: (CGSWindow *) window
                      surfaceID: (CGSSurfaceID) surfaceID
{
    _window = window;
    _surfaceId = surfaceID;
    _bounds = CGRectNull;
    return self;
}

- (CGError) setBounds: (CGRect) rect {
    NSInvalidAbstractInvocation();
}

- (CGError) getBounds: (CGRect *) outBounds {
    if (outBounds == NULL)
        return kCGErrorIllegalArgument;
    *outBounds = _bounds;
    return kCGErrorSuccess;
}

- (void) _boundsDidChange: (CGRect) rect {
    _bounds = rect;
}

- (void *) nativeWindow {
    NSInvalidAbstractInvocation();
}

- (void) invalidate {
    [_window _surfaceInvalidated: _surfaceId];
}
@end
