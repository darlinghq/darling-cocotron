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
#import <AppKit/NSEvent.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <Foundation/NSKeyedArchiver.h>
#import <AppKit/NSButtonCell.h>

@interface NSMenuItemCell : NSButtonCell
@end

@implementation NSMenuItem

@synthesize alternate = _alternate;
@synthesize allowsKeyEquivalentWhenHidden = _allowsKeyEquivalentWhenHidden;
@synthesize identifier = _identifier;

+ (NSMenuItem *) separatorItem {
    return [[[self alloc] initWithTitle: nil action: NULL
                          keyEquivalent: nil] autorelease];
}

- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeObject: _title forKey: @"NSTitle"];
    [coder encodeObject: _keyEquivalent forKey: @"NSKeyEquiv"];
    [coder encodeInt: _keyEquivalentModifierMask
              forKey: @"NSKeyEquivModMask"];
    [coder encodeObject: _submenu forKey: @"NSSubmenu"];
    [coder encodeInt: _tag forKey: @"NSTag"];
    [coder encodeObject: NSStringFromSelector(_action) forKey: @"NSAction"];
    [coder encodeObject: _target forKey: @"NSTarget"];
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
        _tag = [keyed decodeIntForKey: @"NSTag"];
        _hidden = [keyed decodeBoolForKey: @"NSIsHidden"];
        _image = [[coder decodeObjectForKey: @"NSImage"] retain];
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

        // TODO: Figure this out, encodeWithCoder is writing this as 0xffffffffffffffff
        unsigned int unused;

        [coder decodeValuesOfObjCTypes:"i@@IIi@@@@:i@", &flags, &_title, &_keyEquivalent, &_keyEquivalentModifierMask, &unused, &_state, &_image, &_onStateImage, &_mixedStateImage, &_offStateImage, &_action, &_tag, &_representedObject];


        // If we have an empty title, it is for a separator, discard it, see isSeparatorItem
        if (_title && [_title length] == 0) {
            [_title release];
            _title = nil;
        }

        if (version <= 320) {
            if (_action != @selector(submenuAction:)) {
                _target = [coder decodeObject];
            } else {
                _submenu = [[coder decodeObject] retain];
            }
        } else {
            _target = [coder decodeObject];
            _submenu = [[coder decodeObject] retain];
        }

        // Set other default values from [initWithTitle: action: keyEquivalent:]
        _mnemonic = @"";
        _enabled = YES;
    }

    return self;
}

- initWithTitle: (NSString *) title
               action: (SEL) action
        keyEquivalent: (NSString *) keyEquivalent
{
    _title = [title copy];
    _target = nil;
    _action = action;
    _keyEquivalent = [keyEquivalent copy];
    _keyEquivalentModifierMask = 0;
    _mnemonic = @"";
    _mnemonicLocation = 0;
    _submenu = nil;
    _tag = -1;
    _indentationLevel = 0;
    _enabled = YES;
    _hidden = NO;

    return self;
}

- (void) dealloc {
    [_title release];
    [_atitle release];
    [_keyEquivalent release];
    [_submenu release];
    [_image release];
    [_onStateImage release];
    [_mixedStateImage release];
    [_offStateImage release];
    [_representedObject release];
    [_identifier release];
    [super dealloc];
}

- copyWithZone: (NSZone *) zone {
    NSMenuItem *copy = NSCopyObject(self, 0, zone);

    copy->_title = [_title copyWithZone: zone];
    copy->_atitle = [_atitle copyWithZone: zone];
    copy->_submenu = [_submenu copyWithZone: zone];
    copy->_keyEquivalent = [_keyEquivalent copyWithZone: zone];
    ;
    copy->_image = [_image retain];
    copy->_onStateImage = [_onStateImage retain];
    copy->_mixedStateImage = [_mixedStateImage retain];
    copy->_offStateImage = [_offStateImage retain];
    copy->_representedObject = [_representedObject retain];
    return copy;
}

- (NSMenu *) menu {
    return _menu;
}

- (void) _setMenu: (NSMenu *) menu {
    _menu = menu;
    _submenu.supermenu = menu;
}

- (NSString *) title {
    return _title;
}

- (NSAttributedString *) attributedTitle {
    return _atitle;
}

- (NSString *) mnemonic {
    return _mnemonic;
}

- (unsigned) mnemonicLocation {
    return _mnemonicLocation;
}

- (id) target {
    return _target;
}

- (SEL) action {
    return _action;
}

- (NSInteger) indentationLevel {
    return _indentationLevel;
}

- (NSInteger) tag {
    return _tag;
}

- (NSControlStateValue) state {
    return _state;
}

- (NSString *) keyEquivalent {
    return _keyEquivalent;
}

- (unsigned) keyEquivalentModifierMask {
    return _keyEquivalentModifierMask;
}

- (NSImage *) image {
    return _image;
}

- (NSImage *) onStateImage {
    return _onStateImage;
}

- (NSImage *) offStateImage {
    return _offStateImage;
}

- (NSImage *) mixedStateImage {
    return _mixedStateImage;
}

- (id) representedObject {
    return _representedObject;
}

- (BOOL) hasSubmenu {
    return (_submenu != nil) ? YES : NO;
}

- (NSMenu *) submenu {
    return _submenu;
}

- (BOOL) isSeparatorItem {
    return _title == nil;
}

- (BOOL) isEnabled {
    return _enabled;
}

- (BOOL) isHidden {
    return _hidden;
}

- (void) setTitle: (NSString *) title {
    title = [title copy];
    [_title release];
    _title = title;
}

