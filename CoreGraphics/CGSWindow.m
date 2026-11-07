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
#import <Foundation/NSRaise.h>
#import <CoreGraphics/CGWindow.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSValue.h>

const CFStringRef kCGSWindowTitle = CFSTR("WindowTitle");

@implementation CGSWindow
@synthesize windowId = _windowId;

- (instancetype) initWithRegion: (CGSRegionRef) region
                     connection: (CGSConnection *) connection
                       windowID: (CGSWindowID) windowID
{
    _connection = connection;
    _nextSurfaceId = 1;
    _surfaces = [[NSMutableDictionary alloc] initWithCapacity: 1];
    _windowId = windowID;
    return self;
}

- (void) dealloc {
    [_surfaces release];
    [super dealloc];
}

- (CGSSurface *) surfaceForId: (CGSSurfaceID) surfaceId {
    CGSSurface *rv;
    @synchronized(_surfaces) {
        rv = [_surfaces objectForKey: [NSNumber numberWithInt: surfaceId]];
    }
    return rv;
}

- (void) _surfaceInvalidated: (CGSSurfaceID) surfaceId {
    @synchronized(_surfaces) {
        [_surfaces removeObjectForKey: [NSNumber numberWithInt: surfaceId]];
    }
}

- (void) invalidate {
    [_connection _windowInvalidated: _windowId];
}

- (CGError) orderWindow: (CGSWindowOrderingMode) place
             relativeTo: (CGSWindow *) window
{
    NSInvalidAbstractInvocation();
}

- (CGError) moveTo: (const CGPoint *) point {
    NSInvalidAbstractInvocation();
}

- (CGError) setRegion: (CGSRegionRef) region {
    NSInvalidAbstractInvocation();
}

- (CGError) getRect: (CGRect *) outRect {
    NSInvalidAbstractInvocation();
}

- (CGError) setProperty: (CFStringRef) key value: (CFTypeRef) value {
    NSInvalidAbstractInvocation();
}

- (CGError) getProperty: (CFStringRef) key value: (CFTypeRef *) value {
    NSInvalidAbstractInvocation();
}

- (CGSSurface *) createSurface {
    NSInvalidAbstractInvocation();
}

- (void *) nativeWindow {
    NSInvalidAbstractInvocation();
}

@end

CGError CGSSetWindowTitle(CGSConnectionID cid, CGSWindowID wid,
                          CFStringRef title)
{
    return CGSSetWindowProperty(cid, wid, kCGSWindowTitle, title);
}

static NSArray<NSDictionary *> *copyAllWindowDescriptions(void) {
    CGSConnection *connection = _CGSConnectionForID(CGSDefaultConnection);

    return connection ? [connection copyWindowDescriptions]
                      : [[NSArray alloc] init];
}

static CGWindowID windowNumberOf(NSDictionary *description) {
    return [[description objectForKey: (NSString *) kCGWindowNumber]
            unsignedIntValue];
}

// The descriptions the option and the reference window select, front to back.
static NSMutableArray<NSDictionary *> *
copySelectedWindowDescriptions(CGWindowListOption option,
                               CGWindowID relativeToWindow)
{
    NSArray<NSDictionary *> *all = copyAllWindowDescriptions();
    NSMutableArray<NSDictionary *> *selected = [[NSMutableArray alloc] init];
    NSUInteger referenceIndex = NSNotFound;
    BOOL above = (option & kCGWindowListOptionOnScreenAboveWindow) != 0;
    BOOL below = (option & kCGWindowListOptionOnScreenBelowWindow) != 0;
    BOOL including = (option & kCGWindowListOptionIncludingWindow) != 0;
    BOOL onScreenOnly =
            (option & kCGWindowListOptionOnScreenOnly) != 0 || above || below;

    if (relativeToWindow != kCGNullWindowID) {
        for (NSUInteger i = 0; i < [all count]; i++) {
            if (windowNumberOf([all objectAtIndex: i]) == relativeToWindow) {
                referenceIndex = i;
                break;
            }
        }
    }

    // With a reference window that does not exist, the relative options
    // select nothing.
    if ((above || below || including) && referenceIndex == NSNotFound) {
        [all release];
        return selected;
    }

    for (NSUInteger i = 0; i < [all count]; i++) {
        NSDictionary *window = [all objectAtIndex: i];
        BOOL isReference = i == referenceIndex;
        BOOL include;

        if (above)
            include = i < referenceIndex || (including && isReference);
        else if (below)
            include = i > referenceIndex || (including && isReference);
        else if (including)
            include = isReference;
        else
            include = YES;

        if (include && onScreenOnly && !isReference &&
            ![[window objectForKey: (NSString *) kCGWindowIsOnscreen] boolValue])
            include = NO;

        if (include)
            [selected addObject: window];
    }

    [all release];
    return selected;
}

CFArrayRef __nullable CGWindowListCopyWindowInfo(CGWindowListOption option,
                                                 CGWindowID relativeToWindow)
{
    return (CFArrayRef) copySelectedWindowDescriptions(option,
                                                       relativeToWindow);
}

CFArrayRef __nullable CGWindowListCreate(CGWindowListOption option, CGWindowID relativeToWindow)
{
    NSArray<NSDictionary *> *selected =
            copySelectedWindowDescriptions(option, relativeToWindow);
    CFMutableArrayRef numbers =
            CFArrayCreateMutable(NULL, [selected count], NULL);

    // Like the window server, a plain array of CGWindowID values.
    for (NSDictionary *window in selected)
        CFArrayAppendValue(numbers,
                           (const void *) (uintptr_t) windowNumberOf(window));

    [selected release];
    return numbers;
}

CFArrayRef __nullable CGWindowListCreateDescriptionFromArray(CFArrayRef windowArray)
{
    if (windowArray == NULL)
        return NULL;

    NSArray<NSDictionary *> *all = copyAllWindowDescriptions();
    NSMutableArray<NSDictionary *> *descriptions = [[NSMutableArray alloc] init];

    // The array holds CGWindowID values, as CGWindowListCreate() returns
    // them. Windows that no longer exist are left out.
    for (CFIndex i = 0; i < CFArrayGetCount(windowArray); i++) {
        CGWindowID number =
                (CGWindowID) (uintptr_t) CFArrayGetValueAtIndex(windowArray, i);

        for (NSDictionary *window in all) {
            if (windowNumberOf(window) == number) {
                [descriptions addObject: window];
                break;
            }
        }
    }

    [all release];
    return (CFArrayRef) descriptions;
}

CGImageRef __nullable CGWindowListCreateImage(CGRect screenBounds,
                                              CGWindowListOption listOption,
                                              CGWindowID windowID,
                                              CGWindowImageOption imageOption)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

