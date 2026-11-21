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

// Original - Christopher Lloyd <cjwl@objc.net>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSObject+BindingSupport.h>
#import <Foundation/NSKeyedArchiver.h>
#import <AppKit/NSButtonCell.h>
#import <objc/runtime.h>

// Not declared in a public header.
APPKIT_EXPORT NSString *const NSAppleMenuName;
NSString *const NSAppleMenuName = @"NSAppleMenu";

@interface NSMenuItemCell : NSButtonCell
@end

@implementation NSMenuItem

NS_EXTRA_SYNTHESIZE_ASSIGN(NSMenuItem, alternate, _alternate, BOOL, isAlternate, setAlternate:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSMenuItem, allowsKeyEquivalentWhenHidden, _allowsKeyEquivalentWhenHidden, BOOL, allowsKeyEquivalentWhenHidden, setAllowsKeyEquivalentWhenHidden:)
NS_EXTRA_SYNTHESIZE_COPY(NSMenuItem, identifier, _identifier, NSUserInterfaceItemIdentifier, identifier, setIdentifier:)
NS_EXTRA_SYNTHESIZE_RETAIN(NSMenuItem, view, _view, NSView *, view, setView:)
NS_EXTRA_SYNTHESIZE_RETAIN(NSMenuItem, badge, _badge, NSMenuItemBadge *, badge, setBadge:)

+ (NSMenuItem *) separatorItem {
    NSMenuItem *item = [[self alloc] initWithTitle: @""
                                            action: NULL
                                     keyEquivalent: @""];
    // A separator is the item without a title (see -isSeparatorItem).
    [item->_title release];
    item->_title = nil;
    return [item autorelease];
}

+ (NSMenuItem *) sectionHeaderWithTitle: (NSString *) title {
    NSMenuItem *item = [[[self alloc] initWithTitle: title ?: @""
                                             action: NULL
                                      keyEquivalent: @""] autorelease];
    // A section header is an enabled item on macOS (not disabled), see MC26.8.
    NS_EXTRA(NSMenuItem, item)->_isSectionHeader = YES;
    return item;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeObject: _title forKey: @"NSTitle"];
    [coder encodeObject: NS_EXTRA(NSMenuItem, self)->_keyEquivalent forKey: @"NSKeyEquiv"];
    [coder encodeInt: NS_EXTRA(NSMenuItem, self)->_keyEquivalentModifierMask
              forKey: @"NSKeyEquivModMask"];
    [coder encodeObject: NS_EXTRA(NSMenuItem, self)->_submenu forKey: @"NSSubmenu"];
    [coder encodeInt: NS_EXTRA(NSMenuItem, self)->_tag forKey: @"NSTag"];
    [coder encodeObject: NSStringFromSelector(NS_EXTRA(NSMenuItem, self)->_action) forKey: @"NSAction"];
    [coder encodeObject: [self target] forKey: @"NSTarget"];
}

