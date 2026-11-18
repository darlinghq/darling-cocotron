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

#import <AppKit/NSEvent.h>
#import <AppKit/NSTouch.h>

// A touch screen event: every finger down in the window, as this event left it.
@interface NSEvent_touch : NSEvent {
    NSSet *_touches;
}

- (instancetype) initWithWindow: (NSWindow *) window
                       location: (NSPoint) location
                      timestamp: (NSTimeInterval) timestamp
                        touches: (NSSet *) touches;

@end

@interface NSTouch (NSTouchPrivate)
// The view the finger began in, which all its events go to.
- (NSView *) _view;
- (NSWindow *) _window;
@end
