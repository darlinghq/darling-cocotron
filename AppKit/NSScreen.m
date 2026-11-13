/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

// Original - Christopher Lloyd <cjwl@objc.net>
#import <AppKit/NSApplication.h>
#import <AppKit/NSColorSpace.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSWindow.h>
#include <math.h>

NSNotificationName const NSScreenColorSpaceDidChangeNotification = @"NSScreenColorSpaceDidChangeNotification";

@implementation NSScreen

- initWithFrame: (NSRect) frame visibleFrame: (NSRect) visibleFrame {
    _frame = frame;
    _visibleFrame = visibleFrame;
    return self;
}

- (void) dealloc {
    if (_edid)
        [_edid release];
    [super dealloc];
}

+ (NSScreen *) mainScreen {
    NSScreen *result = [[NSApp keyWindow] screen];

    if (result == nil)
        result = [[self screens] objectAtIndex: 0];

    return result;
}

+ (NSArray *) screens {
    return [[NSDisplay currentDisplay] screens];
}

- (NSWindowDepth) depth {
    return _depth;
}

- (NSRect) frame {
    return _frame;
}

- (NSRect) visibleFrame {
    return _visibleFrame;
}

- (CGFloat) userSpaceScaleFactor {
    return 1.0;
}

// Backends whose displays have more than one device pixel per point (the X11
// backend, with a configured scale) override this.
- (CGFloat) backingScaleFactor {
    return 1.0;
}

// No ICC profile is read from the display, so the screen is described as sRGB.
- (NSColorSpace *) colorSpace {
    return [NSColorSpace sRGBColorSpace];
}

- (NSString *) localizedName {
    return [NSString stringWithFormat: @"Display %u",
                                       (unsigned) [self cgDirectDisplayID]];
}

// Screens are driven as standard dynamic range: no component value above 1.0
// is displayable, and reference rendering is not supported.
- (CGFloat) maximumExtendedDynamicRangeColorComponentValue {
    return 1.0;
}

- (CGFloat) maximumPotentialExtendedDynamicRangeColorComponentValue {
    return 1.0;
}

- (CGFloat) maximumReferenceExtendedDynamicRangeColorComponentValue {
    return 0.0;
}

// No screen here has a camera housing or any other region the system reserves
// along an edge, so no part of the frame is unsafe and there are no usable
// areas beside a cut-out.
- (NSEdgeInsets) safeAreaInsets {
    return NSEdgeInsetsMake(0, 0, 0, 0);
}

- (NSRect) auxiliaryTopLeftArea {
    return NSZeroRect;
}

- (NSRect) auxiliaryTopRightArea {
    return NSZeroRect;
}

// The refresh rate of the screen's current mode, as the backend reports it, or
// 60 Hz when it reports none. Displays have a fixed rate here, so the minimum
// and maximum intervals are the same.
- (NSTimeInterval) _refreshInterval {
    NSDisplay *display = [NSDisplay currentDisplay];
    double rate = 0;

    if ([display respondsToSelector: @selector(currentModeForScreen:)]) {
        NSDictionary *mode = [display
                currentModeForScreen: (int) [self cgDirectDisplayID] - 1];
        rate = [[mode objectForKey: @"RefreshRate"] doubleValue];
    }
    if (!(rate > 0))
        rate = 60.0;
    return 1.0 / rate;
}

- (NSTimeInterval) minimumRefreshInterval {
    return [self _refreshInterval];
}

- (NSTimeInterval) maximumRefreshInterval {
    return [self _refreshInterval];
}

// The highest frame rate the screen supports, rounded to a whole number of
// frames; it is the reciprocal of the shortest refresh interval.
- (NSInteger) maximumFramesPerSecond {
    return (NSInteger) lround(1.0 / [self minimumRefreshInterval]);
}

// Screens here refresh at a fixed rate, so an update can only take effect on a
// frame boundary and the granularity is one refresh interval.
- (NSTimeInterval) displayUpdateGranularity {
    return [self minimumRefreshInterval];
}

- (id) description {
    return [NSString stringWithFormat: @"< %@ - frame %@, visible %@ >",
                                       [super description],
                                       NSStringFromRect(_frame),
                                       NSStringFromRect(_visibleFrame)];
}

- (NSDictionary<NSDeviceDescriptionKey, id> *) deviceDescription {
    // AppKit clients use this documented string key to obtain the same display
    // ID used by CoreGraphics and assigned by the window-system backend.
    // The other keys describe the screen as a drawing device: its size in
    // points, 72 dpi per backing scale unit, and 8-bit RGB.
    CGFloat dpi = 72.0 * [self backingScaleFactor];
    return @{
        @"NSScreenNumber" :
                [NSNumber numberWithUnsignedInt: [self cgDirectDisplayID]],
        NSDeviceSize : [NSValue valueWithSize: _frame.size],
        NSDeviceResolution : [NSValue valueWithSize: NSMakeSize(dpi, dpi)],
        NSDeviceIsScreen : @"YES",
        NSDeviceColorSpaceName : NSCalibratedRGBColorSpace,
        NSDeviceBitsPerSample : @8,
    };
}

@end

@implementation NSScreen (Darling)
- (NSData *) edid {
    return self->_edid;
}

- (void) setEdid: (NSData *) data {
    NSData *old = self->_edid;
    self->_edid = [data retain];
    [old release];
}

- (CGDirectDisplayID) cgDirectDisplayID {
    return self->_directDisplayID;
}

- (void) setCgDirectDisplayID: (CGDirectDisplayID) displayID {
    self->_directDisplayID = displayID;
}

@end
