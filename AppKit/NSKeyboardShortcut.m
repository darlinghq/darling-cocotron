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

#import <AppKit/NSKeyboardShortcut.h>
#import <AppKit/NSEvent.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>

// Expected values were observed on macOS 26.7.3; test: tests/appkit-keyboard-shortcut.m.

@implementation NSKeyboardShortcut

+ (instancetype)shortcutWithKeyEquivalent:(NSString *)keyEquivalent modifierMask:(NSUInteger)modifierMask
{
    return [[[self alloc] initWithKeyEquivalent:keyEquivalent modifierMask:modifierMask] autorelease];
}

- (instancetype)initWithKeyEquivalent:(NSString *)keyEquivalent modifierMask:(NSUInteger)modifierMask
{
    if (keyEquivalent == nil) {
        [self release];
        [NSException raise:NSInternalInconsistencyException format:@"Invalid parameter not satisfying: keyEquivalent != nil"];
    }
    self = [super init];
    if (self != nil) {
        _keyEquivalent = [keyEquivalent copy];
        _modifierMask = modifierMask;
    }
    return self;
}

- (void)dealloc
{
    [_keyEquivalent release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    return [self retain];
}

- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSKeyboardShortcut class]])
        return NO;
    NSKeyboardShortcut *shortcut = other;
    return shortcut->_modifierMask == _modifierMask && [shortcut->_keyEquivalent isEqualToString:_keyEquivalent];
}

- (NSUInteger)hash
{
    return [_keyEquivalent hash] ^ _modifierMask;
}

- (NSString *)keyEquivalent
{
    return _keyEquivalent;
}

- (NSUInteger)modifierMask
{
    return _modifierMask;
}

- (BOOL)isEmpty
{
    return [_keyEquivalent length] == 0;
}

- (BOOL)isFunctionKey
{
    if ([_keyEquivalent length] != 1)
        return NO;
    unichar c = [_keyEquivalent characterAtIndex:0];
    return c >= NSF1FunctionKey && c <= NSF35FunctionKey;
}

// The symbols and names shown for keys that are not shown as themselves. Unlike menus, DEL (0x7f)
// is shown as forward delete.
static NSString *specialKeyName(unichar c)
{
    switch (c) {
    case '\t':
    case 0x19: // back tab
        return @"⇥";
    case '\r':
    case '\n':
        return @"↩";
    case 0x03: // enter
        return @"⌤";
    case 0x1b:
        return @"⎋";
    case 0x08:
        return @"⌫";
    case 0x7f:
    case NSDeleteFunctionKey:
        return @"⌦";
    case ' ':
        return @"Space";
    case NSUpArrowFunctionKey:
        return @"↑";
    case NSDownArrowFunctionKey:
        return @"↓";
    case NSLeftArrowFunctionKey:
        return @"←";
    case NSRightArrowFunctionKey:
        return @"→";
    case NSHomeFunctionKey:
        return @"↖";
    case NSEndFunctionKey:
        return @"↘";
    case NSPageUpFunctionKey:
        return @"⇞";
    case NSPageDownFunctionKey:
        return @"⇟";
    case NSClearLineFunctionKey:
        return @"ClrLn";
    case NSHelpFunctionKey:
        return @"Help";
    }
    if (c >= NSF1FunctionKey && c <= NSF35FunctionKey)
        return [NSString stringWithFormat:@"F%d", (int) (c - NSF1FunctionKey + 1)];
    return nil;
}

// A single character is shown upper-cased; a longer key equivalent as it is.
- (NSString *)localizedKeyEquivalentDisplayName
{
    if ([_keyEquivalent length] != 1)
        return _keyEquivalent;
    NSString *name = specialKeyName([_keyEquivalent characterAtIndex:0]);
    return name != nil ? name : [_keyEquivalent uppercaseString];
}

// Control, Option, Shift and Command, in that order, then "fn". Shift is also shown for an
// upper-case key equivalent.
- (NSString *)localizedModifierMaskDisplayName
{
    BOOL shift = (_modifierMask & NSEventModifierFlagShift) != 0
        || ![_keyEquivalent isEqualToString:[_keyEquivalent lowercaseString]];
    NSMutableString *result = [NSMutableString string];
    if (_modifierMask & NSEventModifierFlagControl)
        [result appendString:@"⌃"];
    if (_modifierMask & NSEventModifierFlagOption)
        [result appendString:@"⌥"];
    if (shift)
        [result appendString:@"⇧"];
    if (_modifierMask & NSEventModifierFlagCommand)
        [result appendString:@"⌘"];
    if (_modifierMask & NSEventModifierFlagFunction)
        [result appendString:[result length] != 0 ? @"-fn-" : @"fn-"];
    return result;
}

- (NSString *)localizedDisplayName
{
    if ([self isEmpty])
        return @"";
    return [[self localizedModifierMaskDisplayName] stringByAppendingString:[self localizedKeyEquivalentDisplayName]];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p (%@)>", [self class], self, [self localizedDisplayName]];
}

@end