- (void) setAttributedTitle: (NSAttributedString *) title {
    title = [title copy];
    [_atitle release];
    _atitle = title;
    [self setTitle: [title string]];
}

- (void) setTitleWithMnemonic: (NSString *) mnemonic {
    mnemonic = [mnemonic copy];
    [_mnemonic release];
    _mnemonic = mnemonic;
}

- (void) setMnemonicLocation: (unsigned) location {
    _mnemonicLocation = location;
}

- (void) setTarget: (id) target {
    _target = target;
}

- (void) setAction: (SEL) action {
    _action = action;
}

- (void) setIndentationLevel: (NSInteger) indentationLevel {
    _indentationLevel = indentationLevel;
}

- (void) setTag: (NSInteger) tag {
    _tag = tag;
}

- (void) setState: (NSControlStateValue) state {
    _state = state;
}

- (void) setKeyEquivalent: (NSString *) keyEquivalent {
    keyEquivalent = [keyEquivalent copy];
    [_keyEquivalent release];
    _keyEquivalent = keyEquivalent;
}

- (void) setKeyEquivalentModifierMask: (unsigned) mask {
    _keyEquivalentModifierMask = mask;
}

- (void) setImage: (NSImage *) image {
    image = [image retain];
    [_image release];
    _image = image;
}

- (void) setOnStateImage: (NSImage *) image {
    [_onStateImage release];
    _onStateImage = [image retain];
}

- (void) setOffStateImage: (NSImage *) image {
    [_offStateImage release];
    _offStateImage = [image retain];
}

- (void) setMixedStateImage: (NSImage *) image {
    [_mixedStateImage release];
    _mixedStateImage = [image retain];
}

- (void) setRepresentedObject: (id) object {
    [_representedObject release];
    _representedObject = [object retain];
}

- (void) setSubmenu: (NSMenu *) submenu {
    submenu = [submenu retain];
    [_submenu release];
    _submenu = submenu;
    [submenu setSupermenu: _menu];
}

- (void) setEnabled: (BOOL) flag {
    _enabled = flag;
}

- (void) setHidden: (BOOL) flag {
    _hidden = flag;
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

- (NSString *) _scanModifierMapFor: (NSString *) key longForm: (BOOL) longForm {
    NSDictionary *modmap = [[NSUserDefaults standardUserDefaults]
            dictionaryForKey: @"NSModifierFlagMapping"];

    if ([[modmap objectForKey: @"LeftControl"] isEqual: key])
        return longForm ? @"LCtrl+" : @"Ctrl+";
    else if ([[modmap objectForKey: @"LeftAlt"] isEqual: key])
        return longForm ? @"LAlt+" : @"Alt+";
    else if ([[modmap objectForKey: @"RightAlt"] isEqual: key])
        return longForm ? @"RAlt+" : @"Alt+";
    else if ([[modmap objectForKey: @"RightControl"] isEqual: key])
        return longForm ? @"RCtrl+" : @"Ctrl+";
    else {
        if ([key isEqualToString: @"Alt"]) {
            if ([[modmap objectForKey: @"LeftAlt"] length] == 0)
                return longForm ? @"LAlt+" : @"Alt+";

            if ([[modmap objectForKey: @"RightAlt"] length] == 0)
                return longForm ? @"RAlt+" : @"Alt+";
        }
        return nil;
    }
}

- (NSString *) _keyEquivalentDescription {
    NSString *result = @"";
    NSString *uppercaseKey = [_keyEquivalent uppercaseString];
    NSString *lowercaseKey = [_keyEquivalent lowercaseString];
    NSDictionary *keyNames = [[self class] keyNames];
    NSString *keyName;
    NSString *command = nil, *alt = nil;
    if (![_keyEquivalent
                isEqualToString: lowercaseKey]) // [key
                                                // isEqualToString:uppercaseKey]
                                                // doesn't work for numbers
        result = @"Shift+";

    if (_keyEquivalentModifierMask & NSCommandKeyMask)
        if ((command = [self _scanModifierMapFor: @"Command"
                                        longForm: NO]) == nil)
            return @"";

    if (_keyEquivalentModifierMask & NSAlternateKeyMask)
        if ((alt = [self _scanModifierMapFor: @"Alt" longForm: NO]) == nil)
            return @"";

    if ([command isEqualToString: alt]) {
        command = [self _scanModifierMapFor: @"Command" longForm: YES];
        alt = [self _scanModifierMapFor: @"Alt" longForm: YES];
    }

    if (command != nil)
        result = [result stringByAppendingString: command];
    if (alt != nil)
        result = [result stringByAppendingString: alt];

    if ((keyName = [keyNames objectForKey: _keyEquivalent]) == nil)
        keyName = uppercaseKey;

    result = [result stringByAppendingString: keyName];

    return result;
}

- (NSString *) description {
    return [NSString stringWithFormat:
                             @"<%@[0x%x]: title: %@ action: %@ hasSubmenu: %@>",
                             [self class], self, [self title],
                             NSStringFromSelector(_action),
                             ([self hasSubmenu] ? @"YES" : @"NO")];
}

// This is used by NSMainMenuView To Display The Correct Title
- (NSString *) _mainMenuTitle {
    // On MacOS, main menu items display the title of their sub-menu rather than their own title
    if ([[self menu] supermenu] == nil) {
        // Check if sub-menu exists
        if ([self hasSubmenu]) {
            // Check if sub-menu title exists
            NSString *submenuTitle = [[self submenu] title];
            if (submenuTitle != nil) {
                return submenuTitle;
            }
        }
    }
    return _title;
}

@end
