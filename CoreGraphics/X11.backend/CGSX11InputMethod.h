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

#import <Foundation/NSObject.h>
#import <CoreGraphics/CGGeometry.h>
#import "CGSConnectionX11.h"
#import <X11/Xlib.h>

@class CGSWindowX11;

// The process' connection to the X input method (XIM): the input method is opened when the first window uses
// it, and its input contexts are the windows' (see CGSX11InputContext). See CGSInputMethod.h for what the UI
// layer sees of it.
@interface CGSX11InputMethod : NSObject {
@public
	Display* _display;
	XIM _xim;
	BOOL _opened;     // an attempt to open the input method was made
	BOOL _composes;   // XMODIFIERS names an input method other than Xlib's own
}

-(instancetype) initWithDisplay:(Display*) display;

// The input method, opened on first use; NULL when none could be opened, not even Xlib's own.
-(XIM) xim;
// Whether an input method of the application composes dead keys and Compose sequences, filtering the key events
// and returning the text. Xlib's built-in input method does not count: it composes too, but drops the keys of a
// sequence that no entry of the Compose table continues. NO until a window has used the input method.
-(BOOL) composes;

@end

// The input context of a window: the input method's state for the windows' text, which the window keeps for as
// long as it uses the input method, also when its X window is made again.
@interface CGSX11InputContext : NSObject {
@public
	CGSWindowX11* _window; // Not retained; the window owns this.
	CGSX11InputMethod* _method;
	XIC _ic;
	// Whether the input method shows its composition through the callbacks (on-the-spot preedit, drawn by the
	// application) with the callbacks and the composition's code points and caret.
	BOOL _onTheSpot;
	XIMCallback _callbacks[4];
	NSMutableData* _preedit;
	int _caret;
}

-(instancetype) initWithWindow:(CGSWindowX11*) window method:(CGSX11InputMethod*) method;

// Makes the input context for the window's X window (when there is none, or the X window has changed), and
// destroys it again before the X window goes. The composition is dropped with it.
-(void) create;
-(void) destroy;
// The window got or lost the keyboard focus; the context takes it when it is made while the window holds it.
-(void) setFocused:(BOOL) focused;
// Tells the input method where the text is being entered (the window's cursor rectangle).
-(void) updateSpot;
// The text a key press makes as the input method composes it; nil when the window has no input context.
-(NSString*) textForKeyEvent:(XKeyEvent*) event keySym:(KeySym*) keySym;

@end
