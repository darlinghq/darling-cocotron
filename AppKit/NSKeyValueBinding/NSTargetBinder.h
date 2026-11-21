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

#import "NSBinder.h"

@class NSString;

// The binder of a control's "target" binding and of its "argument",
// "argument2", ... bindings. They are read only: the bound values are not
// written into the control. When the control sends its action, the target
// binding's object is sent the message named by the NSSelectorName option,
// with the argument bindings' values as its arguments.
@interface _NSTargetBinder : _NSBinder {
    BOOL _isObserving;
}
@end

// Whether a binding of a control is handled by _NSTargetBinder.
BOOL _NSIsTargetOrArgumentBinding(NSString *binding);

// Sends the message of the source's target binding, if it has one whose
// object, selector and arguments are all there. Returns whether it was sent.
BOOL _NSSendTargetBindingAction(id source);
