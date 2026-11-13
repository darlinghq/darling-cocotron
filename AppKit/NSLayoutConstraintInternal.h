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

#import <AppKit/NSLayoutConstraint.h>

// Used by NSView to link a constraint with the view that stores it. Not
// installed.
@interface NSLayoutConstraint (NSLayoutConstraintInternal)
// Records the view as the constraint's owner and marks it active. A
// constraint owned by another view is first removed from that view.
- (void) _attachToOwner: (id) owner;
// Clears the owner link and marks the constraint inactive when the owner is
// the given view.
- (void) _detachFromOwner: (id) owner;
@end
