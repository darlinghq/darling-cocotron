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

#import <AppKit/NSEvent.h>
#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSView.h>
#import "NSGestureRecognizer-Private.h"

// Private. Darling has no force touch input, so the recognizer never fires.
@interface NSImmediateActionGestureRecognizer : NSGestureRecognizer {
    id _animationController;
}
@end

@implementation NSImmediateActionGestureRecognizer

+ (unsigned int) _defaultDelayedEvents {
    return _NSGestureRecognizerDelaysPrimaryMouseButtonEvents;
}

- (void) dealloc {
    [_animationController release];
    [super dealloc];
}

// SPI. The object that animates the immediate action (a preview, for one);
// retained, nil unless set, and not archived.
- (id) animationController {
    return _animationController;
}

- (void) setAnimationController: (id) controller {
    [controller retain];
    [_animationController release];
    _animationController = controller;
}

// SPI. How far the immediate action's animation has gone. Darling doesn't
// recognize the force click that drives it, so it stays at its start.
- (CGFloat) animationProgress {
    return 0;
}

@end

@interface NSMagnificationGestureRecognizer : NSGestureRecognizer {
    NS_LEGACY_IVAR_PAD(_NSMagnificationGestureRecognizerReserved, 32)
}
@end

@interface NSRotationGestureRecognizer : NSGestureRecognizer {
    NS_LEGACY_IVAR_PAD(_NSRotationGestureRecognizerReserved, 32)
}
@end

@implementation NSGestureRecognizer
#if __OBJC2__
{
    _NSGESTURERECOGNIZER_IVARS
}
#endif

// Archive keys of the delays properties; each is written only when set.
static const struct {
    unsigned int flag;
    NSString *key;
} delayKeys[] = {
    { _NSGestureRecognizerDelaysPrimaryMouseButtonEvents, @"NSGestureRecognizer.delaysPrimaryMouseButtonEvents" },
    { _NSGestureRecognizerDelaysSecondaryMouseButtonEvents, @"NSGestureRecognizer.delaysSecondaryMouseButtonEvents" },
    { _NSGestureRecognizerDelaysOtherMouseButtonEvents, @"NSGestureRecognizer.delaysOtherMouseButtonEvents" },
    { _NSGestureRecognizerDelaysKeyEvents, @"NSGestureRecognizer.delaysKeyEvents" },
    { _NSGestureRecognizerDelaysMagnificationEvents, @"NSGestureRecognizer.delaysMagnificationEvents" },
    { _NSGestureRecognizerDelaysRotationEvents, @"NSGestureRecognizer.delaysRotationEvents" },
};

+ (unsigned int) _defaultDelayedEvents {
    return 0;
}

- (instancetype) initWithTarget: (id) target action: (SEL) action {
    if ((self = [super init])) {
        _target = target;
        _action = action;
        _enabled = YES;
        _delayedEvents = [[self class] _defaultDelayedEvents];
    }
    return self;
}

- (instancetype) init {
    return [self initWithTarget: nil action: NULL];
}

- (instancetype) initWithCoder: (NSCoder *) coder {
    if (![coder allowsKeyedCoding])
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %s]: only keyed archiving is supported", [self class], sel_getName(_cmd)];
    NSString *action = [coder decodeObjectOfClass: [NSString class] forKey: @"NSGestureRecognizer.action"];
    self = [self initWithTarget: [coder decodeObjectForKey: @"NSGestureRecognizer.target"]
                         action: action ? NSSelectorFromString(action) : NULL];
    if (self) {
        _enabled = ![coder decodeBoolForKey: @"NSGestureRecognizer.disabled"];
        // An archive lists every kind of event it delays, whatever the class's
        // defaults are.
        _delayedEvents = 0;
        for (size_t i = 0; i < sizeof(delayKeys) / sizeof(delayKeys[0]); i++)
            if ([coder decodeBoolForKey: delayKeys[i].key])
                _delayedEvents |= delayKeys[i].flag;
        _allowedTouchTypes = [coder decodeIntegerForKey: @"NSGestureRecognizer.allowedTouchTypes"];
    }
    return self;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    if (![coder allowsKeyedCoding])
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %s]: only keyed archiving is supported", [self class], sel_getName(_cmd)];
    // The name and the pressure configuration aren't archived.
    if (_target != nil)
        [coder encodeConditionalObject: _target forKey: @"NSGestureRecognizer.target"];
    if (_action != NULL)
        [coder encodeObject: NSStringFromSelector(_action) forKey: @"NSGestureRecognizer.action"];
    if (!_enabled)
        [coder encodeBool: YES forKey: @"NSGestureRecognizer.disabled"];
    for (size_t i = 0; i < sizeof(delayKeys) / sizeof(delayKeys[0]); i++)
        if (_delayedEvents & delayKeys[i].flag)
            [coder encodeBool: YES forKey: delayKeys[i].key];
    if (_allowedTouchTypes != 0)
        [coder encodeInteger: _allowedTouchTypes forKey: @"NSGestureRecognizer.allowedTouchTypes"];
}

