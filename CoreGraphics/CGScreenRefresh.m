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

#import <CoreGraphics/CGRemoteOperation.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSValue.h>
#include <dispatch/dispatch.h>

// The registered refresh callbacks, as (callback, userInfo) pairs. No backend
// reports screen refreshes, so they are never called.
static NSMutableArray *refreshCallbacks(void) {
    static NSMutableArray *callbacks;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        callbacks = [[NSMutableArray alloc] init];
    });
    return callbacks;
}

static NSArray *refreshEntry(CGScreenRefreshCallback callback, void *userInfo) {
    return @[ [NSValue valueWithPointer: (void *) callback],
              [NSValue valueWithPointer: userInfo] ];
}

CGError CGRegisterScreenRefreshCallback(CGScreenRefreshCallback callback, void *userInfo) {
    if (callback == NULL)
        return kCGErrorSuccess;
    NSMutableArray *callbacks = refreshCallbacks();
    @synchronized(callbacks) {
        NSArray *entry = refreshEntry(callback, userInfo);
        if (![callbacks containsObject: entry])
            [callbacks addObject: entry];
    }
    return kCGErrorSuccess;
}

void CGUnregisterScreenRefreshCallback(CGScreenRefreshCallback callback, void *userInfo) {
    NSMutableArray *callbacks = refreshCallbacks();
    @synchronized(callbacks) {
        [callbacks removeObject: refreshEntry(callback, userInfo)];
    }
}
