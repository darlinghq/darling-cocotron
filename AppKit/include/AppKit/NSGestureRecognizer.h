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

#import <AppKit/AppKitExport.h>
#import <Foundation/Foundation.h>

@class NSEvent, NSGestureRecognizer, NSView;
@protocol NSGestureRecognizerDelegate;

typedef NS_ENUM(NSInteger, NSGestureRecognizerState) {
    NSGestureRecognizerStatePossible = 0,
    NSGestureRecognizerStateBegan,
    NSGestureRecognizerStateChanged,
    NSGestureRecognizerStateEnded,
    NSGestureRecognizerStateCancelled,
    NSGestureRecognizerStateFailed,
    NSGestureRecognizerStateRecognized = NSGestureRecognizerStateEnded,
} NS_SWIFT_NAME(NSGestureRecognizer.State);

// NSWindow gives a recognizer the mouse and gesture events aimed at its view or
// the view's subviews, before the view itself gets them. Recognizers don't
// delay or cancel the view's events, and failure requirements aren't modelled.
@interface NSGestureRecognizer : NSObject <NSCoding>

- (instancetype) initWithTarget: (id) target action: (SEL) action NS_DESIGNATED_INITIALIZER;
- (instancetype) initWithCoder: (NSCoder *) coder NS_DESIGNATED_INITIALIZER;

@property(assign) id target;
@property SEL action;
@property(readonly) NSGestureRecognizerState state;
@property(assign) id<NSGestureRecognizerDelegate> delegate;
@property(getter=isEnabled) BOOL enabled;
@property(readonly) NSView *view;

- (NSPoint) locationInView: (NSView *) view;

@end

@protocol NSGestureRecognizerDelegate <NSObject>
@optional
- (BOOL) gestureRecognizerShouldBegin: (NSGestureRecognizer *) gestureRecognizer;
- (BOOL) gestureRecognizer: (NSGestureRecognizer *) gestureRecognizer
        shouldAttemptToRecognizeWithEvent: (NSEvent *) event;
@end

@interface NSGestureRecognizer (NSSubclassUse)

// Began and Changed send the action; so do Ended (Recognized) and Cancelled,
// after which NSWindow resets the recognizer once the event is dispatched.
@property(readwrite) NSGestureRecognizerState state;

- (void) reset;

- (void) mouseDown: (NSEvent *) event NS_SWIFT_NAME(mouseDown(with:));
- (void) rightMouseDown: (NSEvent *) event NS_SWIFT_NAME(rightMouseDown(with:));
- (void) otherMouseDown: (NSEvent *) event NS_SWIFT_NAME(otherMouseDown(with:));
- (void) mouseUp: (NSEvent *) event NS_SWIFT_NAME(mouseUp(with:));
- (void) rightMouseUp: (NSEvent *) event NS_SWIFT_NAME(rightMouseUp(with:));
- (void) otherMouseUp: (NSEvent *) event NS_SWIFT_NAME(otherMouseUp(with:));
- (void) mouseDragged: (NSEvent *) event NS_SWIFT_NAME(mouseDragged(with:));
- (void) rightMouseDragged: (NSEvent *) event NS_SWIFT_NAME(rightMouseDragged(with:));
- (void) otherMouseDragged: (NSEvent *) event NS_SWIFT_NAME(otherMouseDragged(with:));
- (void) magnifyWithEvent: (NSEvent *) event;
- (void) rotateWithEvent: (NSEvent *) event;

@end
