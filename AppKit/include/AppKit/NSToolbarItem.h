/* Copyright (c) 2006-2009 Christopher J. W. Lloyd

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

#import <AppKit/AppKitExport.h>
#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSUserInterfaceValidation.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>

@class NSString, NSImage, NSView, NSMenuItem, NSToolbar, NSToolbarItemView;

typedef NSInteger NSToolbarItemVisibilityPriority NS_TYPED_EXTENSIBLE_ENUM;

static const NSToolbarItemVisibilityPriority NSToolbarItemVisibilityPriorityStandard = 0;
static const NSToolbarItemVisibilityPriority NSToolbarItemVisibilityPriorityLow = -1000;
static const NSToolbarItemVisibilityPriority NSToolbarItemVisibilityPriorityHigh = 1000;
static const NSToolbarItemVisibilityPriority NSToolbarItemVisibilityPriorityUser = 2000;

typedef NSString *NSToolbarItemIdentifier NS_EXTENSIBLE_STRING_ENUM;

APPKIT_EXPORT const NSToolbarItemIdentifier
        NSToolbarCustomizeToolbarItemIdentifier;
APPKIT_EXPORT const NSToolbarItemIdentifier
        NSToolbarFlexibleSpaceItemIdentifier;
APPKIT_EXPORT const NSToolbarItemIdentifier NSToolbarPrintItemIdentifier;
APPKIT_EXPORT const NSToolbarItemIdentifier NSToolbarSeparatorItemIdentifier;
APPKIT_EXPORT const NSToolbarItemIdentifier NSToolbarShowColorsItemIdentifier;
APPKIT_EXPORT const NSToolbarItemIdentifier NSToolbarShowFontsItemIdentifier;
APPKIT_EXPORT const NSToolbarItemIdentifier NSToolbarSpaceItemIdentifier;
// The system SDK declares these three without const.
APPKIT_EXPORT NSToolbarItemIdentifier NSToolbarToggleSidebarItemIdentifier;
APPKIT_EXPORT NSToolbarItemIdentifier
        NSToolbarSidebarTrackingSeparatorItemIdentifier;
APPKIT_EXPORT NSToolbarItemIdentifier NSToolbarWritingToolsItemIdentifier;

@interface NSToolbarItem : NSObject <NSCopying, NSValidatedUserInterfaceItem> {
    NS_LEGACY_IVAR_PAD(_NSToolbarItemReserved, 64)
    NS_EXTRA_IVARS_BEGIN(NSToolbarItem)
    NSToolbarItemIdentifier _itemIdentifier;
    NSToolbar *_toolbar;
    NSToolbarItemView *_enclosingView;
    NSString *_toolTip;
    NSInteger _tag;
    NSImage *_image;
    NSString *_label;
    NSString *_paletteLabel;
    id _target;
    SEL _action;
    NSMenuItem *_menuFormRepresentation;
    NSView *_view;
    NSSize _minSize;
    NSSize _maxSize;
    NSInteger _visibilityPriority;
    BOOL _autovalidates;
    BOOL _isEnabled;
    NS_EXTRA_IVARS_END(NSToolbarItem)
}

- (instancetype) initWithItemIdentifier: (NSToolbarItemIdentifier) identifier;

- (NSToolbarItemIdentifier) itemIdentifier;
- (NSToolbar *) toolbar;

@property(nonatomic, copy) NSString *label;
@property(nonatomic, copy) NSString *paletteLabel;
@property(nonatomic, retain) NSMenuItem *menuFormRepresentation;
@property(nonatomic, retain) NSView *view;
@property(nonatomic) NSSize minSize;
@property(nonatomic) NSSize maxSize;
@property(nonatomic) NSInteger visibilityPriority;
@property(nonatomic) BOOL autovalidates;
- (BOOL) allowsDuplicatesInToolbar;


@property(nonatomic, retain) NSImage *image;
- target;
@property(nonatomic) SEL action;
@property(nonatomic) NSInteger tag;
@property(nonatomic, getter=isEnabled) BOOL enabled;
@property(nonatomic, copy) NSString *toolTip;

- (void) setTarget: target;

- (void) validate;

@end

@interface NSObject (NSToolbarItem_validation)
- (BOOL) validateToolbarItem: (NSToolbarItem *) item;
@end