- initWithCoder: (NSCoder *) coder {
    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;
        NSString *title = [keyed decodeObjectForKey: @"NSTitle"];
        NSString *keyEquivalent = [keyed decodeObjectForKey: @"NSKeyEquiv"];

        SEL action = NULL;
        NSString *actionString = [coder decodeObjectForKey: @"NSAction"];
        if (actionString) {
            action = NSSelectorFromString(actionString);
        }
        [self initWithTitle: title action: action keyEquivalent: keyEquivalent];
        id target = [coder decodeObjectForKey: @"NSTarget"];
        [self setTarget: target];

        [self setKeyEquivalentModifierMask:
                        [keyed decodeIntForKey: @"NSKeyEquivModMask"]];
        [self setSubmenu: [keyed decodeObjectForKey: @"NSSubmenu"]];
        NS_EXTRA(NSMenuItem, self)->_tag = [keyed decodeIntForKey: @"NSTag"];
        NS_EXTRA(NSMenuItem, self)->_indentationLevel = [keyed decodeIntForKey: @"NSIndent"];
        if ([keyed containsValueForKey: @"NSState"])
            NS_EXTRA(NSMenuItem, self)->_state = [keyed decodeIntForKey: @"NSState"];
        NS_EXTRA(NSMenuItem, self)->_hidden = [keyed decodeBoolForKey: @"NSIsHidden"];
        NS_EXTRA(NSMenuItem, self)->_image = [[coder decodeObjectForKey: @"NSImage"] retain];
        if ([keyed decodeBoolForKey: @"NSIsSeparator"]) {
            [_title release];
            _title = nil;
        }
    } else {
        NSInteger version = [coder versionForClassName: @"NSMenuItem"];

        if (version == NSNotFound) {
            version = [coder versionForClassName: @"NSMenuCell"];
        }

        _menu = [coder decodeObject];

        int flags;

        // The fifth value (all bits set in Mac archives) is of unknown meaning.
        unsigned int unused;

        [coder decodeValuesOfObjCTypes:"i@@IIi@@@@:i@", &flags, &_title, &NS_EXTRA(NSMenuItem, self)->_keyEquivalent, &NS_EXTRA(NSMenuItem, self)->_keyEquivalentModifierMask, &unused, &NS_EXTRA(NSMenuItem, self)->_state, &NS_EXTRA(NSMenuItem, self)->_image, &NS_EXTRA(NSMenuItem, self)->_onStateImage, &NS_EXTRA(NSMenuItem, self)->_mixedStateImage, &NS_EXTRA(NSMenuItem, self)->_offStateImage, &NS_EXTRA(NSMenuItem, self)->_action, &NS_EXTRA(NSMenuItem, self)->_tag, &NS_EXTRA(NSMenuItem, self)->_representedObject];

        // The flag word, in Mac archives: bit 31 disabled, bit 30 separator (the title is empty
        // then), bit 29 hidden, bit 28 alternate and bits 24-27 the indentation level.
        NS_EXTRA(NSMenuItem, self)->_enabled = !(flags & 0x80000000);
        NS_EXTRA(NSMenuItem, self)->_hidden = (flags & 0x20000000) != 0;
        NS_EXTRA(NSMenuItem, self)->_alternate = (flags & 0x10000000) != 0;
        NS_EXTRA(NSMenuItem, self)->_indentationLevel = (flags >> 24) & 0xf;

        // If we have an empty title, it is for a separator, discard it, see isSeparatorItem
        if (_title && [_title length] == 0) {
            [_title release];
            _title = nil;
        }

        if (version <= 320) {
            if (NS_EXTRA(NSMenuItem, self)->_action != @selector(submenuAction:)) {
                objc_storeWeak(&NS_EXTRA(NSMenuItem, self)->_target, [coder decodeObject]);
            } else {
                NS_EXTRA(NSMenuItem, self)->_submenu = [[coder decodeObject] retain];
            }
        } else {
            objc_storeWeak(&NS_EXTRA(NSMenuItem, self)->_target, [coder decodeObject]);
            NS_EXTRA(NSMenuItem, self)->_submenu = [[coder decodeObject] retain];
        }
        [NS_EXTRA(NSMenuItem, self)->_submenu setSupermenu: _menu];

        // Set other default values from [initWithTitle: action: keyEquivalent:]
        NS_EXTRA(NSMenuItem, self)->_mnemonic = @"";
    }

    return self;
}

