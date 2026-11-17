/* Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <AppKit/NSApplication.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSDocument.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSStringDrawer.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSToolbar.h>
#import <AppKit/NSToolbarItem.h>
#import <AppKit/NSToolbarItemView.h>

const NSToolbarItemIdentifier NSToolbarCustomizeToolbarItemIdentifier =
        @"NSToolbarCustomizeToolbarItem";
const NSToolbarItemIdentifier NSToolbarFlexibleSpaceItemIdentifier =
        @"NSToolbarFlexibleSpaceItem";
const NSToolbarItemIdentifier NSToolbarPrintItemIdentifier =
        @"NSToolbarPrintItem";
const NSToolbarItemIdentifier NSToolbarSeparatorItemIdentifier =
        @"NSToolbarSeparatorItem";
const NSToolbarItemIdentifier NSToolbarShowColorsItemIdentifier =
        @"NSToolbarShowColorsItem";
const NSToolbarItemIdentifier NSToolbarShowFontsItemIdentifier =
        @"NSToolbarShowFontsItem";
const NSToolbarItemIdentifier NSToolbarSpaceItemIdentifier =
        @"NSToolbarSpaceItem";
NSToolbarItemIdentifier NSToolbarToggleSidebarItemIdentifier =
        @"NSToolbarToggleSidebarItem";
NSToolbarItemIdentifier NSToolbarSidebarTrackingSeparatorItemIdentifier =
        @"NSToolbarSidebarTrackingSeparatorItemIdentifier";
NSToolbarItemIdentifier NSToolbarWritingToolsItemIdentifier =
        @"NSToolbarWritingToolsItem";

extern NSSize _NSToolbarSizeRegular;
extern NSSize _NSToolbarSizeSmall;
extern NSSize _NSToolbarIconSizeRegular;
extern NSSize _NSToolbarIconSizeSmall;

@interface NSToolbar (private)
- (NSView *) _view;
- (void) itemSizeDidChange;
- (NSDictionary *) _labelAttributes;
- (NSDictionary *) _labelAttributesForSizeMode: (NSToolbarSizeMode) sizeMode;
@end

@implementation NSToolbarItem

extern NSSize _NSToolbarIconSizeRegular;
extern NSSize _NSToolbarIconSizeSmall;

- (void) _configureAsStandardItemIfNeeded {
    if ([NS_EXTRA(NSToolbarItem, self)->_itemIdentifier isEqualToString: NSToolbarSeparatorItemIdentifier]) {
        NSSize size;

        [self setLabel: @""];
        [self setPaletteLabel: NSLocalizedStringFromTableInBundle(
                                       @"Separator", nil,
                                       [NSBundle
                                               bundleForClass: [NSToolbarItem
                                                                       class]],
                                       @"Describes a toolbar separator item")];
        [self setEnabled: NO];

        size = [self minSize];
        size.width = floor(size.width / 2);
        [self setMinSize: size];
        size = [self maxSize];
        size.width = floor(size.width / 2);
        [self setMaxSize: size];

    } else if ([NS_EXTRA(NSToolbarItem, self)->_itemIdentifier
                       isEqualToString: NSToolbarSpaceItemIdentifier]) {
        NSSize size;

        [self setLabel: @""];
        [self setPaletteLabel: NSLocalizedStringFromTableInBundle(
                                       @"Space", nil,
                                       [NSBundle
                                               bundleForClass: [NSToolbarItem
                                                                       class]],
                                       @"Describes a toolbar space item")];
        [self setEnabled: NO];

        size = [self minSize];
        size.width /= 2;
        [self setMinSize: size];
        size = [self maxSize];
        size.width /= 2;
        [self setMaxSize: size];

    } else if ([NS_EXTRA(NSToolbarItem, self)->_itemIdentifier
                       isEqualToString: NSToolbarFlexibleSpaceItemIdentifier]) {
        NSSize size;

        [self setLabel: @""];
        [self setPaletteLabel:
                        NSLocalizedStringFromTableInBundle(
                                @"Flexible Space", nil,
                                [NSBundle
                                        bundleForClass: [NSToolbarItem class]],
                                @"Describes a toolbar flexible space item")];
        [self setEnabled: NO];

        size = [self minSize];
        size.width /= 2;
        [self setMinSize: size];
        [self setMaxSize: NSMakeSize(-1, [self maxSize].height)];

    } else if ([NS_EXTRA(NSToolbarItem, self)->_itemIdentifier
                       isEqualToString: NSToolbarShowColorsItemIdentifier]) {
        [self setLabel: NSLocalizedStringFromTableInBundle(
                                @"Colors", nil,
                                [NSBundle
                                        bundleForClass: [NSToolbarItem class]],
                                @"Reveals a color picker")];
        [self setPaletteLabel: NSLocalizedStringFromTableInBundle(
                                       @"Show Colors", nil,
                                       [NSBundle
                                               bundleForClass: [NSToolbarItem
                                                                       class]],
                                       @"Reveals a color picker")];
        [self setTarget: [NSApplication sharedApplication]];
        [self setAction: @selector(orderFrontColorPanel:)];
        [self setImage: [NSImage
                                imageNamed: NSToolbarShowColorsItemIdentifier]];
        [self setToolTip: NSLocalizedStringFromTableInBundle(
                                  @"Show the Colors panel.", nil,
                                  [NSBundle bundleForClass: [NSToolbarItem
                                                                    class]],
                                  @"Reveals a color picker")];
    } else if ([NS_EXTRA(NSToolbarItem, self)->_itemIdentifier
                       isEqualToString: NSToolbarShowFontsItemIdentifier]) {
        [self setLabel: NSLocalizedStringFromTableInBundle(
                                @"Fonts", nil,
                                [NSBundle
                                        bundleForClass: [NSToolbarItem class]],
                                @"Reveals a font picker")];
        [self setPaletteLabel: NSLocalizedStringFromTableInBundle(
                                       @"Show Fonts", nil,
                                       [NSBundle
                                               bundleForClass: [NSToolbarItem
                                                                       class]],
                                       @"Reveals a font picker")];
        [self setTarget: [NSFontManager sharedFontManager]];
        [self setAction: @selector(orderFrontFontPanel:)];
        [self setImage: [NSImage imageNamed: NSToolbarShowFontsItemIdentifier]];
        [self setToolTip: NSLocalizedStringFromTableInBundle(
                                  @"Show the Fonts panel.", nil,
                                  [NSBundle bundleForClass: [NSToolbarItem
                                                                    class]],
                                  @"Reveals a font picker")];
    } else if ([NS_EXTRA(NSToolbarItem, self)->_itemIdentifier
                       isEqualToString:
                               NSToolbarCustomizeToolbarItemIdentifier]) {
        [self setLabel: NSLocalizedStringFromTableInBundle(
                                @"Customize", nil,
                                [NSBundle
                                        bundleForClass: [NSToolbarItem class]],
                                @"Reveals a toolbar customization dialog")];
        [self setPaletteLabel:
                        NSLocalizedStringFromTableInBundle(
                                @"Customize", nil,
                                [NSBundle
                                        bundleForClass: [NSToolbarItem class]],
                                @"Reveals a toolbar customization dialog")];
        [self setTarget: nil];
        [self setAction: @selector(runToolbarCustomizationPalette:)];
        [self setImage: [NSImage
                                imageNamed:
                                        NSToolbarCustomizeToolbarItemIdentifier]];
        [self setToolTip: NSLocalizedStringFromTableInBundle(
                                  @"Customize this toolbar.", nil,
                                  [NSBundle bundleForClass: [NSToolbarItem
                                                                    class]],
                                  @"Reveals a toolbar customization dialog")];
    } else if ([NS_EXTRA(NSToolbarItem, self)->_itemIdentifier
                       isEqualToString: NSToolbarPrintItemIdentifier]) {
        [self setLabel: NSLocalizedStringFromTableInBundle(
                                @"Print", nil,
                                [NSBundle
                                        bundleForClass: [NSToolbarItem class]],
                                @"")];
        [self setPaletteLabel: NSLocalizedStringFromTableInBundle(
                                       @"Print Document", nil,
                                       [NSBundle
                                               bundleForClass: [NSToolbarItem
                                                                       class]],
                                       @"")];
        [self setTarget: nil];
        [self setAction: @selector(printDocument:)];
        [self setImage: [NSImage imageNamed: NSToolbarPrintItemIdentifier]];
        [self setToolTip: NSLocalizedStringFromTableInBundle(
                                  @"Print this document.", nil,
                                  [NSBundle bundleForClass: [NSToolbarItem
                                                                    class]],
                                  @"")];
    }
}

- (instancetype) initWithItemIdentifier: (NSToolbarItemIdentifier) identifier {
    NS_EXTRA(NSToolbarItem, self)->_itemIdentifier = [identifier retain];
    NS_EXTRA(NSToolbarItem, self)->_toolbar = nil;
    NS_EXTRA(NSToolbarItem, self)->_enclosingView = [[NSToolbarItemView alloc] init];
    [NS_EXTRA(NSToolbarItem, self)->_enclosingView setToolbarItem: self];
    NS_EXTRA(NSToolbarItem, self)->_image = nil;
    NS_EXTRA(NSToolbarItem, self)->_label = @"";
    NS_EXTRA(NSToolbarItem, self)->_paletteLabel = @"";
    NS_EXTRA(NSToolbarItem, self)->_target = nil;
    NS_EXTRA(NSToolbarItem, self)->_action = NULL;
    NS_EXTRA(NSToolbarItem, self)->_menuFormRepresentation = nil;
    NS_EXTRA(NSToolbarItem, self)->_view = nil;
    NS_EXTRA(NSToolbarItem, self)->_minSize = NSZeroSize;
    NS_EXTRA(NSToolbarItem, self)->_maxSize = NSZeroSize;
    NS_EXTRA(NSToolbarItem, self)->_visibilityPriority = NSToolbarItemVisibilityPriorityStandard;
    NS_EXTRA(NSToolbarItem, self)->_autovalidates = NO;
    NS_EXTRA(NSToolbarItem, self)->_isEnabled = YES;
    [self _configureAsStandardItemIfNeeded];

    return self;
}

- (void) dealloc {
    [NS_EXTRA(NSToolbarItem, self)->_itemIdentifier release];
    NS_EXTRA(NSToolbarItem, self)->_toolbar = nil;
    [NS_EXTRA(NSToolbarItem, self)->_enclosingView setToolbarItem: nil];
    [NS_EXTRA(NSToolbarItem, self)->_enclosingView release];
    [NS_EXTRA(NSToolbarItem, self)->_toolTip release];
    [NS_EXTRA(NSToolbarItem, self)->_image release];
    [NS_EXTRA(NSToolbarItem, self)->_label release];
    [NS_EXTRA(NSToolbarItem, self)->_paletteLabel release];
    [NS_EXTRA(NSToolbarItem, self)->_menuFormRepresentation release];
    [NS_EXTRA(NSToolbarItem, self)->_view release];
    NS_EXTRA_FREE(NSToolbarItem, self);
    [super dealloc];
}

// NSView does not adopt NSCopying, so a view is duplicated through keyed
// archiving, which is what its coding support is for.
static NSView *copyToolbarItemView(NSView *view) {
    if (view == nil)
        return nil;
    if ([view conformsToProtocol: @protocol(NSCopying)])
        return [view copy];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject: view];
    return [[NSKeyedUnarchiver unarchiveObjectWithData: data] retain];
}

- copyWithZone: (NSZone *) zone {
    NSToolbarItem *copy = NSCopyObject(self, 0, zone);
    NS_EXTRA_COPY(NSToolbarItem, copy, self);

    NS_EXTRA(NSToolbarItem, copy)->_itemIdentifier = [NS_EXTRA(NSToolbarItem, self)->_itemIdentifier copy];
    NS_EXTRA(NSToolbarItem, copy)->_toolbar = nil;
    NS_EXTRA(NSToolbarItem, copy)->_toolTip = [NS_EXTRA(NSToolbarItem, self)->_toolTip copy];
    NS_EXTRA(NSToolbarItem, copy)->_image = [NS_EXTRA(NSToolbarItem, self)->_image copy];
    NS_EXTRA(NSToolbarItem, copy)->_label = [NS_EXTRA(NSToolbarItem, self)->_label copy];
    NS_EXTRA(NSToolbarItem, copy)->_paletteLabel = [NS_EXTRA(NSToolbarItem, self)->_paletteLabel copy];
    NS_EXTRA(NSToolbarItem, copy)->_menuFormRepresentation = [NS_EXTRA(NSToolbarItem, self)->_menuFormRepresentation copy];
    NS_EXTRA(NSToolbarItem, copy)->_view = copyToolbarItemView(NS_EXTRA(NSToolbarItem, self)->_view);
    NS_EXTRA(NSToolbarItem, copy)->_enclosingView = [[NSToolbarItemView alloc]
            initWithFrame: [NS_EXTRA(NSToolbarItem, self)->_enclosingView frame]];
    [NS_EXTRA(NSToolbarItem, copy)->_enclosingView setToolbarItem: copy];
    [NS_EXTRA(NSToolbarItem, copy)->_enclosingView setSubview: NS_EXTRA(NSToolbarItem, copy)->_view];

    return copy;
}

- (NSView *) _enclosingView {
    return NS_EXTRA(NSToolbarItem, self)->_enclosingView;
}

- (void) _setToolbar: (NSToolbar *) toolbar {
    NS_EXTRA(NSToolbarItem, self)->_toolbar = toolbar;
}

- (NSToolbarItemIdentifier) itemIdentifier {
    return NS_EXTRA(NSToolbarItem, self)->_itemIdentifier;
}

- (NSToolbar *) toolbar {
    return NS_EXTRA(NSToolbarItem, self)->_toolbar;
}

- (NSString *) label {
    return NS_EXTRA(NSToolbarItem, self)->_label;
}

- (NSString *) paletteLabel {
    return NS_EXTRA(NSToolbarItem, self)->_paletteLabel;
}

// By default, this method returns a singleton menu item with item label as the
// title.  For standard items, the target, action is set.
- (NSMenuItem *) menuFormRepresentation {
    // FIX should update standard item for action/target/label changes?
    if (NS_EXTRA(NSToolbarItem, self)->_menuFormRepresentation == nil && [self label] != nil) {
        NS_EXTRA(NSToolbarItem, self)->_menuFormRepresentation =
                [[NSMenuItem alloc] initWithTitle: [self label]
                                           action: [self action]
                                    keyEquivalent: @""];
        [NS_EXTRA(NSToolbarItem, self)->_menuFormRepresentation setImage: [self image]];
        [NS_EXTRA(NSToolbarItem, self)->_menuFormRepresentation setTarget: [self target]];
        [NS_EXTRA(NSToolbarItem, self)->_menuFormRepresentation setRepresentedObject: self];
    }

    return NS_EXTRA(NSToolbarItem, self)->_menuFormRepresentation;
}

- (NSView *) view {
    return NS_EXTRA(NSToolbarItem, self)->_view;
}

- (NSSize) minSize {
    return NS_EXTRA(NSToolbarItem, self)->_minSize;
}

- (NSSize) maxSize {
    return NS_EXTRA(NSToolbarItem, self)->_maxSize;
}

- (NSInteger) visibilityPriority {
    return NS_EXTRA(NSToolbarItem, self)->_visibilityPriority;
}

- (BOOL) autovalidates {
    return NS_EXTRA(NSToolbarItem, self)->_autovalidates;
}

- (BOOL) allowsDuplicatesInToolbar {
    return NO;
}

- (void) _didChange {
    // Changing a toolbar item doesn't change the height of the toolbar - so
    // this call is not helping
    // [_toolbar itemSizeDidChange];

    [NS_EXTRA(NSToolbarItem, self)->_enclosingView setNeedsDisplay: YES];
}

- (void) setLabel: (NSString *) label {
    // does not forward to view
    label = [label copy];
    [NS_EXTRA(NSToolbarItem, self)->_label release];
    NS_EXTRA(NSToolbarItem, self)->_label = label;
    [self _didChange];
}

- (void) setPaletteLabel: (NSString *) label {
    // does not forward to view
    [NS_EXTRA(NSToolbarItem, self)->_paletteLabel release];
    NS_EXTRA(NSToolbarItem, self)->_paletteLabel = [label retain];
    [self _didChange];
}

- (void) setMenuFormRepresentation: (NSMenuItem *) menuItem {
    // does not forward to view
    menuItem = [menuItem retain];
    [NS_EXTRA(NSToolbarItem, self)->_menuFormRepresentation release];
    NS_EXTRA(NSToolbarItem, self)->_menuFormRepresentation = menuItem;
}

- (void) setView: (NSView *) view {
    view = [view retain];
    [NS_EXTRA(NSToolbarItem, self)->_view release];
    NS_EXTRA(NSToolbarItem, self)->_view = view;
    if (view != nil) {
        NS_EXTRA(NSToolbarItem, self)->_minSize = [NS_EXTRA(NSToolbarItem, self)->_view frame].size;
        NS_EXTRA(NSToolbarItem, self)->_maxSize = [NS_EXTRA(NSToolbarItem, self)->_view frame].size;
    }
    [NS_EXTRA(NSToolbarItem, self)->_enclosingView setSubview: NS_EXTRA(NSToolbarItem, self)->_view];
    [self _didChange];
}

- (void) setMinSize: (NSSize) size {
    NS_EXTRA(NSToolbarItem, self)->_minSize = size;
    [self _didChange];
}

- (void) setMaxSize: (NSSize) size {
    NS_EXTRA(NSToolbarItem, self)->_maxSize = size;
    [self _didChange];
}

- (void) setVisibilityPriority: (NSInteger) value {
    NS_EXTRA(NSToolbarItem, self)->_visibilityPriority = value;
    [self _didChange];
}

- (void) setAutovalidates: (BOOL) value {
    NS_EXTRA(NSToolbarItem, self)->_autovalidates = value;
}

/* The understanding is that NSToolbarItem only forwards
 * enabled/tag/action/target/image setters and getters to the publicly settable
 * view. The rest are managed internally.
 */

