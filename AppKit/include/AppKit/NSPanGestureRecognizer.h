/*
 This file is part of Darling.

 Copyright (C) 2021-2026 Lubos Dolezel

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
#import <AppKit/AppKitIvarLayout.h>
#import <Foundation/Foundation.h>
#import <AppKit/NSGestureRecognizer.h>

// Recognizes a drag with one of the mouse buttons of buttonMask: it begins
// with the first drag after the button goes down, changes with each further
// drag and ends when the button goes up; a click without a drag fails.
// Translation and velocity are kept in window coordinates and converted, as
// vectors, into the view asked about.
@interface NSPanGestureRecognizer : NSGestureRecognizer <NSCoding> {
    // Apple's instance is 48 bytes larger than NSGestureRecognizer's on the
    // legacy ABI: the pad and the pointer to the extras.
    NS_LEGACY_IVAR_PAD(_NSPanGestureRecognizerReserved, 44)
    NS_EXTRA_IVARS_BEGIN(NSPanGestureRecognizer)
        NSUInteger _buttonMask;
        NSInteger _numberOfTouchesRequired;
        NSInteger _trackedButton;
        BOOL _tracking;
        BOOL _hasVelocity;
        NSPoint _startLocation;
        NSPoint _lastLocation;
        NSTimeInterval _lastTime;
        NSPoint _velocity;
        NSTimeInterval _timestamp;
    NS_EXTRA_IVARS_END(NSPanGestureRecognizer)
}

@property NSUInteger buttonMask;
@property NSInteger numberOfTouchesRequired;

- (NSPoint) translationInView: (NSView *) view;
- (void) setTranslation: (NSPoint) translation inView: (NSView *) view;
- (NSPoint) velocityInView: (NSView *) view;

@end

#ifdef DARLING
// Not in the macOS SDK; code built against it declares them itself.
@interface NSPanGestureRecognizer (NSPanGestureRecognizerPrivate)
// The time of the last event the recognizer took, as NSEvent's timestamp.
@property(readonly) NSTimeInterval timestamp;
@end
#endif
