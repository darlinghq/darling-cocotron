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

#ifndef CGSINPUTMETHOD_H
#define CGSINPUTMETHOD_H
#import <Foundation/NSObject.h>
#import <CoreGraphics/CGGeometry.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>

// The window system's input method, as a window uses it (private interface).
//
// CoreGraphics owns the process' connection to the window system, so it also owns the process' part in the
// window system's input method protocol: XIM on X11, and the text input protocol of Wayland. An input method
// turns key presses into text that cannot be taken from a key map (a composition that is shown while it is
// made, candidates to choose from) and tells the window where the text is being entered, so that it can place
// its candidate window there. The UI layer (AppKit's NSTextInputContext and the text input client behind it)
// sits on top of this interface and knows nothing of the protocol. The input method itself stays in the
// application: it composes what a window's text input client edits, and the client is not reachable from here.
//
// Windows are named by their CGS window ids. What a window system says is delivered as toplevel events (see
// CGSWindow.h, -setToplevelEventProc:info:), on the thread that runs the main run loop, while the window system's
// events are handled:
//
//   kCGSToplevelEventInputMethodPreedit   the composition changed; text is all of it, textRange the caret (or
//                                         the selected part) inside it in UTF-16 units. Empty text: the
//                                         composition is over (it was cancelled, or its text has been or is
//                                         about to be committed). The text is only valid during the call.
//   kCGSToplevelEventInputMethodCommit    the final text, which replaces the composition if there is one.
//
// A window system that delivers the committed text as key events (X11: the input method returns it when it is
// asked for the text of a key) does not post a commit: the text is the characters of the key event the
// keyboard posts (see CGEventKeyboardGetUnicodeString), which is where a UI layer takes it from anyway, whether
// or not an input method made it. Dead keys and Compose sequences reach the UI layer the same way, as the
// characters of the key that ends them.
//
// Everything is called on the main thread. A backend that has no input method of its own reports
// _CGSInputMethodAvailable() NO, and the other functions do nothing.

// Whether the backend runs an input method for windows (X11: yes, when the window system has one it can talk
// to or Xlib's built-in one; Wayland: yes, when the compositor has text-input-v3; a backend without: no).
COREGRAPHICS_EXPORT BOOL _CGSInputMethodAvailable(void);

// Lets the window use the input method (or, with NO, stops it: what was composed is dropped, and the window's
// keys are looked up in the keymap again). A window that was never enabled sends no preedit and never has its
// keys filtered. The backend gives the input method the window's keyboard focus whenever the window system
// gives the window the keyboard focus (X11: FocusIn and FocusOut), so the UI layer need not tell it, and it
// follows the window when the window system's window has to be made again. Does nothing for a window that
// does not exist.
COREGRAPHICS_EXPORT void _CGSInputMethodSetEnabled(CGSWindowID window, BOOL enabled);

// Where the text is being entered: the rectangle of the composition's caret (or the insertion point, without a
// composition), in points from the window's top left corner, y down. The input method places its candidates
// near it. Said again whenever it changes (the caret moves, the text scrolls, the window moves inside itself).
// Remembered, and given to the input method when the window gets the keyboard focus. Some styles of input
// method do not take it (X11: the ones that draw the composition themselves); then it is ignored.
COREGRAPHICS_EXPORT void _CGSInputMethodSetCursorRect(CGSWindowID window, CGRect rect);

// The text around the caret, for an input method that wants it (Wayland's text input: to offer text that depends
// on what is there and to delete text next to the caret). text is the text of the window's text input client that
// surrounds the caret, selection the caret (length 0) or the selected part in it, in UTF-16 units of text. Said
// again when it changes; NULL text says there is none. Remembered like the cursor rectangle. A backend whose input
// method does not take it (X11) ignores it. What the input method deletes comes back as
// kCGSToplevelEventInputMethodDeleteSurrounding, in UTF-16 units of the text said last; without any, the deletion is
// not reported (there is nothing to say it is about).
COREGRAPHICS_EXPORT void _CGSInputMethodSetSurroundingText(CGSWindowID window, CFStringRef text, CFRange selection);

// What kind of text the window takes, for an input method that adapts to it (a number pad for digits, no learning
// for a password). The values are those of Wayland's text input (zwp_text_input_v3), and 0 for both is plain text. A backend whose input method does not take it (X11) ignores it.
enum {
	kCGSInputMethodHintCompletion = 0x1,
	kCGSInputMethodHintSpellcheck = 0x2,
	kCGSInputMethodHintAutoCapitalization = 0x4,
	kCGSInputMethodHintLowercase = 0x8,
	kCGSInputMethodHintUppercase = 0x10,
	kCGSInputMethodHintTitlecase = 0x20,
	kCGSInputMethodHintHiddenText = 0x40,
	kCGSInputMethodHintSensitiveData = 0x80,
	kCGSInputMethodHintLatin = 0x100,
	kCGSInputMethodHintMultiline = 0x200,
};
enum {
	kCGSInputMethodPurposeNormal = 0,
	kCGSInputMethodPurposeAlpha = 1,
	kCGSInputMethodPurposeDigits = 2,
	kCGSInputMethodPurposeNumber = 3,
	kCGSInputMethodPurposePhone = 4,
	kCGSInputMethodPurposeUrl = 5,
	kCGSInputMethodPurposeEmail = 6,
	kCGSInputMethodPurposeName = 7,
	kCGSInputMethodPurposePassword = 8,
	kCGSInputMethodPurposePin = 9,
	kCGSInputMethodPurposeDate = 10,
	kCGSInputMethodPurposeTime = 11,
	kCGSInputMethodPurposeDatetime = 12,
	kCGSInputMethodPurposeTerminal = 13,
};
COREGRAPHICS_EXPORT void _CGSInputMethodSetContentType(CGSWindowID window, uint32_t hint, uint32_t purpose);

// How Wayland's text input (zwp_text_input_v3) shows through this interface: _CGSInputMethodSetEnabled is the
// text input's enable and disable for the window's surface (the UI layer enables a window whose first responder
// takes text, and disables it otherwise), and every state it sends (the cursor rectangle, the surrounding text, the
// content type) is followed by the protocol's commit request. The cursor rectangle is the surface's own, from the
// window's top left corner (a backend that has the UI layer draw the window's frame inside the surface adds
// where the content starts). The input method's events of one "done" are posted in the protocol's order: the
// surrounding text that is deleted (a composition that is showing is removed with an empty preedit first), the
// commit, then the preedit; a commit replaces the composition, so no empty preedit comes before it alone, and nothing is posted for a "done" that says what the window has been told already.
// preedit_string is kCGSToplevelEventInputMethodPreedit with its cursor_begin/cursor_end converted from bytes of
// UTF-8 to UTF-16 units (a missing cursor is the end of the text), commit_string is
// kCGSToplevelEventInputMethodCommit, and a composition the compositor took away (the window lost the text input
// focus) ends with an empty preedit.
//
// The input method only works while the window's surface has the text input focus of the compositor, which follows
// the keyboard focus.

#endif