- (NSImage *) image {
    if ([NS_EXTRA(NSToolbarItem, self)->_view respondsToSelector: @selector(image)])
        return [(id) NS_EXTRA(NSToolbarItem, self)->_view image];

    return NS_EXTRA(NSToolbarItem, self)->_image;
}

- target {
    if ([NS_EXTRA(NSToolbarItem, self)->_view respondsToSelector: @selector(target)])
        return [(id) NS_EXTRA(NSToolbarItem, self)->_view target];

    return NS_EXTRA(NSToolbarItem, self)->_target;
}

- (SEL) action {
    if ([NS_EXTRA(NSToolbarItem, self)->_view respondsToSelector: @selector(action)])
        return [(id) NS_EXTRA(NSToolbarItem, self)->_view action];

    return NS_EXTRA(NSToolbarItem, self)->_action;
}

- (NSInteger) tag {
    if ([NS_EXTRA(NSToolbarItem, self)->_view respondsToSelector: @selector(tag)])
        return [(id) NS_EXTRA(NSToolbarItem, self)->_view tag];

    return NS_EXTRA(NSToolbarItem, self)->_tag;
}

- (BOOL) isEnabled {
    if ([NS_EXTRA(NSToolbarItem, self)->_view respondsToSelector: @selector(isEnabled)])
        return [(id) NS_EXTRA(NSToolbarItem, self)->_view isEnabled];

    return NS_EXTRA(NSToolbarItem, self)->_isEnabled;
}

