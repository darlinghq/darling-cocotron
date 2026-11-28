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
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <limits.h>
#include <stdatomic.h>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <math.h>
#import <CoreGraphics/CGSConnection.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <CoreGraphics/CGSWindow.h>
#import <CoreGraphics/CGSSurface.h>
#import <CoreGraphics/CGSNativeConnection.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSRaise.h>
#import <CoreGraphics/CGSScreen.h>
#import <CoreGraphics/CGDisplayConfiguration.h>
#import "CGDisplayReconfiguration.h"

// The counter the window ids of all processes come from. A window id is the window server's name for a window: it is
// the window's NSWindow number and its kCGWindowNumber, and other processes list the window under it, so two processes
// must never give the same id. The processes share a counter in a file the container keeps (it is mapped, and advanced
// with atomic operations). Without the file, a process counts on its own.
static _Atomic uint32_t* sharedWindowIDCounter(void)
{
	static _Atomic uint32_t* counter;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		int fd = open("/var/run/.cgs-window-id", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0644);
		if (fd < 0)
			return;
		struct stat st;
		if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || (st.st_size < (off_t) sizeof(uint32_t) &&
				ftruncate(fd, 4096) != 0))
		{
			close(fd);
			return;
		}
		void* memory = mmap(NULL, sizeof(uint32_t), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
		close(fd);
		if (memory != MAP_FAILED)
			counter = (_Atomic uint32_t*) memory;
	});
	return counter;
}

@implementation CGSConnection
-(CGSWindowID) _allocateWindowID
{
	_Atomic uint32_t* shared = sharedWindowIDCounter();
	if (shared == NULL)
		return _nextWindowId++;

	// 1 ... INT32_MAX; a window id stays positive when it is read as a signed number, and never repeats while the
	// counter is not exhausted.
	uint32_t last = atomic_load(shared), next;
	do
		next = last >= INT32_MAX || last == 0 ? 1 : last + 1;
	while (!atomic_compare_exchange_weak(shared, &last, next));
	return next;
}

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

