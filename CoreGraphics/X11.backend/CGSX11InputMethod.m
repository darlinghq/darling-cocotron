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

#import "CGSX11InputMethod.h"
#import "CGSWindowX11.h"
#import <CoreGraphics/CGSWindow.h>
#import <Foundation/Foundation.h>
#include <math.h>
#include <string.h>
#include <wchar.h>

// Whether the locale modifiers (XMODIFIERS, as XSetLocaleModifiers("") returns them) name an input method other
// than Xlib's own: "@im=none" and "@im=local" are the built-in one, and so is no @im at all.
static BOOL modifiersNameInputMethod(const char* modifiers)
{
	const char* name = modifiers != NULL ? strstr(modifiers, "@im=") : NULL;
	if (name == NULL)
		return NO;
	name += 4;
	size_t length = strcspn(name, "@");
	if (length == 0)
		return NO;
	return !(length == 4 && strncmp(name, "none", 4) == 0) && !(length == 5 && strncmp(name, "local", 5) == 0);
}

@implementation CGSX11InputMethod

-(instancetype) initWithDisplay:(Display*) display
{
	if ((self = [super init]) != nil)
		_display = display;
	return self;
}

-(void) dealloc
{
	if (_xim != NULL)
		XCloseIM(_xim);
	[super dealloc];
}

-(XIM) xim
{
	if (!_opened)
	{
		_opened = YES;
		const char* modifiers = XSetLocaleModifiers("");
		_xim = XOpenIM(_display, NULL, NULL, NULL);
		_composes = _xim != NULL && modifiersNameInputMethod(modifiers);

		if (_xim == NULL)
		{
			NSLog(@"Failed to open XIM, falling back to im=none\n");

			XSetLocaleModifiers("@im=none");
			_xim = XOpenIM(_display, NULL, NULL, NULL);
		}
	}
	return _xim;
}

-(BOOL) composes
{
	return _composes;
}

@end

// Whether the input method offers the on-the-spot preedit style: it then reports the composition through
// callbacks and the application draws it itself.
static BOOL inputMethodHasPreeditCallbacks(XIM xim)
{
	XIMStyles* styles = NULL;
	BOOL found = NO;

	if (xim == NULL)
		return NO;
#if defined(DARLING) && defined(__arm64__)
	// Variadic: called through a non-variadic prototype on arm64, see createInputContext().
	char* failed = ((char* (*)(XIM, const char*, void*, void*)) XGetIMValues)(xim, XNQueryInputStyle, &styles, NULL);
#else
	char* failed = XGetIMValues(xim, XNQueryInputStyle, &styles, NULL);
#endif
	if (failed != NULL || styles == NULL)
		return NO;
	for (unsigned short i = 0; i < styles->count_styles; i++)
	{
		if (styles->supported_styles[i] == (XIMPreeditCallbacks | XIMStatusNothing))
			found = YES;
	}
	XFree(styles);
	return found;
}

// Sets the preedit attribute list `list` on the context. Returns whether Xlib accepted it.
static BOOL setPreeditAttributes(XIC ic, XVaNestedList list)
{
#if defined(DARLING) && defined(__arm64__)
	char* failed = ((char* (*)(XIC, const char*, void*, void*)) XSetICValues)(ic, XNPreeditAttributes, list, NULL);
#else
	char* failed = XSetICValues(ic, XNPreeditAttributes, list, NULL);
#endif
	XFree(list);
	return failed == NULL;
}

// The preedit attribute list that gives the four callbacks of the on-the-spot style.
static XVaNestedList preeditCallbackList(XIMCallback callbacks[4])
{
#if defined(DARLING) && defined(__arm64__)
	// Variadic, see createInputContext() below.
	return ((XVaNestedList (*)(int, const char*, void*, const char*, void*, const char*, void*, const char*, void*, void*))
		XVaCreateNestedList)(0, XNPreeditStartCallback, &callbacks[0], XNPreeditDoneCallback, &callbacks[1],
		XNPreeditDrawCallback, &callbacks[2], XNPreeditCaretCallback, &callbacks[3], NULL);
#else
	return XVaCreateNestedList(0, XNPreeditStartCallback, &callbacks[0], XNPreeditDoneCallback, &callbacks[1],
		XNPreeditDrawCallback, &callbacks[2], XNPreeditCaretCallback, &callbacks[3], NULL);
#endif
}