- (NSString *) toolTip {
    return NS_EXTRA(NSToolbarItem, self)->_toolTip;
}

- (void) setImage: (NSImage *) image {
    image = [image retain];
    [NS_EXTRA(NSToolbarItem, self)->_image release];
    NS_EXTRA(NSToolbarItem, self)->_image = image;

    if ([NS_EXTRA(NSToolbarItem, self)->_view respondsToSelector: @selector(setImage:)]) {
        [(id) NS_EXTRA(NSToolbarItem, self)->_view setImage: image];
    }
    [self _didChange];
}

- (void) setTarget: target {
    NS_EXTRA(NSToolbarItem, self)->_target = target;

    if ([NS_EXTRA(NSToolbarItem, self)->_view respondsToSelector: @selector(setTarget:)])
        [(id) NS_EXTRA(NSToolbarItem, self)->_view setTarget: target];
}

- (void) setAction: (SEL) action {
    NS_EXTRA(NSToolbarItem, self)->_action = action;

    if ([NS_EXTRA(NSToolbarItem, self)->_view respondsToSelector: @selector(setAction:)])
        [(id) NS_EXTRA(NSToolbarItem, self)->_view setAction: action];
}

- (void) setTag: (NSInteger) tag {
    NS_EXTRA(NSToolbarItem, self)->_tag = tag;
    if ([NS_EXTRA(NSToolbarItem, self)->_view respondsToSelector: @selector(setTag:)])
        [(id) NS_EXTRA(NSToolbarItem, self)->_view setTag: tag];
}

