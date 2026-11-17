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

// The text system (NSLayoutManager, NSTextStorage, NSShadow, ...) lives in
// UIFoundation, below AppKit, and cannot link against it. This object, which
// AppKit registers as soon as it is loaded, gives UIFoundation the current
// drawing context from AppKit's NSGraphicsContext stack and the AppKit
// objects (colours, the fallback font, images, attachment cells) the text
// classes need.

#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSTextAttachmentCell.h>
#import <UIFoundation/UIFoundationGraphicsContext.h>

@interface _NSUIFoundationProvider : NSObject <_UIFoundationGraphicsContextProvider>
@end

@implementation _NSUIFoundationProvider

+ (void) load {
    _NSUIFoundationProvider *provider = [[self alloc] init];
    _UIFoundationSetGraphicsContextProvider(provider);
    [provider release];
}

- (CGContextRef) currentCGContext {
    return [[NSGraphicsContext currentContext] graphicsPort];
}

- (BOOL) currentContextIsFlipped {
    return [[NSGraphicsContext currentContext] isFlipped];
}

- (BOOL) currentContextIsDrawingToScreen {
    return [[NSGraphicsContext currentContext] isDrawingToScreen];
}

- (id) textColorForRole: (_UIFoundationTextColorRole) role {
    switch (role) {
    case _UIFoundationTextColorRoleText:
        return [NSColor blackColor];
    case _UIFoundationTextColorRoleControlText:
        return [NSColor controlTextColor];
    case _UIFoundationTextColorRoleSelectedText:
        return [NSColor selectedTextColor];
    case _UIFoundationTextColorRoleSelectedTextBackground:
        return [NSColor selectedTextBackgroundColor];
    case _UIFoundationTextColorRoleSpellingIndicator:
        return [NSColor redColor];
    case _UIFoundationTextColorRoleShadow:
        // A shadow is black with an alpha of one third until told otherwise.
        return [NSColor colorWithCalibratedWhite: 0 alpha: 1.0 / 3.0];
    }
    return nil;
}

- (id) defaultTextFont {
    return [NSFont fontWithName: @"Arial" size: 12.0];
}

- (id) imageWithData: (NSData *) data {
    return [[[NSImage alloc] initWithData: data] autorelease];
}

- (id) newTextAttachmentCell {
    return [[NSTextAttachmentCell alloc] init];
}

@end
