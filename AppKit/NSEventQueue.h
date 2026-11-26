/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

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

// AppKit's events live in the main event queue of HIToolbox; AppKit has no queue of its own.
// Not a public header.

#import <AppKit/NSEvent.h>
#import <CoreGraphics/CGEvent.h>

// Posts an event an application (or AppKit itself, for the events it synthesises) made, as
// -[NSApplication postEvent:atStart:] does: in front of everything with atStart, otherwise after the events already queued. The event
// does not go through the event taps and is not coalesced. Any thread.
__attribute__((visibility("hidden")))
void _NSEventQueuePost(NSEvent *event, BOOL atStart);

// One wait of -[NSApplication nextEventMatchingMask:untilDate:inMode:dequeue:]: runs the run loop
// of the main thread once in the mode (without blocking when a wanted event is queued), then
// returns the first event the mask selects, or nil. Main thread.
__attribute__((visibility("hidden")))
NSEvent *_NSEventQueueNextEvent(NSEventMask mask, NSDate *untilDate, NSString *mode, BOOL dequeue);

// -[NSApplication discardEventsMatchingMask:beforeEvent:]. Returns the number of events removed.
__attribute__((visibility("hidden")))
NSUInteger _NSEventQueueDiscard(NSEventMask mask, NSEvent *beforeEvent);

// The main event queue starts to keep the window system's events now (see
// _HIBeginEventStreamReading). Called when AppKit connects to the window system.
__attribute__((visibility("hidden")))
void _NSEventQueueBeginReading(void);

// The CGEvent an NSEvent stands for, in CoreGraphics' global coordinates, which have their origin
// at the top left corner of the main screen (whose top is mainScreenMaxY in AppKit's coordinates).
// Never NULL; the caller releases it.
__attribute__((visibility("hidden")))
CGEventRef _NSEventCreateCGEvent(NSEvent *event, CGFloat mainScreenMaxY);

// The NSEvent a CGEvent stands for (not retained by the result), or nil.
__attribute__((visibility("hidden")))
NSEvent *_NSEventCreateFromCGEvent(CGEventRef cgEvent);

// The top of the main screen, in AppKit's screen coordinates, or 0 without a screen.
__attribute__((visibility("hidden")))
CGFloat _NSEventMainScreenMaxY(void);

@interface NSEvent (NSEventQueue)
// The CGEvent and Carbon event this event was made from or taken from the queue as; only the
// first ones set are kept.
- (void) _setCGEvent: (CGEventRef) cgEvent eventRef: (void *) eventRef;
- (CGEventRef) _storedCGEvent;
@end
