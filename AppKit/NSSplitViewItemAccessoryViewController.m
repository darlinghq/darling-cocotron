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

#import <AppKit/NSSplitViewItemAccessoryViewController.h>

// Stores the two documented flags. NSSplitViewItem has no way to attach an
// accessory yet, so a controller of this class is never shown.
@implementation NSSplitViewItemAccessoryViewController
@synthesize hidden = _hidden;
@synthesize automaticallyAppliesContentInsets = _automaticallyAppliesContentInsets;

- (instancetype) initWithNibName: (NSString *) nibName bundle: (NSBundle *) bundle {
    if ((self = [super initWithNibName: nibName bundle: bundle]) != nil)
        _automaticallyAppliesContentInsets = YES;
    return self;
}

// An accessory loaded from a nib takes this path, not the one above.
- (instancetype) initWithCoder: (NSCoder *) coder {
    if ((self = [super initWithCoder: coder]) != nil)
        _automaticallyAppliesContentInsets = YES;
    return self;
}

@end
