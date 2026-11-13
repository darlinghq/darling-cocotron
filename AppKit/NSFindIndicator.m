/*
 This file is part of Darling.

 Copyright (C) 2026 Darling developers

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

#import <Foundation/Foundation.h>

// Private: the highlight shown over find results. Darling doesn't draw it, so
// showing one only runs the completion handler.
@interface NSFindIndicator : NSObject {
    void (^_completionHandler)(void);
}
@end

@implementation NSFindIndicator

- (void) dealloc {
    [_completionHandler release];
    [super dealloc];
}

- (void) setRects: (NSArray *) rects {
}

- (void) setView: (id) view {
}

- (void) setContentDrawer: (id) contentDrawer {
}

- (void) setCompletionHandler: (void (^)(void)) completionHandler {
    [_completionHandler release];
    _completionHandler = [completionHandler copy];
}

- (void) pulseAndFade: (BOOL) fade {
    void (^handler)(void) = _completionHandler;
    _completionHandler = nil;
    if (handler != nil)
        handler();
    [handler release];
}

@end
