/*
 This file is part of Darling.

 Copyright (C) 2021 Lubos Dolezel

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

#import <AppKit/AppKitExport.h>
#import <AppKit/AppKitIvarLayout.h>
#import <Foundation/Foundation.h>
#import <AppKit/NSUserInterfaceItemIdentification.h>

@class NSView, NSLayoutDimension, NSLayoutXAxisAnchor, NSLayoutYAxisAnchor;

@interface NSLayoutGuide : NSObject <NSCoding, NSUserInterfaceItemIdentification> {
    NSRect _frame;
    NSView *_owningView;
    NSString *_identifier;
    NS_LEGACY_IVAR_PAD(_NSLayoutGuideReserved, 68)
}

- (instancetype) init;
- (instancetype) initWithCoder: (NSCoder *) coder;
- (void) encodeWithCoder: (NSCoder *) coder;

@property (assign) NSView *owningView;
@property (copy) NSString *identifier;
@property (readonly) NSRect frame;

@property (readonly, retain) NSLayoutDimension *widthAnchor;
@property (readonly, retain) NSLayoutDimension *heightAnchor;
@property (readonly, retain) NSLayoutXAxisAnchor *leadingAnchor;
@property (readonly, retain) NSLayoutXAxisAnchor *trailingAnchor;
@property (readonly, retain) NSLayoutXAxisAnchor *leftAnchor;
@property (readonly, retain) NSLayoutXAxisAnchor *rightAnchor;
@property (readonly, retain) NSLayoutXAxisAnchor *centerXAnchor;
@property (readonly, retain) NSLayoutYAxisAnchor *topAnchor;
@property (readonly, retain) NSLayoutYAxisAnchor *bottomAnchor;
@property (readonly, retain) NSLayoutYAxisAnchor *centerYAnchor;

@end
