/* CoreGraphics Wayland backend: the keyboard.

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

#import "CGSWaylandKeyboard.h"
#import "CGSConnectionWayland.h"
#import "CGSWaylandKeymap.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import "../X11.backend/CarbonKeys.h"
#import <CoreGraphics/CGEvent.h>
#import <CoreGraphics/CGEventSource.h>
#import <CoreGraphics/CGSNativeConnection.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>

// The device-dependent bits of the modifier flags (IOKit's IOLLEvent.h) that say which key of a pair is
// down. The flags that apply to the keyboard as a whole come only from the compositor's modifier mask.
static uint64_t modifierDeviceMask(int code) {
    switch (code) {
    case kVK_Control: return 0x0001;
    case kVK_Shift: return 0x0002;
    case kVK_RightShift: return 0x0004;
    case kVK_Command: return 0x0008;
    case 0x36: return 0x0010; // The right Command key.
    case kVK_Option: return 0x0020;
    case kVK_RightOption: return 0x0040;
    case kVK_RightControl: return 0x2000;
    default: return 0;
    }
}

static void repeatTimerCallback(CFRunLoopTimerRef timer, void *info) {
    @autoreleasepool {
        [(CGSWaylandKeyboard *) info repeatKey];
    }
}

@interface CGSWaylandKeyboard ()
- (void) repeatKey;
@end

@implementation CGSWaylandKeyboard

@synthesize focusSurface = _focus;

- (instancetype) initWithConnection: (CGSConnectionWayland *) connection keymap: (CGSWaylandKeymap *) keymap {
    self = [super init];
    if (self == nil)
        return nil;
    _connection = connection;
    _keymap = keymap;
    // Seat default until the compositor sends repeat_info (version 4).
    _repeatRate = 25;
    _repeatDelay = 600;
    _heldKeyIdentities = [NSMutableDictionary new];
    // The keyboard is hardware: the events it posts change the state the hardware state functions report.
    _source = (void *) CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    return self;
}

- (void) dealloc {
    [self stop];
    [_heldKeyIdentities release];
    if (_source != NULL)
        CFRelease((CFTypeRef) _source);
    [super dealloc];
}

- (id<CGSNativeConnectionObserver>) observer {
    return [CGSConnection nativeObserver];
}

#pragma mark - Modifiers

- (uint64_t) modifierFlags {
    uint64_t flags = [_keymap activeModifierFlags];
    for (NSNumber *identity in [_heldKeyIdentities allValues])
        flags |= modifierDeviceMask([identity intValue]);
    return flags;
}

- (void) cancelPendingModifier {
    if (_modifierSync != NULL) {
        WL.wl_proxy_destroy(_modifierSync);
        _modifierSync = NULL;
    }
    _hasModifierKeycode = NO;
}

- (void) flushPendingModifier {
    if (_hasModifierKeycode)
        [self postModifierKeycode: (unsigned short) _modifierKeycode];
    [self cancelPendingModifier];
}

- (void) classifyHeldKeys {
    for (NSNumber *key in [_heldKeyIdentities allKeys]) {
        int identity = [_keymap modifierKeyCodeForKeycode: [key unsignedIntValue]];
        [_heldKeyIdentities setObject: @(identity) forKey: key];
    }
    _classifyHeldKeys = NO;
}

- (void) resetKeyboardModifiers {
    [self cancelPendingModifier];
    [_heldKeyIdentities removeAllObjects];
    _syncModifierFlags = NO;
    _classifyHeldKeys = NO;
    [_keymap resetModifiers];
}

#pragma mark - Posting

// Posts a key or flags changed event. unicode and unmodified are the characters of a key event.
- (void) postEventOfType: (CGEventType) type
                 keyCode: (unsigned short) keyCode
                   flags: (uint64_t) flags
              characters: (NSString *) characters
      unmodifiedCharacters: (NSString *) unmodified
                  repeat: (BOOL) repeat
                  serial: (uint32_t) serial
{
    CGEventRef event = CGEventCreateKeyboardEvent((CGEventSourceRef) _source, keyCode, type != kCGEventKeyUp);
    if (event == NULL)
        return;
    if (type == kCGEventFlagsChanged)
        CGEventSetType(event, type);
    CGEventSetFlags(event, (CGEventFlags) flags);

    NSUInteger length = [characters length];
    if (type != kCGEventFlagsChanged) {
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
    CGEventSetIntegerValueField(event, kCGSEventNativeWindow, (int64_t) (intptr_t) _focus);
    CGEventSetIntegerValueField(event, kCGSEventInputSerial, serial);

    _CGSEventStreamPost(event);
    CFRelease(event);
}

- (void) postModifierKeycode: (unsigned short) code {
    if (_focus == NULL)
        return;
    [self postEventOfType: kCGEventFlagsChanged
                  keyCode: code
                    flags: [self modifierFlags]
               characters: nil
     unmodifiedCharacters: nil
                   repeat: NO
                   serial: 0];
}

- (void) postKeyEventForKeycode: (uint32_t) keycode pressed: (BOOL) pressed repeat: (BOOL) repeat serial: (uint32_t) serial {
    if (_focus == NULL)
        return;
    [self postEventOfType: pressed ? kCGEventKeyDown : kCGEventKeyUp
                  keyCode: keycode < 256 ? x11ToCarbon[keycode] : 0
                    flags: [self modifierFlags]
               characters: [_keymap charactersForKeycode: keycode]
     unmodifiedCharacters: [_keymap unmodifiedCharactersForKeycode: keycode]
                   repeat: repeat
                   serial: serial];
}

#pragma mark - Key repeat

- (void) startKeyRepeat: (uint32_t) keycode {
    [self stopKeyRepeat];
    _repeatKeycode = keycode;

    CFRunLoopTimerContext context = {.version = 0, .info = self};
    _repeatTimer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + _repeatDelay / 1000.0,
                                        1.0 / _repeatRate, 0, 0, repeatTimerCallback, &context);
    CFRunLoopAddTimer(CFRunLoopGetMain(), _repeatTimer, kCFRunLoopCommonModes);
}

- (void) stopKeyRepeat {
    if (_repeatTimer != NULL) {
        CFRunLoopTimerInvalidate(_repeatTimer);
        CFRelease(_repeatTimer);
        _repeatTimer = NULL;
    }
    _repeatKeycode = 0;
}

- (void) repeatKey {
    if (![_keymap isUsable] || _repeatKeycode == 0)
        return;
    [self postKeyEventForKeycode: _repeatKeycode pressed: YES repeat: YES serial: 0];
}

#pragma mark - Events

- (void) keyboardEvent: (uint32_t) opcode arguments: (union wl_argument *) args {
    id<CGSNativeConnectionObserver> observer = [self observer];
    // What the observer queued about the pointer before this event must go out first.
    if ([observer respondsToSelector: @selector(nativeConnectionWillPostKeyboardEvent)])
        [observer nativeConnectionWillPostKeyboardEvent];

    switch (opcode) {
    case WP_KEYBOARD_EV_KEYMAP:
        // The descriptor is the connection's to close.
        if ([_keymap installKeymapAndReport: args[0].u fd: args[1].h size: args[2].u])
            [self keymapInstalled];
        break;

    case WP_KEYBOARD_EV_ENTER: {
        [self resetKeyboardModifiers];
        _focus = (struct wl_proxy *) args[1].o;
        struct wl_array *keys = args[2].a;
        for (size_t i = 0; i < keys->size / sizeof(uint32_t); i++) {
            uint32_t raw = ((uint32_t *) keys->data)[i];
            [_heldKeyIdentities setObject: @(-1) forKey: @(raw + 8)];
        }
        // Enter is followed by modifiers: classify under that current group, without inventing key
        // presses for keys held before focus arrived.
        _classifyHeldKeys = YES;
        _syncModifierFlags = YES;
        if ([observer respondsToSelector: @selector(nativeConnectionKeyboardFocusChanged:)])
            [observer nativeConnectionKeyboardFocusChanged: _focus];
        break;
    }

    case WP_KEYBOARD_EV_LEAVE:
        _focus = NULL;
        [self stopKeyRepeat];
        [self resetKeyboardModifiers];
        if ([observer respondsToSelector: @selector(nativeConnectionKeyboardFocusChanged:)])
            [observer nativeConnectionKeyboardFocusChanged: NULL];
        break;

    case WP_KEYBOARD_EV_KEY: {
        if (![_keymap isUsable] || _focus == NULL)
            break;
        [self flushPendingModifier];
        uint32_t keycode = args[2].u + 8;
        BOOL pressed = args[3].u == WP_KEYBOARD_KEY_STATE_PRESSED;
        uint32_t serial = args[0].u;
        if (pressed && [observer respondsToSelector: @selector(nativeConnectionKeyPressedWithSerial:)])
            [observer nativeConnectionKeyPressedWithSerial: serial];

        NSNumber *held = [_heldKeyIdentities objectForKey: @(keycode)];
        int modifier = held != nil ? [held intValue] : [_keymap modifierKeyCodeForKeycode: keycode];
        if (pressed)
            [_heldKeyIdentities setObject: @(modifier) forKey: @(keycode)];
        else
            [_heldKeyIdentities removeObjectForKey: @(keycode)];
        if (modifier >= 0) {
            _modifierKeycode = modifier;
            _hasModifierKeycode = YES;
            // A mask-changing key is followed by modifiers; an overlapping modifier need not be. A
            // sync drains the compositor's already queued events even across socket reads before the
            // idle fallback. It is not a keyboard frame or a fence for future input events.
            union wl_argument syncArgs[1] = {{.o = NULL}};
            _modifierSync = [_connection createObject: (struct wl_proxy *) _connection->_wlDisplay
                                               opcode: WP_DISPLAY_SYNC
                                            interface: &wl_callback_interface
                                            arguments: syncArgs
                                                 kind: CGSWaylandObjectKeyboardSync
                                               object: self];
            [_connection flush];
            break; // Modifiers are neither text nor repeatable keys.
        }
        [self postKeyEventForKeycode: keycode pressed: pressed repeat: NO serial: pressed ? serial : 0];
        if (pressed && _repeatRate > 0 && [_keymap keyRepeats: keycode])
            [self startKeyRepeat: keycode];
        else if (!pressed && keycode == _repeatKeycode)
            [self stopKeyRepeat];
        break;
    }

    case WP_KEYBOARD_EV_MODIFIERS: {
        uint64_t oldFlags = [self modifierFlags];
        if ([_keymap isUsable]) {
            [_keymap updateDepressed: args[1].u latched: args[2].u locked: args[3].u group: args[4].u];
            if (_classifyHeldKeys)
                [self classifyHeldKeys];
        }
        if (_hasModifierKeycode)
            [self flushPendingModifier];
        else if (_syncModifierFlags || [self modifierFlags] != oldFlags)
            [self postModifierKeycode: 0xFFFF];
        _syncModifierFlags = NO;
        break;
    }

    case WP_KEYBOARD_EV_REPEAT_INFO:
        _repeatRate = args[0].i;
        _repeatDelay = args[1].i;
        if (_repeatRate <= 0)
            [self stopKeyRepeat];
        break;
    }
}

- (void) modifierSyncDone: (struct wl_proxy *) proxy {
    if (proxy == _modifierSync)
        [self flushPendingModifier];
}

- (void) keymapInstalled {
    [self stopKeyRepeat];
    [self cancelPendingModifier];
    // Preserve press-time identities through keymap changes until release. Only keys the enter
    // event seeded need classification under the current group.
    _syncModifierFlags = _focus != NULL;
}

- (void) stop {
    [self stopKeyRepeat];
    [self cancelPendingModifier];
    _focus = NULL;
}

- (void) surfaceDestroyed: (struct wl_proxy *) surface {
    if (_focus == NULL || surface != _focus)
        return;
    _focus = NULL;
    [self stopKeyRepeat];
    [self resetKeyboardModifiers];
}

@end
