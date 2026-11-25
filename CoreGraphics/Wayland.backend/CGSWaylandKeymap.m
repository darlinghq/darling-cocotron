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
#import <Foundation/NSString.h>

#include <errno.h>
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
    struct xkb_keymap *keymap = [self keymapFromFormat: format fd: fd size: size];
    close(fd);
    [self install: keymap];
}

// Makes keymap (NULL: none usable; the reference is taken over) the one in force.
- (void) install: (struct xkb_keymap *) keymap {
    struct xkb_state *state = keymap != NULL ? WL.xkb_state_new(keymap) : NULL;
    if (state == NULL) {
        if (keymap != NULL)
            WL.xkb_keymap_unref(keymap);
        return;
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
    }
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

@end
