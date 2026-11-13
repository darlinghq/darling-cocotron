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
#import <AppKit/NSView.h>
#import "NSGestureRecognizer-Private.h"

// Private. Darling has no force touch input, so the recognizer never fires.
@interface NSImmediateActionGestureRecognizer : NSGestureRecognizer
@end

@implementation NSImmediateActionGestureRecognizer

- (instancetype) initWithTarget: (id) target action: (SEL) action {
    return [super init];
}

@end

@interface NSMagnificationGestureRecognizer : NSGestureRecognizer
@end

@interface NSRotationGestureRecognizer : NSGestureRecognizer
@end

@implementation NSGestureRecognizer
#if __OBJC2__
{
    _NSGESTURERECOGNIZER_IVARS
}
#endif

- (instancetype) initWithTarget: (id) target action: (SEL) action {
    if ((self = [super init])) {
        _target = target;
        _action = action;
        _enabled = YES;
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
    NSString *action = [coder decodeObjectOfClass: [NSString class] forKey: @"Action"];
    self = [self initWithTarget: [coder decodeObjectForKey: @"Target"]
                         action: action ? NSSelectorFromString(action) : NULL];
    if (self && [coder containsValueForKey: @"Enabled"])
        _enabled = [coder decodeBoolForKey: @"Enabled"];
    return self;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    if (![coder allowsKeyedCoding])
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %s]: only keyed archiving is supported", [self class], sel_getName(_cmd)];
    [coder encodeConditionalObject: _target forKey: @"Target"];
    if (_action != NULL)
        [coder encodeObject: NSStringFromSelector(_action) forKey: @"Action"];
    [coder encodeBool: _enabled forKey: @"Enabled"];
}

- (void) dealloc {
    [_lastEvent release];
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

@end

@implementation NSRotationGestureRecognizer

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

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