- (void) setEnabled: (BOOL) enabled {
    NS_EXTRA(NSToolbarItem, self)->_isEnabled = enabled;
    if ([NS_EXTRA(NSToolbarItem, self)->_view respondsToSelector: @selector(setEnabled:)])
        [(id) NS_EXTRA(NSToolbarItem, self)->_view setEnabled: enabled];
    [self _didChange];
}

- (void) setToolTip: (NSString *) tip {
    tip = [tip copy];
    [NS_EXTRA(NSToolbarItem, self)->_toolTip release];
    NS_EXTRA(NSToolbarItem, self)->_toolTip = tip;
}

- (void) validate {
    BOOL enabled = NO;

    id target = [NSApp targetForAction: [self action]
                                    to: [self target]
                                  from: nil];

    if ([self action] == nil && [self view] != nil) {
        // Views can be arbitrarily complex - so let's not try to figure out
        // what they want. Apple docs say use a subclass to do more
        // sophisticated validation in this case.
        enabled = YES;
    } else if ((target == nil) || ![target respondsToSelector: [self action]]) {
        enabled = NO;
    } else if ([target respondsToSelector: @selector(validateToolbarItem:)]) {
        enabled = [target validateToolbarItem: self];
    } else if ([target respondsToSelector: @selector
                       (validateUserInterfaceItem:)]) { // New validation scheme
        enabled = [target validateUserInterfaceItem: self];
    } else {
        enabled = YES;
    }
    if (enabled != [self isEnabled]) {
        [self setEnabled: enabled];
    }
}