- (void) dealloc {
    [_lastEvent release];
    [_pressureConfiguration release];
    [_name release];
    [super dealloc];
}

- (id) target {
    return _target;
}

- (void) setTarget: (id) target {
    _target = target;
}

- (SEL) action {
    return _action;
}

- (void) setAction: (SEL) action {
    _action = action;
}

- (id<NSGestureRecognizerDelegate>) delegate {
    return _delegate;
}

- (void) setDelegate: (id<NSGestureRecognizerDelegate>) delegate {
    _delegate = delegate;
}

- (NSView *) view {
    return _view;
}

- (void) _setView: (NSView *) view {
    _view = view;
}

- (BOOL) isEnabled {
    return _enabled;
}

- (void) setEnabled: (BOOL) enabled {
    _enabled = enabled;
    if (!enabled && (_state == NSGestureRecognizerStateBegan || _state == NSGestureRecognizerStateChanged))
        [self setState: NSGestureRecognizerStateCancelled];
    if (!enabled)
        [self _resetIfFinished];
}

- (NSGestureRecognizerState) state {
    return _state;
}

- (void) setState: (NSGestureRecognizerState) state {
    BOOL starting = _state == NSGestureRecognizerStatePossible &&
                    (state == NSGestureRecognizerStateBegan || state == NSGestureRecognizerStateEnded);
    if (starting && [_delegate respondsToSelector: @selector(gestureRecognizerShouldBegin:)] &&
        ![_delegate gestureRecognizerShouldBegin: self])
        state = NSGestureRecognizerStateFailed;
    _state = state;
    if (state != NSGestureRecognizerStatePossible && state != NSGestureRecognizerStateFailed && _action != NULL)
        [_target performSelector: _action withObject: self];
}

- (void) reset {
}

- (void) _resetIfFinished {
    if (_state == NSGestureRecognizerStateEnded || _state == NSGestureRecognizerStateCancelled ||
        _state == NSGestureRecognizerStateFailed) {
        _state = NSGestureRecognizerStatePossible;
        [self reset];
    }
}

- (NSPressureConfiguration *) pressureConfiguration {
    return _pressureConfiguration;
}

- (void) setPressureConfiguration: (NSPressureConfiguration *) configuration {
    [configuration retain];
    [_pressureConfiguration release];
    _pressureConfiguration = configuration;
}

- (BOOL) _delays: (unsigned int) flag {
    return (_delayedEvents & flag) != 0;
}

- (void) _setDelays: (unsigned int) flag to: (BOOL) delays {
    if (delays)
        _delayedEvents |= flag;
    else
        _delayedEvents &= ~flag;
}

- (BOOL) delaysPrimaryMouseButtonEvents {
    return [self _delays: _NSGestureRecognizerDelaysPrimaryMouseButtonEvents];
}

- (void) setDelaysPrimaryMouseButtonEvents: (BOOL) delays {
    [self _setDelays: _NSGestureRecognizerDelaysPrimaryMouseButtonEvents to: delays];
}

- (BOOL) delaysSecondaryMouseButtonEvents {
    return [self _delays: _NSGestureRecognizerDelaysSecondaryMouseButtonEvents];
}

- (void) setDelaysSecondaryMouseButtonEvents: (BOOL) delays {
    [self _setDelays: _NSGestureRecognizerDelaysSecondaryMouseButtonEvents to: delays];
}

- (BOOL) delaysOtherMouseButtonEvents {
    return [self _delays: _NSGestureRecognizerDelaysOtherMouseButtonEvents];
}

- (void) setDelaysOtherMouseButtonEvents: (BOOL) delays {
    [self _setDelays: _NSGestureRecognizerDelaysOtherMouseButtonEvents to: delays];
}

- (BOOL) delaysKeyEvents {
    return [self _delays: _NSGestureRecognizerDelaysKeyEvents];
}

- (void) setDelaysKeyEvents: (BOOL) delays {
    [self _setDelays: _NSGestureRecognizerDelaysKeyEvents to: delays];
}

- (BOOL) delaysMagnificationEvents {
    return [self _delays: _NSGestureRecognizerDelaysMagnificationEvents];
}

- (void) setDelaysMagnificationEvents: (BOOL) delays {
    [self _setDelays: _NSGestureRecognizerDelaysMagnificationEvents to: delays];
}

- (BOOL) delaysRotationEvents {
    return [self _delays: _NSGestureRecognizerDelaysRotationEvents];
}

