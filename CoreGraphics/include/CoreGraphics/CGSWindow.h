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
#ifndef CGSWINDOW_H
#define CGSWINDOW_H
#import <Foundation/NSObject.h>
#import <Foundation/NSDictionary.h>
#include <CoreGraphics/CoreGraphicsPrivate.h>
#include <stdatomic.h>

@class CGSSurface;
@class CGSConnection;

@interface CGSWindow : NSObject {
	CGSConnection* _connection;
	CGSWindowID _windowId;
	_Atomic CGSSurfaceID _nextSurfaceId;
	NSMutableDictionary<NSNumber*, CGSSurface*>* _surfaces;
}

-(instancetype) initWithRegion:(CGSRegionRef) region
						connection:(CGSConnection*) connection
						windowID:(CGSWindowID) windowID;
-(void) dealloc;
-(CGSSurface*) surfaceForId:(CGSSurfaceID) surfaceId;

-(CGError) orderWindow:(CGSWindowOrderingMode) place relativeTo:(CGSWindow*) window;
-(CGError) moveTo:(const CGPoint*) point;
-(CGError) setRegion:(CGSRegionRef) region;
-(CGError) getRect:(CGRect*) outRect;
-(CGError) setProperty:(CFStringRef) key value:(CFTypeRef) value;
-(CGError) getProperty:(CFStringRef) key value:(CFTypeRef*) value;
-(void) invalidate;

// Used, for example, by CGWindowContextCreate()
-(void*) nativeWindow;
-(CGSSurface*) createSurface;

@property (readonly) CGSWindowID windowId;

-(void) _surfaceInvalidated:(CGSSurfaceID) surfaceId;

@end

#endif
