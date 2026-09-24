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

#import <QuartzCore/CAAnimation.h>

// Animates along a damped spring (mass on a spring with a damper) from
// fromValue to toValue instead of a timing function. Time is in seconds
// since the animation began; set duration to settlingDuration to let the
// spring come to rest.
@interface CASpringAnimation : CABasicAnimation {
    CGFloat _mass;
    CGFloat _stiffness;
    CGFloat _damping;
    CGFloat _initialVelocity;
}

@property CGFloat mass;            // default 1; must be > 0
@property CGFloat stiffness;       // default 100; must be > 0
@property CGFloat damping;         // default 10; must be >= 0
@property CGFloat initialVelocity; // default 0, in fromValue-to-toValue distances per second
@property(readonly) CFTimeInterval settlingDuration;

@end
