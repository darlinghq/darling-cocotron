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

// Global key grabs of the X11 backend: a key with modifiers is grabbed on the
// root window, so its presses and releases reach this connection wherever the
// keyboard focus is. Plain C on Xlib (no CoreGraphics, no Objective-C), so that
// tests/x11-hotkey-grab.c can build this file natively and run it on an Xvfb.
//
// A passive grab is exclusive in X11: while one client holds a key and
// modifier combination, another client's attempt fails with BadAccess. The
// grab is also made for every combination of the lock modifiers (Caps Lock
// and Num Lock), because X11 matches the modifier state exactly and a hot
// key must work whatever the locks are.

#ifndef X11HOTKEY_H
#define X11HOTKEY_H

#include <pthread.h>
#include <stdbool.h>
#include <X11/Xlib.h>

enum
{
	// The modifiers that take part in matching a hot key. Caps Lock (LockMask)
	// and Num Lock (Mod2Mask on the usual keymaps) never do.
	X11HotKeyRelevantMask = ShiftMask | ControlMask | Mod1Mask | Mod4Mask,
};

typedef enum
{
	X11HotKeyGrabbed = 0,
	X11HotKeyGrabBusy,      // another client holds the combination
	X11HotKeyGrabFailed,    // some other X error
} X11HotKeyGrabResult;

// The modifier mask of a hot key. The Command key is Mod4 (Super) and Option is
// Mod1 (Alt), as everywhere in the X11 backends.
static inline unsigned X11HotKeyModifiers(bool shift, bool control, bool option, bool command)
{
	return (shift ? ShiftMask : 0) | (control ? ControlMask : 0) | (option ? Mod1Mask : 0) | (command ? Mod4Mask : 0);
}

// Whether a key event's state selects the hot key with the given modifiers
static inline bool X11HotKeyMatches(unsigned eventState, unsigned hotKeyModifiers)
{
	return (eventState & X11HotKeyRelevantMask) == hotKeyModifiers;
}

static const unsigned x11HotKeyLockVariants[4] = { 0, LockMask, Mod2Mask, LockMask | Mod2Mask };

// Xlib reports a failed request later and process-wide, so the grab swaps in
// an error handler for the duration of a synchronised request.
static pthread_mutex_t x11HotKeyErrorLock = PTHREAD_MUTEX_INITIALIZER;
static Display* x11HotKeyErrorDisplay;
static int x11HotKeyErrorCode;
static XErrorHandler x11HotKeyPreviousHandler;

static int X11HotKeyErrorHandler(Display* display, XErrorEvent* event)
{
	if (display == x11HotKeyErrorDisplay)
	{
		if (x11HotKeyErrorCode == 0)
			x11HotKeyErrorCode = event->error_code;
		return 0;
	}
	return x11HotKeyPreviousHandler ? x11HotKeyPreviousHandler(display, event) : 0;
}

// Grabs keycode with modifiers (and its lock variants) on the root window.
// Either every variant is grabbed or none is.
static inline X11HotKeyGrabResult X11HotKeyGrab(Display* display, int keycode, unsigned modifiers)
{
	Window root = DefaultRootWindow(display);
	X11HotKeyGrabResult result = X11HotKeyGrabbed;

	pthread_mutex_lock(&x11HotKeyErrorLock);
	x11HotKeyErrorDisplay = display;
	x11HotKeyErrorCode = 0;
	x11HotKeyPreviousHandler = XSetErrorHandler(X11HotKeyErrorHandler);

	for (int i = 0; i < 4; i++)
		XGrabKey(display, keycode, modifiers | x11HotKeyLockVariants[i], root, False, GrabModeAsync, GrabModeAsync);
	XSync(display, False);

	if (x11HotKeyErrorCode != 0)
	{
		result = x11HotKeyErrorCode == BadAccess ? X11HotKeyGrabBusy : X11HotKeyGrabFailed;
		// The variants that were granted
		for (int i = 0; i < 4; i++)
			XUngrabKey(display, keycode, modifiers | x11HotKeyLockVariants[i], root);
		XSync(display, False);
	}

	XSetErrorHandler(x11HotKeyPreviousHandler);
	x11HotKeyErrorDisplay = NULL;
	pthread_mutex_unlock(&x11HotKeyErrorLock);
	return result;
}

static inline void X11HotKeyUngrab(Display* display, int keycode, unsigned modifiers)
{
	Window root = DefaultRootWindow(display);

	for (int i = 0; i < 4; i++)
		XUngrabKey(display, keycode, modifiers | x11HotKeyLockVariants[i], root);
	XFlush(display);
}

#endif
