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
#ifndef CGSCONNECTION_H
#define CGSCONNECTION_H
#import <Foundation/NSObject.h>
#import <Foundation/NSDictionary.h>
#include <CoreGraphics/CoreGraphicsPrivate.h>
#include <stdatomic.h>

@class CGSWindow;
@class CGSScreen;
@class CGSKeyboardLayout;

@interface CGSConnection : NSObject {
	CGSConnectionID _connectionId;
	_Atomic CGSWindowID _nextWindowId;
	NSMutableDictionary<NSNumber*, CGSWindow*>* _windows;
}
-(instancetype) initWithConnectionID:(CGSConnectionID)connId;
-(void) dealloc;
-(CGSWindow*) windowForId:(CGSWindowID)winId;
-(CGSWindow*) newWindow:(CGSRegionRef)region;
-(CGError) destroyWindow:(CGSWindowID)winId;

// The windows of Darling processes, front to back, each described with the
// kCGWindow* keys of CGWindowListCopyWindowInfo(). Only the caller's own
// windows carry kCGWindowName. The default implementation knows no windows.
-(NSArray<NSDictionary*>*) copyWindowDescriptions;

// Mouse location in CG coordinates, i.e. relative to the upper left corner
-(CGPoint) mouseLocation;

// Hardware state of a key (a virtual key code) and of a mouse button. The
// default implementation reports them as up.
-(BOOL) isKeyDown:(CGKeyCode)keyCode;
-(BOOL) isMouseButtonDown:(CGMouseButton)button;

-(BOOL) setMode:(NSDictionary *)mode forScreen:(int)screenIndex;
// Implementations should cache this information, because it may be accessed frequently
-(NSArray<CGSScreen*>*) createScreens;

// Implementations should also emit kTISNotifySelectedKeyboardInputSourceChanged via NSDistributedNotificationCenter
// if layout changes.
// Implementations should also cache this and return the same pointer if nothing changed.
-(CGSKeyboardLayout*) createKeyboardLayout;

+(BOOL) isAvailable;

-(void) _windowInvalidated: (CGSWindowID) winId;

// For CGL
-(void*) nativeDisplay;
@end

#endif

