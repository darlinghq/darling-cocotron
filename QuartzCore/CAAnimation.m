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

+ animation {
    return [[[self alloc] init] autorelease];
}

- init {
    _duration = [CATransaction animationDuration];
    _timingFunction = [[CATransaction animationTimingFunction] retain];
    return self;
}

- (void) dealloc {
    [_timingFunction release];
    [super dealloc];
}

- copyWithZone: (NSZone *) zone {
    NSUnimplementedMethod();
    return nil;
}

- delegate {
    return _delegate;
}

- (void) setDelegate: object {
    object = [object retain];
    [_delegate release];
    _delegate = object;
}

- (BOOL) isRemovedOnCompletion {
    return _removedOnCompletion;
}

- (void) setRemovedOnCompletion: (BOOL) value {
    _removedOnCompletion = value;
}

- (CAMediaTimingFunction *) timingFunction {
    return _timingFunction;
}

- (void) setTimingFunction: (CAMediaTimingFunction *) value {
    value = [value retain];
    [_timingFunction release];
    _timingFunction = value;
}

- (BOOL) autoreverses {
    return _autoreverses;
}

- (void) setAutoreverses: (BOOL) value {
    _autoreverses = value;
}

- (CFTimeInterval) beginTime {
    return _beginTime;
}

- (void) setBeginTime: (CFTimeInterval) value {
    _beginTime = value;
}

- (CFTimeInterval) duration {
    return _duration;
}

- (void) setDuration: (CFTimeInterval) value {
    _duration = value;
}

- (NSString *) fillMode {
    return _fillMode;
}

- (void) setFillMode: (NSString *) value {
    value = [value copy];
    [_fillMode release];
    _fillMode = value;
}

- (CGFloat) repeatCount {
    return _repeatCount;
}

- (void) setRepeatCount: (CGFloat) value {
    _repeatCount = value;
}

- (CFTimeInterval) repeatDuration {
    return _repeatDuration;
}

- (void) setRepeatDuration: (CFTimeInterval) value {
    _repeatDuration = value;
}

- (CGFloat) speed {
    return _speed;
}

- (void) setSpeed: (CGFloat) value {
    _speed = value;
}

- (CFTimeInterval) timeOffset {
    return _timeOffset;
}

- (void) setTimeOffset: (CFTimeInterval) value {
    _timeOffset = value;
}

@end

@implementation CAKeyframeAnimation

- (NSMethodSignature *) methodSignatureForSelector: (SEL) aSelector {
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void) forwardInvocation: (NSInvocation *) anInvocation {
    NSLog(@"Stub called: %@ in %@",
          NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