- (NSSize) _labelSize {
    switch ([NS_EXTRA(NSToolbarItem, self)->_toolbar displayMode]) {
    case NSToolbarDisplayModeIconOnly:
        return NSZeroSize;

    case NSToolbarDisplayModeLabelOnly:
    case NSToolbarDisplayModeIconAndLabel:
    case NSToolbarDisplayModeDefault:
    default:
        return [NS_EXTRA(NSToolbarItem, self)->_label
                sizeWithAttributes: [NS_EXTRA(NSToolbarItem, self)->_toolbar _labelAttributesForSizeMode:
                                                      [NS_EXTRA(NSToolbarItem, self)->_toolbar sizeMode]]];
    }
}

- (NSSize) sizeForSizeMode: (NSToolbarSizeMode) sizeMode
               displayMode: (NSToolbarDisplayMode) displayMode
                   minSize: (NSSize) minSize
                   maxSize: (NSSize) maxSize
{
    NSSize result;

    switch (sizeMode) {
    case NSToolbarSizeModeSmall:
        result = _NSToolbarSizeSmall;
        break;

    case NSToolbarSizeModeRegular:
    case NSToolbarSizeModeDefault:
    default:
        result = _NSToolbarSizeRegular;
        break;
    }

    if (minSize.width > 0 && result.width < minSize.width)
        result.width = minSize.width;
    if (minSize.height > 0 && result.height < minSize.height)
        result.height = minSize.height;
    if (maxSize.width > 0 && result.width > maxSize.width)
        result.width = maxSize.width;
    if (maxSize.height > 0 && result.height > maxSize.height)
        result.height = maxSize.height;

    NSSize labelSize = [NS_EXTRA(NSToolbarItem, self)->_label
            sizeWithAttributes: [NS_EXTRA(NSToolbarItem, self)->_toolbar
                                        _labelAttributesForSizeMode: sizeMode]];
    labelSize.width += 8; // label margins

    switch (displayMode) {
    case NSToolbarDisplayModeIconOnly:
        break;

    case NSToolbarDisplayModeLabelOnly:
        result.height = labelSize.height;
        if (result.width < labelSize.width)
            result.width = labelSize.width;
        break;

    case NSToolbarDisplayModeIconAndLabel:
    case NSToolbarDisplayModeDefault:
    default:
        result.height += labelSize.height;
        if (result.width < labelSize.width)
            result.width = labelSize.width;
        break;
    }

    return result;
}

