/*
 * This file is part of Darling.
 *
 * Copyright (C) 2024 Darling Developers
 *
 * Darling is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Darling is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Darling.  If not, see <http://www.gnu.org/licenses/>.
 */

 #import <AppKit/NSMenuItemCell.h>
 #import <AppKit/NSAttributedString.h>
 #import <AppKit/NSFont.h>
 #import <AppKit/NSImage.h>
 #import <AppKit/NSMenuItem.h>
 #import <AppKit/NSStringDrawing.h>

 @implementation NSMenuItemCell

 @synthesize menuItem = _menuItem;

 - initWithCoder: (NSCoder *) coder {
    self = [super initWithCoder: coder];

    if ([coder allowsKeyedCoding]) {
        _menuItem = [[coder decodeObjectForKey:@"NSMenuItem"] retain];
    } else {
        NSInteger version = [coder versionForClassName: @"NSMenuItemCell"];

        if (version >= 207) {
            id object;
            [coder decodeValuesOfObjCTypes:"@@", &_menuItem, &object];

            // Discard for now
            [object release];

            if (version <= 209) {
                [self setBordered: NO];
            }
        } else {
            [self setBordered: NO];
        }
    }

    return self;
 }

 - (void) dealloc {
    [_menuItem release];
    [super dealloc];
}

// The widths of the parts of a menu item as the cell lays them out: state
// column, image, title and key equivalent. A cell without a menu item has
// none of them. The values follow what macOS 26.7.3 reports for cells not
// drawn by a menu view.

// The state column takes 18 points whatever the font, or the width of the
// widest state image the item has, if that is more.
- (CGFloat) stateImageWidth {
    NSMenuItem *item = [self menuItem];
    if (item == nil)
        return 0;
    CGFloat width = 18;
    width = MAX(width, [[item onStateImage] size].width);
    width = MAX(width, [[item offStateImage] size].width);
    width = MAX(width, [[item mixedStateImage] size].width);
    return width;
}

- (CGFloat) imageWidth {
    NSImage *image = [[self menuItem] image];
    return image != nil ? [image size].width : 0;
}

// The width of the title in the cell's font, with 2 points of margin on
// each side.
- (CGFloat) titleWidth {
    NSMenuItem *item = [self menuItem];
    if (item == nil)
        return 0;
    NSAttributedString *attributed = [item attributedTitle];
    if (attributed != nil)
        return [attributed size].width + 4;
    NSString *title = [item title];
    NSFont *font = [self font];
    NSDictionary *attributes = font != nil ? [NSDictionary dictionaryWithObject: font forKey: NSFontAttributeName] : nil;
    return [title sizeWithAttributes: attributes].width + 4;
}

// Key equivalents are shown only in menus, which draw their items
// themselves; a cell on its own leaves no room for one.
- (CGFloat) keyEquivalentWidth {
    return 0;
}

 @end
