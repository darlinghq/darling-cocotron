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

#import <CoreGraphics/CGSDrag.h>
#import <CoreGraphics/CGSConnection.h>
#import <CoreGraphics/CGSWindow.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <CoreGraphics/CGSServerSPI.h>
#import <Foundation/Foundation.h>

// What a connection that has drag and drop offers. A backend without any leaves the base class' answer, which is
// that it has none.
@interface CGSConnection (CGSDragBackend)
- (BOOL) _dragAvailable;
- (BOOL) _dragUsesImage;
- (id<CGSDragSession>) _beginDrag: (const CGSDragDescription*) description;
@end

static CGSConnection* dragConnection(void)
{
	CGSConnectionID connId = CGSMainConnectionID();
	return connId != 0 ? _CGSConnectionForID(connId) : nil;
}

BOOL _CGSDragAvailable(void)
{
	CGSConnection* connection = dragConnection();
	return [connection respondsToSelector: @selector(_dragAvailable)] && [connection _dragAvailable];
}

BOOL _CGSDragUsesImage(void)
{
	CGSConnection* connection = dragConnection();
	return [connection respondsToSelector: @selector(_dragUsesImage)] && [connection _dragUsesImage];
}

id<CGSDragSession> _CGSDragBegin(const CGSDragDescription* description)
{
	CGSConnection* connection = dragConnection();
	if (description == NULL || !_CGSDragAvailable())
		return nil;
	return [connection _beginDrag: description];
}

void _CGSDragSetDestination(CGSWindowID window, id<CGSDragDestination> destination)
{
	CGSConnection* connection = dragConnection();
	if (!_CGSDragAvailable())
		return;
	[[connection windowForId: window] setDragDestination: destination];
}
