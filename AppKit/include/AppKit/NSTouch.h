/*
 This file is part of Darling.

 Copyright (C) 2026 Darling Team

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
#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

@class NSView, NSWindow;

typedef NS_OPTIONS(NSUInteger, NSTouchPhase) {
    NSTouchPhaseBegan = 1U << 0,
    NSTouchPhaseMoved = 1U << 1,
    NSTouchPhaseStationary = 1U << 2,
    NSTouchPhaseEnded = 1U << 3,
    NSTouchPhaseCancelled = 1U << 4,

    NSTouchPhaseTouching = NSTouchPhaseBegan | NSTouchPhaseMoved | NSTouchPhaseStationary,
    NSTouchPhaseAny = NSUIntegerMax
};

typedef NS_ENUM(NSInteger, NSTouchType) {
    NSTouchTypeDirect,
    NSTouchTypeIndirect
};

typedef NS_OPTIONS(NSUInteger, NSTouchTypeMask) {
    NSTouchTypeMaskDirect = 1U << NSTouchTypeDirect,
    NSTouchTypeMaskIndirect = 1U << NSTouchTypeIndirect
};

/*
 * A finger on a touch screen. Darling's windowing backends report touch
 * screens as direct touches (NSEventTypeDirectTouch), sent to a view whose
 * allowedTouchTypes include NSTouchTypeMaskDirect and whose class implements
 * touchesBeganWithEvent:. A finger that lands on any other view moves the
 * mouse instead, as it would without touch support.
 */
@interface NSTouch : NSObject <NSCopying> {
@private
    id<NSObject, NSCopying> _identity;
    NSTouchPhase _phase;
    NSPoint _location;
    NSPoint _previousLocation;
    NSView *_view;
    NSWindow *_window;
@public
    BOOL _movesMouse;
    NSInteger _clickCount;
}

@property (readonly, retain) id<NSObject, NSCopying> identity;
@property (readonly) NSTouchPhase phase;
@property (readonly) NSTouchType type;
@property (readonly) BOOL isResting;
// Trackpad touches only; a direct touch has no normalized position.
@property (readonly) NSPoint normalizedPosition;
@property (readonly) NSSize deviceSize;
@property (readonly, assign) id device;

- (NSPoint) locationInView: (NSView *) view;
- (NSPoint) previousLocationInView: (NSView *) view;

@end
