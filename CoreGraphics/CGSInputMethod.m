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

#import <CoreGraphics/CGSInputMethod.h>
#import <CoreGraphics/CGSConnection.h>
#import <CoreGraphics/CGSWindow.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <CoreGraphics/CGSServerSPI.h>
#import <Foundation/Foundation.h>

// What a connection that has an input method offers. A backend without one leaves the base class' answer, which
// is that it has none.
@interface CGSConnection (CGSInputMethodBackend)
- (BOOL) _inputMethodAvailable;
@end

static CGSConnection* inputMethodConnection(void)
{
	CGSConnectionID connId = CGSMainConnectionID();
	return connId != 0 ? _CGSConnectionForID(connId) : nil;
}

BOOL _CGSInputMethodAvailable(void)
{
	CGSConnection* connection = inputMethodConnection();
	return [connection respondsToSelector: @selector(_inputMethodAvailable)] && [connection _inputMethodAvailable];
}

void _CGSInputMethodSetEnabled(CGSWindowID window, BOOL enabled)
{
	if (!_CGSInputMethodAvailable())
		return;
	[[inputMethodConnection() windowForId: window] setInputMethodEnabled: enabled];
}

void _CGSInputMethodSetSurroundingText(CGSWindowID window, CFStringRef text, CFRange selection)
{
	if (!_CGSInputMethodAvailable())
		return;
	[[inputMethodConnection() windowForId: window] setInputMethodSurroundingText: (NSString*) text selection: selection];
}

void _CGSInputMethodSetContentType(CGSWindowID window, uint32_t hint, uint32_t purpose)
{
	if (!_CGSInputMethodAvailable())
		return;
	[[inputMethodConnection() windowForId: window] setInputMethodContentHint: hint purpose: purpose];
}

void _CGSInputMethodSetCursorRect(CGSWindowID window, CGRect rect)
{
	if (!_CGSInputMethodAvailable())
		return;
	[[inputMethodConnection() windowForId: window] setInputMethodCursorRect: rect];
}
