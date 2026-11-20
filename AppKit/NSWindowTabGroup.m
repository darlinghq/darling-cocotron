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

#import <AppKit/NSWindowTabGroup.h>
#import <AppKit/NSWindowTabGroup+Private.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>

@implementation NSWindowTabGroup

- (instancetype) _initWithWindow: (NSWindow *) window {
    if ((self = [super init]) != nil) {
        _window = window;
        _identifier = [[window tabbingIdentifier] copy];
    }
    return self;
}

- (void) dealloc {
    [_identifier release];
    [super dealloc];
}

- (void) _windowWillDeallocate {
    _window = nil;
}

- (NSWindowTabbingIdentifier) identifier {
    return _identifier;
}

- (NSArray<NSWindow *> *) windows {
    return _window != nil ? [NSArray arrayWithObject: _window] : [NSArray array];
}

- (BOOL) isOverviewVisible {
    return _overviewVisible;
}

// There is no tab overview to show; the value is kept for callers to read.
- (void) setOverviewVisible: (BOOL) visible {
    _overviewVisible = visible;
}

- (BOOL) isTabBarVisible {
    return NO;
}

- (NSWindow *) selectedWindow {
    return _window;
}

// The group's only window is always the selected one.
- (void) setSelectedWindow: (NSWindow *) window {
}

- (void) addWindow: (NSWindow *) window {
}

- (void) insertWindow: (NSWindow *) window atIndex: (NSInteger) index {
}

- (void) removeWindow: (NSWindow *) window {
}

@end
