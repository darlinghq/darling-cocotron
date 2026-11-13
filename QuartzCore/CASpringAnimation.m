/*
 This file is part of Darling.

 Copyright (C) 2021 Lubos Dolezel

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

#import <QuartzCore/CASpringAnimation.h>
#include <float.h>
#include <math.h>

// Displacements below this fraction of the fromValue-to-toValue distance
// count as at rest for settlingDuration.
static const double kRestThreshold = 0.001;
static const double kSettlingStep = 1.0 / 240;

static const CGFloat kDefaultMass = 1;
static const CGFloat kDefaultStiffness = 100;
static const CGFloat kDefaultDamping = 10;

@interface CAPropertyAnimation (Private)
- initWithKeyPath: (NSString *) keyPath;
@end

@implementation CASpringAnimation

- (void) _setSpringDefaults {
    _mass = kDefaultMass;
    _stiffness = kDefaultStiffness;
    _damping = kDefaultDamping;
    _initialVelocity = 0;
}

- init {
    self = [super init];
    if (self != nil)
        [self _setSpringDefaults];
    return self;
}

- initWithKeyPath: (NSString *) keyPath {
    self = [super initWithKeyPath: keyPath];
    if (self != nil)
        [self _setSpringDefaults];
    return self;
}

- (CGFloat) mass {
    return _mass;
}

// QUIRK: assigning a mass that is not positive, a stiffness that is not
// positive or a negative damping does not raise; the property returns to its
// default (1, 100 and 10). A damping of 0 is accepted. Not documented.
// Evidence: black-box observation on macOS 26.7.3 (tier 2), vd-upstream
// mac-probes/v315-caspring-validation.m.
// Test: tests/quartzcore-spring-animation.m (quirk_invalid_values_reset_to_defaults)
- (void) setMass: (CGFloat) value {
    _mass = value > 0 ? value : kDefaultMass;
}

- (CGFloat) stiffness {
    return _stiffness;
}

- (void) setStiffness: (CGFloat) value {
    _stiffness = value > 0 ? value : kDefaultStiffness;
}

- (CGFloat) damping {
    return _damping;
}

- (void) setDamping: (CGFloat) value {
    _damping = value >= 0 ? value : kDefaultDamping;
}

- (CGFloat) initialVelocity {
    return _initialVelocity;
}

- (void) setInitialVelocity: (CGFloat) value {
    _initialVelocity = value;
}

typedef struct {
    double w0, zeta, wd, b;  // underdamped
    double r1, r2, c1, c2;   // overdamped: c1 e^(r1 t) + c2 e^(r2 t), r2 < r1 < 0
} Spring;

// Solution of m x'' + c x' + k x = 0 with x(0) = -1, x'(0) = v0: the
// displacement from toValue as a fraction of the fromValue-to-toValue distance.
static Spring makeSpring(double m, double k, double c, double v0) {
    Spring s = {0};
    s.w0 = sqrt(k / m);
    s.zeta = c / (2 * sqrt(k * m));
    if (s.zeta < 1) {
        s.wd = s.w0 * sqrt(1 - s.zeta * s.zeta);
        s.b = (v0 - s.zeta * s.w0) / s.wd;
    } else if (s.zeta == 1) {
        s.b = v0 - s.w0;
    } else {
        double root = s.w0 * sqrt(s.zeta * s.zeta - 1);
        s.r1 = -s.zeta * s.w0 + root;
        s.r2 = -s.zeta * s.w0 - root;
        s.c2 = (v0 + s.r1) / (s.r2 - s.r1);
        s.c1 = -1 - s.c2;
    }
    return s;
}

static double displacement(const Spring *s, double t) {
    if (s->zeta < 1)
        return exp(-s->zeta * s->w0 * t) * (-cos(s->wd * t) + s->b * sin(s->wd * t));
    if (s->zeta == 1)
        return exp(-s->w0 * t) * (-1 + s->b * t);
    return s->c1 * exp(s->r1 * t) + s->c2 * exp(s->r2 * t);
}

// A time after which |displacement| stays below the rest threshold, from a
// decaying bound on its magnitude.
static double restBound(const Spring *s) {
    if (s->zeta < 1)
        return log(sqrt(1 + s->b * s->b) / kRestThreshold) / (s->zeta * s->w0);
    if (s->zeta > 1)
        return fmax(0, log((fabs(s->c1) + fabs(s->c2)) / kRestThreshold) / -s->r1);
    // (1 + |b| t) e^(-w0 t) decreases after its peak.
    double t = fmax(0, 1 / s->w0 - 1 / fmax(fabs(s->b), 1e-12));
    while ((1 + fabs(s->b) * t) * exp(-s->w0 * t) >= kRestThreshold)
        t += kSettlingStep;
    return t;
}

// Fraction of the way from fromValue to toValue, t seconds after the start.
- (CGFloat) _springProgressAtTime: (CFTimeInterval) t {
    Spring s = makeSpring(_mass, _stiffness, _damping, _initialVelocity);
    return 1 + displacement(&s, t);
}

// An undamped spring never comes to rest; it reports the largest float.
// QUIRK: macOS reports FLT_MAX rather than infinity for it. Not documented.
// Evidence: black-box observation on macOS 26.7.3 (tier 2), vd-upstream
// mac-probes/v315-caspring-validation.m.
// Test: tests/quartzcore-spring-animation.m (quirk_undamped_settling_duration)
- (CFTimeInterval) settlingDuration {
    if (_damping == 0)
        return FLT_MAX;
    Spring s = makeSpring(_mass, _stiffness, _damping, _initialVelocity);
    double bound = restBound(&s), lastMoving = 0;
    for (double t = 0; t <= bound; t += kSettlingStep) {
        if (fabs(displacement(&s, t)) >= kRestThreshold)
            lastMoving = t;
    }
    return lastMoving + kSettlingStep;
}

@end