- (void) setDelaysRotationEvents: (BOOL) delays {
    [self _setDelays: _NSGestureRecognizerDelaysRotationEvents to: delays];
}

- (NSString *) name {
    return _name;
}

- (void) setName: (NSString *) name {
    name = [name copy];
    [_name release];
    _name = name;
}

- (NSEventModifierFlags) modifierFlags {
    return [_lastEvent modifierFlags];
}

- (NSTouchTypeMask) allowedTouchTypes {
    return _allowedTouchTypes;
}

- (void) setAllowedTouchTypes: (NSTouchTypeMask) types {
    _allowedTouchTypes = types;
}

// Without failure requirements, any two recognizers may prevent each other
// and none waits for another to fail.
- (BOOL) canPreventGestureRecognizer: (NSGestureRecognizer *) preventedGestureRecognizer {
    return YES;
}

- (BOOL) canBePreventedByGestureRecognizer: (NSGestureRecognizer *) preventingGestureRecognizer {
    return YES;
}

- (BOOL) shouldRequireFailureOfGestureRecognizer: (NSGestureRecognizer *) otherGestureRecognizer {
    return NO;
}

- (BOOL) shouldBeRequiredToFailByGestureRecognizer: (NSGestureRecognizer *) otherGestureRecognizer {
    return NO;
}

- (NSPoint) locationInView: (NSView *) view {
    NSPoint location = [_lastEvent locationInWindow];
    return view ? [view convertPoint: location fromView: nil] : location;
}

// Called by NSWindow: returns NO when the recognizer does not take the event.
- (BOOL) _receiveEvent: (NSEvent *) event {
    if (!_enabled || _state == NSGestureRecognizerStateFailed)
        return NO;
    if ([_delegate respondsToSelector: @selector(gestureRecognizer:shouldAttemptToRecognizeWithEvent:)] &&
        ![_delegate gestureRecognizer: self shouldAttemptToRecognizeWithEvent: event])
        return NO;
    [event retain];
    [_lastEvent release];
    _lastEvent = event;

    switch ([event type]) {
    case NSEventTypeLeftMouseDown: [self mouseDown: event]; break;
    case NSEventTypeRightMouseDown: [self rightMouseDown: event]; break;
    case NSEventTypeOtherMouseDown: [self otherMouseDown: event]; break;
    case NSEventTypeLeftMouseUp: [self mouseUp: event]; break;
    case NSEventTypeRightMouseUp: [self rightMouseUp: event]; break;
    case NSEventTypeOtherMouseUp: [self otherMouseUp: event]; break;
    case NSEventTypeLeftMouseDragged: [self mouseDragged: event]; break;
    case NSEventTypeRightMouseDragged: [self rightMouseDragged: event]; break;
    case NSEventTypeOtherMouseDragged: [self otherMouseDragged: event]; break;
    case NSEventTypeMagnify: [self magnifyWithEvent: event]; break;
    case NSEventTypeRotate: [self rotateWithEvent: event]; break;
    case NSEventTypeTabletPoint: [self tabletPoint: event]; break;
    default: return NO;
    }
    return YES;
}

// Subclasses override the ones they recognize.
- (void) mouseDown: (NSEvent *) event {}
- (void) rightMouseDown: (NSEvent *) event {}
- (void) otherMouseDown: (NSEvent *) event {}
- (void) mouseUp: (NSEvent *) event {}
- (void) rightMouseUp: (NSEvent *) event {}
- (void) otherMouseUp: (NSEvent *) event {}
- (void) mouseDragged: (NSEvent *) event {}
- (void) rightMouseDragged: (NSEvent *) event {}
- (void) otherMouseDragged: (NSEvent *) event {}
- (void) magnifyWithEvent: (NSEvent *) event {}
- (void) rotateWithEvent: (NSEvent *) event {}
- (void) mouseCancelled: (NSEvent *) event {}
- (void) keyDown: (NSEvent *) event {}
- (void) keyUp: (NSEvent *) event {}
- (void) flagsChanged: (NSEvent *) event {}
- (void) tabletPoint: (NSEvent *) event {}
- (void) pressureChangeWithEvent: (NSEvent *) event {}
- (void) touchesBeganWithEvent: (NSEvent *) event {}
- (void) touchesMovedWithEvent: (NSEvent *) event {}
- (void) touchesEndedWithEvent: (NSEvent *) event {}
- (void) touchesCancelledWithEvent: (NSEvent *) event {}

@end

@implementation NSRotationGestureRecognizer

+ (unsigned int) _defaultDelayedEvents {
    return _NSGestureRecognizerDelaysRotationEvents;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end

@implementation NSMagnificationGestureRecognizer

+ (unsigned int) _defaultDelayedEvents {
    return _NSGestureRecognizerDelaysMagnificationEvents;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
