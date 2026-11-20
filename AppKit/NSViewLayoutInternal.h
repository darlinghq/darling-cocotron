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

#import <AppKit/NSView.h>

// Not installed.
@interface NSView (NSViewLayoutInternal)
// Sent to a view's superview by -invalidateIntrinsicContentSize. A container
// that arranges its subviews from their intrinsic sizes without constraints
// overrides it to arrange them again; the default does nothing.
- (void) _subviewIntrinsicContentSizeDidChange: (NSView *) subview;
// Sent to a view's superview when the view's content hugging priority changes, for a container
// that arranges its subviews itself; the default does nothing.
- (void) _subviewContentHuggingPriorityDidChange: (NSView *) subview;
// The intrinsic size the constraint solver uses for the view. By default the
// public -intrinsicContentSize; a text field that wraps at the width layout
// gives it answers the height of its wrapped text there.
- (NSSize) _intrinsicContentSizeForLayout;
// The content hugging priority of a view whose priority was not set: NSLayoutPriorityDefaultLow,
// unless the class (or its state, as a button's bezel) calls for another one.
- (NSLayoutPriority) _defaultContentHuggingPriorityForOrientation: (NSLayoutConstraintOrientation) orientation;
@end
