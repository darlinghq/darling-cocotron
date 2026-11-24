/* The wire protocol between AppKit's Pocket backend and a phone host.

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

/*
 * Plain C with no Darwin headers, so that a host (for instance the native
 * code of an Android app) includes it as it is. The host is not part of this
 * repository; this file is the whole contract.
 *
 * Transport. The host listens on a Unix stream socket and each application
 * connects to it (the application finds the socket's path in the environment
 * variable DARLING_POCKET_DISPLAY). Every message is a struct pocket_header
 * and then `size` bytes of payload, in the machine's byte order (both ends run
 * on the same device). The structs below have no padding, and the sizes are
 * checked at compile time, so a 32-bit and a 64-bit process agree on them.
 * A message longer than POCKET_MAX_MESSAGE, or a payload shorter than its
 * struct, is a broken peer: the receiver closes the connection. Unknown
 * message types are ignored, so a newer peer can add messages.
 *
 * Start. The application sends POCKET_HELLO. The host answers with
 * POCKET_SCREEN before anything else, and again whenever the screen changes
 * (rotation, a new scale, insets). A host that does not
 * accept the version in POCKET_HELLO closes the connection. The application
 * waits up to ten seconds for the first POCKET_SCREEN; without it the backend
 * does not start and AppKit tries the next one.
 *
 * Windows. The application describes each window with POCKET_WINDOW (again
 * whenever it moves, resizes, changes level or is shown or hidden), and gives
 * the window's pixels as POCKET_BUFFER: a shared memory buffer, one file
 * descriptor sent with the message (SCM_RIGHTS, attached to its first byte)
 * that the host maps read-only. A new POCKET_BUFFER for the same window
 * replaces the old buffer. POCKET_ORDER lists the windows from the bottom up.
 * POCKET_DESTROY ends a window.
 *
 * Coordinates are the screen's pixels, from its top left. The pixels of a
 * window are rows from the top in POCKET_FORMAT_BGRA: 32 bits, premultiplied
 * alpha, blue in the lowest byte.
 *
 * Frames. POCKET_PRESENT says that (a part of) the buffer holds a finished
 * frame. After it the application does not write to the buffer until the host
 * answers POCKET_RELEASE for the window, so the host may read the buffer in
 * its own time and nothing tears. Then the application may present again.
 * A host releases every presented frame, also of a window it does not show.
 *
 * Input. The host sends POCKET_TOUCH for each finger, POCKET_KEY for a key
 * (hardware keyboard, or the soft keyboard's keys that are not text) and
 * POCKET_TEXT for the text an input method commits. The application asks for
 * the soft keyboard with POCKET_KEYBOARD while text is being edited, and the
 * host reports how much of the screen the keyboard covers in
 * POCKET_KEYBOARD_FRAME.
 *
 * Trying a host. Any program that follows the above works: listen on a
 * socket, export DARLING_POCKET_DISPLAY=<the socket's path as the application
 * sees it> for the application, read POCKET_HELLO, send POCKET_SCREEN, and the
 * application's windows arrive as POCKET_WINDOW and POCKET_BUFFER messages.
 * tests/appkit-pocket-protocol.c is a minimal host in this sense.
 */

#ifndef POCKET_PROTOCOL_H
#define POCKET_PROTOCOL_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define POCKET_PROTOCOL_VERSION 1
// Longer messages are a broken peer.
#define POCKET_MAX_MESSAGE 4096

struct pocket_header {
    uint32_t type;
    uint32_t size; // payload bytes after this header
};

enum {
    // App to host.
    POCKET_HELLO = 1,    // struct pocket_hello
    POCKET_WINDOW = 2,   // struct pocket_window: a new window, or its new state
    POCKET_BUFFER = 3,   // struct pocket_buffer, with the buffer's descriptor
    POCKET_PRESENT = 4,  // struct pocket_present
    POCKET_DESTROY = 5,  // struct pocket_window_id
    POCKET_ORDER = 6,    // uint32_t windows[], from the bottom up
    POCKET_KEYBOARD = 7, // struct pocket_keyboard: show or hide the soft keyboard

    // Host to app.
    POCKET_SCREEN = 101,         // struct pocket_screen, first, and again on a change
    POCKET_RELEASE = 102,        // struct pocket_window_id
    POCKET_TOUCH = 103,          // struct pocket_touch
    POCKET_KEY = 104,            // struct pocket_key, then the characters (UTF-8)
    POCKET_TEXT = 105,           // UTF-8 text the input method commits
    POCKET_KEYBOARD_FRAME = 106, // struct pocket_keyboard_frame: the soft keyboard came, went or resized
};

enum {
    POCKET_FORMAT_BGRA = 1,
};

enum {
    POCKET_WINDOW_VISIBLE = 1,
    POCKET_WINDOW_OPAQUE = 2,
};

