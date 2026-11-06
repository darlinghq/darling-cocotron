/*
 This file is part of Darling.

 Copyright (C) 2026 Darling Developers

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

#import <AppKit/NSColorSampler.h>
#import <AppKit/NSColor.h>
#include <dispatch/dispatch.h>

@implementation NSColorSampler

// There is no screen sampling user interface, so the sampler ends at once the
// way a cancelled one does: the handler gets nil. It runs later on the main
// queue, as it would after the user's choice, not before this returns.
- (void) showSamplerWithSelectionHandler:
        (void (^)(NSColor *selectedColor)) selectionHandler
{
    if (selectionHandler == nil)
        return;

    void (^handler)(NSColor *) = [selectionHandler copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(nil);
        [handler release];
    });
}

@end
