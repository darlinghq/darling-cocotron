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

#import <Onyx2D/O2Paint_ramp.h>

// The paint of a conic shading: the colour of a point is the shading's
// function at the fraction of a full turn from the start angle to the
// direction of the point as seen from the centre.
@interface O2Paint_conicGradient : O2Paint_ramp {
    O2Float _angle;
}

- initWithShading: (O2Shading *) shading
        deviceTransform: (O2AffineTransform) deviceTransform;

@end
