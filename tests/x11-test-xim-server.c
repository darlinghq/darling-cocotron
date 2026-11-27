// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Lubos Dolezel
//
// A small X input method (XIM server) for the tests of the window system's input method (see
// CGSInputMethod.h). It runs on the host, on $DISPLAY, under the name given as the first argument (clients
// select it with XMODIFIERS=@im=<name>), and offers the on-the-spot preedit style: the input method draws
// nothing, it tells the client what is composed and the client shows it. Its behavior is fixed so that a test
// can type into a window and know what the client must see:
//   a-z         are added to the composition, which the client is told (preedit draw) as a whole each time
//   BackSpace   removes the last character of the composition
//   Escape      removes the composition (preedit draw with nothing)
//   Return      commits the composition in upper case (preedit cleared first); with no composition, the key is
//               forwarded to the client like any other
//   2           composes the fixed text U+65E5 U+672C U+8A9E (non-ASCII, caret after the first character)
//   3           composes U+1F600 and "a" (a character outside the BMP, caret after the first character)
//   4           commits U+65E5 U+672C U+8A9E (the composition is cleared first)
//   other keys  are forwarded to the client unchanged (they are the client's keys)
// The key releases of the keys it took are not forwarded.
// The server logs to the file named by the second argument (one line each, flushed): READY once it is
// serving, STYLE <name> for the input style of a client's input context, FOCUS and UNFOCUS when a context gets
// or loses the focus, KEY down|up <keysym> for each key event the client sends it, and SPOT <x> <y> when the
// client sets the spot location of its preedit area.
// Usage: x11-test-xim-server <name> <log file>
// Build: cc -o x11-test-xim-server x11-test-xim-server.c -lxcb -lxcb-imdkit -lxcb-keysyms
#include <X11/keysym.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <xcb/xcb.h>
#include <xcb/xcb_keysyms.h>
#include <xcb-imdkit/encoding.h>
#include <xcb-imdkit/imdkit.h>

static FILE *logFile;
static xcb_key_symbols_t *symbols;
static xcb_im_t *im;

#define LOG(...) do { fprintf(logFile, __VA_ARGS__); fputc('\n', logFile); fflush(logFile); } while (0)

// The state of one client input context: its composition (lower case ASCII) and the keys it took.
typedef struct {
    char text[64];
    int length;
    int preeditOpen;
    uint8_t taken[256];
} Context;

static Context *contextOf(xcb_im_input_context_t *ic) {
    Context *context = xcb_im_input_context_get_data(ic);
    if (context == NULL) {
        context = calloc(1, sizeof(Context));
        xcb_im_input_context_set_data(ic, context, free);
    }
    return context;
}

// Tells the client what is composed: replaces all the text it holds with the composition.
static void drawPreedit(xcb_im_input_context_t *ic, Context *context, int previousLength) {
    if (!context->preeditOpen) {
        xcb_im_preedit_start_callback(im, ic);
        context->preeditOpen = 1;
    }
    size_t compoundLength = 0;
    char *compound = xcb_utf8_to_compound_text(context->text, context->length, &compoundLength);
    xcb_im_preedit_draw_fr_t frame;
    memset(&frame, 0, sizeof(frame));
    frame.caret = context->length;
    frame.chg_first = 0;
    frame.chg_length = previousLength;
    frame.length_of_preedit_string = compoundLength;
    frame.preedit_string = (uint8_t *) compound;
    uint32_t feedback[64];
    for (int i = 0; i < context->length; i++)
        feedback[i] = XCB_XIM_UNDERLINE;
    frame.feedback_array.size = context->length;
    frame.feedback_array.items = feedback;
    xcb_im_preedit_draw_callback(im, ic, &frame);
    free(compound);
}