- (NSSize) sizeForSizeMode: (NSToolbarSizeMode) sizeMode
               displayMode: (NSToolbarDisplayMode) displayMode
{
    return [self sizeForSizeMode: sizeMode
                     displayMode: displayMode
                         minSize: NS_EXTRA(NSToolbarItem, self)->_minSize
                         maxSize: NS_EXTRA(NSToolbarItem, self)->_maxSize];
}

- (NSSize) constrainedSize {
    return [self sizeForSizeMode: [NS_EXTRA(NSToolbarItem, self)->_toolbar sizeMode]
                     displayMode: [NS_EXTRA(NSToolbarItem, self)->_toolbar displayMode]
                         minSize: NS_EXTRA(NSToolbarItem, self)->_minSize
                         maxSize: NS_EXTRA(NSToolbarItem, self)->_maxSize];
}

- (void) _setItemViewFrame: (NSRect) rect {
    [NS_EXTRA(NSToolbarItem, self)->_enclosingView setFrame: rect];
}

- (CGFloat) _expandWidth: (CGFloat) width {
    if ([self view] != nil) {
        return MIN(width, NS_EXTRA(NSToolbarItem, self)->_maxSize.width);
    }

    if ([NS_EXTRA(NSToolbarItem, self)->_itemIdentifier isEqualToString: NSToolbarFlexibleSpaceItemIdentifier])
        return width;

    return [self constrainedSize].width;
}

