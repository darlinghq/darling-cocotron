/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

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

#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSUserInterfaceValidation.h>
#import <Foundation/NSObject.h>
#import <AppKit/NSUserInterfaceItemIdentification.h>

@class NSMenu, NSImage, NSAttributedString, NSView, NSMenuItemBadge;

// Legacy ObjC ABI (i386): instance size must stay 0x40, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
NS_ASSUME_NONNULL_BEGIN

@interface NSMenuItem : NSObject <NSCopying, NSValidatedUserInterfaceItem, NSUserInterfaceItemIdentification> {
    NSMenu *_menu;
    NSString *_title;
    NS_LEGACY_IVAR_PAD(_NSMenuItemReserved1, 48)
    NS_EXTRA_IVARS_BEGIN(NSMenuItem)
        NSAttributedString *_atitle;
        id _target;
        SEL _action;
        NSString *_keyEquivalent;
        unsigned _keyEquivalentModifierMask;
        NSString *_mnemonic;
        unsigned _mnemonicLocation;
        NSMenu *_submenu;
        NSInteger _tag;
        NSInteger _indentationLevel;
        BOOL _enabled;
        BOOL _hidden;
        NSControlStateValue _state;
        id _representedObject;
        NSImage *_image;
        NSImage *_onStateImage;
        NSImage *_offStateImage;
        NSImage *_mixedStateImage;
        BOOL _alternate;
        BOOL _allowsKeyEquivalentWhenHidden;
        NSUserInterfaceItemIdentifier _identifier;
        NSView *_view;
        NSString *_toolTip;
        NSMenuItemBadge *_badge;
        BOOL _isSectionHeader;
        NSImage *_actionImage;
    NS_EXTRA_IVARS_END(NSMenuItem)
}

@property(nullable, copy) NSString *toolTip;

@property(getter=isAlternate) BOOL alternate;
@property BOOL allowsKeyEquivalentWhenHidden;
@property(nullable, retain) NSView *view;
@property(nullable, retain) NSMenuItemBadge *badge;

+ (NSMenuItem *) separatorItem;
// macOS 14: a non-selectable item that titles the items after it.
+ (null_unspecified NSMenuItem *) sectionHeaderWithTitle: (NSString *) title;

- (instancetype) initWithTitle: (NSString *) title
                        action: (nullable SEL) action
                 keyEquivalent: (NSString *) keyEquivalent;

- (nullable NSMenu *) menu;
// The item whose submenu holds this item, nil for an item of a top-level menu.
@property(nullable, readonly, nonatomic) NSMenuItem *parentItem;
@property(nonatomic, copy) NSString *title;
@property(nullable, nonatomic, copy) NSAttributedString *attributedTitle;
- (null_unspecified NSString *) mnemonic;
@property(nonatomic) unsigned mnemonicLocation;
@property(nullable, weak) id target;
@property(nonatomic) SEL action;
@property(nonatomic) NSInteger indentationLevel;
@property(nonatomic) NSInteger tag;
@property(nonatomic) NSControlStateValue state;
@property(nonatomic, copy) NSString *keyEquivalent;
@property(nonatomic) unsigned keyEquivalentModifierMask;
@property(nullable, nonatomic, retain) NSImage *image;
@property(null_resettable, nonatomic, retain) NSImage *onStateImage;
@property(nullable, nonatomic, retain) NSImage *offStateImage;
@property(null_resettable, nonatomic, retain) NSImage *mixedStateImage;

- (nullable id) representedObject;

@property(nonatomic, readonly) BOOL hasSubmenu;
@property(nullable, nonatomic, retain) NSMenu *submenu;

@property(nonatomic, getter=isSeparatorItem, readonly) BOOL separatorItem;
- (BOOL) isSectionHeader;
@property(nonatomic, getter=isEnabled) BOOL enabled;
@property(nonatomic, getter=isHidden) BOOL hidden;

- (void) setTitleWithMnemonic: (NSString *) mnemonic;
- (void) setRepresentedObject: (nullable id) object;

- (null_unspecified NSString *) _keyEquivalentDescription;

- (null_unspecified NSString *) _mainMenuTitle;

@end

NS_ASSUME_NONNULL_END
