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
#import <AppKit/NSToolbarItem.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSObject.h>

@class NSString, NSMutableArray, NSArray, NSDictionary, NSNotification,
        NSMutableDictionary, NSWindow, NSView, NSToolbarItem, NSToolbarView,
        NSToolbarCustomizationPalette;

typedef NS_ENUM(NSUInteger, NSToolbarSizeMode) {
    NSToolbarSizeModeDefault,
    NSToolbarSizeModeRegular,
    NSToolbarSizeModeSmall
};

typedef NS_ENUM(NSUInteger, NSToolbarDisplayMode) {
    NSToolbarDisplayModeDefault,
    NSToolbarDisplayModeIconAndLabel,
    NSToolbarDisplayModeIconOnly,
    NSToolbarDisplayModeLabelOnly
};

APPKIT_EXPORT const NSNotificationName NSToolbarWillAddItemNotification;
APPKIT_EXPORT const NSNotificationName NSToolbarDidRemoveItemNotification;
APPKIT_EXPORT NSString *const NSToolbarItemKey;

typedef NSString *NSToolbarIdentifier NS_SWIFT_BRIDGED_TYPEDEF;

@protocol NSToolbarDelegate;

@interface NSToolbar : NSObject {
    NSToolbarIdentifier _identifier;
    id<NSToolbarDelegate> _delegate;
    NSMutableArray *_items;
    NSString *_selectedItemIdentifier;
    NSMutableArray *_allowedItems;
    NSMutableArray *_defaultItems;
    NSMutableArray *_selectableItems;
    NSMutableDictionary *_identifiedItems;
    NSWindow *_window;
    NSToolbarView *_view;
    NSToolbarCustomizationPalette *_palette;
    NSToolbarSizeMode _sizeMode;
    NSToolbarDisplayMode _displayMode;
    BOOL _showsBaselineSeparator;
    BOOL _autosavesConfiguration;
    BOOL _visible;
    BOOL _allowsUserCustomization;
    BOOL _isLoadingConfiguration;
    BOOL _loadDefaultItems;
}

- (instancetype) initWithIdentifier: (NSToolbarIdentifier) identifier;

- (NSToolbarIdentifier) identifier;
@property(nonatomic, assign) id<NSToolbarDelegate> delegate;
@property(nonatomic, getter=isVisible) BOOL visible;
@property(nonatomic) NSToolbarSizeMode sizeMode;
@property(nonatomic) NSToolbarDisplayMode displayMode;
@property(nonatomic) BOOL showsBaselineSeparator;
- (NSArray *) items;
- (NSArray *) visibleItems;
- (NSDictionary *) configurationDictionary;
@property(nonatomic) BOOL autosavesConfiguration;
@property(nonatomic) BOOL allowsUserCustomization;
@property(nonatomic, copy) NSString *selectedItemIdentifier;

- (void) setConfigurationFromDictionary: (NSDictionary *) dictionary;

- (void) insertItemWithItemIdentifier: (NSToolbarItemIdentifier) identifier
                              atIndex: (NSInteger) index;
- (void) removeItemAtIndex: (NSInteger) index;

- (void) validateVisibleItems;

- (BOOL) customizationPaletteIsRunning;
- (void) runCustomizationPalette: sender;

@end

@interface NSToolbar (NSToolbarCustomization)

- (Class) toolbarItemClass;

@end

@protocol NSToolbarDelegate <NSObject>

@optional
- (NSToolbarItem *) toolbar: (NSToolbar *) toolbar
            itemForItemIdentifier: (NSToolbarItemIdentifier) identifier
        willBeInsertedIntoToolbar: (BOOL) flag;

- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *) toolbar;
- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *) toolbar;
- (NSArray *) toolbarSelectableItemIdentifiers: (NSToolbar *) toolbar;

- (void) toolbarWillAddItem: (NSNotification *) note;
- (void) toolbarDidRemoveItem: (NSNotification *) note;

@end
