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

#import <AppKit/NSCursor.h>

// QUIRK: +busyButClickableCursor returns a shared wait cursor whose clicks still reach the application.
// Not documented. Evidence: Mozilla's MPL-2.0 nsCursorManager.mm calls the selector and Chromium's
// BSD-licensed cursor code names the same CoreCursor shape (tier 3, independent public Cocoa clients). No
// OS-version dependence is known.
// https://github.com/mozilla/gecko-dev/blob/5836a062726f715fda621338a17b51aff30d0a8c/widget/cocoa/nsCursorManager.mm
// Test: appkit-cursor-busy-but-clickable.
@interface NSCursor (NSPrivateStandardCursors)
+ (NSCursor *) busyButClickableCursor;
@end