- (void) drawInRect: (NSRect) bounds highlighted: (BOOL) highlighted {

    if ([NS_EXTRA(NSToolbarItem, self)->_itemIdentifier isEqualToString: NSToolbarSeparatorItemIdentifier]) {
        bounds.origin.x = floor(bounds.origin.x + (bounds.size.width / 2));
        bounds.size.width = 1;
        [[NSColor blackColor] set];
        NSDottedFrameRect(bounds);

        return;
    }
    CGFloat labelHeight = 0;
    CGFloat padding = 4;

    if ([NS_EXTRA(NSToolbarItem, self)->_toolbar displayMode] != NSToolbarDisplayModeIconOnly) {
        NSMutableDictionary *attributes = [NSMutableDictionary
                dictionaryWithDictionary: [NS_EXTRA(NSToolbarItem, self)->_toolbar _labelAttributes]];
        NSColor *color = [self isEnabled] ? [NSColor controlTextColor]
                                          : [NSColor disabledControlTextColor];

        [attributes setObject: color forKey: NSForegroundColorAttributeName];

        NSRect labelRect;
        labelRect.size = [NS_EXTRA(NSToolbarItem, self)->_label sizeWithAttributes: attributes];
        labelRect.origin.x =
                floor((bounds.size.width - labelRect.size.width) / 2);
        labelRect.origin.y = bounds.origin.y;

        if (!highlighted) {
            NSMutableDictionary *shadowAttributes =
                    [[attributes mutableCopy] autorelease];
            NSRect shadowRect = labelRect;

            [shadowAttributes setObject: [NSColor whiteColor]
                                 forKey: NSForegroundColorAttributeName];

            shadowRect.origin.y--;

            [NS_EXTRA(NSToolbarItem, self)->_label _clipAndDrawInRect: shadowRect
                        withAttributes: shadowAttributes];
        }

        [NS_EXTRA(NSToolbarItem, self)->_label _clipAndDrawInRect: labelRect withAttributes: attributes];
        labelHeight = labelRect.size.height;
        labelHeight += padding;
    }

    if ([NS_EXTRA(NSToolbarItem, self)->_toolbar displayMode] != NSToolbarDisplayModeLabelOnly) {
        if ([self view] == nil) {
            NSImage *image = [self image];
            NSRect imageRect;

            if ([NS_EXTRA(NSToolbarItem, self)->_toolbar sizeMode] == NSToolbarSizeModeSmall)
                imageRect.size = _NSToolbarIconSizeSmall;
            else
                imageRect.size = _NSToolbarIconSizeRegular;

            imageRect.origin.y = bounds.origin.y + labelHeight;
            imageRect.origin.x =
                    bounds.origin.x +
                    floor((bounds.size.width - imageRect.size.width) / 2);
            CGContextRef ctx = NULL;
            if ([self isEnabled] == NO) {
                ctx = [[NSGraphicsContext currentContext] graphicsPort];
                CGContextClipToRect(ctx, imageRect);
                CGContextBeginTransparencyLayer(ctx, NULL);
            }
            [image drawInRect: imageRect
                     fromRect: NSZeroRect
                    operation: NSCompositeSourceOver
                     fraction: highlighted ? 0.5 : 1.0];
            if ([self isEnabled] == NO) {
                [[NSColor colorWithCalibratedWhite: 0.0 alpha: 0.33] set];
                NSRectFillUsingOperation(imageRect, NSCompositeSourceAtop);
            }
            CGContextEndTransparencyLayer(ctx);
        }
    }
}

