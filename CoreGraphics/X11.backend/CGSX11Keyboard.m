/* CoreGraphics X11 backend: the keyboard.

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

#import "CGSX11Keyboard.h"
#import "CGSConnectionX11.h"
#import "CGSModifierKeys.h"
#import "X11KeyEvent.h"
#import <CoreGraphics/CGEvent.h>
#import <CoreGraphics/CGEventSource.h>
#import <CoreGraphics/CGSKeySymToUnicodePrivate.h>
#import <CoreGraphics/CGSKeyboardLayout.h>
#import "../DarlingUnicodeKeyLayout.h"
#import <CoreGraphics/CGSNativeConnection.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>
#ifdef CGS_HAVE_KEY_COMPOSE
#import "../CGSKeyCompose.h"
#endif
#include <X11/XKBlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>
#include <stdlib.h>
#include <string.h>

// The CGEventFlags the X server's modifier state stands for. Mod1 is Alt (Option), Mod4 the logo key
// (Command) and Mod5 the third-level shift (AltGr), which is reported as the Fn flag.
static uint64_t flagsForState(unsigned int state) {
    uint64_t flags = 0;
    if (state & ShiftMask)
        flags |= kCGEventFlagMaskShift;
    if (state & ControlMask)
        flags |= kCGEventFlagMaskControl;
    if (state & LockMask)
        flags |= kCGEventFlagMaskAlphaShift;
    if (state & Mod4Mask)
        flags |= kCGEventFlagMaskCommand;
    if (state & Mod1Mask)
        flags |= kCGEventFlagMaskAlternate;
    if (state & Mod5Mask)
        flags |= kCGEventFlagMaskSecondaryFn;
    return flags;
}

// A modifier key is reported as a flags changed event and never as a key down or up, so each modifier
// keysym is mapped to the virtual key code the event carries and the X mask bit it drives. `toggle`
// marks the lock keys, whose press flips the bit and whose release changes nothing. A key code of -1
// means the keysym is not a modifier at all.
typedef struct {
    int keyCode;
    unsigned int xMask;
    BOOL toggle;
} ModifierKey;

static ModifierKey modifierKeyForKeysym(KeySym keySym) {
    ModifierKey notAModifier = {-1, 0, NO};
    switch (keySym) {
    case XK_Shift_L: return (ModifierKey){kVK_Shift, ShiftMask, NO};
    case XK_Shift_R: return (ModifierKey){kVK_RightShift, ShiftMask, NO};
    case XK_Control_L: return (ModifierKey){kVK_Control, ControlMask, NO};
    case XK_Control_R: return (ModifierKey){kVK_RightControl, ControlMask, NO};
    case XK_Alt_L: return (ModifierKey){kVK_Option, Mod1Mask, NO};
    case XK_Alt_R: return (ModifierKey){kVK_RightOption, Mod1Mask, NO};
    case XK_Super_L: return (ModifierKey){kVK_Command, Mod4Mask, NO};
    case XK_Super_R: return (ModifierKey){0x36, Mod4Mask, NO};
    case XK_ISO_Level3_Shift: return (ModifierKey){kVK_Function, Mod5Mask, NO};
    case XK_Caps_Lock: return (ModifierKey){kVK_CapsLock, LockMask, YES};
    case XK_Num_Lock: return (ModifierKey){kVK_ANSI_KeypadClear, Mod2Mask, NO};
    default: return notAModifier;
    }
}

// The server fills `state` with the modifier and button state as it was *before* the event, so the key's
// own contribution has to be applied to reach the state after it.
static unsigned int stateAfterKeyEvent(const ModifierKey *key, unsigned int state, BOOL pressed) {
    if (pressed)
        return key->toggle ? (state ^ key->xMask) : (state | key->xMask);
    if (key->toggle)
        return state;
    return state & ~key->xMask;
}

@implementation CGSX11Keyboard

- (instancetype) initWithConnection: (CGSConnectionX11 *) connection {
    self = [super init];
    if (self == nil)
        return nil;
    _connection = connection;
    _display = connection->_display;
    memset(_heldKeyCode, 0xFF, sizeof(_heldKeyCode)); // -1: no key held
    // The keyboard is hardware: the events it posts change the state the hardware state functions report.
    _source = (void *) CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    return self;
}

- (void) dealloc {
#ifdef CGS_HAVE_KEY_COMPOSE
    CGSKeyComposeDestroy(_compose);
#endif
    [_composingKeys release];
    if (_source != NULL)
        CFRelease((CFTypeRef) _source);
    [super dealloc];
}

#pragma mark - Modifier state

+ (uint64_t) flagsForState: (unsigned int) state {
    return flagsForState(state);
}

- (uint64_t) modifierFlags {
    uint64_t flags = _flags;
    for (unsigned int code = 0; code < 256; code++) {
        if (_heldKeyCode[code] >= 0)
            flags |= CGSModifierDeviceMask(_heldKeyCode[code]);
    }
    return flags;
}

- (void) holdModifier: (const ModifierKey *) key atKeycode: (unsigned int) code {
    if (code >= 256)
        return;
    _heldKeyCode[code] = (short) key->keyCode;
    // The X masks are the eight modifier bits.
    _heldMask[code] = (unsigned char) key->xMask;
}

- (void) releaseModifierAtKeycode: (unsigned int) code {
    if (code >= 256)
        return;
    _heldKeyCode[code] = -1;
    _heldMask[code] = 0;
}

// The X masks still driven by held modifier keys other than `keycode`. A key's release only drops a mask
// when no other key drives it: releasing one Shift key leaves Shift down because the other one is held.
- (unsigned int) maskOfHeldModifierKeysExcept: (unsigned int) keycode {
    unsigned int mask = 0;
    for (unsigned int code = 0; code < 256; code++) {
        if (code != keycode && _heldKeyCode[code] >= 0)
            mask |= _heldMask[code];
    }
    return mask;
}

#pragma mark - Posting

// Posts a key or flags changed event for the X window `window`. The characters are those of a key event.
- (void) postEventOfType: (CGEventType) type
                 keyCode: (unsigned short) keyCode
                   flags: (uint64_t) flags
              characters: (NSString *) characters
    unmodifiedCharacters: (NSString *) unmodified
                  repeat: (BOOL) repeat
                  window: (Window) window
                    root: (CGPoint) root {
    CGEventRef event = CGEventCreateKeyboardEvent((CGEventSourceRef) _source, keyCode, type != kCGEventKeyUp);
    if (event == NULL)
        return;
    if (type == kCGEventFlagsChanged)
        CGEventSetType(event, type);
    CGEventSetFlags(event, (CGEventFlags) flags);
    CGEventSetLocation(event, [_connection _cgPointFromRoot: root]);

    if (type != kCGEventFlagsChanged) {
        NSUInteger length = [characters length];
        if (length > 0) {
            UniChar stackBuffer[32];
            UniChar *buffer = length <= 32 ? stackBuffer : malloc(length * sizeof(UniChar));
            if (buffer != NULL) {
                [characters getCharacters: buffer range: NSMakeRange(0, length)];
                CGEventKeyboardSetUnicodeString(event, length, buffer);
                if (buffer != stackBuffer)
                    free(buffer);
            }
        }
        CGEventSetIntegerValueField(event, kCGKeyboardEventAutorepeat, repeat);

        // At most four units: no key has more characters without its modifiers.
        NSUInteger unmodifiedLength = MIN([unmodified length], (NSUInteger) 4);
        int64_t packed = 0;
        for (NSUInteger i = 0; i < unmodifiedLength; i++)
            packed |= (int64_t) [unmodified characterAtIndex: i] << (16 * i);
        CGEventSetIntegerValueField(event, kCGSKeyboardEventUnmodifiedUnicode, packed);
        CGEventSetIntegerValueField(event, kCGSKeyboardEventUnmodifiedLength, unmodifiedLength);
        CGEventSetIntegerValueField(event, kCGSKeyboardEventUnmodifiedKeyCode, keyCode);
    }
    CGEventSetIntegerValueField(event, kCGSEventNativeWindow, (int64_t) window);

    _CGSEventStreamPost(event);
    CFRelease(event);
}

// A flags changed event for a modifier key (`keyCode`), or 0xFFFF when no single key is responsible
// (the flags changed while another client had the keyboard).
- (void) postFlagsChanged: (unsigned short) keyCode window: (Window) window root: (CGPoint) root {
    [self postEventOfType: kCGEventFlagsChanged
                  keyCode: keyCode
                    flags: [self modifierFlags]
               characters: nil
     unmodifiedCharacters: nil
                   repeat: NO
                   window: window
                     root: root];
}

#pragma mark - Pointer events and focus

- (void) resyncWithState: (unsigned int) state window: (Window) window root: (CGPoint) root {
    uint64_t flags = flagsForState(state);
    if (flags == _flags)
        return;

    // A held modifier key whose mask the server no longer has set went up unseen.
    for (unsigned int code = 0; code < 256; code++) {
        if (_heldKeyCode[code] >= 0 && !(state & _heldMask[code]))
            [self releaseModifierAtKeycode: code];
    }
    _flags = flags;
    [self postFlagsChanged: 0xFFFF window: window root: root];
}

- (void) focusGainedInWindow: (Window) window {
    [self resetComposition];
    char keys[32];
    Window rootWindow, child;
    int rootX, rootY, winX, winY;
    unsigned int state;

    XQueryKeymap(_display, keys);
    for (unsigned int code = 0; code < 256; code++) {
        BOOL down = (keys[code / 8] & (1 << (code % 8))) != 0;
        ModifierKey key = modifierKeyForKeysym(XKeycodeToKeysym(_display, code, 0));
        if (down && key.keyCode >= 0 && !key.toggle)
            [self holdModifier: &key atKeycode: code];
        else
            [self releaseModifierAtKeycode: code];
    }

    if (XQueryPointer(_display, DefaultRootWindow(_display), &rootWindow, &child, &rootX, &rootY, &winX, &winY, &state))
        [self resyncWithState: state window: window root: CGPointMake(rootX, rootY)];
}

#pragma mark - Keys

// The characters of a key press: the text the input method of the window composed (the observer is the
// framework that owns the input contexts), or the plain lookup in the keymap.
- (NSString *) textForKeyEvent: (XKeyEvent *) event keySym: (KeySym *) keySym {
    if (event->type == KeyPress) {
        id<CGSNativeConnectionObserver> observer = [CGSConnection nativeObserver];
        if ([observer respondsToSelector: @selector(nativeConnectionComposedTextForKeyEvent:keySym:)]) {
            NSString *composed = [observer nativeConnectionComposedTextForKeyEvent: event keySym: keySym];
            if (composed != nil)
                return composed;
        }
    }
    // Xutf8LookupString() may not be used with KeyRelease, and needs an input context.
    char buffer[32];
    int length = XLookupString(event, buffer, sizeof(buffer) - 1, keySym, NULL);
    if (length <= 0)
        return @"";
    // XLookupString() returns Latin-1.
    return [[[NSString alloc] initWithBytes: buffer length: length encoding: NSISOLatin1StringEncoding] autorelease];
}

#pragma mark - Dead keys and Compose sequences

// Whether CoreGraphics composes dead keys and Compose sequences: when no input method of the application does
// (Xlib's built-in one, which the application gets without XMODIFIERS, composes by itself but drops what it was
// typed when no table entry continues a sequence) and libxkbcommon is there to read the Compose table.
- (BOOL) composesKeys {
#ifdef CGS_HAVE_KEY_COMPOSE
    if (!_composeLoaded) {
        _composeLoaded = YES;
        id<CGSNativeConnectionObserver> observer = [CGSConnection nativeObserver];
        BOOL inputMethod = [observer respondsToSelector: @selector(nativeConnectionInputMethodComposes)] &&
                           [observer nativeConnectionInputMethodComposes];
        if (!inputMethod) {
            _compose = CGSKeyComposeCreate();
            _composingKeys = [NSMutableSet new];
        }
    }
    return _compose != NULL;
#else
    return NO;
#endif
}

- (void) resetComposition {
#ifdef CGS_HAVE_KEY_COMPOSE
    if (_compose != NULL) {
        CGSKeyComposeReset(_compose);
        [_composingKeys removeAllObjects];
    }
#endif
}

// Feeds a key press or release to the sequence in progress. YES when the key makes no event: it started or
// continued a sequence, or it is the release (or a repeat) of such a key. A key that ends a sequence returns
// the text of the sequence in `text`; any other key is the keymap's.
- (BOOL) composeKeyEvent: (XKeyEvent *) event text: (NSString **) text {
#ifdef CGS_HAVE_KEY_COMPOSE
    NSNumber *key = @(event->keycode);
    if ([_composingKeys containsObject: key]) {
        // A key of the sequence that stays down repeats: the repeat is not a step of the sequence.
        if (event->type == KeyRelease)
            [_composingKeys removeObject: key];
        return YES;
    }
    if (event->type != KeyPress)
        return NO;

    KeySym symbol = NoSymbol;
    char ignored[32];
    XLookupString(event, ignored, sizeof(ignored), &symbol, NULL);
    // A shortcut is not text: a key with Control or Command is no part of a sequence and ends one.
    BOOL shortcut = (event->state & (ControlMask | Mod4Mask)) != 0;
    if (CGSKeyComposeFeed(_compose, (uint32_t) symbol, shortcut, text) != CGSKeyComposeConsumed)
        return NO;
    [_composingKeys addObject: key];
    return YES;
#else
    return NO;
#endif
}

- (void) keyEvent: (XEvent *) ev {
    // Xlib wants every event through XFilterEvent(), key events included, and an input method only sees
    // a key that goes through it: one that is switched by a modifier alone (an input method's Shift
    // trigger key) never hears of a modifier that is handled first. Xlib's own compose handling is not wanted
    // when CoreGraphics composes (see -composesKeys): it would take the keys of a sequence away.
    BOOL composing = [self composesKeys];
    BOOL filtered = !composing && XFilterEvent(ev, None) != False;
    BOOL pressed = ev->type == KeyPress;
    unsigned int keycode = ev->xkey.keycode;
    CGPoint root = CGPointMake(ev->xkey.x_root, ev->xkey.y_root);
    Window window = ev->xkey.window;

    // A modifier is not text. One the input method took is left alone (X11KeyEvent.h): the unfiltered
    // copy it forwards back updates the flags and is posted as a flags changed event, and one it keeps is
    // corrected by the modifier state of the next key or pointer event, with the key code that means
    // that no single key is responsible.
    ModifierKey modifier = modifierKeyForKeysym(XKeycodeToKeysym(_display, keycode, 0));
    X11KeyEventPlan plan = X11KeyEventPlanFor(modifier.keyCode >= 0, filtered, ev->xany.send_event);
    if (modifier.keyCode >= 0) {
        if (!plan.trackModifier)
            return;
        // A lock key changes the state on its press only.
        if (modifier.toggle && !pressed)
            return;
        unsigned int after = stateAfterKeyEvent(&modifier, ev->xkey.state, pressed);
        if (!modifier.toggle) {
            if (pressed)
                [self holdModifier: &modifier atKeycode: keycode];
            else
                [self releaseModifierAtKeycode: keycode];
            // The other key of a pair keeps the mask down.
            if (!pressed)
                after |= [self maskOfHeldModifierKeysExcept: keycode] & modifier.xMask;
        }
        _flags = flagsForState(after);
        [self postFlagsChanged: (unsigned short) modifier.keyCode window: window root: root];
        return; // Modifiers are neither text nor repeatable keys.
    }
    if (plan.resyncFromState)
        [self resyncWithState: ev->xkey.state window: window root: root];
    if (!plan.lookUpText)
        return; // The input method took the key; what it commits comes back as another event.

    NSString *composed = nil;
    if (composing && [self composeKeyEvent: &ev->xkey text: &composed])
        return; // a step of a sequence; what it makes comes with the key that completes it

    KeySym keySym = NoSymbol;
    NSString *text = composed != nil ? composed : [self textForKeyEvent: &ev->xkey keySym: &keySym];

    // Shortcut characters ignore modifiers other than Shift.
    KeySym shortcutKeySym = X11KeySymIgnoringModifiers(&ev->xkey);

    // Arrow, function and editing keys produce no text; they are reported as the NS*FunctionKey
    // private-use characters, as macOS does.
    if ([text length] == 0) {
        uint32_t functionKey = CGSKeySymToUnicode(keySym != NoSymbol ? keySym : shortcutKeySym);
        if (functionKey >= 0xF700 && functionKey <= 0xF8FF) {
            unichar functionKeyChar = (unichar) functionKey;
            text = [NSString stringWithCharacters: &functionKeyChar length: 1];
        }
    }

    // A key the keymap lookup has no text for, but a Mac layout gives a control code (ISO_Left_Tab, the keysym of
    // Shift+Tab, gives U+0009): that code is its characters
    if ([text length] == 0) {
        uint32_t control = DarlingKeysymControlCode(keySym != NoSymbol ? (uint32_t) keySym : (uint32_t) shortcutKeySym);
        if (control != 0) {
            unichar controlChar = (unichar) control;
            text = [NSString stringWithCharacters: &controlChar length: 1];
        }
    }

    uint16_t shortcutCode = (uint16_t) CGSKeySymToUnicode(shortcutKeySym);
    if (shortcutCode == 0)
        shortcutCode = (uint16_t) DarlingKeysymControlCode((uint32_t) shortcutKeySym);
    NSString *unmodified = shortcutCode != 0 ? [NSString stringWithCharacters: &shortcutCode length: 1] : @"";

    // Applications that use the constants of HIToolbox/Events.h (kVK_ANSI_A) get the key code of the key.
    unsigned short keyCode = keycode < 256 ? x11ToCarbon[keycode] : 0;

    // With detectable auto-repeat a held key reports its presses without releases in between. A key whose
    // keysym is unknown (a composed text forwarded by the input method) is never a repeat.
    BOOL repeat = NO;
    if (pressed) {
        repeat = keySym != NoSymbol && _lastKeySym == keySym;
        _lastKeySym = keySym;
    } else {
        _lastKeySym = NoSymbol;
    }

    // The event's own state, which the server filled in, has the flags of the keyboard as a whole.
    uint64_t flags = flagsForState(ev->xkey.state);
    for (unsigned int code = 0; code < 256; code++) {
        if (_heldKeyCode[code] >= 0)
            flags |= CGSModifierDeviceMask(_heldKeyCode[code]);
    }
    [self postEventOfType: pressed ? kCGEventKeyDown : kCGEventKeyUp
                  keyCode: keyCode
                    flags: flags
               characters: text
     unmodifiedCharacters: unmodified
                   repeat: repeat
                   window: window
                     root: root];
}

@end
