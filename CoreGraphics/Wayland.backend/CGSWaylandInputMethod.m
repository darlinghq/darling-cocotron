/* CoreGraphics Wayland backend: the text input (the compositor's input method).

 Copyright (C) 2026 Lubos Dolezel

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

#import "CGSWaylandInputMethod.h"
#import "CGSConnectionWayland.h"
#import "CGSWindowWayland.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import <CoreGraphics/CGSInputMethod.h>
#import <CoreGraphics/CGSWindow.h>
#import <Foundation/NSString.h>
#include <limits.h>
#include <math.h>

// A message of the protocol is at most 4000 bytes long, and the surrounding text goes in one.
static const NSUInteger kMaxSurroundingBytes = 4000;

@implementation CGSWaylandInputMethod

- (instancetype) initWithConnection: (CGSConnectionWayland *) connection {
    if ((self = [super init]) != nil) {
        _connection = connection;
        _sentRect = CGRectNull;
        _pendingCursorBegin = _pendingCursorEnd = -1;
    }
    return self;
}

- (void) dealloc {
    [self stop];
    [super dealloc];
}

#pragma mark - The object

- (BOOL) available {
    return _textInput != NULL;
}

- (uint32_t) managerName {
    return _manager != NULL ? _managerName : 0;
}

- (uint32_t) seatName {
    return _seat != NULL ? _seatName : 0;
}

- (void) attach {
    if (_manager == NULL || _seat == NULL || _textInput != NULL)
        return;
    union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _seat}};
    _textInput = [_connection createObject: _manager
                                    opcode: WP_TEXT_INPUT_MANAGER_GET_TEXT_INPUT
                                 interface: &zwp_text_input_v3_interface
                                 arguments: args
                                      kind: CGSWaylandObjectTextInput
                                    object: self];
}

- (void) detach {
    if (_textInput == NULL)
        return;
    [self left: YES];
    WaylandMarshal(_textInput, WP_TEXT_INPUT_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    _textInput = NULL;
}

- (void) managerBound: (struct wl_proxy *) manager name: (uint32_t) name seat: (struct wl_proxy *) seat {
    _manager = manager;
    _managerName = name;
    if (_seat == NULL && seat != NULL)
        _seat = seat;
    [self attach];
}

- (void) seatBound: (struct wl_proxy *) seat name: (uint32_t) name {
    _seat = seat;
    _seatName = name;
    [self attach];
}

- (void) managerRemoved {
    if (_manager == NULL)
        return;
    [self detach];
    WaylandMarshal(_manager, WP_TEXT_INPUT_MANAGER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    _manager = NULL;
    _managerName = 0;
}

- (void) seatRemoved {
    // The text input is made from the seat, and goes with it.
    [self detach];
    _seat = NULL;
    _seatName = 0;
}

- (void) stop {
    [self detach];
    if (_manager != NULL) {
        WaylandMarshal(_manager, WP_TEXT_INPUT_MANAGER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
        _manager = NULL;
    }
    _seat = NULL;
}

#pragma mark - Windows

- (CGSWindow *) enteredWindow {
    return _entered != 0 ? [_connection windowForId: (CGSWindowID) _entered] : nil;
}

static void postEvent(CGSWindow *window, CGSToplevelEventKind kind, NSString *text, CFRange range) {
    CGSToplevelEvent event = {.kind = kind, .rect = CGRectNull, .text = (CFStringRef) text, .textRange = range};

    [window postToplevelEvent: &event];
}

// The byte offset in the UTF-8 form of `text` of a UTF-16 offset; an offset inside a surrogate pair is the pair's start.
static int utf8OffsetOfUTF16Offset(NSString *text, NSUInteger offset) {
    NSUInteger length = [text length];

    if (offset > length)
        offset = length;
    if (offset > 0 && offset < length) {
        unichar c = [text characterAtIndex: offset];
        if (c >= 0xDC00 && c < 0xE000)
            offset--;
    }
    return (int) [[text substringToIndex: offset] lengthOfBytesUsingEncoding: NSUTF8StringEncoding];
}

// The UTF-16 offset in `text` of a byte offset in its UTF-8 form: the end of the text for a negative offset, and
// the start of the character that a byte inside one belongs to.
static NSUInteger utf16OffsetOfUTF8Offset(NSString *text, int byteOffset) {
    NSUInteger length = [text length];

    if (byteOffset < 0)
        return length;

    NSUInteger offset = 0;
    int bytes = 0;

    while (offset < length) {
        unichar c = [text characterAtIndex: offset];
        int size;
        NSUInteger units = 1;

        if (c >= 0xD800 && c < 0xDC00 && offset + 1 < length) {
            size = 4;
            units = 2;
        } else {
            size = c < 0x80 ? 1 : (c < 0x800 ? 2 : 3);
        }
        if (bytes + size > byteOffset)
            break;
        bytes += size;
        offset += units;
    }
    return offset;
}

// Sends what the window with the text input focus says of itself to the compositor. Only a change is sent: the
// compositor answers every commit.
- (void) sync {
    CGSWindow *window = [self enteredWindow];

    if (_textInput == NULL || window == nil)
        return;

    BOOL wanted = [window inputMethodEnabled];
    BOOL changed = NO;

    if (wanted != _sentEnabled) {
        WaylandMarshal(_textInput, wanted ? WP_TEXT_INPUT_ENABLE : WP_TEXT_INPUT_DISABLE, NULL, 0, NULL);
        _sentEnabled = wanted;
        changed = YES;
        // The compositor starts from nothing at an enable.
        [self forgetSentState];
        if (!wanted) {
            [_preedit release];
            _preedit = nil;
        }
    }
    if (wanted) {
        uint32_t hint = [window inputMethodContentHint], purpose = [window inputMethodContentPurpose];

        if (hint != _sentHint || purpose != _sentPurpose) {
            union wl_argument args[2] = {{.u = hint}, {.u = purpose}};
            WaylandMarshal(_textInput, WP_TEXT_INPUT_SET_CONTENT_TYPE, NULL, 0, args);
            _sentHint = hint;
            _sentPurpose = purpose;
            changed = YES;
        }

        NSString *text = [window inputMethodSurroundingText];
        CFRange selection = [window inputMethodSurroundingSelection];

        if ([text lengthOfBytesUsingEncoding: NSUTF8StringEncoding] > kMaxSurroundingBytes)
            text = nil;
        if (text != nil || _sentSurroundingValid) {
            NSString *sendText = text != nil ? text : @"";
            int cursor = text != nil ? utf8OffsetOfUTF16Offset(text, selection.location) : 0;
            int anchor = text != nil ? utf8OffsetOfUTF16Offset(text, selection.location + selection.length) : 0;

            if (!_sentSurroundingValid || ![sendText isEqualToString: _sentSurrounding] ||
                cursor != _sentCursor || anchor != _sentAnchor) {
                union wl_argument args[3] = {{.s = [sendText UTF8String]}, {.i = cursor}, {.i = anchor}};
                WaylandMarshal(_textInput, WP_TEXT_INPUT_SET_SURROUNDING_TEXT, NULL, 0, args);
                [_sentSurrounding release];
                _sentSurrounding = [sendText copy];
                _sentCursor = cursor;
                _sentAnchor = anchor;
                _sentSurroundingValid = YES;
                changed = YES;
            }
        }

        // The caret's rectangle in the surface's logical coordinates, y down: the window says it from its top left
        // corner, and the frame the UI layer draws inside the surface moves it.
        CGRect rect = [window inputMethodCursorRect];
        if (CGRectIsNull(rect))
            rect = CGRectZero;
        else if ([window isKindOfClass: [CGSWindowWayland class]]) {
            CGPoint offset = [(CGSWindowWayland *) window toplevelContentOffset];
            rect = CGRectOffset(rect, offset.x, offset.y);
        }
        if (changed || !CGRectEqualToRect(rect, _sentRect)) {
            union wl_argument args[4] = {{.i = (int32_t) floor(rect.origin.x)},
                                         {.i = (int32_t) floor(rect.origin.y)},
                                         {.i = (int32_t) ceil(rect.size.width)},
                                         {.i = (int32_t) ceil(rect.size.height)}};
            WaylandMarshal(_textInput, WP_TEXT_INPUT_SET_CURSOR_RECTANGLE, NULL, 0, args);
            _sentRect = rect;
            changed = YES;
        }
    }
    if (changed) {
        WaylandMarshal(_textInput, WP_TEXT_INPUT_COMMIT, NULL, 0, NULL);
        [_connection flush];
    }
}

- (void) forgetSentState {
    [_sentSurrounding release];
    _sentSurrounding = nil;
    _sentSurroundingValid = NO;
    _sentCursor = _sentAnchor = 0;
    _sentHint = _sentPurpose = 0;
    _sentRect = CGRectNull;
}

- (void) windowChanged: (CGSWindow *) window {
    if (_entered != 0 && [window windowId] == _entered)
        [self sync];
}

- (void) windowUnmapped: (CGSWindow *) window {
    if (_entered != 0 && [window windowId] == _entered)
        [self left: YES];
}

- (void) windowDestroyed: (uint32_t) windowID {
    if (_entered != 0 && windowID == _entered)
        [self left: NO];
}

// The compositor took the text input away from the window, or the window went: a composition that was showing is
// removed (when the window can still be told), as no commit can follow it.
- (void) left: (BOOL) tellWindow {
    CGSWindow *window = tellWindow ? [self enteredWindow] : nil;

    if (_preedit != nil && window != nil)
        postEvent(window, kCGSToplevelEventInputMethodPreedit, @"", CFRangeMake(0, 0));
    [_preedit release];
    _preedit = nil;
    [_pendingPreedit release];
    _pendingPreedit = nil;
    [_pendingCommit release];
    _pendingCommit = nil;
    _pendingCursorBegin = _pendingCursorEnd = -1;
    _pendingDeleteBefore = _pendingDeleteAfter = 0;
    _entered = 0;
    _sentEnabled = NO;
    [self forgetSentState];
}

#pragma mark - Events

// Applies one done as the protocol orders it: the composition that is showing goes when text is deleted, the
// surrounding text is deleted, the committed text is inserted, the new composition is shown with its caret.
- (void) done {
    NSString *commit = [_pendingCommit autorelease];
    NSString *preedit = [_pendingPreedit autorelease];
    int cursorBegin = _pendingCursorBegin, cursorEnd = _pendingCursorEnd;
    uint32_t deleteBefore = _pendingDeleteBefore, deleteAfter = _pendingDeleteAfter;
    CGSWindow *window = [self enteredWindow];

    _pendingCommit = nil;
    _pendingPreedit = nil;
    _pendingCursorBegin = _pendingCursorEnd = -1;
    _pendingDeleteBefore = _pendingDeleteAfter = 0;

    if (window == nil)
        return;
    if ([preedit length] == 0)
        preedit = nil;

    // What was deleted is told in the window's units, from the text the window gave; without it there is nothing the
    // compositor could have meant.
    NSString *surrounding = [window inputMethodSurroundingText];
    BOOL deleting = (deleteBefore != 0 || deleteAfter != 0) && surrounding != nil && _sentSurroundingValid;

    // Nothing the window has not already got: the compositor answers each commit with a done.
    BOOL samePreedit = preedit == nil ? _preedit == nil : [preedit isEqualToString: _preedit];
    if ([commit length] == 0 && samePreedit && !deleting)
        return;

    if (deleting && _preedit != nil) {
        postEvent(window, kCGSToplevelEventInputMethodPreedit, @"", CFRangeMake(0, 0));
        [_preedit release];
        _preedit = nil;
    }
    if (deleting) {
        CFRange selection = [window inputMethodSurroundingSelection];
        NSUInteger start = selection.location, end = selection.location + selection.length;
        int startByte = utf8OffsetOfUTF16Offset(surrounding, start), endByte = utf8OffsetOfUTF16Offset(surrounding, end);
        NSUInteger from = utf16OffsetOfUTF8Offset(surrounding, startByte > (int) deleteBefore ? startByte - (int) deleteBefore : 0);
        NSUInteger to = utf16OffsetOfUTF8Offset(surrounding, endByte + (int) MIN(deleteAfter, (uint32_t) INT_MAX / 2));

        postEvent(window, kCGSToplevelEventInputMethodDeleteSurrounding, nil, CFRangeMake(start - from, to - end));
    }
    if ([commit length] > 0) {
        // The commit replaces the composition.
        [_preedit release];
        _preedit = nil;
        postEvent(window, kCGSToplevelEventInputMethodCommit, commit, CFRangeMake(0, 0));
    }
    if (preedit == nil) {
        if (_preedit != nil)
            postEvent(window, kCGSToplevelEventInputMethodPreedit, @"", CFRangeMake(0, 0));
        [_preedit release];
        _preedit = nil;
        return;
    }
    NSUInteger begin = utf16OffsetOfUTF8Offset(preedit, cursorBegin);
    NSUInteger end = cursorEnd < 0 ? begin : utf16OffsetOfUTF8Offset(preedit, cursorEnd);
    if (end < begin)
        end = begin;
    [_preedit release];
    _preedit = [preedit copy];
    postEvent(window, kCGSToplevelEventInputMethodPreedit, preedit, CFRangeMake(begin, end - begin));
}

- (void) textInputEvent: (uint32_t) opcode arguments: (union wl_argument *) args {
    switch (opcode) {
    case WP_TEXT_INPUT_EV_ENTER:
        [self left: YES];
        _entered = [_connection windowIDForSurface: (struct wl_proxy *) args[0].o];
        [self sync];
        break;

    case WP_TEXT_INPUT_EV_LEAVE:
        [self left: YES];
        break;

    case WP_TEXT_INPUT_EV_PREEDIT_STRING:
        [_pendingPreedit release];
        _pendingPreedit = args[0].s != NULL ? [[NSString alloc] initWithUTF8String: args[0].s] : nil;
        _pendingCursorBegin = args[1].i;
        _pendingCursorEnd = args[2].i;
        break;

    case WP_TEXT_INPUT_EV_COMMIT_STRING:
        [_pendingCommit release];
        _pendingCommit = args[0].s != NULL ? [[NSString alloc] initWithUTF8String: args[0].s] : nil;
        break;

    case WP_TEXT_INPUT_EV_DELETE_SURROUNDING_TEXT:
        _pendingDeleteBefore = args[0].u;
        _pendingDeleteAfter = args[1].u;
        break;

    case WP_TEXT_INPUT_EV_DONE:
        [self done];
        break;
    }
}

@end