- initWithTitle: (NSString *) title
               action: (SEL) action
        keyEquivalent: (NSString *) keyEquivalent
{
    _title = [title copy];
    objc_storeWeak(&NS_EXTRA(NSMenuItem, self)->_target, nil);
    NS_EXTRA(NSMenuItem, self)->_action = action;
    NS_EXTRA(NSMenuItem, self)->_keyEquivalent = [keyEquivalent copy];
    NS_EXTRA(NSMenuItem, self)->_keyEquivalentModifierMask = NSCommandKeyMask;
    NS_EXTRA(NSMenuItem, self)->_mnemonic = @"";
    NS_EXTRA(NSMenuItem, self)->_mnemonicLocation = 0;
    NS_EXTRA(NSMenuItem, self)->_submenu = nil;
    NS_EXTRA(NSMenuItem, self)->_tag = -1;
    NS_EXTRA(NSMenuItem, self)->_indentationLevel = 0;
    NS_EXTRA(NSMenuItem, self)->_enabled = YES;
    NS_EXTRA(NSMenuItem, self)->_hidden = NO;
    // The documented defaults: a check mark for the on state, a dash for the mixed state and nothing for off.
    NS_EXTRA(NSMenuItem, self)->_onStateImage = [[NSImage imageNamed: @"NSMenuCheckmark"] retain];
    NS_EXTRA(NSMenuItem, self)->_mixedStateImage = [[NSImage imageNamed: @"NSMenuMixedState"] retain];

    return self;
}

- (void) dealloc {
    objc_storeWeak(&NS_EXTRA(NSMenuItem, self)->_target, nil);
    [_title release];
    [NS_EXTRA(NSMenuItem, self)->_atitle release];
    [NS_EXTRA(NSMenuItem, self)->_keyEquivalent release];
    [NS_EXTRA(NSMenuItem, self)->_submenu release];
    [NS_EXTRA(NSMenuItem, self)->_image release];
    [NS_EXTRA(NSMenuItem, self)->_onStateImage release];
    [NS_EXTRA(NSMenuItem, self)->_mixedStateImage release];
    [NS_EXTRA(NSMenuItem, self)->_offStateImage release];
    [NS_EXTRA(NSMenuItem, self)->_representedObject release];
    [NS_EXTRA(NSMenuItem, self)->_identifier release];
    [NS_EXTRA(NSMenuItem, self)->_view release];
    [NS_EXTRA(NSMenuItem, self)->_toolTip release];
    [NS_EXTRA(NSMenuItem, self)->_badge release];
    [NS_EXTRA(NSMenuItem, self)->_actionImage release];
    NS_EXTRA_FREE(NSMenuItem, self);
    [super dealloc];
}

- copyWithZone: (NSZone *) zone {
    NSMenuItem *copy = NSCopyObject(self, 0, zone);
    NS_EXTRA_COPY(NSMenuItem, copy, self);
    // The copied weak slot is not registered with the runtime yet.
    NS_EXTRA(NSMenuItem, copy)->_target = nil;
    objc_storeWeak(&NS_EXTRA(NSMenuItem, copy)->_target, [self target]);

    copy->_title = [_title copyWithZone: zone];
    NS_EXTRA(NSMenuItem, copy)->_atitle = [NS_EXTRA(NSMenuItem, self)->_atitle copyWithZone: zone];
    NS_EXTRA(NSMenuItem, copy)->_submenu = [NS_EXTRA(NSMenuItem, self)->_submenu copyWithZone: zone];
    NS_EXTRA(NSMenuItem, copy)->_keyEquivalent = [NS_EXTRA(NSMenuItem, self)->_keyEquivalent copyWithZone: zone];
    ;
    NS_EXTRA(NSMenuItem, copy)->_image = [NS_EXTRA(NSMenuItem, self)->_image retain];
    NS_EXTRA(NSMenuItem, copy)->_onStateImage = [NS_EXTRA(NSMenuItem, self)->_onStateImage retain];
    NS_EXTRA(NSMenuItem, copy)->_mixedStateImage = [NS_EXTRA(NSMenuItem, self)->_mixedStateImage retain];
    NS_EXTRA(NSMenuItem, copy)->_offStateImage = [NS_EXTRA(NSMenuItem, self)->_offStateImage retain];
    NS_EXTRA(NSMenuItem, copy)->_representedObject = [NS_EXTRA(NSMenuItem, self)->_representedObject retain];
    NS_EXTRA(NSMenuItem, copy)->_identifier = [NS_EXTRA(NSMenuItem, self)->_identifier copyWithZone: zone];
    NS_EXTRA(NSMenuItem, copy)->_view = [NS_EXTRA(NSMenuItem, self)->_view retain];
    NS_EXTRA(NSMenuItem, copy)->_toolTip = [NS_EXTRA(NSMenuItem, self)->_toolTip copyWithZone: zone];
    NS_EXTRA(NSMenuItem, copy)->_badge = [NS_EXTRA(NSMenuItem, self)->_badge retain];
    NS_EXTRA(NSMenuItem, copy)->_actionImage = [NS_EXTRA(NSMenuItem, self)->_actionImage retain];
    return copy;
}

