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

#ifndef CGSDRAG_H
#define CGSDRAG_H
#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDate.h>
#import <CoreGraphics/CGGeometry.h>
#import <CoreGraphics/CGImage.h>
#import <CoreGraphics/CGSSelection.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>

// Drag and drop between applications (private interface).
//
// CoreGraphics owns the process' connection to the window system, so it also owns the process' part in the window
// system's drag and drop protocol: XDND on X11 and the data device's drag on Wayland. The UI layer (AppKit's
// NSDraggingSession and NSDraggingInfo) sits on top of this interface and knows nothing of the protocol: it
// starts a drag with what is dragged, and it hears what happens to the windows that take drops.
//
// Both halves use the same operation bits as NSDragOperation (public, so the values are fixed). A window system
// can express fewer operations than that (XDND: copy, move and link); what a destination accepts is narrowed to
// what the window system can say before it is reported, and what a source offers is narrowed to it as well.
//
// The data of a drag goes through the selection layer of CGSSelection.h: the source gives its data when the
// destination asks for it (nothing is read in advance), and a destination reads the source's data with
// -[CGSDropSession dataForType:]. Types are named as there, in the UTI spelling (public.utf8-plain-text); a list
// of file names is NSFilenamesPboardType, as in the selection layer.
//
// Everything is called on the main thread. A backend that has no drag and drop of its own reports
// _CGSDragAvailable() NO, and the UI layer keeps whatever it does itself in that case.

typedef NSUInteger CGSDragOperation;
enum {
	kCGSDragOperationNone    = 0,
	kCGSDragOperationCopy    = 1,
	kCGSDragOperationLink    = 2,
	kCGSDragOperationGeneric = 4,
	kCGSDragOperationPrivate = 8,
	kCGSDragOperationMove    = 16,
	kCGSDragOperationDelete  = 32,
};

#pragma mark - The window system's drags of this process: the source

// What a drag is made of, besides what the window system needs to run it.
@protocol CGSDragSource <CGSSelectionSource>
// The operations to announce to the destination under the pointer now: the ones the drag offers, narrowed by
// whatever the source applies at that moment (the modifier keys held). Called with every position the
// destination is told of.
- (CGSDragOperation) dragOperationsNarrowing: (CGSDragOperation) offered;
@end

typedef struct {
	// The window the drag starts in (a window of the process, the one the gesture that starts it happened in).
	CGSWindowID window;
	// The types the drag offers, in the order of preference, and the source that gives their data.
	NSArray<NSString*>* types;
	id<CGSDragSource> source;
	// What other applications may do with the dragged items, and what this process' own windows may. A drag that
	// allows nothing to other applications and something to this process is local: only the process' own
	// windows are told of it, with the local operations.
	CGSDragOperation operations;
	CGSDragOperation localOperations;
	// The image dragged along with the pointer, or NULL for none (see _CGSDragUsesImage()), and where its top
	// left corner is from the pointer, in points, y down (usually negative).
	CGImageRef image;
	CGPoint imageOffset;
	// How many pixels of the image make a point (the scale it was drawn at); 0 is the same as 1.
	CGFloat imageScale;
} CGSDragDescription;

// A drag that is running. It follows the pointer by itself where the window system makes the source do so
// (X11), and reports on its own where the window system decides (Wayland, where the compositor ends the drag).
@protocol CGSDragSession <NSObject>
// Whether the drag has ended without the source ending it (the window system cancelled it, or the destination
// finished with it).
@property (readonly) BOOL finished;
// Lets the drag look at the pointer: where the window system makes the source follow it, the destination under
// the pointer is told of a new position. Returns whether the pointer has moved (nothing is said where the
// window system does not tell the source of positions).
- (BOOL) update;
// The gesture that started the drag is over (the button was released): the drag is dropped on the destination
// that accepted it, or cancelled when none did, and the drop is waited for until the destination has finished
// with the data, a bounded time. Returns what the destination did with it (kCGSDragOperationNone when it
// refused, failed or the drag was cancelled). While it waits it calls pump(date) repeatedly; pump handles the
// process' events (the destination's requests for the data come with them) until the date at the latest.
- (CGSDragOperation) concludePumping: (void (^)(NSDate* until)) pump;
// Gives up whatever the drag holds (the window system's grab, the data it offers). Idempotent; the session
// does nothing after it.
- (void) close;
@end

// Whether the backend runs drags (X11: yes; a backend without drag and drop: no, and the other functions fail).
COREGRAPHICS_EXPORT BOOL _CGSDragAvailable(void);
// Whether the backend draws the image of a drag (if not, a description needs no image).
COREGRAPHICS_EXPORT BOOL _CGSDragUsesImage(void);
// Starts a drag, holding the pointer for its window, and tells the destination under the pointer of its first
// position. nil when it cannot start (nothing it can describe to the window system, the pointer cannot be
// grabbed, a drag is running already). The caller owns the result.
COREGRAPHICS_EXPORT id<CGSDragSession> _CGSDragBegin(const CGSDragDescription* description);

#pragma mark - The window system's drags into the windows of this process: the destination

// A drag from this process or another one that is over a window that has a destination.
@protocol CGSDropSession <NSObject>
// The types the source offers (a type the process does not know by a name of its own keeps the window
// system's name).
@property (readonly) NSArray<NSString*>* types;
// What the source allows (never more than the window system can say), before the operations that a destination
// narrows are applied.
@property (readonly) CGSDragOperation sourceOperations;
// Whether the source is a drag of this process (started by _CGSDragBegin()).
@property (readonly) BOOL fromThisProcess;
// The data of a type of the source. nil when the source has none, refuses or does not answer in a few seconds.
// The calling thread keeps handling the window system's events while it waits (so the callbacks of another
// drag, or of this one ending, can come meanwhile).
- (NSData*) dataForType: (NSString*) type;
@end

// What a window does with the drags over it. Positions are in points from the window's top left corner, y down.
// The operations a destination returns are the ones it would perform at that position; the first position of a
// session is -dropSession:enteredAtPoint:, and a session ends with exactly one of -dropSessionExited: (the
// source left, or went away) and -dropSession:performWithOperation: (the source dropped, also when no
// destination accepted: the destination is told, so that it can end what it started). The callbacks may handle
// events (the data is read while they run), and no position is reported once a drop is being performed.
@protocol CGSDragDestination <NSObject>
- (CGSDragOperation) dropSession: (id<CGSDropSession>) session enteredAtPoint: (CGPoint) point;
- (CGSDragOperation) dropSession: (id<CGSDropSession>) session updatedAtPoint: (CGPoint) point;
- (void) dropSessionExited: (id<CGSDropSession>) session;
// The source dropped. operation is the one the window system was told the drop would do (a single one, one of
// those the last position returned; kCGSDragOperationNone when the last position was not accepted, and nothing
// is to be performed then). Returns the operation actually performed, kCGSDragOperationNone when the drop was
// refused or failed.
- (CGSDragOperation) dropSession: (id<CGSDropSession>) session performWithOperation: (CGSDragOperation) operation;
@end

// Makes the window take drops (or, with nil, stops it taking them): the drags over it are reported to the
// destination, which is retained for as long as the window has it. A window that was never given a destination
// is not offered to a drag. Does nothing for a window that does not exist, or when the backend has no drags.
COREGRAPHICS_EXPORT void _CGSDragSetDestination(CGSWindowID window, id<CGSDragDestination> destination);

#endif