// An input context for the window. With an input method that supports on-the-spot preedit the composition is
// delivered through the callbacks in `callbacks` (client data: the context); otherwise the input method shows its
// own preedit and status.
static XIC createInputContext(XIM xim, Window window, XIMCallback callbacks[4], BOOL* onTheSpot)
{
	XIC ic = NULL;

	*onTheSpot = NO;
	if (inputMethodHasPreeditCallbacks(xim))
	{
		// Xlib takes the preedit callbacks only when the context is created: setting them afterwards is refused
		// (XSetICValues() names XNPreeditAttributes as the failed attribute), which leaves a context whose
		// composition nobody shows.
		XVaNestedList list = preeditCallbackList(callbacks);
#if defined(DARLING) && defined(__arm64__)
		// XCreateIC() is variadic and lives in the native (Linux) libX11. Darwin arm64 passes variadic arguments on
		// the stack, Linux arm64 in registers, so call it through a non-variadic prototype: the arguments that do
		// not fit the registers are on the stack in both.
		ic = ((XIC (*)(XIM, const char*, long, const char*, Window, const char*, Window, const char*, void*, void*)) XCreateIC)(
			xim,
			XNInputStyle, (long) (XIMPreeditCallbacks | XIMStatusNothing),
			XNClientWindow, window,
			XNFocusWindow, window,
			XNPreeditAttributes, list,
			NULL);
#else
		ic = XCreateIC(xim,
			XNInputStyle, (long) (XIMPreeditCallbacks | XIMStatusNothing),
			XNClientWindow, window,
			XNFocusWindow, window,
			XNPreeditAttributes, list,
			NULL);
#endif
		XFree(list);
		if (ic != NULL)
		{
			*onTheSpot = YES;
			return ic;
		}
	}

	// Without the callbacks the composition would be invisible: use the input method's own.
#if defined(DARLING) && defined(__arm64__)
	return ((XIC (*)(XIM, const char*, long, const char*, Window, const char*, Window, void*)) XCreateIC)(
		xim,
		XNInputStyle, (long) (XIMPreeditNothing | XIMStatusNothing),
		XNClientWindow, window,
		XNFocusWindow, window,
		NULL);
#else
	return XCreateIC(xim,
		XNInputStyle, (long) (XIMPreeditNothing | XIMStatusNothing),
		XNClientWindow, window,
		XNFocusWindow, window,
		NULL);
#endif
}

// The composition is held as the code points the input method sent: its draw callback replaces a range of
// characters, counted in characters, not UTF-16 units.

static int preeditStartCallback(XIC ic, XPointer clientData, XPointer callData)
{
	// The composition may be any length.
	return -1;
}

static void preeditDoneCallback(XIC ic, XPointer clientData, XPointer callData)
{
	[(CGSX11InputContext*) clientData preeditDone];
}

static void preeditDrawCallback(XIC ic, XPointer clientData, XPointer callData)
{
	XIMPreeditDrawCallbackStruct* draw = (XIMPreeditDrawCallbackStruct*) callData;
	NSString* text = nil;

	if (draw == NULL)
		return;
	if (draw->text != NULL)
	{
		if (draw->text->encoding_is_wchar)
		{
			// wchar_t is 32 bits wide on the host the library runs on.
			const wchar_t* wide = draw->text->string.wide_char;
			if (wide != NULL)
				text = [[[NSString alloc] initWithBytes: wide
				                                 length: wcslen(wide) * sizeof(wchar_t)
				                               encoding: NSUTF32LittleEndianStringEncoding] autorelease];
		}
		else if (draw->text->string.multi_byte != NULL)
		{
			// The locale's multi-byte encoding is UTF-8, as for Xutf8LookupString().
			text = [NSString stringWithUTF8String: draw->text->string.multi_byte];
		}
	}
	[(CGSX11InputContext*) clientData preeditReplaceCharactersFrom: draw->chg_first
	                                                        length: draw->chg_length
	                                                      withText: text ?: @""
	                                                         caret: draw->caret];
}

