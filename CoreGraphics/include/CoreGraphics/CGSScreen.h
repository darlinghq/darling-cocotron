/*
 This file is part of Darling.

 Copyright (C) 2020 Lubos Dolezel

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
#ifndef CGSSCREEN_H
#define CGSSCREEN_H
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSData.h>
#import <Foundation/NSString.h>
#include <CoreGraphics/CGDirectDisplay.h>
#include <CoreGraphics/CGGeometry.h>

// One active display, as a connection's backend describes it (see -[CGSConnection createScreens]).
@interface CGSScreen : NSObject {
	NSData* _edid;
	NSArray<NSDictionary*>* _modes;
	CFIndex _currentMode;
	CGDirectDisplayID _displayID;
	CGRect _bounds;
	CGFloat _backingScale;
	NSString* _name;
	NSDictionary* _colorInfo;
}

// The display's CGDirectDisplayID. The backend ties it to the output it drives, so it does not
// change when other displays come and go.
@property(readwrite, assign) CGDirectDisplayID displayID;
// The display's rectangle in CoreGraphics' global space, in points: the origin is the main
// display's top-left corner and y points down, so a display above the main one has a negative y.
@property(readwrite, assign) CGRect bounds;
// Device pixels per point. At least 1.
@property(readwrite, assign) CGFloat backingScale;
// The name the window system gives the output (a description or connector name), or nil. It is
// only used when the display has no EDID that names the monitor.
@property(readwrite, copy) NSString* name;
// The output's color description from the window system (see the kCGSDisplayColor* keys in
// CoreGraphicsPrivate.h), or nil when it is unknown.
@property(readwrite, copy) NSDictionary* colorInfo;
@property(readwrite, strong) NSData* edid;
// The modes the display can be set to. A mode has Width and Height in points, PixelWidth and
// PixelHeight in device pixels, Depth and RefreshRate (Hz, 0 when unknown).
@property(readwrite, strong) NSArray<NSDictionary*>* modes;
// The index in modes of the mode the display is in. -1 when modes does not list it.
@property(readwrite, assign) CFIndex currentMode;

// The mode the display is in, or nil.
@property(readonly) NSDictionary* currentModeDictionary;

@end

#endif