// Stored only: Darling's menus don't show tooltips.
- (NSString *) toolTip {
    return NS_EXTRA(NSMenuItem, self)->_toolTip;
}

- (void) setToolTip: (NSString *) toolTip {
    if (toolTip != NS_EXTRA(NSMenuItem, self)->_toolTip) {
        [NS_EXTRA(NSMenuItem, self)->_toolTip release];
        NS_EXTRA(NSMenuItem, self)->_toolTip = [toolTip copy];
        [_menu itemChanged: self];
    }
}

// A menu item's value binding drives its state (checkmark), not an objectValue.
- (id) _replacementKeyPathForBinding: (id) binding {
    if ([binding isEqual: @"value"]) {
        return @"state";
    }
    return [super _replacementKeyPathForBinding: binding];
}

// A bound value that is nil (an unset default with no transformer) unchecks the item.
- (void) setNilValueForKey: (NSString *) key {
    if ([key isEqualToString: @"state"])
        [self setState: NSOffState];
    else
        [super setNilValueForKey: key];
}

- (NSMenu *) menu {
    return _menu;
}

- (NSMenuItem *) parentItem {
    NSMenu *supermenu = [_menu supermenu];
    if (supermenu == nil)
        return nil;
    for (NSMenuItem *item in [supermenu itemArray])
        if ([item submenu] == _menu)
            return item;
    return nil;
}

- (void) _setMenu: (NSMenu *) menu {
    _menu = menu;
    NS_EXTRA(NSMenuItem, self)->_submenu.supermenu = menu;
}

- (NSString *) title {
    return _title;
}

- (NSAttributedString *) attributedTitle {
    return NS_EXTRA(NSMenuItem, self)->_atitle;
}

- (NSString *) mnemonic {
    return NS_EXTRA(NSMenuItem, self)->_mnemonic;
}

- (unsigned) mnemonicLocation {
    return NS_EXTRA(NSMenuItem, self)->_mnemonicLocation;
}

// The target is weak: it reads nil once the object is deallocated.
- (id) target {
    return objc_loadWeak(&NS_EXTRA(NSMenuItem, self)->_target);
}

- (SEL) action {
    return NS_EXTRA(NSMenuItem, self)->_action;
}

- (NSInteger) indentationLevel {
    return NS_EXTRA(NSMenuItem, self)->_indentationLevel;
}

- (NSInteger) tag {
    return NS_EXTRA(NSMenuItem, self)->_tag;
}

- (NSControlStateValue) state {
    return NS_EXTRA(NSMenuItem, self)->_state;
}

- (NSString *) keyEquivalent {
    return NS_EXTRA(NSMenuItem, self)->_keyEquivalent;
}

- (unsigned) keyEquivalentModifierMask {
    return NS_EXTRA(NSMenuItem, self)->_keyEquivalentModifierMask;
}

- (NSImage *) image {
    return NS_EXTRA(NSMenuItem, self)->_image;
}

- (NSImage *) onStateImage {
    return NS_EXTRA(NSMenuItem, self)->_onStateImage;
}

