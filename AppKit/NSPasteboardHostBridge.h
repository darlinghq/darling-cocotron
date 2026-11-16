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

#import <AppKit/NSPasteboard.h>

// The host clipboard and the general pasteboard.
//
// The general pasteboard lives in CoreFoundation's pasteboard (shared by every process of the user). A window
// system backend that can reach the host's clipboard provides it through its pasteboard class, which
// implements this protocol, and registers it with NSPasteboardRegisterHostClipboard(): the clipboard is then kept
// in step with the general pasteboard in both directions. -types and -dataForType: of the object read the
// host clipboard; -declareTypes:owner: and -setData:forType: publish to it.
@protocol NSPasteboardHostClipboard <NSObject>

// Whether this process holds the host clipboard (what it publishes is shown to other host programs).
- (BOOL) ownsHostClipboard;

// The handler is called, on the main thread, when another host client took the clipboard over.
- (void) setHostClipboardChangeHandler: (void (^)(void)) handler;

@end

// A type no host program uses, added to what is published, that tells another Darling process which sees the
// clipboard through the same window system that its contents already are the general pasteboard.
extern NSPasteboardType const NSPasteboardHostBridgeOriginType;

// Registers the clipboard (once per process, before the process creates the general pasteboard: the
// backend's display initialization is the place). Does nothing if a clipboard is registered already.
void NSPasteboardRegisterHostClipboard(NSPasteboard<NSPasteboardHostClipboard> *clipboard);
