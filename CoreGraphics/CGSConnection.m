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
#import <CoreGraphics/CGSConnection.h>
#import <CoreGraphics/CGSWindow.h>
#import <CoreGraphics/CGSSurface.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSRaise.h>

@implementation CGSConnection
-(instancetype) initWithConnectionID:(CGSConnectionID)connId
{
	_nextWindowId = 1;
	_connectionId = connId;
	_windows = [[NSMutableDictionary alloc] initWithCapacity: 1];
	return self;
}

-(CGSWindow*) windowForId:(CGSWindowID)winId
{
	@synchronized(_windows)
	{
		return [_windows objectForKey: [NSNumber numberWithInt: winId]];
	}
}

-(void) _windowInvalidated: (CGSWindowID) winId
{
	@synchronized(_windows)
	{
		[_windows removeObjectForKey: [NSNumber numberWithInt: winId]];
	}
}

-(void) dealloc
{
	[_windows release];
	[super dealloc];
}

+(BOOL) isAvailable
{
	NSInvalidAbstractInvocation();
}

-(CGSKeyboardLayout*) createKeyboardLayout
{
	NSInvalidAbstractInvocation();
}

-(CGPoint) mouseLocation
{
	NSInvalidAbstractInvocation();
}

-(BOOL) isKeyDown:(CGKeyCode)keyCode
{
	return NO;
}

-(BOOL) isMouseButtonDown:(CGMouseButton)button
{
	return NO;
}

extern void _CGSPostHotKeyEvent(CGSConnectionID connection, int uid, BOOL pressed, CGEventFlags flags, CGPoint location, uint64_t time);

-(void) setHotKeyWithUID:(int)uid keyCode:(CGKeyCode)keyCode flags:(CGEventFlags)flags exclusion:(int)exclusion
{
}

-(BOOL) getHotKeyWithUID:(int)uid keyCode:(CGKeyCode*)outKeyCode flags:(CGEventFlags*)outFlags
{
	return NO;
}

-(void) removeHotKeyWithUID:(int)uid
{
}

-(BOOL) isHotKeyEnabledWithUID:(int)uid
{
	return NO;
}

-(void) setHotKeyWithUID:(int)uid enabled:(BOOL)enabled
{
}

-(CGError) getGlobalHotKeyOperatingMode:(int*)outMode
{
	if (!outMode)
		return kCGErrorIllegalArgument;
	*outMode = _hotKeyOperatingMode;
	return kCGErrorSuccess;
}

-(CGError) setGlobalHotKeyOperatingMode:(int)mode
{
	if (mode < 0 || mode > 2)
		return kCGErrorIllegalArgument;
	_hotKeyOperatingMode = mode;
	[self hotKeyOperatingModeChanged];
	return kCGErrorSuccess;
}

-(void) hotKeyOperatingModeChanged
{
}

-(void) postHotKeyEventForUID:(int)uid pressed:(BOOL)pressed flags:(CGEventFlags)flags location:(CGPoint)location time:(uint64_t)time
{
	_CGSPostHotKeyEvent(_connectionId, uid, pressed, flags, location, time);
}

-(NSArray *) modesForScreen:(int)screenIndex
{
	NSInvalidAbstractInvocation();
}

-(BOOL) setMode:(NSDictionary *)mode forScreen:(int)screenIndex
{
	NSInvalidAbstractInvocation();
}

-(NSDictionary*) currentModeForScreen:(int)screenIndex
{
	NSInvalidAbstractInvocation();
}

-(CGSWindow*) newWindow:(CGSRegionRef)region
{
	NSInvalidAbstractInvocation();
}

-(void*) nativeDisplay
{
	NSInvalidAbstractInvocation();
}

-(NSArray<NSDictionary*>*) copyWindowDescriptions
{
	return [[NSArray alloc] init];
}

-(CGError) destroyWindow:(CGSWindowID)winId
{
	CGSWindow* win = [self windowForId: winId];
	if (win == nil)
		return kCGErrorIllegalArgument;
	[win invalidate];

	@synchronized (_windows)
	{
		[_windows removeObjectForKey: [NSNumber numberWithInt: winId]];
	}
	return kCGSErrorSuccess;
}

@end
