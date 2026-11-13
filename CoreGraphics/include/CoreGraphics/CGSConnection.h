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
#include <CoreGraphics/CGSServerSPI.h>
#include <CoreGraphics/CGEventTypes.h>
#include <CoreGraphics/CoreGraphicsPrivate.h>
#include <stdatomic.h>

@class CGSWindow;
@class CGSScreen;
@class CGSKeyboardLayout;

@interface CGSConnection : NSObject {
	CGSConnectionID _connectionId;
	_Atomic CGSWindowID _nextWindowId;
	NSMutableDictionary<NSNumber*, CGSWindow*>* _windows;
	_Atomic int _hotKeyOperatingMode;
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

// Global hot keys, behind CGSSetHotKeyWithExclusion() and the rest of that family. A hot
// key is a virtual key code with modifier flags (the kCGEventFlagMask{Shift,Control,
// Alternate,Command} bits; the others are ignored), identified by a uid the caller chooses,
// whose presses and releases are reported wherever the keyboard focus is: each calls
// -postHotKeyEventForUID:pressed:flags:location:time: on the main run loop, which delivers it as a
// system-defined event (see CGSSetHotKeyWithExclusion in CoreGraphicsPrivate.h). Autorepeat
// produces no extra presses. A uid set again replaces the old hot key. A hot key that
// cannot be set up (another client holds the combination, no such key on this system) is not
// stored: -getHotKeyWithUID:... then returns NO. A hot key reports only while it is enabled and
// the global operating mode is 0. The default implementations store nothing.
-(void) setHotKeyWithUID:(int)uid keyCode:(CGKeyCode)keyCode flags:(CGEventFlags)flags exclusion:(int)exclusion;
-(BOOL) getHotKeyWithUID:(int)uid keyCode:(CGKeyCode*)outKeyCode flags:(CGEventFlags*)outFlags;
-(void) removeHotKeyWithUID:(int)uid;
-(BOOL) isHotKeyEnabledWithUID:(int)uid;
-(void) setHotKeyWithUID:(int)uid enabled:(BOOL)enabled;
// 0: hot keys are reported, 1: none is, 2: none is (the hot keys of universal access are
// the exception on macOS, and this system has none). Other values are illegal arguments.
-(CGError) getGlobalHotKeyOperatingMode:(int*)outMode;
-(CGError) setGlobalHotKeyOperatingMode:(int)mode;
// For backends: the operating mode has changed
-(void) hotKeyOperatingModeChanged;
// For backends: a hot key was pressed or released. flags, location (CG global coordinates) and
// time (nanoseconds since startup) are those of the key event (the time is when it was seen).
-(void) postHotKeyEventForUID:(int)uid pressed:(BOOL)pressed flags:(CGEventFlags)flags location:(CGPoint)location time:(uint64_t)time;

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