-(NSArray<CGSWindow*>*) copyAllWindows
{
	@synchronized(_windows)
	{
		return [[_windows allValues] retain];
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
	[_screens release];
	[_cursor release];
	[_reportedScreens release];
	[_windows release];
	[super dealloc];
}

+(BOOL) isAvailable
{
	NSInvalidAbstractInvocation();
}

+(CGError) activateWindowsOfProcess:(pid_t)pid options:(uint32_t)options
{
	return kCGErrorNotImplemented;
}

+(CGError) copyFrontProcessID:(pid_t*)pid
{
	return kCGErrorNotImplemented;
}

// A backend that can read the window system's keymap overrides this; nil means it has no layout.
-(CGSKeyboardLayout*) createKeyboardLayout
{
	return nil;
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

-(BOOL) setMode:(NSDictionary *)mode forScreen:(int)screenIndex
{
	return NO;
}

-(NSArray<CGSScreen*>*) buildScreens
{
	NSInvalidAbstractInvocation();
}

-(NSArray<CGSScreen*>*) createScreens
{
	@synchronized (self)
	{
		if (_screens == nil)
		{
			_screens = [[self buildScreens] retain];
			// The first look at the displays is what later changes are measured against.
			if (_reportedScreens == nil && _screens != nil)
				_reportedScreens = [_screens retain];
		}
		return [_screens retain];
	}
}

-(void) invalidateScreens
{
	@synchronized (self)
	{
		[_screens release];
		_screens = nil;
	}
}

-(CGError) warpPointerToPoint:(CGPoint)point
{
	return kCGErrorCannotComplete;
}

-(BOOL) managesPointer
{
	return NO;
}

-(void) hideCursor
{
	@synchronized (self)
	{
		if (_pointerHideCount < INT_MAX)
			_pointerHideCount++;
	}
	[self cursorHiddenStateChanged: YES];
}

-(void) unhideCursor
{
	BOOL shown = NO;
	@synchronized (self)
	{
		if (_pointerHideCount > 0)
			shown = --_pointerHideCount == 0;
	}
	if (shown)
		[self cursorHiddenStateChanged: NO];
}

-(void) forceShowCursor
{
	BOOL shown;
	@synchronized (self)
	{
		shown = _pointerHideCount > 0;
		_pointerHideCount = 0;
	}
	if (shown)
		[self cursorHiddenStateChanged: NO];
}

-(void) setCursor:(CGSCursor*)cursor
{
	@synchronized (self)
	{
		if (cursor != _cursor)
		{
			[cursor retain];
			[_cursor release];
			_cursor = cursor;
		}
	}
	[self cursorChanged];
}

-(CGSCursor*) cursor
{
	@synchronized (self)
	{
		return [[_cursor retain] autorelease];
	}
}

-(void) cursorChanged
{
}

-(BOOL) cursorIsVisible
{
	@synchronized (self)
	{
		return _pointerHideCount == 0;
	}
}

-(void) setMouseAssociatedWithCursor:(BOOL)associated
{
	@synchronized (self)
	{
		_pointerDisassociated = !associated;
	}
	[self mouseAssociationChanged: associated];
}

-(BOOL) mouseAssociated
{
	@synchronized (self)
	{
		return !_pointerDisassociated;
	}
}

// Whole units are taken; the fraction stays for the next call.
-(void) takeMouseDeltaX:(int32_t*)dx y:(int32_t*)dy
{
	double wholeX, wholeY;
	@synchronized (self)
	{
		wholeX = _pointerDeltaX < 0 ? ceil(_pointerDeltaX) : floor(_pointerDeltaX);
		wholeY = _pointerDeltaY < 0 ? ceil(_pointerDeltaY) : floor(_pointerDeltaY);
		_pointerDeltaX -= wholeX;
		_pointerDeltaY -= wholeY;
	}
	if (dx != NULL)
		*dx = (int32_t) wholeX;
	if (dy != NULL)
		*dy = (int32_t) wholeY;
}

-(void) accumulateMouseDeltaX:(double)dx y:(double)dy
{
	@synchronized (self)
	{
		_pointerDeltaX += dx;
		_pointerDeltaY += dy;
	}
}

-(void) cursorHiddenStateChanged:(BOOL)hidden
{
}

-(void) mouseAssociationChanged:(BOOL)associated
{
}

// After CGWarpMouseCursorPosition() with the mouse connected to the cursor, the local mouse motion is dropped for
// CGSetLocalEventsSuppressionInterval() seconds (the motion still counts for CGGetLastMouseDelta()).
-(void) noteMouseWarp
{
	double interval = _CGSLocalEventsSuppressionInterval();
	@synchronized (self)
	{
		_pointerSuppressUntil = interval > 0 ? CFAbsoluteTimeGetCurrent() + interval : 0;
	}
}

-(BOOL) localMouseMotionSuppressed
{
	@synchronized (self)
	{
		if (_pointerSuppressUntil <= 0)
			return NO;
		if (CFAbsoluteTimeGetCurrent() < _pointerSuppressUntil)
			return YES;
		_pointerSuppressUntil = 0;
		return NO;
	}
}

-(BOOL) relativeMouseState:(BOOL*)requested frozenRoot:(CGPoint*)frozenRoot
{
	if (requested != NULL)
		*requested = NO;
	return NO;
}

-(BOOL) carriesApplicationMenuAddress
{
	return NO;
}

-(BOOL) placesMenuBar
{
	return NO;
}

-(BOOL) globalMenuAvailable
{
	@synchronized (self)
	{
		return _globalMenuAvailable;
	}
}

-(void) setGlobalMenuAvailable:(BOOL) available
{
	@synchronized (self)
	{
		_globalMenuAvailable = available;
	}
}

-(void) pointerWindowsChanged
{
}

-(void) selectTouchInputOnNativeWindow:(unsigned long)window
{
}

-(BOOL) displaySleepPrevented
{
	return NO;
}

-(id) waylandColorManager
{
	return nil;
}

-(id) waylandRenderManager
{
	return nil;
}

-(BOOL) extendedDynamicRangeAvailable
{
	return NO;
}

-(BOOL) cancelsHiddenUntilMouseMoves
{
	return NO;
}

-(void) setCursorHiddenUntilMouseMoves:(BOOL)flag
{
	@synchronized (self)
	{
		if (_pointerHiddenUntilMouseMoves == flag)
			return;
		_pointerHiddenUntilMouseMoves = flag;
	}
	if (flag)
		[self hideCursor];
	else
		[self unhideCursor];
}

-(void) pointerDidMove
{
	BOOL pending;
	@synchronized (self)
	{
		pending = _pointerHiddenUntilMouseMoves;
		_pointerHiddenUntilMouseMoves = NO;
	}
	if (pending)
		[self unhideCursor];
}

-(BOOL) pointerLocked
{
	return NO;
}

-(void) pointerLockTargetMayHaveChanged
{
}

-(BOOL) isDisplayOverlayNativeWindow:(void*)nativeWindow
{
	return NO;
}

static CGSScreen* screenWithID(NSArray<CGSScreen*>* screens, CGDirectDisplayID displayID)
{
	for (CGSScreen* screen in screens)
	{
		if (screen.displayID == displayID)
			return screen;
	}
	return nil;
}

// What a display's change is called to the reconfiguration callbacks; 0 when it stayed as it was.
// A nil side is a display that was not there.
static CGDisplayChangeSummaryFlags changeFlags(CGSScreen* before, CGSScreen* after, BOOL becameMain)
{
	if (before == nil)
		return kCGDisplayAddFlag | (becameMain ? kCGDisplaySetMainFlag : 0);
	if (after == nil)
		return kCGDisplayRemoveFlag;

	CGDisplayChangeSummaryFlags flags = 0;
	if (!CGPointEqualToPoint(before.bounds.origin, after.bounds.origin))
		flags |= kCGDisplayMovedFlag;
	if (!CGSizeEqualToSize(before.bounds.size, after.bounds.size) || before.backingScale != after.backingScale ||
		![before.currentModeDictionary isEqual: after.currentModeDictionary])
		flags |= kCGDisplaySetModeFlag | kCGDisplayDesktopShapeChangedFlag;
	if (becameMain)
		flags |= kCGDisplaySetMainFlag;
	return flags;
}

-(BOOL) changeMode:(NSDictionary *)mode forScreen:(int)screenIndex
{
	_suppressLayoutReports++;
	BOOL changed = [self setMode: mode forScreen: screenIndex];
	if (changed)
		[self acceptDisplayLayout];
	_suppressLayoutReports--;
	return changed;
}

-(void) displayLayoutChanged
{
	NSArray<CGSScreen*>* before;
	NSArray<CGSScreen*>* after;

	if (_suppressLayoutReports > 0)
	{
		[self invalidateScreens];
		return;
	}

	@synchronized (self)
	{
		[self invalidateScreens];
		before = [_reportedScreens retain];
		after = [self createScreens];
		// A change before the displays were first read has nothing to be compared with.
		if (before != nil)
		{
			[_reportedScreens release];
			_reportedScreens = [after retain];
		}
	}

	if (before != nil)
	{
		CGDirectDisplayID oldMain = [before count] > 0 ? before[0].displayID : kCGNullDirectDisplay;
		CGDirectDisplayID newMain = [after count] > 0 ? after[0].displayID : kCGNullDirectDisplay;
		NSMutableArray<NSNumber*>* ids = [NSMutableArray array];
		NSMutableArray<NSNumber*>* flagsList = [NSMutableArray array];

		for (CGSScreen* screen in before)
			[ids addObject: @(screen.displayID)];
		for (CGSScreen* screen in after)
		{
			if (screenWithID(before, screen.displayID) == nil)
				[ids addObject: @(screen.displayID)];
		}
		for (NSNumber* number in ids)
		{
			CGDirectDisplayID displayID = [number unsignedIntValue];
			BOOL becameMain = displayID == newMain && displayID != oldMain;
			[flagsList addObject: @(changeFlags(screenWithID(before, displayID), screenWithID(after, displayID), becameMain))];
		}
		// Every changed display gets the begin notification, then all of them the summary.
		for (NSUInteger i = 0; i < [ids count]; i++)
		{
			if ([flagsList[i] unsignedIntValue] != 0)
				CGDisplayPostReconfiguration([ids[i] unsignedIntValue], kCGDisplayBeginConfigurationFlag);
		}
		for (NSUInteger i = 0; i < [ids count]; i++)
		{
			if ([flagsList[i] unsignedIntValue] != 0)
				CGDisplayPostReconfiguration([ids[i] unsignedIntValue], [flagsList[i] unsignedIntValue]);
		}
	}
	[before release];
	[after release];
}

-(void) acceptDisplayLayout
{
	@synchronized (self)
	{
		[self invalidateScreens];
		NSArray<CGSScreen*>* now = [self createScreens];
		[_reportedScreens release];
		_reportedScreens = now;
	}
}

-(CGSWindow*) newWindow:(CGSRegionRef)region
{
	NSInvalidAbstractInvocation();
}

-(CGSWindow*) newToplevelWindowWithAttributes:(const CGSToplevelAttributes*)attributes
{
	return nil;
}

-(BOOL) supportsTranslucentToplevels
{
	return NO;
}

-(NSArray<NSNumber*>*) orderedToplevelWindowIDs
{
	return @[];
}

-(void*) nativeDisplay
{
	NSInvalidAbstractInvocation();
}

// The observer is not retained: it is the framework's display, which lives as long as the process.
static void* g_nativeObserver;

+(int) nativeConnectionKind
{
	return 0;
}

+(id) nativeObserver
{
	return (id) __atomic_load_n(&g_nativeObserver, __ATOMIC_ACQUIRE);
}

+(void) setNativeObserver:(id)observer
{
	__atomic_store_n(&g_nativeObserver, (void*) observer, __ATOMIC_RELEASE);
}

-(void) processPendingEvents
{
}

-(void*) keyboardFocus
{
	return NULL;
}

-(uint64_t) modifierFlags
{
	return 0;
}

-(uint64_t) hardwareModifierFlags
{
	return [self modifierFlags];
}

-(void) nativeObjectDestroyed:(void*)object
{
}

-(void) flushPendingKeyboardEvents
{
}

-(void*) nativePointer
{
	return NULL;
}

-(void) setPointerSurfacePointX:(double)x y:(double)y
{
}

-(int) keyboardLayoutGroup
{
	return -1;
}

-(NSString*) keyboardLayoutName
{
	return nil;
}

-(void) activationRequested
{
	id<CGSNativeConnectionObserver> observer = [CGSConnection nativeObserver];
	if ([observer respondsToSelector: @selector(nativeConnectionActivationRequested)])
		[observer nativeConnectionActivationRequested];
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
