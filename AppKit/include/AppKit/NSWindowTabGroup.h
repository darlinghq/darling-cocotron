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

#import <Foundation/NSObject.h>
#import <AppKit/NSWindow.h>

NS_ASSUME_NONNULL_BEGIN

// The windows shown as tabs of one window (macOS 10.13). Window tabbing is not
// implemented, so a group holds only the window it belongs to, its tab bar is
// never visible, and adding or removing windows has no effect.
@interface NSWindowTabGroup : NSObject {
    NSWindow *_window;
    NSWindowTabbingIdentifier _identifier;
    BOOL _overviewVisible;
}

@property(readonly, copy) NSWindowTabbingIdentifier identifier;
@property(readonly, copy) NSArray<NSWindow *> *windows;
@property(getter=isOverviewVisible) BOOL overviewVisible;
@property(readonly, getter=isTabBarVisible) BOOL tabBarVisible;
@property(nullable, assign) NSWindow *selectedWindow;

- (void) addWindow: (NSWindow *) window;
- (void) insertWindow: (NSWindow *) window atIndex: (NSInteger) index;
- (void) removeWindow: (NSWindow *) window;

@end

NS_ASSUME_NONNULL_END