// The phases of UITouch.Phase, without stationary (which the host never sends).
enum {
    POCKET_TOUCH_BEGAN = 0,
    POCKET_TOUCH_MOVED = 1,
    POCKET_TOUCH_ENDED = 3,
    POCKET_TOUCH_CANCELLED = 4,
};

enum {
    POCKET_KEYBOARD_SECURE = 1,    // a password: nothing remembered or suggested
    POCKET_KEYBOARD_MULTILINE = 2, // Return starts a new line
};

struct pocket_hello {
    uint32_t version; // POCKET_PROTOCOL_VERSION
    uint32_t pid;
};

struct pocket_window_id {
    uint32_t window;
};

struct pocket_window {
    uint32_t window;
    int32_t x, y, width, height;
    uint32_t flags;
    int32_t level; // AppKit's window level; higher is in front
};

struct pocket_buffer {
    uint32_t window;
    uint32_t width, height, stride; // pixels, pixels, bytes
    uint32_t format;                // POCKET_FORMAT_*
};

struct pocket_present {
    uint32_t window;
    // The part that changed.
    int32_t x, y, width, height;
};

// Hosts take the fields after `shown` only when the message is long enough.
struct pocket_keyboard {
    uint32_t shown;
    // The text's UITextInputTraits, with iOS's values.
    uint32_t keyboard_type;      // UIKeyboardType
    uint32_t return_key;         // UIReturnKeyType
    uint32_t autocapitalization; // UITextAutocapitalizationType
    uint32_t autocorrection;     // UITextAutocorrectionType
    uint32_t flags;              // POCKET_KEYBOARD_*
};

struct pocket_keyboard_frame {
    uint32_t height; // pixels the keyboard covers at the bottom; 0 once it is gone
};

struct pocket_screen {
    uint32_t width, height; // pixels
    uint32_t scale_milli;   // pixels per point, times 1000
    // Pixels a notch, a status bar or a navigation bar cover.
    uint32_t inset_top, inset_left, inset_bottom, inset_right;
};

struct pocket_touch {
    uint32_t phase;  // POCKET_TOUCH_*
    uint32_t finger; // the same while the finger is down, reused afterwards
    float x, y;      // pixels
    double time;     // seconds, any epoch
};

struct pocket_key {
    uint32_t down;
    // A Mac virtual key code (kVK_*), 0xFFFF for none. For Return, Tab,
    // Delete, Escape, the arrows and the like the app knows the characters.
    uint32_t keycode;
    uint32_t modifiers; // NSEventModifierFlags
    uint32_t length;    // bytes of characters that follow
};

#define POCKET_CHECK_SIZE(type, bytes) \
    typedef char pocket_size_of_##type[(sizeof(struct type) == (bytes)) ? 1 : -1]
POCKET_CHECK_SIZE(pocket_header, 8);
POCKET_CHECK_SIZE(pocket_hello, 8);
POCKET_CHECK_SIZE(pocket_window_id, 4);
POCKET_CHECK_SIZE(pocket_window, 28);
POCKET_CHECK_SIZE(pocket_buffer, 20);
POCKET_CHECK_SIZE(pocket_present, 20);
POCKET_CHECK_SIZE(pocket_keyboard, 24);
POCKET_CHECK_SIZE(pocket_keyboard_frame, 4);
POCKET_CHECK_SIZE(pocket_screen, 28);
POCKET_CHECK_SIZE(pocket_touch, 24);
POCKET_CHECK_SIZE(pocket_key, 16);

// Writes a message (header and payload) to `out`, which holds at least
// sizeof(struct pocket_header) + POCKET_MAX_MESSAGE bytes. Returns the
// message's length, or 0 when the payload is longer than POCKET_MAX_MESSAGE.
static inline size_t pocket_pack(uint8_t *out, uint32_t type, const void *payload, size_t size) {
    struct pocket_header header;
    if (size > POCKET_MAX_MESSAGE)
        return 0;
    header.type = type;
    header.size = (uint32_t) size;
    memcpy(out, &header, sizeof(header));
    if (size > 0)
        memcpy(out + sizeof(header), payload, size);
    return sizeof(header) + size;
}

// Looks at the bytes received so far. Returns 1 when they start with a whole
// message: `header` is filled in, and header + payload take
// sizeof(*header) + header->size bytes. Returns 0 when more bytes are needed
// and -1 when the peer is broken (a message longer than POCKET_MAX_MESSAGE).
static inline int pocket_unpack(const uint8_t *in, size_t length, struct pocket_header *header) {
    if (length < sizeof(*header))
        return 0;
    memcpy(header, in, sizeof(*header));
    if (header->size > POCKET_MAX_MESSAGE)
        return -1;
    return length - sizeof(*header) >= header->size ? 1 : 0;
}

#endif