static void preeditCaretCallback(XIC ic, XPointer clientData, XPointer callData)
{
	XIMPreeditCaretCallbackStruct* caret = (XIMPreeditCaretCallbackStruct*) callData;

	if (caret != NULL)
		[(CGSX11InputContext*) clientData preeditMoveCaretTo: caret->position direction: caret->direction];
}

@interface CGSX11InputContext ()
-(void) preeditReplaceCharactersFrom:(int) first length:(int) length withText:(NSString*) text caret:(int) caret;
-(void) preeditMoveCaretTo:(int) position direction:(XIMCaretDirection) direction;
-(void) preeditDone;
@end

@implementation CGSX11InputContext

-(instancetype) initWithWindow:(CGSWindowX11*) window method:(CGSX11InputMethod*) method
{
	if ((self = [super init]) != nil)
	{
		_window = window;
		_method = [method retain];
	}
	return self;
}

-(void) dealloc
{
	[self destroy];
	[_method release];
	[_preedit release];
	[super dealloc];
}

-(void) create
{
	if (_ic != NULL || _window->_window == None)
		return;
	XIM xim = [_method xim];
	if (xim == NULL)
		return;

	_callbacks[0] = (XIMCallback) { (XPointer) self, (XIMProc) preeditStartCallback };
	_callbacks[1] = (XIMCallback) { (XPointer) self, (XIMProc) preeditDoneCallback };
	_callbacks[2] = (XIMCallback) { (XPointer) self, (XIMProc) preeditDrawCallback };
	_callbacks[3] = (XIMCallback) { (XPointer) self, (XIMProc) preeditCaretCallback };
	_ic = createInputContext(xim, _window->_window, _callbacks, &_onTheSpot);
	if (_ic == NULL)
		return;
	// A window that holds the keyboard focus already got its FocusIn before it had an input context.
	Window focused = None;
	int revert;
	XGetInputFocus(_window->_display, &focused, &revert);
	if (focused == _window->_window)
	{
		XSetICFocus(_ic);
		[self updateSpot];
	}
}

-(void) destroy
{
	// _ic is NULL when there is no input method; XDestroyIC() doesn't accept NULL.
	if (_ic != NULL)
	{
		XDestroyIC(_ic);
		_ic = NULL;
	}
	[_preedit setLength: 0];
	_caret = 0;
	_onTheSpot = NO;
}

-(void) setFocused:(BOOL) focused
{
	if (_ic == NULL)
		return;
	if (focused)
	{
		XSetICFocus(_ic);
		[self updateSpot];
	}
	else
		XUnsetICFocus(_ic);
}

// Gives the input method the spot where the client's composition is, so that it places its candidate window
// there.
-(void) updateSpot
{
	if (_ic == NULL || !_onTheSpot)
		return;

	CGRect rect = [_window inputMethodCursorRect];
	if (CGRectIsNull(rect) || CGRectEqualToRect(rect, CGRectZero))
		return;

	CGFloat scale = [_window toplevelBackingScaleFactor];
	// The bottom-left corner of the caret rectangle: the baseline side, in X's device pixels.
	XPoint point = { (short) lround(rect.origin.x * scale), (short) lround((rect.origin.y + rect.size.height) * scale) };
	// Only some styles take a spot; the error for one that does not is of no interest.
#if defined(DARLING) && defined(__arm64__)
	XVaNestedList list = ((XVaNestedList (*)(int, const char*, void*, void*))
		XVaCreateNestedList)(0, XNSpotLocation, &point, NULL);
#else
	XVaNestedList list = XVaCreateNestedList(0, XNSpotLocation, &point, NULL);
#endif
	setPreeditAttributes(_ic, list);
}

-(NSString*) textForKeyEvent:(XKeyEvent*) keyEvent keySym:(KeySym*) keySym
{
	if (_ic == NULL)
		return nil;

	char buf[64];
	char* text = buf;
	KeySym symbol = NoSymbol;
	Status status;
	int length = Xutf8LookupString(_ic, (XKeyPressedEvent*) keyEvent, buf, sizeof(buf) - 1, &symbol, &status);
	if (status == XBufferOverflow)
	{
		// Composed and input method text can be longer than buf. Nothing was copied and length is the size needed;
		// Xlib says to repeat the lookup with a large enough buffer.
		char* larger = malloc(length + 1);
		if (larger != NULL)
		{
			text = larger;
			length = Xutf8LookupString(_ic, (XKeyPressedEvent*) keyEvent, text, length, &symbol, &status);
		}
	}
	// The text and the keysym are only valid for the statuses that report them.
	if ((status != XLookupChars && status != XLookupBoth) || length < 0)
		length = 0;
	if (status != XLookupKeySym && status != XLookupBoth)
		symbol = NoSymbol;
	NSString* result = [[[NSString alloc] initWithBytes: text length: length encoding: NSUTF8StringEncoding] autorelease];
	if (text != buf)
		free(text);
	*keySym = symbol;
	return result != nil ? result : @"";
}

