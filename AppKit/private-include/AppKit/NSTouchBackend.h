/*
 Copyright (C) 2026 Lubos Dolezel

 This file is part of Darling.

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
#import <AppKit/NSTouch.h>

@class NSWindow;

/*
 * How a windowing backend (or a host embedding Darling, such as a phone
 * shell) reports a finger. The identifier names the finger while it is
 * down and may be reused afterwards. The location is in the window's base
 * coordinates, from its bottom left. The finger is hit tested when it
 * begins and stays with the view it began in. An end or a cancel may give
 * NAN coordinates for the finger's last location.
 */
APPKIT_EXPORT void NSTouchPost(NSWindow *window, long long identifier,
                               NSTouchPhase phase, NSPoint location,
                               NSTimeInterval timestamp);

// Cancels every finger down in the window, or in all windows for nil (a
// compositor that takes the touch screen for itself).
APPKIT_EXPORT void NSTouchCancelAll(NSWindow *window);