- (NSImage *) offStateImage {
    return NS_EXTRA(NSMenuItem, self)->_offStateImage;
}

- (NSImage *) mixedStateImage {
    return NS_EXTRA(NSMenuItem, self)->_mixedStateImage;
}

- (id) representedObject {
    return NS_EXTRA(NSMenuItem, self)->_representedObject;
}

- (BOOL) hasSubmenu {
    return (NS_EXTRA(NSMenuItem, self)->_submenu != nil) ? YES : NO;
}

- (NSMenu *) submenu {
    return NS_EXTRA(NSMenuItem, self)->_submenu;
}

- (BOOL) isSectionHeader {
    return NS_EXTRA(NSMenuItem, self)->_isSectionHeader;
}

- (BOOL) isSeparatorItem {
    return _title == nil;
}

- (BOOL) isEnabled {
    return NS_EXTRA(NSMenuItem, self)->_enabled;
}

- (BOOL) isHidden {
    return NS_EXTRA(NSMenuItem, self)->_hidden;
}

- (void) setTitle: (NSString *) title {
    title = [title copy];
    [_title release];
    _title = title;
    [_menu itemChanged: self];
}

- (void) setAttributedTitle: (NSAttributedString *) title {
    title = [title copy];
    [NS_EXTRA(NSMenuItem, self)->_atitle release];
    NS_EXTRA(NSMenuItem, self)->_atitle = title;
    [self setTitle: [title string]];
}

- (void) setTitleWithMnemonic: (NSString *) mnemonic {
    mnemonic = [mnemonic copy];
    [NS_EXTRA(NSMenuItem, self)->_mnemonic release];
    NS_EXTRA(NSMenuItem, self)->_mnemonic = mnemonic;
}

- (void) setMnemonicLocation: (unsigned) location {
    NS_EXTRA(NSMenuItem, self)->_mnemonicLocation = location;
}

- (void) setTarget: (id) target {
    objc_storeWeak(&NS_EXTRA(NSMenuItem, self)->_target, target);
}

- (void) setAction: (SEL) action {
    NS_EXTRA(NSMenuItem, self)->_action = action;
}

- (void) setIndentationLevel: (NSInteger) indentationLevel {
    NS_EXTRA(NSMenuItem, self)->_indentationLevel = indentationLevel;
    [_menu itemChanged: self];
}

- (void) setTag: (NSInteger) tag {
    NS_EXTRA(NSMenuItem, self)->_tag = tag;
}

- (void) setState: (NSControlStateValue) state {
    NS_EXTRA(NSMenuItem, self)->_state = state;
    [_menu itemChanged: self];
}

- (void) setKeyEquivalent: (NSString *) keyEquivalent {
    keyEquivalent = [keyEquivalent copy];
    [NS_EXTRA(NSMenuItem, self)->_keyEquivalent release];
    NS_EXTRA(NSMenuItem, self)->_keyEquivalent = keyEquivalent;
    [_menu itemChanged: self];
}

- (void) setKeyEquivalentModifierMask: (unsigned) mask {
    NS_EXTRA(NSMenuItem, self)->_keyEquivalentModifierMask = mask;
    [_menu itemChanged: self];
}

- (void) setImage: (NSImage *) image {
    image = [image retain];
    [NS_EXTRA(NSMenuItem, self)->_image release];
    NS_EXTRA(NSMenuItem, self)->_image = image;
    [_menu itemChanged: self];
}

// QUIRK: replacing a state image posts NSMenuDidChangeItemNotification only when it is the image of the item's
// current state; the other two state images change silently. Not documented. Evidence: black-box observation on
// macOS 26.7.3 (tier 2).
// Test: tests/appkit-menu-item-change-notifications.m
- (void) _replaceStateImage: (NSImage **) slot with: (NSImage *) image forState: (NSControlStateValue) state {
    if (*slot == image)
        return;
    [*slot release];
    *slot = [image retain];
    if ([self state] == state)
        [_menu itemChanged: self];
}

