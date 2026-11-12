/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

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
#import <AppKit/NSCell.h>
#import <AppKit/NSTableView.h>

@class NSTextField, NSImageView;

@interface NSTableCellView : NSView {
    NSTextField *_textField;
    NSImageView *_imageView;
    id _objectValue;
    NSBackgroundStyle _backgroundStyle;
    NSTableViewRowSizeStyle _rowSizeStyle;
}

@property (assign) IBOutlet NSTextField *textField;
@property (assign) IBOutlet NSImageView *imageView;
@property (retain) id objectValue;
@property NSBackgroundStyle backgroundStyle;
@property NSTableViewRowSizeStyle rowSizeStyle;

@end
