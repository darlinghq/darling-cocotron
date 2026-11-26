/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
#import <AppKit/NSGraphics.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>
#include <math.h>

// Private scrolling physics for clients that scroll content of their own (web
// engines): the momentum that carries a scroll on after the fingers lift, the
// rubber band past the ends of the content, and the filter that keeps each
// scroll delta to its predominant axis.
//
// None of it is documented. The rubber band and the axis filter follow what
// macOS gives (black-box observation, see each). The momentum was not measured:
// its constants are Darling's own choices (inferred), picked so the motion
// settles in well under a second, and only its shape (monotonic, settling at
// the destination) is checked.

// --- Momentum ---

// The velocity decays exponentially, v(t) = v0 e^(-kt), so the offset moves
// v0 / k in all. Inferred: k matches UIKit's documented normal deceleration
// rate (the velocity keeps 0.998 of itself per millisecond); not a value
// observed in AppKit.
static const double kMomentumDecay = 2.0020026706730793; // -1000 ln(0.998)

static CGFloat clampToRange(CGFloat value, CGFloat minimum, CGFloat maximum) {
    if (maximum < minimum)
        maximum = minimum;
    return MIN(MAX(value, minimum), maximum);
}

@interface _NSScrollingMomentumCalculator : NSObject {
    NSPoint _initialOrigin;
    NSPoint _velocity;
    NSPoint _destinationOrigin;
    NSRect _documentFrame;
    NSPoint _constrainedClippingOrigin;
    NSSize _clippingSize;
    NSSize _tolerance;
}
- (instancetype) initWithInitialOrigin: (NSPoint) origin
                              velocity: (NSPoint) velocity
                         documentFrame: (NSRect) documentFrame
             constrainedClippingOrigin: (NSPoint) constrainedClippingOrigin
                          clippingSize: (NSSize) clippingSize
                             tolerance: (NSSize) tolerance;
- (NSPoint) positionAfterDuration: (NSTimeInterval) duration;
- (void) calculateToReachDestination;
@property NSPoint destinationOrigin;
@property (readonly) NSTimeInterval durationUntilStop;
@end

@implementation _NSScrollingMomentumCalculator

@synthesize destinationOrigin = _destinationOrigin;

// The origin (of the clipping rectangle in the document) starts at origin and
// moves with the velocity, in points per second. It stops at the natural end of
// the motion, kept inside the document: from the document frame's origin to
// its far edge less the clipping size.
- (instancetype) initWithInitialOrigin: (NSPoint) origin
                              velocity: (NSPoint) velocity
                         documentFrame: (NSRect) documentFrame
             constrainedClippingOrigin: (NSPoint) constrainedClippingOrigin
                          clippingSize: (NSSize) clippingSize
                             tolerance: (NSSize) tolerance
{
    if ((self = [super init]) == nil)
        return nil;

    _initialOrigin = origin;
    _velocity = velocity;
    _documentFrame = documentFrame;
    _constrainedClippingOrigin = constrainedClippingOrigin;
    _clippingSize = clippingSize;
    _tolerance = tolerance;

    NSPoint destination = NSMakePoint(origin.x + velocity.x / kMomentumDecay, origin.y + velocity.y / kMomentumDecay);

    destination.x = clampToRange(destination.x, NSMinX(documentFrame), NSMaxX(documentFrame) - clippingSize.width);
    destination.y = clampToRange(destination.y, NSMinY(documentFrame), NSMaxY(documentFrame) - clippingSize.height);
    _destinationOrigin = destination;
    // A destination at an edge is reached by a slower motion of the same shape.
    [self calculateToReachDestination];
    return self;
}

// Makes the motion end at the destination origin: the velocity becomes the one
// whose decay covers the distance to it.
- (void) calculateToReachDestination {
    _velocity.x = (_destinationOrigin.x - _initialOrigin.x) * kMomentumDecay;
    _velocity.y = (_destinationOrigin.y - _initialOrigin.y) * kMomentumDecay;
}

- (NSPoint) positionAfterDuration: (NSTimeInterval) duration {
    if (duration <= 0)
        return _initialOrigin;
    if (duration >= [self durationUntilStop])
        return _destinationOrigin;

    double travelled = 1 - exp(-kMomentumDecay * duration);

    return NSMakePoint(_initialOrigin.x + (_destinationOrigin.x - _initialOrigin.x) * travelled,
                       _initialOrigin.y + (_destinationOrigin.y - _initialOrigin.y) * travelled);
}

// The time until the origin is within the tolerance of the destination on both
// axes.
static double timeToWithin(CGFloat distance, CGFloat tolerance) {
    distance = fabs(distance);
    if (tolerance <= 0)
        tolerance = 1;
    if (distance <= tolerance)
        return 0;
    return log(distance / tolerance) / kMomentumDecay;
}