- (void) setOnStateImage: (NSImage *) image {
    [self _replaceStateImage: &NS_EXTRA(NSMenuItem, self)->_onStateImage with: image forState: NSControlStateValueOn];
}

- (void) setOffStateImage: (NSImage *) image {
    [self _replaceStateImage: &NS_EXTRA(NSMenuItem, self)->_offStateImage with: image forState: NSControlStateValueOff];
}

- (void) setMixedStateImage: (NSImage *) image {
    [self _replaceStateImage: &NS_EXTRA(NSMenuItem, self)->_mixedStateImage with: image forState: NSControlStateValueMixed];
}

- (void) setRepresentedObject: (id) object {
    [NS_EXTRA(NSMenuItem, self)->_representedObject release];
    NS_EXTRA(NSMenuItem, self)->_representedObject = [object retain];
}

- (void) setSubmenu: (NSMenu *) submenu {
    submenu = [submenu retain];
    [NS_EXTRA(NSMenuItem, self)->_submenu release];
    NS_EXTRA(NSMenuItem, self)->_submenu = submenu;
    [submenu setSupermenu: _menu];
    [_menu itemChanged: self];
}

- (void) setEnabled: (BOOL) flag {
    NS_EXTRA(NSMenuItem, self)->_enabled = flag;
    [_menu itemChanged: self];
}

- (void) setHidden: (BOOL) flag {
    NS_EXTRA(NSMenuItem, self)->_hidden = flag;
    [_menu itemChanged: self];
}

+ (NSDictionary *) keyNames {
    static NSDictionary *shared = nil;

    if (shared == nil) {
        NSBundle *bundle = [NSBundle bundleForClass: self];
        NSString *path = [bundle pathForResource: @"NSMenu" ofType: @"plist"];

        shared = [[NSDictionary alloc] initWithContentsOfFile: path];
    }

    return shared;
}

// How a key equivalent's key is shown. The symbols are the ones macOS uses next
// to the modifier symbols; the names are for the Ctrl+Key form. Characters that
// have neither show as themselves, upper-cased; function keys show as F1 to F35.
static NSString *keyEquivalentKeyName(NSString *key, BOOL symbols) {
    static NSDictionary *glyphs = nil, *names = nil;

    if (glyphs == nil) {
        glyphs = [[NSDictionary alloc] initWithObjectsAndKeys:
                @"\u21E5", @"\t", @"\u21A9", @"\r", @"\u21A9", @"\n",
                @"\u21A9", @"\x03", @"\u238B", @"\x1b", @"\u232B", @"\x08",
                @"\u232B", @"\x7f", @"\u2326", @"\uF728", @"\u2191", @"\uF700",
                @"\u2193", @"\uF701", @"\u2190", @"\uF702", @"\u2192", @"\uF703",
                @"\u2196", @"\uF729", @"\u2198", @"\uF72B", @"\u21DE", @"\uF72C",
                @"\u21DF", @"\uF72D", @"Space", @" ", nil];
        names = [[NSDictionary alloc] initWithObjectsAndKeys:
                @"Tab", @"\t", @"Return", @"\r", @"Return", @"\n",
                @"Enter", @"\x03", @"Esc", @"\x1b", @"Backspace", @"\x08",
                @"Backspace", @"\x7f", @"Delete", @"\uF728", @"Home", @"\uF729",
                @"End", @"\uF72B", @"PgUp", @"\uF72C", @"PgDn", @"\uF72D",
                @"Space", @" ", nil];
    }

    NSString *name = symbols ? [glyphs objectForKey: key] : [names objectForKey: key];

    if (name == nil && [key length] == 1) {
        unichar c = [key characterAtIndex: 0];

        // F1 to F35
        if (c >= NSF1FunctionKey && c <= NSF35FunctionKey)
            name = [NSString stringWithFormat: @"F%d", (int) (c - NSF1FunctionKey + 1)];
    }
    if (name == nil)
        name = [key uppercaseString];
    return name;
}