- (NSString *) description {
    return [NSString
            stringWithFormat: @"<%@[%p] %@ label: \"%@\" image: %@ view: %@>",
                              [self class], self, NS_EXTRA(NSToolbarItem, self)->_itemIdentifier, NS_EXTRA(NSToolbarItem, self)->_label,
                              [self image], NS_EXTRA(NSToolbarItem, self)->_view];
}

- initWithCoder: (NSCoder *) coder {
    if (![coder allowsKeyedCoding])
        NSUnimplementedMethod();
    else {
        NS_EXTRA(NSToolbarItem, self)->_itemIdentifier =
                [[coder decodeObjectForKey: @"NSToolbarItemIdentifier"] retain];

        NS_EXTRA(NSToolbarItem, self)->_enclosingView = [[NSToolbarItemView alloc] init];
        [NS_EXTRA(NSToolbarItem, self)->_enclosingView setToolbarItem: self];
        [self setView: [coder decodeObjectForKey: @"NSToolbarItemView"]];
        [self setTarget: [coder decodeObjectForKey: @"NSToolbarItemTarget"]];
        [self setAction: NSSelectorFromString([coder
                                 decodeObjectForKey: @"NSToolbarItemAction"])];

        [self setImage: [coder decodeObjectForKey: @"NSToolbarItemImage"]];
        [self setLabel: [coder decodeObjectForKey: @"NSToolbarItemLabel"]];
        [self setPaletteLabel: [coder decodeObjectForKey:
                                               @"NSToolbarItemPaletteLabel"]];

        NS_EXTRA(NSToolbarItem, self)->_maxSize = [coder decodeSizeForKey: @"NSToolbarItemMaxSize"];
        NS_EXTRA(NSToolbarItem, self)->_minSize = [coder decodeSizeForKey: @"NSToolbarItemMinSize"];
        [self setEnabled: [coder decodeBoolForKey: @"NSToolbarItemEnabled"]];
        [self setTag: [coder decodeIntForKey: @"NSToolbarItemTag"]];

        [self setAutovalidates: [coder decodeBoolForKey:
                                                @"NSToolbarItemAutovalidates"]];
        [self setToolTip: [coder decodeObjectForKey: @"NSToolbarItemToolTip"]];
        [self setVisibilityPriority:
                        [coder decodeIntForKey:
                                        @"NSToolbarItemVisibilityPriority"]];

        /*
         NSToolbarIsUserRemovable = 1;
         */
        [self _configureAsStandardItemIfNeeded];
    }

    return self;
}
@end

@interface NSToolbarSpaceItem : NSToolbarItem
@end

@implementation NSToolbarSpaceItem
@end

@interface NSToolbarFlexibleSpaceItem : NSToolbarItem
@end

@implementation NSToolbarFlexibleSpaceItem
@end

@interface NSToolbarSeparatorItem : NSToolbarItem
@end

@implementation NSToolbarSeparatorItem
@end
