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

#import <AppKit/NSRaise.h>
#import <QuartzCore/CAAnimation.h>
#import <QuartzCore/CALayer.h>
#import <QuartzCore/CATransaction.h>

NSString *const kCATransitionFade = @"fade";
NSString *const kCATransitionMoveIn = @"moveIn";
NSString *const kCATransitionPush = @"push";
NSString *const kCATransitionReveal = @"reveal";

NSString *const kCATransitionFromLeft = @"fromLeft";
NSString *const kCATransitionFromRight = @"fromRight";
NSString *const kCATransitionFromTop = @"fromTop";
NSString *const kCATransitionFromBottom = @"fromBottom";

NSString *const kCAAnimationLinear = @"linear";
NSString *const kCAAnimationDiscrete = @"discrete";
NSString *const kCAAnimationPaced = @"paced";
NSString *const kCAAnimationCubic = @"cubic";
NSString *const kCAAnimationCubicPaced = @"cubicPaced";

NSString *const kCAAnimationRotateAuto = @"auto";
NSString *const kCAAnimationRotateAutoReverse = @"autoReverse";

@implementation CAAnimation

+ (instancetype) animation {
    return [[[self alloc] init] autorelease];
}

// As +[CALayer defaultValueForKey:]. Values observed on macOS 26.7.3: speed 1 and
// removedOnCompletion YES, nil for the rest (duration included).
+ (id) defaultValueForKey: (NSString *) key {
    if ([key isEqualToString: @"speed"])
        return @1.0f;
    if ([key isEqualToString: @"removedOnCompletion"])
        return @YES;
    return nil;
}

// An animation used as a layer action animates the property it was found for.
- (void) runActionForKey: (NSString *) event
                  object: (id) anObject
               arguments: (NSDictionary *) dict
{
    if ([anObject isKindOfClass: [CALayer class]])
        [(CALayer *) anObject addAnimation: self forKey: event];
}

- init {
    NS_EXTRA(CAAnimation, self)->_duration = [CATransaction animationDuration];
    NS_EXTRA(CAAnimation, self)->_timingFunction = [[CATransaction animationTimingFunction] retain];
    return self;
}

- (void) dealloc {
    [NS_EXTRA(CAAnimation, self)->_timingFunction release];
    [NS_EXTRA(CAAnimation, self)->_undefinedKeyValues release];
    NS_EXTRA_FREE(CAAnimation, self);
    [super dealloc];
}

// An animation is a key-value coding container, as a layer is: a key it has no property for holds
// whatever value is set for it, and reads as nil until then (Core Animation Programming Guide,
// "Key-Value Coding Extensions"). Test: tests/quartzcore-kvc-arbitrary-keys.m.
- (id) valueForUndefinedKey: (NSString *) key {
    return [[[NS_EXTRA(CAAnimation, self)->_undefinedKeyValues objectForKey: key] retain] autorelease];
}

- (void) setValue: (id) value forUndefinedKey: (NSString *) key {
    if (value == nil) {
        [NS_EXTRA(CAAnimation, self)->_undefinedKeyValues removeObjectForKey: key];
        return;
    }
    if (NS_EXTRA(CAAnimation, self)->_undefinedKeyValues == nil)
        NS_EXTRA(CAAnimation, self)->_undefinedKeyValues = [[NSMutableDictionary alloc] init];
    [NS_EXTRA(CAAnimation, self)->_undefinedKeyValues setObject: value forKey: key];
}

- copyWithZone: (NSZone *) zone {
    NSUnimplementedMethod();
    return nil;
}

- delegate {
    return NS_EXTRA(CAAnimation, self)->_delegate;
}

- (void) setDelegate: object {
    object = [object retain];
    [NS_EXTRA(CAAnimation, self)->_delegate release];
    NS_EXTRA(CAAnimation, self)->_delegate = object;
}

- (BOOL) isRemovedOnCompletion {
    return NS_EXTRA(CAAnimation, self)->_removedOnCompletion;
}

- (void) setRemovedOnCompletion: (BOOL) value {
    NS_EXTRA(CAAnimation, self)->_removedOnCompletion = value;
}

- (CAMediaTimingFunction *) timingFunction {
    return NS_EXTRA(CAAnimation, self)->_timingFunction;
}

- (void) setTimingFunction: (CAMediaTimingFunction *) value {
    value = [value retain];
    [NS_EXTRA(CAAnimation, self)->_timingFunction release];
    NS_EXTRA(CAAnimation, self)->_timingFunction = value;
}

- (BOOL) autoreverses {
    return NS_EXTRA(CAAnimation, self)->_autoreverses;
}

- (void) setAutoreverses: (BOOL) value {
    NS_EXTRA(CAAnimation, self)->_autoreverses = value;
}

- (CFTimeInterval) beginTime {
    return NS_EXTRA(CAAnimation, self)->_beginTime;
}

- (void) setBeginTime: (CFTimeInterval) value {
    NS_EXTRA(CAAnimation, self)->_beginTime = value;
}

- (CFTimeInterval) duration {
    return NS_EXTRA(CAAnimation, self)->_duration;
}

- (void) setDuration: (CFTimeInterval) value {
    NS_EXTRA(CAAnimation, self)->_duration = value;
}

- (NSString *) fillMode {
    return NS_EXTRA(CAAnimation, self)->_fillMode;
}

- (void) setFillMode: (NSString *) value {
    value = [value copy];
    [NS_EXTRA(CAAnimation, self)->_fillMode release];
    NS_EXTRA(CAAnimation, self)->_fillMode = value;
}

- (float) repeatCount {
    return NS_EXTRA(CAAnimation, self)->_repeatCount;
}

- (void) setRepeatCount: (float) value {
    NS_EXTRA(CAAnimation, self)->_repeatCount = value;
}

- (CFTimeInterval) repeatDuration {
    return NS_EXTRA(CAAnimation, self)->_repeatDuration;
}

- (void) setRepeatDuration: (CFTimeInterval) value {
    NS_EXTRA(CAAnimation, self)->_repeatDuration = value;
}

- (float) speed {
    return NS_EXTRA(CAAnimation, self)->_speed;
}

- (void) setSpeed: (float) value {
    NS_EXTRA(CAAnimation, self)->_speed = value;
}

- (CFTimeInterval) timeOffset {
    return NS_EXTRA(CAAnimation, self)->_timeOffset;
}

- (void) setTimeOffset: (CFTimeInterval) value {
    NS_EXTRA(CAAnimation, self)->_timeOffset = value;
}

@end
