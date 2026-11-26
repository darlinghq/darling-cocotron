/* Copyright (C) 2026 Lubos Dolezel

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

#import "CGSWaylandKeymap.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import <CoreGraphics/CGSKeyboardLayout.h>
#import <CoreGraphics/CGSKeySymToUnicodePrivate.h>
#import "../DarlingUnicodeKeyLayout.h"
#import "../DarlingUnicodeKeyLayoutCompose.h"
// The table of virtual key codes and the keycodes of the keymap, shared with the X11 backend.
#import "../X11.backend/CarbonKeys.h"
#import "../CGSKeyCompose.h"
#import <CoreGraphics/CGEventTypes.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>

#include <ctype.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

// What the keyboard layout builder needs of the compositor's keymap: a scratch XKB state that
// is put into each modifier layer in turn, so XKB itself decides the level of a key.
typedef struct {
    struct xkb_state *state;
    xkb_layout_index_t group;
    xkb_mod_mask_t shift, caps, option;
} CGSWaylandKeyLayoutContext;

static uint32_t keyLayoutKeysym(void *context, int carbonKey, unsigned layer) {
    CGSWaylandKeyLayoutContext *keymap = context;
    const int keycode = carbonToX11[carbonKey];
    if (keycode == 0)
        return 0;

    xkb_mod_mask_t depressed = 0, locked = 0;
    if (layer & DarlingKeyLayerShift)
        depressed |= keymap->shift;
    if (layer & DarlingKeyLayerOption)
        depressed |= keymap->option;
    if (layer & DarlingKeyLayerCaps)
        locked |= keymap->caps;
    WL.xkb_state_update_mask(keymap->state, depressed, 0, locked, 0, 0, keymap->group);
    xkb_keysym_t keysym = WL.xkb_state_key_get_one_sym(keymap->state, keycode);
    return keysym == XKB_KEY_NoSymbol ? 0 : keysym;
}

static uint32_t keyLayoutCodepoint(void *context, uint32_t keysym) {
    uint32_t codepoint = CGSKeySymToUnicode(keysym);
    return codepoint != 0 ? codepoint : WL.xkb_keysym_to_utf32(keysym);
}

@implementation CGSWaylandKeymap

- (instancetype) init {
    self = [super init];
    if (self == nil)
        return nil;
    if (!WaylandLibraryLoad() || !WaylandCheckOpcodes()) {
        [self release];
        return nil;
    }
    _context = WL.xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    if (_context == NULL) {
        NSLog(@"CoreGraphics Wayland backend: cannot create an xkbcommon context, the keyboard layout is unknown");
        [self release];
        return nil;
    }
    [self install: WL.xkb_keymap_new_from_names(_context, NULL, XKB_KEYMAP_COMPILE_NO_FLAGS)];
    return self;
}

- (void) dealloc {
    if (_state != NULL)
        WL.xkb_state_unref(_state);
    if (_keymap != NULL)
        WL.xkb_keymap_unref(_keymap);
    if (_context != NULL)
        WL.xkb_context_unref(_context);
    [_layout release];
    CGSKeyComposeDestroy(_compose);
    [super dealloc];
}

- (struct xkb_keymap *) keymapFromFormat: (uint32_t) format fd: (int) fd size: (uint32_t) size {
    struct xkb_keymap *keymap = NULL;

    if (format == WP_KEYBOARD_KEYMAP_FORMAT_XKB_V1 && size == 0) {
        NSLog(@"CoreGraphics Wayland backend: the compositor sent an empty keymap");
    } else if (format == WP_KEYBOARD_KEYMAP_FORMAT_XKB_V1) {
        char *map = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
        if (map == MAP_FAILED) {
            NSLog(@"CoreGraphics Wayland backend: cannot map the keymap: %s", strerror(errno));
        } else {
            keymap = WL.xkb_keymap_new_from_buffer(_context, map, strnlen(map, size),
                                                   XKB_KEYMAP_FORMAT_TEXT_V1,
                                                   XKB_KEYMAP_COMPILE_NO_FLAGS);
            munmap(map, size);
            if (keymap == NULL)
                NSLog(@"CoreGraphics Wayland backend: cannot compile the compositor's keymap");
        }
    } else if (format != WP_KEYBOARD_KEYMAP_FORMAT_NO_KEYMAP) {
        NSLog(@"CoreGraphics Wayland backend: unsupported keymap format %u", format);
    }
    return keymap;
}

- (void) installKeymapWithFormat: (uint32_t) format fd: (int) fd size: (uint32_t) size {
    [self installKeymapAndReport: format fd: fd size: size];
}

- (BOOL) installKeymapAndReport: (uint32_t) format fd: (int) fd size: (uint32_t) size {
    struct xkb_keymap *keymap = [self keymapFromFormat: format fd: fd size: size];
    close(fd);
    return [self install: keymap];
}

// Makes keymap (NULL: none usable; the reference is taken over) the one in force. Returns whether it was.
- (BOOL) install: (struct xkb_keymap *) keymap {
    struct xkb_state *state = keymap != NULL ? WL.xkb_state_new(keymap) : NULL;
    if (state == NULL) {
        if (keymap != NULL)
            WL.xkb_keymap_unref(keymap);
        return NO;
    }
    @synchronized (self) {
        if (_state != NULL)
            WL.xkb_state_unref(_state);
        if (_keymap != NULL)
            WL.xkb_keymap_unref(_keymap);
        _keymap = keymap;
        _state = state;
        [_layout release];
        _layout = nil;
        if (_compose != NULL)
            CGSKeyComposeReset(_compose);
    }
    return YES;
}

- (void) updateDepressed: (uint32_t) depressed latched: (uint32_t) latched locked: (uint32_t) locked
                   group: (uint32_t) group {
    @synchronized (self) {
        if (_state == NULL)
            return;
        xkb_layout_index_t before = WL.xkb_state_serialize_layout(_state, XKB_STATE_LAYOUT_EFFECTIVE);
        WL.xkb_state_update_mask(_state, depressed, latched, locked, 0, 0, group);
        if (WL.xkb_state_serialize_layout(_state, XKB_STATE_LAYOUT_EFFECTIVE) != before) {
            [_layout release];
            _layout = nil;
        }
    }
}

// Called with the lock held.
- (CGSKeyboardLayout *) buildLayout {
    xkb_layout_index_t group = WL.xkb_state_serialize_layout(_state, XKB_STATE_LAYOUT_EFFECTIVE);

    CGSWaylandKeyLayoutContext context;
    context.state = WL.xkb_state_new(_keymap);
    if (context.state == NULL)
        return nil;
    context.group = group;
    xkb_mod_index_t shift = WL.xkb_keymap_mod_get_index(_keymap, XKB_MOD_NAME_SHIFT);
    xkb_mod_index_t caps = WL.xkb_keymap_mod_get_index(_keymap, XKB_MOD_NAME_CAPS);
    xkb_mod_index_t option = WL.xkb_keymap_mod_get_index(_keymap, "Mod5"); // AltGr
    context.shift = shift != XKB_MOD_INVALID ? 1u << shift : 0;
    context.caps = caps != XKB_MOD_INVALID ? 1u << caps : 0;
    context.option = option != XKB_MOD_INVALID ? 1u << option : 0;

    DarlingKeyLayoutSource source = {
        .context = &context,
        .keysym = keyLayoutKeysym,
        .codepoint = keyLayoutCodepoint,
        .compose = DarlingComposeCharacters,
    };
    uint32_t length = 0;
    UCKeyboardLayout *uchr = DarlingCreateUnicodeKeyLayout(&source, &length);
    WL.xkb_state_unref(context.state);
    if (uchr == NULL)
        return nil;

    NSString *name = @"?";
    const char *xkbName = WL.xkb_keymap_layout_get_name(_keymap, group);
    if (xkbName != NULL)
        name = [NSString stringWithUTF8String: xkbName] ?: @"?";

    CGSKeyboardLayout *layout = [[CGSKeyboardLayout alloc] init];
    [layout setLayout: uchr length: length];
    layout.name = name;
    layout.fullName = name;
    free(uchr);
    return layout;
}

- (CGSKeyboardLayout *) copyLayout {
    @synchronized (self) {
        if (_layout == nil && _state != NULL && _keymap != NULL)
            _layout = [self buildLayout];
        return [_layout retain];
    }
}

#pragma mark - Keyboard decoding

static NSString *stringWithCodepoint(uint32_t codepoint) {
    if (codepoint == 0 || codepoint > 0x10FFFF)
        return @"";
    if (codepoint < 0x10000) {
        unichar character = (unichar) codepoint;
        return [NSString stringWithCharacters: &character length: 1];
    }
    codepoint -= 0x10000;
    unichar pair[2] = {(unichar) (0xD800 + (codepoint >> 10)), (unichar) (0xDC00 + (codepoint & 0x3FF))};
    return [NSString stringWithCharacters: pair length: 2];
}

// The virtual key code of the modifier key that produces the keysym, or -1 for any other key. The
// identity only says which physical key it is: the modifiers event of the compositor decides the flags.
static int modifierKeyCodeOfKeysym(xkb_keysym_t sym) {
    switch (sym) {
    case XKB_KEY_Shift_L: return kVK_Shift;
    case XKB_KEY_Shift_R: return kVK_RightShift;
    case XKB_KEY_Control_L: return kVK_Control;
    case XKB_KEY_Control_R: return kVK_RightControl;
    case XKB_KEY_Alt_L: return kVK_Option;
    case XKB_KEY_Alt_R: return kVK_RightOption;
    case XKB_KEY_Super_L: case XKB_KEY_Meta_L: return kVK_Command;
    case XKB_KEY_Super_R: case XKB_KEY_Meta_R: return 0x36; // The right Command key.
    case XKB_KEY_Caps_Lock: return kVK_CapsLock;
    case XKB_KEY_ISO_Level3_Shift: case XKB_KEY_Mode_switch: return kVK_Function;
    default: return -1;
    }
}

// Called with the lock held.
- (BOOL) modifierActive: (const char *) name {
    return _state != NULL && WL.xkb_state_mod_name_is_active(_state, name, XKB_STATE_MODS_EFFECTIVE) > 0;
}

- (BOOL) isUsable {
    @synchronized (self) {
        return _state != NULL;
    }
}

- (int) modifierKeyCodeForKeycode: (uint32_t) keycode {
    @synchronized (self) {
        return _state != NULL ? modifierKeyCodeOfKeysym(WL.xkb_state_key_get_one_sym(_state, keycode)) : -1;
    }
}

- (uint64_t) activeModifierFlags {
    @synchronized (self) {
        uint64_t flags = 0;
        if ([self modifierActive: XKB_MOD_NAME_SHIFT])
            flags |= kCGEventFlagMaskShift;
        if ([self modifierActive: XKB_MOD_NAME_CTRL])
            flags |= kCGEventFlagMaskControl;
        if ([self modifierActive: XKB_MOD_NAME_CAPS])
            flags |= kCGEventFlagMaskAlphaShift;
        if ([self modifierActive: XKB_MOD_NAME_LOGO])
            flags |= kCGEventFlagMaskCommand;
        if ([self modifierActive: XKB_MOD_NAME_ALT])
            flags |= kCGEventFlagMaskAlternate;
        if ([self modifierActive: "Mod5"]) // AltGr
            flags |= kCGEventFlagMaskSecondaryFn;
        return flags;
    }
}

- (uint32_t) codepointForKeysym: (xkb_keysym_t) keysym {
    // CGSKeySymToUnicode knows the private-use codes of the function keys; XKB keysyms have the
    // values of the X11 ones.
    uint32_t codepoint = CGSKeySymToUnicode(keysym);
    if (codepoint == 0)
        codepoint = WL.xkb_keysym_to_utf32(keysym);
    // A key xkbcommon has no text for, but a Mac layout gives a control code (ISO_Left_Tab, the keysym of Shift+Tab)
    if (codepoint == 0)
        codepoint = DarlingKeysymControlCode(keysym);
    return codepoint;
}

// Called with the lock held.
- (xkb_keysym_t) keysymForKeycode: (xkb_keycode_t) keycode level: (xkb_level_index_t) level {
    xkb_layout_index_t layout = WL.xkb_state_key_get_layout(_state, keycode);
    if (layout == XKB_LAYOUT_INVALID)
        return XKB_KEY_NoSymbol;

    const xkb_keysym_t *keysyms = NULL;
    int count = WL.xkb_keymap_key_get_syms_by_level(_keymap, keycode, layout, level, &keysyms);
    if (count <= 0 && level > 0)
        count = WL.xkb_keymap_key_get_syms_by_level(_keymap, keycode, layout, 0, &keysyms);
    return count > 0 ? keysyms[0] : XKB_KEY_NoSymbol;
}

- (NSString *) charactersForKeycode: (uint32_t) keycode {
    @synchronized (self) {
        if (_state == NULL)
            return @"";
        xkb_keysym_t keysym = WL.xkb_state_key_get_one_sym(_state, keycode);
        uint32_t special = CGSKeySymToUnicode(keysym);
        if (special >= 0xF700 && special <= 0xF8FF)
            return stringWithCodepoint(special);

        char buffer[64];
        int length = WL.xkb_state_key_get_utf8(_state, keycode, buffer, sizeof(buffer));
        NSString *text = @"";
        if (length >= (int) sizeof(buffer)) {
            char *larger = malloc(length + 1);
            if (larger == NULL)
                return @"";
            WL.xkb_state_key_get_utf8(_state, keycode, larger, length + 1);
            text = [NSString stringWithUTF8String: larger] ?: @"";
            free(larger);
        } else if (length > 0) {
            text = [NSString stringWithUTF8String: buffer] ?: @"";
        }
        // No text from xkbcommon for a key that has a control code in a Mac layout: that code (ISO_Left_Tab gives U+0009)
        if ([text length] == 0)
            text = stringWithCodepoint(DarlingKeysymControlCode(keysym));
        return text;
    }
}

- (NSString *) unmodifiedCharactersForKeycode: (uint32_t) keycode {
    @synchronized (self) {
        if (_state == NULL)
            return @"";
        // Every modifier is ignored except Shift.
        xkb_level_index_t level = [self modifierActive: XKB_MOD_NAME_SHIFT] ? 1 : 0;
        return stringWithCodepoint([self codepointForKeysym: [self keysymForKeycode: keycode level: level]]);
    }
}

#pragma mark - Dead keys and compose sequences

- (void) resetCompose {
    @synchronized (self) {
        if (_compose != NULL)
            CGSKeyComposeReset(_compose);
    }
}

- (CGSKeyComposeResult) composeKeycode: (uint32_t) keycode text: (NSString **) text {
    *text = nil;
    @synchronized (self) {
        if (_state == NULL)
            return CGSKeyComposeNone;
        if (!_composeLoaded) {
            _composeLoaded = YES;
            _compose = CGSKeyComposeCreate();
        }
        if (_compose == NULL)
            return CGSKeyComposeNone;
        // A shortcut is not text: a key with Control or Command is no part of a sequence and ends one.
        BOOL shortcut = [self modifierActive: XKB_MOD_NAME_CTRL] || [self modifierActive: XKB_MOD_NAME_LOGO];
        return CGSKeyComposeFeed(_compose, WL.xkb_state_key_get_one_sym(_state, keycode), shortcut, text);
    }
}

- (BOOL) keyRepeats: (uint32_t) keycode {
    @synchronized (self) {
        return _keymap != NULL && WL.xkb_keymap_key_repeats(_keymap, keycode) > 0;
    }
}

- (void) resetModifiers {
    @synchronized (self) {
        if (_state == NULL)
            return;
        xkb_layout_index_t before = WL.xkb_state_serialize_layout(_state, XKB_STATE_LAYOUT_EFFECTIVE);
        WL.xkb_state_update_mask(_state, 0, 0, 0, 0, 0, 0);
        if (WL.xkb_state_serialize_layout(_state, XKB_STATE_LAYOUT_EFFECTIVE) != before) {
            [_layout release];
            _layout = nil;
        }
    }
}

- (int) layoutGroup {
    @synchronized (self) {
        return _state != NULL ? (int) WL.xkb_state_serialize_layout(_state, XKB_STATE_LAYOUT_EFFECTIVE) : -1;
    }
}

- (NSString *) layoutName {
    @synchronized (self) {
        if (_state == NULL)
            return nil;
        const char *name = WL.xkb_keymap_layout_get_name(_keymap,
                WL.xkb_state_serialize_layout(_state, XKB_STATE_LAYOUT_EFFECTIVE));
        return name != NULL ? [NSString stringWithUTF8String: name] : nil;
    }
}

// A fresh state keeps the decoder's state (and its Compose sequence) untouched. The XDG shortcut
// specification names keysyms without the XKB_KEY_ prefix and allows only those characters.
- (NSString *) portalKeysymNameForKeyCode: (uint32_t) keyCode {
    if (_keymap == NULL || keyCode >= sizeof(carbonToX11) / sizeof(carbonToX11[0]))
        return nil;
    int keycode = carbonToX11[keyCode];
    if (keycode == 0)
        return nil;

    int group = [self layoutGroup];
    if (group < 0)
        return nil;
    struct xkb_state *state = WL.xkb_state_new(_keymap);
    if (state == NULL)
        return nil;
    WL.xkb_state_update_mask(state, 0, 0, 0, 0, 0, (xkb_layout_index_t) group);
    xkb_keysym_t keysym = WL.xkb_state_key_get_one_sym(state, keycode);
    WL.xkb_state_unref(state);

    char name[64];
    int length = WL.xkb_keysym_get_name(keysym, name, sizeof(name));
    if (length <= 0)
        return nil;
    const char *start = name;
    if (strncmp(start, "XKB_KEY_", 8) == 0)
        start += 8;
    if (*start == '\0')
        return nil;
    for (const char *c = start; *c != '\0'; c++) {
        if (!isalnum((unsigned char) *c) && *c != '_')
            return nil;
    }
    return [NSString stringWithUTF8String: start];
}

@end