// Replaces the composition with a fixed UTF-8 text (utf8Characters characters long), caret after caretCharacters.
static void setFixedPreedit(xcb_im_input_context_t *ic, Context *context, const char *utf8, int utf8Characters, int caretCharacters) {
    if (!context->preeditOpen) {
        xcb_im_preedit_start_callback(im, ic);
        context->preeditOpen = 1;
    }
    size_t compoundLength = 0;
    char *compound = xcb_utf8_to_compound_text(utf8, strlen(utf8), &compoundLength);
    xcb_im_preedit_draw_fr_t frame;
    memset(&frame, 0, sizeof(frame));
    frame.caret = caretCharacters;
    frame.chg_first = 0;
    frame.chg_length = context->length;
    frame.length_of_preedit_string = compoundLength;
    frame.preedit_string = (uint8_t *) compound;
    uint32_t feedback[64];
    for (int i = 0; i < utf8Characters; i++)
        feedback[i] = XCB_XIM_UNDERLINE;
    frame.feedback_array.size = utf8Characters;
    frame.feedback_array.items = feedback;
    xcb_im_preedit_draw_callback(im, ic, &frame);
    free(compound);
    context->length = utf8Characters;
    memset(context->text, 'x', utf8Characters);
    context->text[utf8Characters] = 0;
}

static void clearPreedit(xcb_im_input_context_t *ic, Context *context) {
    int previous = context->length;
    context->length = 0;
    context->text[0] = 0;
    if (previous > 0)
        drawPreedit(ic, context, previous);
}

static void forwardKey(xcb_im_input_context_t *ic, xcb_key_press_event_t *event) {
    xcb_im_forward_event(im, ic, event);
}

static void keyEvent(xcb_im_input_context_t *ic, xcb_key_press_event_t *event) {
    Context *context = contextOf(ic);
    int press = (event->response_type & 0x7f) == XCB_KEY_PRESS;
    xcb_keysym_t keysym = xcb_key_symbols_get_keysym(symbols, event->detail, 0);
    LOG("KEY %s %#x", press ? "down" : "up", keysym);

    if (!press) {
        if (context->taken[event->detail]) {
            context->taken[event->detail] = 0;
            return;
        }
        forwardKey(ic, event);
        return;
    }
    if (keysym == XK_2 && context->length == 0) {
        setFixedPreedit(ic, context, "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e", 3, 1);
        context->taken[event->detail] = 1;
    } else if (keysym == XK_3 && context->length == 0) {
        setFixedPreedit(ic, context, "\xf0\x9f\x98\x80" "a", 2, 1);
        context->taken[event->detail] = 1;
    } else if (keysym == XK_4) {
        clearPreedit(ic, context);
        const char *japanese = "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e";
        size_t compoundLength = 0;
        char *compound = xcb_utf8_to_compound_text(japanese, strlen(japanese), &compoundLength);
        xcb_im_commit_string(im, ic, XCB_XIM_LOOKUP_CHARS, compound, compoundLength, 0);
        free(compound);
        context->taken[event->detail] = 1;
    } else if (keysym >= XK_a && keysym <= XK_z && (event->state & (XCB_MOD_MASK_CONTROL | XCB_MOD_MASK_1 | XCB_MOD_MASK_4)) == 0
        && context->length < 63) {
        int previous = context->length;
        context->text[context->length++] = (char) keysym;
        context->text[context->length] = 0;
        drawPreedit(ic, context, previous);
        context->taken[event->detail] = 1;
    } else if (keysym == XK_BackSpace && context->length > 0) {
        int previous = context->length;
        context->text[--context->length] = 0;
        drawPreedit(ic, context, previous);
        context->taken[event->detail] = 1;
    } else if (keysym == XK_Escape && context->length > 0) {
        clearPreedit(ic, context);
        context->taken[event->detail] = 1;
    } else if (keysym == XK_Return && context->length > 0) {
        char upper[64];
        int length = context->length;
        for (int i = 0; i < length; i++)
            upper[i] = (char) (context->text[i] - 'a' + 'A');
        upper[length] = 0;
        clearPreedit(ic, context);
        size_t compoundLength = 0;
        char *compound = xcb_utf8_to_compound_text(upper, length, &compoundLength);
        xcb_im_commit_string(im, ic, XCB_XIM_LOOKUP_CHARS, compound, compoundLength, 0);
        free(compound);
        context->taken[event->detail] = 1;
    } else {
        forwardKey(ic, event);
    }
}

