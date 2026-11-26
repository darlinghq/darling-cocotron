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
#import "CGSConnectionX11.h"
#import <X11/Xlib.h>

@class CGSX11DragSession, CGSX11DropSession;

// XDND (version 5), both halves, on the process' connection: the target half advertises the windows that have a
// drag destination as drop targets and answers the ClientMessages a source sends them; the source half runs the
// drags that _CGSDragBegin() starts: it owns the drag's selection (the data goes through the selection layer of
// CGSSelection.h), holds the pointer and sends XdndEnter, XdndPosition, XdndDrop and XdndLeave until the target
// it is talking to is done with the drag. See CGSDrag.h for what the UI layer sees of it.
@interface CGSX11Drag : NSObject {
@public
	CGSConnectionX11* _connection; // Not retained; the connection owns this.
	Display* _display;
	struct {
		Atom aware, proxy, enter, position, status, leave, drop, finished;
		Atom selection, typeList, actionCopy, actionMove, actionLink, actionList;
	} _atom;
	CGSX11DragSession* _drag; // The drag this process runs, nil when there is none. Not retained.
@private
	CGSX11DropSession* _session;
	BOOL _inDrop;
}

-(instancetype) initWithConnection:(CGSConnectionX11*) connection;

// A window got or lost its drag destination, or has a new X window: it is (not any more) a target.
-(void) windowDestinationChanged:(CGSWindowX11*) window;
// A window was reparented (a window manager's frame came or went): the frame has to point at it.
-(void) windowReparented:(CGSWindowX11*) window intoParent:(Window) parent;
// An event of the connection. Returns YES when it was drag and drop's (an XDND message).
-(BOOL) handleClientMessage:(XClientMessageEvent*) message;

-(id<CGSDragSession>) beginDragWithDescription:(const CGSDragDescription*) description;

-(CGSDragOperation) operationForAction:(Atom) action;
-(Atom) atomForOperations:(CGSDragOperation) operations;

@end

@interface CGSConnectionX11 (CGSX11Drag)
// The connection's drag and drop, made on first use.
-(CGSX11Drag*) _drag;
@end