- (NSTimeInterval) durationUntilStop {
    return MAX(timeToWithin(_destinationOrigin.x - _initialOrigin.x, _tolerance.width),
               timeToWithin(_destinationOrigin.y - _initialOrigin.y, _tolerance.height));
}

@end

// --- Rubber band ---

// Observed on macOS 26.7.3 and 10.14.4 (black-box, the same on both, for
// pulls from 0.3 to 100000 points and times from -0.1 to 2 seconds):
//  - a pull past an end of the content shows a stretch of a twentieth of it,
//    and the inverse gives the pull back;
//  - released from a stretch x0 at velocity v0, the stretch t seconds later is
//    (x0 - 0.31 v0 t) e^(-12.5 t); a negative time is not clamped.
// Test: tests/appkit-scrolling-spi.m
static const double kStretchPerPull = 0.05;
static const double kReboundRate = 12.5;
static const double kReboundVelocityFactor = 0.31;

CGFloat _NSElasticDeltaForReboundDelta(CGFloat delta) {
    return delta * kStretchPerPull;
}

CGFloat _NSReboundDeltaForElasticDelta(CGFloat delta) {
    return delta / kStretchPerPull;
}

CGFloat _NSElasticDeltaForTimeDelta(CGFloat initialPosition, CGFloat initialVelocity, CGFloat elapsedTime) {
    return (initialPosition - kReboundVelocityFactor * initialVelocity * elapsedTime) * exp(-kReboundRate * elapsedTime);
}

// --- Predominant axis ---

// Observed on macOS 26.7.3 and 10.14.4 (black-box, the same on both):
//  - each delta keeps only its larger axis, the vertical one on a tie; nothing
//    carries over from earlier deltas;
//  - the velocity of each axis comes from the kept delta over the time since
//    the previous one. The first delta of a gesture has none; the first time
//    that passes gives it as is; after that it is smoothed, 0.2 of the old
//    velocity and 0.8 of the new, except that a new velocity the other way is
//    taken as is;
//  - when no time passed the velocity stays; after a gap longer than
//    kVelocityTimeout (0.2 s still counts, 0.25 s does not; the cutoff is
//    taken as 0.2 s), or when the time goes back, it is 0 and the next time
//    that passes gives it as is again.
// Test: tests/appkit-scrolling-spi.m
static const NSTimeInterval kVelocityTimeout = 0.2;
static const CGFloat kVelocityKeep = 0.2;

@interface _NSScrollingPredominantAxisFilter : NSObject {
    NSPoint _velocity;
    NSTimeInterval _lastTimestamp;
    BOOL _hasLastTimestamp;
    BOOL _hasVelocity;
}
- (void) filterInputDelta: (NSPoint) delta
                timestamp: (NSTimeInterval) timestamp
              outputDelta: (NSPoint *) outputDelta
                 velocity: (NSPoint *) velocity;
- (void) reset;
@end

static CGFloat smoothedVelocity(CGFloat old, CGFloat current) {
    if (current != 0 && (current < 0) != (old < 0))
        return current;
    return kVelocityKeep * old + (1 - kVelocityKeep) * current;
}

@implementation _NSScrollingPredominantAxisFilter

- (void) filterInputDelta: (NSPoint) delta
                timestamp: (NSTimeInterval) timestamp
              outputDelta: (NSPoint *) outputDelta
                 velocity: (NSPoint *) velocity
{
    NSPoint filtered = delta;

    if (fabs(delta.y) >= fabs(delta.x))
        filtered.x = 0;
    else
        filtered.y = 0;

    if (_hasLastTimestamp && timestamp != _lastTimestamp) {
        NSTimeInterval interval = timestamp - _lastTimestamp;

        if (interval < 0 || interval > kVelocityTimeout) {
            _velocity = NSZeroPoint;
            _hasVelocity = NO;
        } else {
            NSPoint current = NSMakePoint(filtered.x / interval, filtered.y / interval);

            _velocity = _hasVelocity ? NSMakePoint(smoothedVelocity(_velocity.x, current.x),
                                                   smoothedVelocity(_velocity.y, current.y))
                                     : current;
            _hasVelocity = YES;
        }
    }
    _lastTimestamp = timestamp;
    _hasLastTimestamp = YES;

    if (outputDelta != NULL)
        *outputDelta = filtered;
    if (velocity != NULL)
        *velocity = _velocity;
}

- (void) reset {
    _velocity = NSZeroPoint;
    _hasVelocity = NO;
    _lastTimestamp = 0;
    _hasLastTimestamp = NO;
}

@end
