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

#ifndef CGSSELECTION_H
#define CGSSELECTION_H
#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSString.h>
#include <stdbool.h>

// The window system's clipboard and selections (private interface).
//
// CoreGraphics owns the process' connection to the window system, so it also owns the process' part in
// the window system's selection protocols: the ICCCM selections on X11 (CLIPBOARD, and the selection a drag
// publishes) and the data device's selection on Wayland. The general pasteboard of CoreFoundation is kept in step
// with the host clipboard from here (see _CGSHostClipboardStart()), so a process that never creates a window
// gets the clipboard too, and AppKit's NSPasteboard only has to be a view of CoreFoundation's pasteboard.
//
// An endpoint is one selection as seen by this process: it holds the selection when the process is its owner (and
// serves what the source gives it to the clients that ask), and reads the selection of the client that owns it
// when it is not. Types are named as NSPasteboard names them in the UTI spelling (public.utf8-plain-text); the
// window system's own names (X11 targets, MIME types) are mapped to them and back.

@protocol CGSSelectionSource <NSObject>
// The data of a type of the selection this process owns, nil when it has none (the requesting client is then
// refused). Called on the main thread, while an event of the window system is being handled (X11), or once the
// selection is published (Wayland: for every type, at that time).
- (NSData *) selectionDataForType: (NSString *) type;
// Another client took the selection over from this process (the types declared are no longer offered).
- (void) selectionLost;
@end

@protocol CGSSelectionEndpoint <NSObject>
// Not retained.
@property(assign) id<CGSSelectionSource> source;
// Counts every change of the selection that this process makes or notices (a new owner, new types).
- (NSInteger) changeCount;
- (void) bumpChangeCount;

// Whether this process is the selection's owner.
- (BOOL) ownsSelection;
// Makes the process the owner of the selection, and an owner of no types until -setLocalTypes: says.
- (void) acquire;
// The types the process offers (replacing the earlier ones), in the order they are listed in. Wayland: the
// compositor is told when the input event that entitles the process to publish is known.
- (void) setLocalTypes: (NSArray<NSString *> *) types;
// Forgets what the process offered, without telling the window system and without a call to the source.
- (void) relinquish;

// The types the client that owns the selection offers: those of the selection itself (nothing when it has no
// owner or the process owns it).
- (NSArray<NSString *> *) remoteTypes;
// The data of a type of the owner's selection, converted to the type's usual representation (text is UTF-8).
// nil when it has none or does not answer in a few seconds. The calling thread keeps handling the window
// system's events while it waits.
- (NSData *) remoteDataForType: (NSString *) type;

// Called on the main thread when another client has become the owner of the selection (while this process was
// not its owner): what the process knew of the selection is out of date. X11 sends no event for that, so the
// owner is polled.
- (void) setHostChangeHandler: (void (^)(void)) handler;

@optional
// X11: the helper window that owns the selection and answers its requests, and the selection's atom. A drag
// publishes the window as the source of its XDND session.
- (unsigned long) windowHandle;
- (unsigned long) selectionAtom;
@end

// A selection endpoint of the process' connection to the window system (X11: the selection of that name, such
// as XdndSelection; Wayland: only the clipboard, named CLIPBOARD, made by the connection itself). nil without a
// connection or when the backend has none by that name. The caller owns the result (a new endpoint is made
// for every call).
extern id<CGSSelectionEndpoint> _CGSNativeConnectionNewSelection(NSString *name);

// Connects the general pasteboard of CoreFoundation with the host clipboard that the endpoint stands for:
// everything put on the pasteboard (by this or any other process of the user) is offered to the host's programs,
// and what a host program copies becomes the pasteboard's contents. Called by the backend once, when it has the
// connection (CFPasteboardRegisterHostBridge() needs it to happen before the process makes its first
// pasteboard). Does nothing if a bridge is registered already.
extern void _CGSHostClipboardStart(id<CGSSelectionEndpoint> clipboard);

// The type no host program uses, added to what the bridge publishes: it tells another Darling process which sees
// the clipboard through the same window system that its contents already are the general pasteboard.
extern NSString *const CGSHostClipboardOriginType;

// Mapping of the types to the names the window systems use for them, and back.
// X11: the selection targets a type is converted to (the most specific first), the type a target stands for and
// the MIME type XDND names a type by (nil when it has none).
extern NSArray<NSString *> *_CGSSelectionTargetsForType(NSString *type);
extern NSString *_CGSSelectionTypeForTarget(NSString *target);
extern NSString *_CGSSelectionMimeTypeForType(NSString *type);
// Wayland: the MIME types a type is offered as (the first the preferred), the types a MIME type stands for, and
// the data of a type as it is offered (a list of file names becomes a text/uri-list; nil if it cannot be offered or
// is too large) and as it is read from a MIME type (the inverse).
extern NSArray<NSString *> *_CGSSelectionMimeTypesForType(NSString *type);
extern NSArray<NSString *> *_CGSSelectionTypesForMime(NSString *mime);
extern NSData *_CGSSelectionEncodeData(NSData *data, NSString *type);
extern NSData *_CGSSelectionDecodeData(NSData *data, NSString *type, NSString *mime);
// The largest transfer either direction takes (16 MiB).
extern const NSUInteger CGSSelectionTransferLimit;
// Writes the data to the descriptor from a short-lived thread bounded to a few seconds, so that a slow reader
// cannot hold the caller up, and closes the descriptor (also when data is nil).
extern void _CGSSelectionSendData(NSData *data, int fd);

#endif
