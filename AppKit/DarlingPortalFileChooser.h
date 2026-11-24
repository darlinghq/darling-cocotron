/* Copyright (C) 2026 Lubos Dolezel

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

#pragma once
#import <Foundation/Foundation.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSSavePanel.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>

// Optional use of the desktop's file chooser, the FileChooser interface of
// org.freedesktop.portal.Desktop (xdg-desktop-portal), for NSOpenPanel and
// NSSavePanel. The built-in panel stays the default. The portal is used only
// when the DesktopFileChooser preference is true (the application's own value,
// else the org.darlinghq.AppKit domain), the session bus has the portal, and
// the panel asks for nothing the portal cannot express. Otherwise the panel behaves exactly as without this file.

// YES when the DesktopFileChooser preference is true. Read once per process.
BOOL DarlingPortalFileChooserEnabled(void);

// The pop-up buttons and check boxes of an accessory view as the portal's
// "choices", or nil when the view holds anything else (or no control at all).
// Only pop-up buttons (not pull-down) and check boxes, static labels and plain
// container views (NSView, NSBox) are supported; every control must be
// enabled and shown. One dictionary for each control, top to bottom:
//   id       "c0", "c1", ...
//   label    a pop-up's nearest static label (a colon at its end removed), else
//            the title of the selected item; a check box's title
//   options  array of [id, label], the pop-up's usable items (id is the item's
//            index); empty for a check box
//   initial  the id of the selected option; "true" or "false" for a check box
//   control, itemIndexes  the control and the item index of each option
// In the request they are the "choices" option, as [id, label, options,
// initial].
NSArray *DarlingPortalChoicesForAccessoryView(NSView *view);

// Why the portal cannot show this panel, or nil when it can: an accessory
// view that is not expressible as choices, a delegate that filters or validates, a subclass of the panel class,
// hidden files shown, packages treated as folders, or an open panel that
// chooses files and folders at once.
NSString *DarlingPortalUnsupportedFeature(NSSavePanel *panel);

// The method name and arguments for the panel, as a plain description:
//   method  "OpenFile" or "SaveFile"
//   title   string
//   options dictionary: accept_label, modal, multiple, directory (strings and
//           booleans), choices (the accessory view's, see above), filters (array of [name, [[kind, pattern]...]], kind 0
//           is a glob, 1 a MIME type), current_filter (one such filter),
//           current_name (string), current_folder (NUL-terminated host path as
//           NSData).
// Only keys with a value are present.
NSDictionary *DarlingPortalRequestForPanel(NSSavePanel *panel);

// The guest paths for the "uris" of a portal response, or nil when the list is
// empty or too long, or any entry is not one well formed file URI (see
// DarlingFileURIList.h).
NSArray *DarlingPortalPathsFromURIs(NSArray *uris);

// The NSModalResponse for the portal's response code: 0 (success) is
// NSModalResponseOK, 1 (cancelled) and 2 (ended otherwise) are
// NSModalResponseCancel.
NSInteger DarlingPortalModalResponseForCode(uint32_t code);

// The portal's host path for a guest path (the guest sees the host's files
// below /Volumes/SystemRoot), or nil for a path that exists only in the guest.
NSString *DarlingPortalHostPathForGuestPath(NSString *path);

// Runs the panel through the portal. Used by the panels in place of their own
// window; each returns NO, without side effects, when the portal is not to be
// used, so the caller shows its own panel.

// Blocks (running the run loop) until the portal's dialog is closed. On
// NSModalResponseOK the panel's filename and filenames are set.
BOOL DarlingPortalRunModal(NSSavePanel *panel, NSModalResponse *response);

// Returns at once; the handler runs on the main thread when the dialog closes.
// The parent window, if any, is the window the dialog belongs to.
BOOL DarlingPortalBegin(NSSavePanel *panel, NSWindow *parent,
                        void (^handler)(NSModalResponse response));
