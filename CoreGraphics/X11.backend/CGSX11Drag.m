/* Copyright (c) 2008 Johannes Fortmann

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

// The XDND code was AppKit's X11 backend (X11DraggingManager, X11DropSession), written by Johannes Fortmann in
// 2008 and extended since; it moved here with the window system connection that it talks to.

#import "CGSX11Drag.h"
#import "CGSWindowX11.h"
#import <CoreGraphics/CGSSelection.h>
#import "CGSX11Selection.h"
#import <Foundation/Foundation.h>
#import <X11/Xatom.h>
#include <stdlib.h>

// XDND version 5: XdndFinished gained the performed flag and its action field.
static const unsigned CGSXdndVersion = 5;

// How long the source waits for the answer to the position it is dropping on, and for the target to finish with
// the data it asked for. Both are bounded: a target that never answers must not hang the drag, and a target
// that never says it is done must not keep the data alive for ever.
static const NSTimeInterval CGSXdndStatusGrace = 0.5;
static const NSTimeInterval CGSXdndFinishedGrace = 10.0;

// The operations XDND has an action atom for: a target names the one it wants, and the rest could not be named
// on the wire.
static const CGSDragOperation CGSXdndOperations =
	kCGSDragOperationCopy | kCGSDragOperationMove | kCGSDragOperationLink;

static BOOL pointerInRoot(Display* display, int* x, int* y)
{
	Window root, child;
	int windowX, windowY;
	unsigned int mask;
	return XQueryPointer(display, DefaultRootWindow(display), &root, &child, x, y, &windowX, &windowY, &mask);
}

static BOOL windowHasProperty(Display* display, Window window, Atom property, Atom type)
{
	Atom actualType;
	int format;
	unsigned long count, remaining;
	unsigned char* data = NULL;
	BOOL present = XGetWindowProperty(display, window, property, 0, 1, False, type, &actualType, &format, &count,
			&remaining, &data) == Success && actualType == type && format == 32 && count >= 1;
	if (data)
		XFree(data);
	return present;
}

// The window the XdndProxy property of the window names (the property's value, not its type), or None if the
// window has no such property.
static Window proxyOfWindow(Display* display, Window window, Atom proxyAtom)
{
	Atom actualType;
	int format;
	unsigned long count, remaining;
	unsigned char* data = NULL;
	Window proxy = None;
	if (XGetWindowProperty(display, window, proxyAtom, 0, 1, False, XA_WINDOW, &actualType, &format, &count,
			&remaining, &data) == Success && actualType == XA_WINDOW && format == 32 && count >= 1)
		proxy = (Window) ((unsigned long*) data)[0];
	if (data)
		XFree(data);
	return proxy;
}

static NSString* atomName(Display* display, Atom atom)
{
	// XdndEnter leaves the unused type slots at None; asking the server for the name of None is a BadAtom error.
	if (atom == None)
		return nil;
	char* name = XGetAtomName(display, atom);
	if (name == NULL)
		return nil;
	NSString* result = [NSString stringWithUTF8String: name];
	XFree(name);
	return result;
}

#pragma mark - An incoming drag

// One incoming XDND offer, from the XdndEnter that announced it until the drop or the XdndLeave that ends it.
@interface CGSX11DropSession : NSObject <CGSDropSession> {
	CGSX11Drag* _manager;
	CGSWindowX11* _window;
	Window _source;
	NSArray<NSString*>* _types;
	CGSDragOperation _sourceOperations;
	id<CGSSelectionEndpoint> _selection;
	BOOL _fromThisProcess;
	BOOL _entered, _dropAnnounced, _invalidated;
	CGSDragOperation _accepted;
}
-(instancetype) initWithManager:(CGSX11Drag*) manager source:(Window) source target:(CGSWindowX11*) target
		types:(NSArray<NSString*>*) types sourceOperations:(CGSDragOperation) operations;
-(BOOL) matchesSource:(Window) source;
-(CGSDragOperation) updateAtRootX:(int) rootX rootY:(int) rootY requestedActions:(CGSDragOperation) actions;
-(CGSDragOperation) performDrop;
-(void) leave;
-(void) setFromThisProcess:(BOOL) local;
@end

@implementation CGSX11DropSession

@synthesize types = _types;
@synthesize sourceOperations = _sourceOperations;
@synthesize fromThisProcess = _fromThisProcess;

-(instancetype) initWithManager:(CGSX11Drag*) manager source:(Window) source target:(CGSWindowX11*) target
		types:(NSArray<NSString*>*) types sourceOperations:(CGSDragOperation) operations
{
	if ((self = [super init]))
	{
		_manager = manager;
		_window = [target retain];
		_source = source;
		_types = [types copy];
		_sourceOperations = operations;
		// The drag is always served on the XdndSelection selection; this endpoint reads it.
		_selection = [manager->_connection newSelectionEndpointNamed: @"XdndSelection"];
		if (_selection == nil)
		{
			[self release];
			return nil;
		}
	}
	return self;
}

-(void) dealloc
{
	[_selection relinquish];
	[_selection release];
	[_window release];
	[_types release];
	[super dealloc];
}

-(void) setFromThisProcess:(BOOL) local
{
	_fromThisProcess = local;
}

-(BOOL) matchesSource:(Window) source
{
	// XDND requires a target to ignore every message that is not part of the drag it is currently holding.
	return !_invalidated && source != None && source == _source;
}

-(CGSDragOperation) updateAtRootX:(int) rootX rootY:(int) rootY requestedActions:(CGSDragOperation) actions
{
	if (_invalidated)
		return kCGSDragOperationNone;

	int windowX = 0, windowY = 0;
	Window child;
	// XDND positions are root-relative device pixels, while the destination is addressed in window coordinates.
	// A reparenting window manager inserts frames between the root and this window, so translate rather than
	// subtract.
	Display* display = _manager->_display;
	if (!XTranslateCoordinates(display, DefaultRootWindow(display), _window->_window, rootX, rootY, &windowX,
			&windowY, &child))
		return kCGSDragOperationNone;
	CGFloat scale = [_window toplevelBackingScaleFactor];
	CGPoint point = CGPointMake(windowX / scale, windowY / scale);

	// A drop already being performed owns the outcome; the source keeps sending positions while the destination
	// reads the selection, and those must not renegotiate it.
	if (_dropAnnounced)
		return kCGSDragOperationNone;

	id<CGSDragDestination> destination = [_window dragDestination];
	CGSDragOperation operation = kCGSDragOperationNone;
	if (destination != nil)
	{
		if (!_entered)
		{
			_entered = YES;
			operation = [destination dropSession: self enteredAtPoint: point];
		}
		else
			operation = [destination dropSession: self updatedAtPoint: point];
	}
	if (_invalidated)
		return kCGSDragOperationNone;

	// A source that leaves the action field empty is not refusing, it is just older than the action negotiation,
	// so fall back to everything it offers.
	if (actions == kCGSDragOperationNone)
		actions = _sourceOperations;

	// The action the source requested is the one taken when the destination allows several.
	CGSDragOperation accepted = operation;
	// One operation for the whole drag: the source draws its cursor from XdndStatus and later reports one action
	// in XdndFinished, so narrowing to a single bit keeps the three in step.
	if (accepted & actions & CGSXdndOperations)
		accepted &= actions;
	if (accepted & kCGSDragOperationCopy)
		accepted = kCGSDragOperationCopy;
	else if (accepted & kCGSDragOperationMove)
		accepted = kCGSDragOperationMove;
	else if (accepted & kCGSDragOperationLink)
		accepted = kCGSDragOperationLink;
	else
		accepted = kCGSDragOperationNone;
	_accepted = accepted;
	return accepted;
}

-(CGSDragOperation) performDrop
{
	_dropAnnounced = YES;

	CGSDragOperation performed = kCGSDragOperationNone;
	id<CGSDragDestination> destination = [_window dragDestination];
	if (!_invalidated && destination != nil)
		performed = [destination dropSession: self performWithOperation: _accepted];
	_invalidated = YES;
	return performed;
}

-(void) leave
{
	// A source may send XdndLeave as soon as it sees XdndDrop, while the transfer this session owns is still
	// running.
	if (_dropAnnounced)
		return;
	_invalidated = YES;
	if (_entered)
		[[_window dragDestination] dropSessionExited: self];
}

-(NSData*) dataForType:(NSString*) type
{
	// NSFilenamesPboardType has no X counterpart; file managers publish their files as text/uri-list.
	BOOL files = [type isEqual: @"NSFilenamesPboardType"];
	NSData* data = [_selection remoteDataForType: files ? @"text/uri-list" : type];
	if (data == nil || !files)
		return data;
	return _CGSSelectionDecodeData(data, type, @"text/uri-list");
}

@end

#pragma mark - An outgoing drag

@interface CGSX11DragSession : NSObject <CGSDragSession> {
	CGSX11Drag* _manager;
	Display* _display;
	// _selection owns the drag selection, and its helper window is the XDND source window, so the properties a
	// target reads and the data it converts are answered by one window.
	id<CGSSelectionEndpoint> _selection;
	id<CGSDragSource> _source;
	Window _window; // the window the pointer is grabbed for
	Window _dragWindow;
	// The window the last XdndEnter and XdndLeave went to, and the one whose XdndStatus is the answer the drag is
	// currently decided on.
	Window _enteredWindow, _targetWindow;
	// The window the pointer is actually over. Under a reparenting window manager that is the frame, and a
	// target reached through XdndProxy names it rather than the proxy in its replies, so it is the other window a
	// reply may name.
	Window _pointerWindow;
	Atom* _dragTypes;
	unsigned long _dragTypeCount;
	CGSDragOperation _offeredOperations, _chosenOperations;
	BOOL _localOnly; // the source allows nothing outside this application: only its windows are targets
	CGRect _suppressionRect;
	Atom _dropAction;
	int _lastX, _lastY;
	BOOL _targetAccepts, _suppressionWanted, _awaitingStatus, _dropFinished, _closed;
}
-(instancetype) initWithManager:(CGSX11Drag*) manager description:(const CGSDragDescription*) description;
-(Window) dragWindow;
-(void) handleStatus:(XClientMessageEvent*) message;
-(void) handleFinished:(XClientMessageEvent*) message;
@end

@implementation CGSX11DragSession

-(Window) dragWindow
{
	return _dragWindow;
}

// The X selection target names each type converts to, so this is both the type list a drag advertises and the
// set of names a target may ask for. Building it from the same table a SelectionRequest is answered with is what
// keeps an advertised name and the type behind it from drifting apart.
static NSArray<NSString*>* selectionTargets(NSArray<NSString*>* types)
{
	NSMutableArray<NSString*>* names = [NSMutableArray array];
	for (NSString* type in types)
		for (NSString* name in _CGSSelectionTargetsForType(type))
			if (![names containsObject: name])
				[names addObject: name];
	return names;
}

-(instancetype) initWithManager:(CGSX11Drag*) manager description:(const CGSDragDescription*) description
{
	if (!(self = [super init]))
		return nil;
	_manager = manager;
	_display = manager->_display;

	// A source that allows nothing outside this application can still be dragged within it: the drag then
	// offers what it allows within it, to this application's windows only.
	CGSDragOperation operations = description->operations & CGSXdndOperations;
	BOOL localOnly = NO;
	if (operations == kCGSDragOperationNone)
	{
		operations = description->localOperations & CGSXdndOperations;
		localOnly = operations != kCGSDragOperationNone;
	}

	NSArray<NSString*>* names = selectionTargets(description->types);
	if (operations == kCGSDragOperationNone || [names count] == 0)
	{
		NSLog(@"X11 backend: nothing to drag that XDND could describe");
		[self release];
		return nil;
	}

	// The grab goes on the window the drag started in, so its motion and button events keep arriving as the
	// connection's normal pointer events.
	CGSWindowX11* origin = (CGSWindowX11*) [manager->_connection windowForId: description->window];
	if (![origin isKindOfClass: [CGSWindowX11 class]] || origin->_window == None)
	{
		NSLog(@"X11 backend: the drag event has no window to grab the pointer on");
		[self release];
		return nil;
	}

	// XDND fixes the selection a drag is served on: a target converts XdndSelection and nothing else, so the
	// endpoint owns exactly that selection (one drag runs at a time).
	_selection = [manager->_connection newSelectionEndpointNamed: @"XdndSelection"];
	if (_selection == nil)
	{
		[self release];
		return nil;
	}
	_source = [description->source retain];
	[_selection setSource: _source];
	[_selection acquire];
	[_selection setLocalTypes: description->types];

	_dragWindow = (Window) [_selection windowHandle];
	unsigned long version = CGSXdndVersion;
	XChangeProperty(_display, _dragWindow, manager->_atom.aware, XA_ATOM, 32, PropModeReplace,
			(unsigned char*) &version, 1);
	// XdndActionList names the actions this source can perform.
	Atom actions[3];
	int actionCount = 0;
	if (operations & kCGSDragOperationCopy)
		actions[actionCount++] = manager->_atom.actionCopy;
	if (operations & kCGSDragOperationMove)
		actions[actionCount++] = manager->_atom.actionMove;
	if (operations & kCGSDragOperationLink)
		actions[actionCount++] = manager->_atom.actionLink;
	XChangeProperty(_display, _dragWindow, manager->_atom.actionList, XA_ATOM, 32, PropModeReplace,
			(unsigned char*) actions, actionCount);
	_dragTypeCount = [names count];
	_dragTypes = malloc(sizeof(Atom) * _dragTypeCount);
	for (unsigned long i = 0; i < _dragTypeCount; i++)
		_dragTypes[i] = XInternAtom(_display, [[names objectAtIndex: i] UTF8String], False);
	// The message has room for three names, and this drag has more, so a target has to read this property to see
	// the rest. Listing all of them here as well keeps a target that only reads the message from missing a type it
	// could have used.
	XChangeProperty(_display, _dragWindow, manager->_atom.typeList, XA_ATOM, 32, PropModeReplace,
			(unsigned char*) _dragTypes, _dragTypeCount);

	if (XGrabPointer(_display, origin->_window, False, ButtonReleaseMask | ButtonMotionMask | PointerMotionMask,
			GrabModeAsync, GrabModeAsync, None, None, CurrentTime) != GrabSuccess)
	{
		NSLog(@"X11 backend: cannot grab the pointer, the drag never started");
		// The drag's state is not published yet, so it is released here: the endpoint owns an X window that has
		// to go back to the server.
		[self release];
		return nil;
	}
	_window = origin->_window;

	_offeredOperations = operations;
	_localOnly = localOnly;
	manager->_drag = self;

	int rootX = 0, rootY = 0;
	pointerInRoot(_display, &rootX, &rootY);
	[self sendPositionAtRootX: rootX rootY: rootY];
	_lastX = rootX;
	_lastY = rootY;
	return self;
}

-(void) dealloc
{
	[self close];
	[super dealloc];
}

// The drag is over as soon as the state is released: the selection is given up with the window that owns it, and
// the negotiated action with the negotiation.
-(void) close
{
	if (_closed)
		return;
	_closed = YES;
	if (_manager != nil && _manager->_drag == self)
		_manager->_drag = nil;
	if (_window != None)
	{
		XUngrabPointer(_display, CurrentTime);
		XSync(_display, False);
	}
	// Releasing the endpoint destroys the source window, and a destroyed window gives up every selection it
	// owned. A target still converting gets a refusal instead of the data, which is what the protocol promises
	// it once the source has heard XdndFinished.
	[_selection setSource: nil];
	[_selection relinquish];
	[_selection release];
	_selection = nil;
	[_source release];
	_source = nil;
	_window = None;
	_dragWindow = None;
	_targetWindow = None;
	_enteredWindow = None;
	_pointerWindow = None;
	free(_dragTypes);
	_dragTypes = NULL;
	_dragTypeCount = 0;
}

-(BOOL) finished
{
	return _dropFinished;
}

-(BOOL) update
{
	if (_closed)
		return NO;
	int rootX = 0, rootY = 0;
	// One position at a time. The answer to a position says which action the target would take there, so a drag
	// that outran its target would be deciding on an answer to a place the pointer has left.
	if (_awaitingStatus || !pointerInRoot(_display, &rootX, &rootY) || (rootX == _lastX && rootY == _lastY))
		return NO;
	_lastX = rootX;
	_lastY = rootY;
	// A target's own rectangle says it needs no positions while the pointer is inside it, unless it asked for
	// them anyway.
	if (![self pointerInsideSuppressionRectAtRootX: rootX rootY: rootY])
		[self sendPositionAtRootX: rootX rootY: rootY];
	return YES;
}

-(CGSDragOperation) concludePumping:(void (^)(NSDate*)) pump
{
	if (_closed)
		return kCGSDragOperationNone;
	// A release and the answer to the position it belongs to arrive over the same connection and either can be
	// read first, so the answer is waited for before the drag decides what it did. A target that has already sent
	// XdndFinished is done with the drag and gets nothing further from it.
	if (_awaitingStatus && !_dropFinished)
	{
		NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow: CGSXdndStatusGrace];
		while (_awaitingStatus && [deadline timeIntervalSinceNow] > 0)
			pump(deadline);
	}
	if (_targetAccepts && !_dropFinished)
	{
		[self sendDrop];
		NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow: CGSXdndFinishedGrace];
		while (!_dropFinished && [deadline timeIntervalSinceNow] > 0)
			pump(deadline);
	}
	else
		[self sendLeaveTo: _enteredWindow];
	// The target's own report of what it performed is the only thing that can turn this drag into a result, and
	// only an action this source offered counts, so a target that performed nothing reports nothing.
	if (_dropAction != None)
		return [_manager operationForAction: _dropAction] & _offeredOperations;
	return kCGSDragOperationNone;
}

#pragma mark Replies

-(void) handleStatus:(XClientMessageEvent*) message
{
	// data.l[0] names the window in which the pointer was, which for a target reached through XdndProxy is the
	// frame rather than the proxy that answers.
	Window target = (Window) message->data.l[0];
	if (target == None)
		return;
	// A target the pointer has already left keeps answering positions it was sent before the pointer moved on,
	// and its answer describes a place that no longer has anything to do with where the drop would land.
	// Accepting it would let a stale target claim the drag, or clear the acceptance the target under the pointer
	// had already given.
	if (target != _enteredWindow && target != _pointerWindow)
	{
		[self sendLeaveTo: target];
		return;
	}
	_targetWindow = _enteredWindow != None ? _enteredWindow : target;
	_awaitingStatus = NO;
	if (message->data.l[1] & 1)
	{
		Atom action = (Atom) message->data.l[4];
		// A target older than version 2 accepts with an empty action field, and the protocol's default action is
		// copy.
		_chosenOperations = action != None ? [_manager operationForAction: action]
				: (_offeredOperations & kCGSDragOperationCopy);
	}
	else
		_chosenOperations = kCGSDragOperationNone;
	// A target that reports an action this source never offered has agreed to nothing, and agreeing to that would
	// be the one way a refusal could turn into a reported success.
	_chosenOperations &= _offeredOperations;
	_targetAccepts = _chosenOperations != kCGSDragOperationNone;
	long origin = message->data.l[2], size = message->data.l[3];
	_suppressionRect = CGRectMake((origin >> 16) & 0xFFFF, origin & 0xFFFF, (size >> 16) & 0xFFFF, size & 0xFFFF);
	// Bit 1 asks for positions inside the rectangle as well, which is what a destination that draws its own
	// feedback needs to stay in step.
	_suppressionWanted = (message->data.l[1] & 2) != 0;
}

-(void) handleFinished:(XClientMessageEvent*) message
{
	// Version 5 added both fields read here. A target that rejects the drop sends neither, and reading a success
	// out of an answer without them would report a drop that never happened.
	_dropAction = (message->data.l[1] & 1) ? (Atom) message->data.l[2] : None;
	_dropFinished = YES;
}

#pragma mark Sending

-(void) sendXdndMessage:(Atom) type destination:(Window) destination fields:(const long*) fields
{
	if (destination == None)
		return;
	XEvent event = {0};
	event.xclient.type = ClientMessage;
	// The window field names the window the message is about. Under a reparenting window manager that is the
	// window that carries XdndProxy, which is also the one the message is sent to, since it is the client that
	// created it.
	event.xclient.window = destination;
	event.xclient.message_type = type;
	event.xclient.format = 32;
	for (int i = 0; i < 5; i++)
		event.xclient.data.l[i] = fields[i];
	// An empty event mask sends the message to the client that created the destination window, which is the only
	// one that can act on it.
	XSendEvent(_display, destination, False, NoEventMask, &event);
	XFlush(_display);
}

-(void) sendEnterTo:(Window) target
{
	if (target == None)
		return;
	_enteredWindow = target;
	long fields[5] = { (long) _dragWindow, 1 | ((long) CGSXdndVersion << 24), 0, 0, 0 };
	for (unsigned long i = 0; i < _dragTypeCount && i < 3; i++)
		fields[2 + i] = (long) _dragTypes[i];
	[self sendXdndMessage: _manager->_atom.enter destination: target fields: fields];
}

-(void) sendPositionAtRootX:(int) rootX rootY:(int) rootY
{
	// A target is told about the drag when the pointer enters its window, so sending a position to a new one has
	// to tell it first: a target that was never sent an XdndEnter does not know a drag is happening at all.
	Window target = [self xdndAwareWindowAtRootX: rootX rootY: rootY];
	if (_localOnly && target != None && [_manager->_connection _cgsWindowForNativeWindow: target] == nil)
		target = None;
	if (target != _enteredWindow)
	{
		[self sendLeaveTo: _enteredWindow];
		_enteredWindow = None;
		[self sendEnterTo: target];
	}
	// Over a window that takes no drops there is no one to answer and nothing to wait for, and an earlier target's
	// acceptance no longer applies
	if (target == None)
	{
		_enteredWindow = _targetWindow = None;
		_targetAccepts = NO;
		_chosenOperations = kCGSDragOperationNone;
		_suppressionRect = CGRectZero;
		return;
	}
	// The position is the root-relative pointer location packed into two 16-bit halves of one word, the x
	// coordinate in the high half and y in the low half. The time is the one the target must convert the
	// selection with, and zero means the current time, which is the best this backend has: its events carry no X
	// timestamp, and a drag's selection is a window and an atom of its own, so a time could not tell this drag
	// from the next one either.
	long fields[5] = { (long) _dragWindow, 0, ((long) (rootX & 0xFFFF) << 16) | (rootY & 0xFFFF), 0,
			(long) [_manager atomForOperations: [_source dragOperationsNarrowing: _offeredOperations]] };
	[self sendXdndMessage: _manager->_atom.position destination: target fields: fields];
	_awaitingStatus = YES;
}

-(void) sendDrop
{
	// The drop goes to the target the pointer is over, which is the one whose XdndStatus said it would take the
	// drop: sending it anywhere else would offer a window that never agreed to anything.
	if (_targetWindow == None)
		return;
	// The time is the one the target converts the selection with, and zero means the current time, which is when
	// the selection was taken.
	long fields[5] = { (long) _dragWindow, 0, 0, 0, 0 };
	[self sendXdndMessage: _manager->_atom.drop destination: _targetWindow fields: fields];
}

// XdndLeave goes to the window the message is about, and names the source in data.l[0], which is how the target
// tells this apart from another client's drag.
-(void) sendLeaveTo:(Window) target
{
	if (target == None || target == _dragWindow)
		return;
	long fields[5] = { (long) _dragWindow, 0, 0, 0, 0 };
	[self sendXdndMessage: _manager->_atom.leave destination: target fields: fields];
}

-(BOOL) pointerInsideSuppressionRectAtRootX:(int) rootX rootY:(int) rootY
{
	// An empty rectangle is the protocol's way of saying "no suppression", and a target that wants a position for
	// every move says so with the flag instead.
	return !_suppressionWanted && !CGRectIsEmpty(_suppressionRect) &&
			CGRectContainsPoint(_suppressionRect, CGPointMake(rootX, rootY));
}

// The XdndProxy a window names, if it is valid: the specification says to ignore one left behind by a crashed
// client, so it has to point at itself, and the window it names has to still exist and be aware. An XID that has
// since been reused would otherwise hand the whole drag to an unrelated client.
-(Window) validProxyOf:(Window) window
{
	Window proxy = proxyOfWindow(_display, window, _manager->_atom.proxy);
	if (proxy == None)
		return None;
	XWindowAttributes attributes;
	if (!XGetWindowAttributes(_display, proxy, &attributes) ||
			proxyOfWindow(_display, proxy, _manager->_atom.proxy) != proxy)
		return None;
	return windowHasProperty(_display, proxy, _manager->_atom.aware, XA_ATOM) ? proxy : None;
}

// The window a message is about: the one under the pointer that carries XdndAware, following XdndProxy so that
// a reparenting window manager's frame resolves to the window inside it.
-(Window) xdndAwareWindowAtRootX:(int) rootX rootY:(int) rootY
{
	Window root, child;
	int windowX, windowY;
	unsigned int mask;
	if (!XQueryPointer(_display, DefaultRootWindow(_display), &root, &child, &rootX, &rootY, &windowX, &windowY,
			&mask))
		return None;
	// A target answers with the window the pointer is in, which under a reparenting window manager is the frame
	// rather than the window inside it.
	_pointerWindow = child;

	// A window manager's frame carries no XdndAware: the window that listens is inside it, at any depth (a frame
	// may wrap the client in windows of its own), so the search goes down toward the pointer, as the
	// specification describes. A window on the way may name the one that listens with XdndProxy.
	Window window = child, from = DefaultRootWindow(_display);
	for (int depth = 0; window != None && depth < 16; depth++)
	{
		if (windowHasProperty(_display, window, _manager->_atom.aware, XA_ATOM))
			return window;
		Window proxy = [self validProxyOf: window];
		if (proxy != None)
			return proxy;
		Window inner = None;
		if (!XTranslateCoordinates(_display, from, window, rootX, rootY, &windowX, &windowY, &inner))
			return None;
		from = window;
		rootX = windowX;
		rootY = windowY;
		window = inner;
	}
	return None;
}

@end

#pragma mark - The connection's drag and drop

@implementation CGSX11Drag

-(instancetype) initWithConnection:(CGSConnectionX11*) connection
{
	if ((self = [super init]))
	{
		_connection = connection;
		_display = connection->_display;
		_atom.aware = XInternAtom(_display, "XdndAware", False);
		_atom.proxy = XInternAtom(_display, "XdndProxy", False);
		_atom.enter = XInternAtom(_display, "XdndEnter", False);
		_atom.position = XInternAtom(_display, "XdndPosition", False);
		_atom.status = XInternAtom(_display, "XdndStatus", False);
		_atom.leave = XInternAtom(_display, "XdndLeave", False);
		_atom.drop = XInternAtom(_display, "XdndDrop", False);
		_atom.finished = XInternAtom(_display, "XdndFinished", False);
		_atom.selection = XInternAtom(_display, "XdndSelection", False);
		_atom.typeList = XInternAtom(_display, "XdndTypeList", False);
		_atom.actionCopy = XInternAtom(_display, "XdndActionCopy", False);
		_atom.actionMove = XInternAtom(_display, "XdndActionMove", False);
		_atom.actionLink = XInternAtom(_display, "XdndActionLink", False);
		_atom.actionList = XInternAtom(_display, "XdndActionList", False);
	}
	return self;
}

-(void) dealloc
{
	[_session release];
	[super dealloc];
}

#pragma mark Target registration

// XdndAware has to be on every top-level window that can accept a drop, and carries the highest XDND version
// this target speaks. Under a reparenting window manager the pointer sits over the frame, which belongs to the
// window manager and carries no XdndAware, so a source can only find the window that is listening through the
// frame's XdndProxy. The specification also requires the proxy to point at itself, and types the property as
// WINDOW.
-(void) windowDestinationChanged:(CGSWindowX11*) window
{
	Window handle = window->_window;
	if (handle == None)
		return;
	if ([window dragDestination] == nil)
	{
		XDeleteProperty(_display, handle, _atom.aware);
		XDeleteProperty(_display, handle, _atom.proxy);
		XFlush(_display);
		return;
	}
	unsigned long version = CGSXdndVersion;
	XChangeProperty(_display, handle, _atom.aware, XA_ATOM, 32, PropModeReplace, (unsigned char*) &version, 1);
	Window root, parent, *children = NULL;
	unsigned int count;
	if (XQueryTree(_display, handle, &root, &parent, &children, &count))
	{
		if (children)
			XFree(children);
		[self windowReparented: window intoParent: parent];
	}
	XFlush(_display);
}

-(void) windowReparented:(CGSWindowX11*) window intoParent:(Window) parent
{
	Window handle = window->_window;
	if (handle == None || parent == None || parent == DefaultRootWindow(_display) || [window dragDestination] == nil)
		return;
	XChangeProperty(_display, parent, _atom.proxy, XA_WINDOW, 32, PropModeReplace, (unsigned char*) &handle, 1);
	XChangeProperty(_display, handle, _atom.proxy, XA_WINDOW, 32, PropModeReplace, (unsigned char*) &handle, 1);
}

#pragma mark Messages

-(BOOL) handleClientMessage:(XClientMessageEvent*) message
{
	if (message->format != 32)
		return NO;
	Atom type = message->message_type;

	if (type == _atom.status || type == _atom.finished)
	{
		// The replies a target addresses to a drag's source window.
		CGSX11DragSession* drag = _drag;
		if (drag != nil && message->window == [drag dragWindow])
		{
			if (type == _atom.status)
				[drag handleStatus: message];
			else
				[drag handleFinished: message];
		}
		return YES;
	}

	if (type != _atom.position && type != _atom.drop && type != _atom.enter && type != _atom.leave)
		return NO;
	CGSWindowX11* window = [_connection _cgsWindowForNativeWindow: message->window];
	if (window == nil || [window dragDestination] == nil)
		return YES;

	if (type == _atom.position)
		[self handlePosition: message toWindow: window];
	else if (type == _atom.drop)
		[self handleDrop: message toWindow: window];
	else if (type == _atom.enter)
		[self handleEnter: message toWindow: window];
	else
	{
		// A target has to ignore messages from any source but the one it is holding a session for.
		if ([_session matchesSource: (Window) message->data.l[0]])
		{
			[_session leave];
			// The session is over (unless the leave came while a drop is being performed, which is not
			// interrupted); it must not keep its window alive.
			if (!_inDrop)
			{
				[_session release];
				_session = nil;
			}
		}
	}
	return YES;
}

#pragma mark Source properties

// The type of a type atom: XDND type names are MIME types, which the selection layer maps to the types it
// knows. File managers publish dragged files as text/uri-list, which is the X11 spelling of
// NSFilenamesPboardType.
-(NSString*) typeForAtom:(Atom) atom
{
	NSString* name = atomName(_display, atom);
	if (name == nil)
		return nil;
	if ([name isEqualToString: @"text/uri-list"])
		return @"NSFilenamesPboardType";
	return _CGSSelectionTypeForTarget(name);
}

-(NSArray<NSString*>*) typesFromEnter:(XClientMessageEvent*) message source:(Window) source
{
	NSMutableArray<NSString*>* types = [NSMutableArray array];
	for (int i = 2; i <= 4; i++)
	{
		NSString* type = [self typeForAtom: (Atom) message->data.l[i]];
		if (type)
			[types addObject: type];
	}
	// Bit 0 of data.l[1] says the three inline slots did not hold every type.
	if (message->data.l[1] & 1)
	{
		Atom type;
		int format;
		unsigned long count, remaining;
		unsigned char* data = NULL;
		if (XGetWindowProperty(_display, source, _atom.typeList, 0, 1024, False, XA_ATOM, &type, &format, &count,
				&remaining, &data) == Success && type == XA_ATOM && format == 32)
		{
			for (unsigned long i = 0; i < count; i++)
			{
				NSString* listed = [self typeForAtom: ((Atom*) data)[i]];
				if (listed)
					[types addObject: listed];
			}
		}
		if (data)
			XFree(data);
	}
	return types;
}

// The actions a source lists in XdndActionList, as drag operations.
-(CGSDragOperation) actionListOfSource:(Window) source
{
	CGSDragOperation operations = kCGSDragOperationNone;
	Atom type;
	int format;
	unsigned long count, remaining;
	unsigned char* data = NULL;
	if (XGetWindowProperty(_display, source, _atom.actionList, 0, 32, False, XA_ATOM, &type, &format, &count,
			&remaining, &data) == Success && type == XA_ATOM && format == 32)
	{
		for (unsigned long i = 0; i < count; i++)
		{
			Atom action = ((Atom*) data)[i];
			if (action == _atom.actionCopy)
				operations |= kCGSDragOperationCopy;
			else if (action == _atom.actionMove)
				operations |= kCGSDragOperationMove;
			else if (action == _atom.actionLink)
				operations |= kCGSDragOperationLink;
		}
	}
	if (data)
		XFree(data);
	return operations;
}

-(CGSDragOperation) operationsFromSource:(Window) source version:(unsigned) version
{
	// Versions 0 and 1 predate action negotiation, and their action is always copy.
	if (version < 2)
		return kCGSDragOperationCopy;
	// The specified default for a source that lists no action at all.
	CGSDragOperation operations = [self actionListOfSource: source];
	return operations != kCGSDragOperationNone ? operations : kCGSDragOperationCopy;
}

-(CGSDragOperation) operationForAction:(Atom) action
{
	if (action == _atom.actionCopy)
		return kCGSDragOperationCopy;
	if (action == _atom.actionMove)
		return kCGSDragOperationMove;
	if (action == _atom.actionLink)
		return kCGSDragOperationLink;
	// XdndActionAsk and XdndActionPrivate name actions only both ends understand, and this source offers neither,
	// so there is no operation to map them to.
	return kCGSDragOperationNone;
}

-(Atom) atomForOperations:(CGSDragOperation) operations
{
	if (operations & kCGSDragOperationCopy)
		return _atom.actionCopy;
	if (operations & kCGSDragOperationMove)
		return _atom.actionMove;
	if (operations & kCGSDragOperationLink)
		return _atom.actionLink;
	return None;
}

#pragma mark Target

-(void) handleEnter:(XClientMessageEvent*) message toWindow:(CGSWindowX11*) window
{
	Window source = (Window) message->data.l[0];
	// The protocol version is in the top byte of the word; a source newer than this target is spoken to in the
	// target's own version.
	unsigned version = (unsigned) ((message->data.l[1] >> 24) & 0xFF);
	if (version > CGSXdndVersion)
		version = CGSXdndVersion;
	// A new offer is refused while a drop is being performed, because the destination's own callbacks can pump
	// the X connection and the running session must survive.
	if (source == None || _inDrop)
		return;

	NSArray<NSString*>* types = [self typesFromEnter: message source: source];
	if ([types count] == 0)
		return;

	// A source that re-enters without leaving first would otherwise strand the destination it had already
	// entered.
	[_session leave];
	[_session release];
	_session = [[CGSX11DropSession alloc] initWithManager: self source: source target: window types: types
			sourceOperations: [self operationsFromSource: source version: version]];
	if (_drag != nil && source == [_drag dragWindow])
		[_session setFromThisProcess: YES];
}

-(void) handlePosition:(XClientMessageEvent*) message toWindow:(CGSWindowX11*) window
{
	Window source = (Window) message->data.l[0];
	CGSDragOperation accepted = kCGSDragOperationNone;
	if ([_session matchesSource: source])
	{
		// XdndPosition packs the root-relative pointer position into two 16-bit halves of one word, x in the high
		// half and y in the low half.
		long packed = message->data.l[2];
		accepted = [_session updateAtRootX: (int) ((packed >> 16) & 0xFFFF) rootY: (int) (packed & 0xFFFF)
				requestedActions: [self operationForAction: (Atom) message->data.l[4]]];
	}
	[self sendStatusTo: window source: source operations: accepted];
}

-(void) handleDrop:(XClientMessageEvent*) message toWindow:(CGSWindowX11*) window
{
	Window source = (Window) message->data.l[0];
	if (_inDrop)
		return;
	CGSDragOperation performed = kCGSDragOperationNone;
	BOOL dropped = NO;
	if ([_session matchesSource: source])
	{
		dropped = YES;
		_inDrop = YES;
		@try
		{
			performed = [_session performDrop];
		}
		@finally
		{
			_inDrop = NO;
		}
	}
	[self sendFinishedTo: window source: source operations: performed];
	// The drop ends the session, and with it the hold on its window.
	if (dropped)
	{
		[_session release];
		_session = nil;
	}
}

// Both replies are addressed to the source window, which is where the source reads them, but name this target in
// data.l[0] so it can match them against the session it started, which it may still be holding after XdndLeave.
-(void) sendStatusTo:(CGSWindowX11*) window source:(Window) source operations:(CGSDragOperation) operations
{
	Window target = window->_window;
	if (target == None || source == None)
		return;
	XEvent event = {0};
	event.xclient.type = ClientMessage;
	event.xclient.window = source;
	event.xclient.message_type = _atom.status;
	event.xclient.format = 32;
	event.xclient.data.l[0] = (long) target;
	event.xclient.data.l[1] = operations != kCGSDragOperationNone ? 1 : 0;
	// Bit 1 stays clear and the suppression rectangle is empty, which means "send a position for every mouse
	// move": a destination has to keep its feedback in step with the pointer.
	event.xclient.data.l[2] = 0;
	event.xclient.data.l[3] = 0;
	event.xclient.data.l[4] = (long) [self atomForOperations: operations];
	XSendEvent(_display, source, False, NoEventMask, &event);
	XFlush(_display);
}

-(void) sendFinishedTo:(CGSWindowX11*) window source:(Window) source operations:(CGSDragOperation) operations
{
	Window target = window->_window;
	if (target == None || source == None)
		return;
	XEvent event = {0};
	event.xclient.type = ClientMessage;
	event.xclient.window = source;
	event.xclient.message_type = _atom.finished;
	event.xclient.format = 32;
	event.xclient.data.l[0] = (long) target;
	// Version 5 added the performed flag. A source older than that assumes success on any XdndFinished, so the
	// flag only has to be truthful for a peer that negotiated version 5.
	event.xclient.data.l[1] = operations != kCGSDragOperationNone ? 1 : 0;
	event.xclient.data.l[2] = (long) [self atomForOperations: operations];
	XSendEvent(_display, source, False, NoEventMask, &event);
	XFlush(_display);
}

#pragma mark Source

-(id<CGSDragSession>) beginDragWithDescription:(const CGSDragDescription*) description
{
	if (_drag != nil)
	{
		NSLog(@"X11 backend: a drag is already running, this one never started");
		return nil;
	}
	return [[CGSX11DragSession alloc] initWithManager: self description: description];
}

@end

@implementation CGSConnectionX11 (CGSX11Drag)

-(CGSX11Drag*) _drag
{
	@synchronized (self)
	{
		if (_dragSupport == nil)
			_dragSupport = [[CGSX11Drag alloc] initWithConnection: self];
		return _dragSupport;
	}
}

-(BOOL) _dragAvailable
{
	return YES;
}

-(BOOL) _dragUsesImage
{
	return NO;
}

-(id<CGSDragSession>) _beginDrag:(const CGSDragDescription*) description
{
	return [[self _drag] beginDragWithDescription: description];
}

@end