static const char *styleName(uint32_t style) {
    if (style & XCB_IM_PreeditCallbacks)
        return "onthespot";
    if (style & XCB_IM_PreeditNothing)
        return "nothing";
    return "other";
}

static void logSpot(xcb_im_input_context_t *ic) {
    if (xcb_im_input_context_get_preedit_attr_mask(ic) & XCB_XIM_XNSpotLocation_MASK) {
        const xcb_im_preedit_attr_t *attr = xcb_im_input_context_get_preedit_attr(ic);
        LOG("SPOT %d %d", attr->spot_location.x, attr->spot_location.y);
    }
}

static void callback(xcb_im_t *server, xcb_im_client_t *client, xcb_im_input_context_t *ic,
                     const xcb_im_packet_header_fr_t *header, void *frame, void *arg, void *userData) {
    switch (header->major_opcode) {
    case XCB_XIM_CREATE_IC:
        LOG("STYLE %s", styleName(xcb_im_input_context_get_input_style(ic)));
        logSpot(ic);
        break;
    case XCB_XIM_SET_IC_VALUES:
        logSpot(ic);
        break;
    case XCB_XIM_SET_IC_FOCUS:
        LOG("FOCUS");
        break;
    case XCB_XIM_UNSET_IC_FOCUS:
        LOG("UNFOCUS");
        break;
    case XCB_XIM_FORWARD_EVENT:
        keyEvent(ic, arg);
        break;
    case XCB_XIM_RESET_IC: {
        Context *context = contextOf(ic);
        clearPreedit(ic, context);
        break;
    }
    default:
        break;
    }
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: x11-test-xim-server <name> <log file>\n");
        return 2;
    }
    logFile = fopen(argv[2], "w");
    if (logFile == NULL)
        return 2;
    int screenNumber = 0;
    xcb_connection_t *connection = xcb_connect(NULL, &screenNumber);
    if (xcb_connection_has_error(connection)) {
        LOG("FAIL cannot connect to the X server");
        return 1;
    }
    xcb_screen_t *screen;
    xcb_screen_iterator_t screens = xcb_setup_roots_iterator(xcb_get_setup(connection));
    for (int i = 0; i < screenNumber; i++)
        xcb_screen_next(&screens);
    screen = screens.data;
    xcb_window_t window = xcb_generate_id(connection);
    xcb_create_window(connection, XCB_COPY_FROM_PARENT, window, screen->root, 0, 0, 1, 1, 1, XCB_WINDOW_CLASS_INPUT_OUTPUT,
                      screen->root_visual, 0, NULL);
    symbols = xcb_key_symbols_alloc(connection);

    uint32_t styleList[] = {XCB_IM_PreeditCallbacks | XCB_IM_StatusNothing, XCB_IM_PreeditNothing | XCB_IM_StatusNothing};
    xcb_im_styles_t styles = {.nStyles = 2, .styles = styleList};
    char encodingName[] = "COMPOUND_TEXT";
    xcb_im_encoding_t encodingList[] = {encodingName};
    xcb_im_encodings_t encodings = {.nEncodings = 1, .encodings = encodingList};
    xcb_compound_text_init();
    im = xcb_im_create(connection, screenNumber, window, argv[1], XCB_IM_ALL_LOCALES, &styles, NULL, NULL, &encodings,
                       XCB_EVENT_MASK_KEY_PRESS | XCB_EVENT_MASK_KEY_RELEASE, callback, NULL);
    if (im == NULL || !xcb_im_open_im(im)) {
        LOG("FAIL cannot open the input method");
        return 1;
    }
    xcb_im_set_use_sync_mode(im, true);
    xcb_flush(connection);
    LOG("READY");

    xcb_generic_event_t *event;
    while ((event = xcb_wait_for_event(connection)) != NULL) {
        xcb_im_filter_event(im, event);
        free(event);
    }
    return 0;
}
