/* Copyright (C) 2026 Lubos Dolezel

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

// Shared by menu items and buttons: whether a key event matches a key equivalent and its
// modifier mask.
#import <AppKit/NSEvent.h>
#import <Foundation/NSString.h>

// QUIRK: the key equivalent is compared as a whole string with the event's
// charactersIgnoringModifiers, and the Shift bit plays no part, in the mask of the item or in the flags of
// the event: Shift counts only through the character it produces ("Z" for Shift+z, "{" for Shift+[). Command,
// Option and Control must match exactly. So an item "z" with Command (or with Command and Shift in its mask)
// takes Command+z and not Shift+Command+z, whose characters ignoring modifiers are "Z", and an item "Z" with
// Command takes Shift+Command+z and not Command+z; a key code and the event's characters play no part. With
// Caps Lock in the flags the case of a letter in the characters follows the Shift flag instead. Not documented.
// Evidence: black-box observation on macOS 26.7.3 (events built by hand and events AppKit made from key
// codes, through -[NSMenu performKeyEquivalent:], the main menu and -[NSApplication sendEvent:]) and on 10.14.4
// (x86_64 and i386, the events built by hand) (tier 2), probes p766.m and p766b.m of batch 12a in
// mac-probes/cristim.
// Test: appkit-menu-key-equivalent-shifted-characters
// (test_quirk_key_equivalent_compares_characters_ignoring_modifiers)
static inline BOOL NSKeyEquivalentMatchesEvent(NSString *key, NSUInteger itemMask, NSEvent *event) {
    const NSUInteger exactModifiers = NSCommandKeyMask | NSAlternateKeyMask | NSControlKeyMask;
    NSUInteger flags = [event modifierFlags];

    if ([key length] == 0 || (flags & exactModifiers) != (itemMask & exactModifiers))
        return NO;

    NSString *characters = [event charactersIgnoringModifiers];

    if (flags & NSAlphaShiftKeyMask) {
        NSString *cased = (flags & NSShiftKeyMask) ? [characters uppercaseString] : [characters lowercaseString];

        // a letter whose case change changes the length (the German sharp s) is left as it is
        if ([cased length] == [characters length])
            characters = cased;
    }

    return [key isEqualToString: characters];
}
