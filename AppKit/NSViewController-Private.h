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

#import <AppKit/NSViewController.h>
#import <AppKit/NSView.h>

@class NSView, NSWindow;

@interface NSView (NSView_viewController)
// The controller whose -view this is, not retained: set by -[NSViewController setView:].
- (NSViewController *) _viewController;
- (void) _setViewController: (NSViewController *) controller;
@end

// The appearance callbacks (-viewWillAppear and its siblings) follow whether a
// controller's view is in a visible window and not hidden. Whoever changes one
// of the things that decide that asks for the transitions first, makes the
// change, and then reports the same list as done:
//
//   NSArray *t = [NSViewController _appearanceTransitionsUnder: root ...];
//   [NSViewController _willPerformAppearanceTransitions: t];
//   ...the change...
//   [NSViewController _didPerformAppearanceTransitions: t];
//
// The list holds the controllers under root whose appeared state differs from
// what it will be after the change, in view hierarchy order (a parent's view
// comes before its subviews).
@interface NSViewController (NSViewController_appearance)
- (BOOL) _appeared;
- (void) _setAppeared: (BOOL) appeared;
// window: the window the views will be in (nil: none). visible: whether that
// window will be shown. rootSuperview: the superview root will have.
// useRootHidden/rootHidden: root's hidden flag as it will be, when it changes.
+ (NSArray *) _appearanceTransitionsUnder: (NSView *) root
                                   window: (NSWindow *) window
                            windowVisible: (BOOL) visible
                            rootSuperview: (NSView *) rootSuperview
                            useRootHidden: (BOOL) useRootHidden
                                rootHidden: (BOOL) rootHidden;
+ (void) _willPerformAppearanceTransitions: (NSArray *) transitions;
+ (void) _didPerformAppearanceTransitions: (NSArray *) transitions;
@end