#pragma mark - Composition

-(NSString*) preeditString
{
	NSUInteger count = [_preedit length] / sizeof(uint32_t);

	if (count == 0)
		return @"";
	return [[[NSString alloc] initWithBytes: [_preedit bytes]
	                                 length: count * sizeof(uint32_t)
	                               encoding: NSUTF32LittleEndianStringEncoding] autorelease];
}

// The caret as a UTF-16 offset in the composition string.
-(NSUInteger) preeditCaretUTF16Offset
{
	const uint32_t* chars = [_preedit bytes];
	NSUInteger count = [_preedit length] / sizeof(uint32_t);
	NSUInteger offset = 0;

	for (NSUInteger i = 0; i < (NSUInteger) _caret && i < count; i++)
		offset += chars[i] > 0xFFFF ? 2 : 1;
	return offset;
}

// Tells the window's UI layer what is composed now (empty: nothing).
-(void) postPreedit
{
	NSString* text = [self preeditString];
	CGSToplevelEvent event = {
		.kind = kCGSToplevelEventInputMethodPreedit,
		.rect = CGRectNull,
		.text = (CFStringRef) text,
		.textRange = CFRangeMake((CFIndex) [self preeditCaretUTF16Offset], 0),
	};
	[_window postToplevelEvent: &event];
}

-(void) preeditReplaceCharactersFrom:(int) first length:(int) length withText:(NSString*) text caret:(int) caret
{
	NSData* incoming = [text dataUsingEncoding: NSUTF32LittleEndianStringEncoding];
	NSUInteger count = [_preedit length] / sizeof(uint32_t);

	if (_preedit == nil)
		_preedit = [[NSMutableData alloc] init];
	// The server's range is trusted only as far as it lies in the string.
	if (first < 0 || (NSUInteger) first > count)
		first = (int) count;
	if (length < 0 || (NSUInteger) (first + length) > count)
		length = (int) (count - first);
	[_preedit replaceBytesInRange: NSMakeRange(first * sizeof(uint32_t), length * sizeof(uint32_t))
	                    withBytes: [incoming bytes]
	                       length: [incoming length]];
	count = [_preedit length] / sizeof(uint32_t);
	_caret = caret < 0 ? 0 : ((NSUInteger) caret > count ? (int) count : caret);
	[self postPreedit];
}

-(void) preeditMoveCaretTo:(int) position direction:(XIMCaretDirection) direction
{
	switch (direction)
	{
	case XIMForwardChar:
		position = _caret + 1;
		break;
	case XIMBackwardChar:
		position = _caret - 1;
		break;
	case XIMAbsolutePosition:
		break;
	default:
		return; // Word and line moves: the caret stays where the last draw put it.
	}
	NSUInteger count = [_preedit length] / sizeof(uint32_t);
	_caret = position < 0 ? 0 : ((NSUInteger) position > count ? (int) count : position);
	[self postPreedit];
}

// The composition ended, by commit or by cancel; the committed text, if any, arrives as a key event and
// replaces nothing that is still marked.
-(void) preeditDone
{
	[_preedit setLength: 0];
	_caret = 0;
	[self postPreedit];
}

@end

// The connection's input method.
@implementation CGSConnectionX11 (CGSX11InputMethodSupport)

-(BOOL) _inputMethodAvailable
{
	return YES;
}

-(CGSX11InputMethod*) _inputMethod
{
	if (_inputMethodSupport == nil)
		_inputMethodSupport = [[CGSX11InputMethod alloc] initWithDisplay: _display];
	return _inputMethodSupport;
}

-(BOOL) _inputMethodComposes
{
	return [_inputMethodSupport composes];
}

@end
