/* Copyright (C) 2026 Lubos Dolezel

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

// Shared by menu items and buttons: whether a key event matches a key equivalent and its
// modifier mask.
#import <AppKit/NSEvent.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSString.h>

// QUIRK: Command, Option and Control must match exactly, but Shift is not compared for an
// equivalent that is not an uppercase letter: Command+A and Command+Shift+A both perform an
// item "a" with the Command mask, and an item whose mask includes Shift also matches events
// without Shift. An uppercase equivalent implies Shift and needs it on the event. The key
// code plays no part; only the characters are compared (with the letter case ignored while
// Shift is held, as backends report either spelling). Not documented. Evidence: black-box
// observation on macOS 26.7.3 (tier 2), MC26.4 (probes v274-menu-keyeq.m and
// v274-keybindings.m). Test: appkit-menu-key-equivalents.m
// (test_quirk_extra_shift_does_not_block_lowercase_equivalent)
static inline BOOL NSKeyEquivalentMatchesEvent(NSString *key, NSUInteger itemMask, NSEvent *event) {
    const NSUInteger keyModifiers = NSCommandKeyMask | NSAlternateKeyMask | NSShiftKeyMask | NSControlKeyMask;
    NSUInteger eventMask = [event modifierFlags] & keyModifiers;
    NSUInteger wanted = itemMask & keyModifiers;
    NSString *characters = [event charactersIgnoringModifiers];

    if ([key length] == 0)
        return NO;

    BOOL uppercase = ![key isEqualToString: [key lowercaseString]];
    if (uppercase)
        wanted |= NSShiftKeyMask;
    else {
        eventMask &= ~(NSUInteger)NSShiftKeyMask;
        wanted &= ~(NSUInteger)NSShiftKeyMask;
    }
    if (eventMask != wanted)
        return NO;

    if ([key isEqualToString: characters])
        return YES;
    if ([event modifierFlags] & NSShiftKeyMask)
        return [[key lowercaseString] isEqualToString: [characters lowercaseString]];
    return NO;
}

// Whether an event that matched an equivalent agrees with it on Shift. The equivalent asks for Shift when it is an
// uppercase letter or the mask has Shift; the event agrees when it has Shift exactly then. The exception is a single
// symbol (not a letter or a digit) that the event carries as typed, like "{": Shift is part of typing it, so an event
// with Shift agrees. A symbol that needs no Shift on the layout, delivered with Shift held, looks the same and
// counts as agreeing. A menu prefers the item that agrees over one that matches through the Shift quirk above, so
// Command+Shift+Z performs the "Z" item (Redo) rather than the "z" item (Undo) ahead of it, and Command+Z the other way.
static inline BOOL NSKeyEquivalentAgreesOnShift(NSString *key, NSUInteger itemMask, NSEvent *event) {
    BOOL uppercase = [key length] > 0 && ![key isEqualToString: [key lowercaseString]];
    BOOL wantsShift = uppercase || (itemMask & NSShiftKeyMask) != 0;
    BOOL hasShift = ([event modifierFlags] & NSShiftKeyMask) != 0;

    if (!hasShift)
        return !wantsShift;
    if (wantsShift)
        return YES;
    return [key length] == 1 &&
           ![[NSCharacterSet alphanumericCharacterSet] characterIsMember: [key characterAtIndex: 0]] &&
           [key isEqualToString: [event charactersIgnoringModifiers]];
}