// The shortcut as the user types it on this system. The modifiers shown are the
// ones the input side delivers for those keys: Command is the Super key and is
// shown as the Command symbol, unless the display delivers Control as Command
// for the key (-controlStandsInForCommand:keyEquivalent:), when the shortcut is
// written with names and Command shows as Ctrl. Option is Alt, Shift and
// Control are themselves. The symbols are in the macOS order.
- (NSString *) _keyEquivalentDescription {
    NSString *key = NS_EXTRA(NSMenuItem, self)->_keyEquivalent;

    if ([key length] == 0)
        return @"";

    NSUInteger mask = NS_EXTRA(NSMenuItem, self)->_keyEquivalentModifierMask;
    BOOL command = (mask & NSCommandKeyMask) != 0;
    BOOL control = (mask & NSControlKeyMask) != 0;
    BOOL alt = (mask & NSAlternateKeyMask) != 0;
    // an upper-case key equivalent implies Shift
    BOOL shift = (mask & NSShiftKeyMask) != 0 || ![key isEqualToString: [key lowercaseString]];
    BOOL controlIsCommand = NO;

    // Control and Command together are two keys, so Control is not Command's stand-in.
    if (command && !control && [key length] == 1) {
        NSEventModifierFlags chord = (mask & ~NSCommandKeyMask) | NSControlKeyMask;
        unichar lower = [[key lowercaseString] characterAtIndex: 0];

        controlIsCommand = [[NSDisplay currentDisplay] controlStandsInForCommand: chord
                                                                    keyEquivalent: lower];
    }

    NSMutableString *result = [NSMutableString string];

    if (controlIsCommand) {
        [result appendString: @"Ctrl+"];
        if (alt)
            [result appendString: @"Alt+"];
        if (shift)
            [result appendString: @"Shift+"];
        [result appendString: keyEquivalentKeyName(key, NO)];
        return result;
    }

    if (control)
        [result appendString: @"\u2303"];
    if (alt)
        [result appendString: @"\u2325"];
    if (shift)
        [result appendString: @"\u21E7"];
    if (command)
        [result appendString: @"\u2318"];
    [result appendString: keyEquivalentKeyName(key, YES)];
    return result;
}

- (NSString *) description {
    return [NSString stringWithFormat:
                             @"<%@[0x%x]: title: %@ action: %@ hasSubmenu: %@>",
                             [self class], self, [self title],
                             NSStringFromSelector(NS_EXTRA(NSMenuItem, self)->_action),
                             ([self hasSubmenu] ? @"YES" : @"NO")];
}

// This is used by NSMainMenuView To Display The Correct Title
- (NSString *) _mainMenuTitle {
    // On MacOS, main menu items display the title of their sub-menu rather than their own title
    if ([[self menu] supermenu] == nil) {
        // Check if sub-menu exists
        if ([self hasSubmenu]) {
            // An empty sub-menu title would leave nothing to show, so the
            // item's own title is used then.
            NSString *submenuTitle = [[self submenu] title];
            if ([submenuTitle length] > 0) {
                return submenuTitle;
            }
        }
    }
    return _title;
}

// Private AppKit API (macOS 26): an image describing the item's action, which
// apps set from a system symbol image. Stored and returned; Cocotron's menus
// don't draw it.
- (NSImage *) _actionImage {
    return NS_EXTRA(NSMenuItem, self)->_actionImage;
}

- (void) _setActionImage: (NSImage *) image {
    image = [image retain];
    [NS_EXTRA(NSMenuItem, self)->_actionImage release];
    NS_EXTRA(NSMenuItem, self)->_actionImage = image;
}

@end
