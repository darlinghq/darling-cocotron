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
#import <AppKit/NSWindow-Private.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#include <math.h>

NSNotificationName const NSScreenColorSpaceDidChangeNotification = @"NSScreenColorSpaceDidChangeNotification";

// Shared with the Wayland window backend; kept out of AppKit's public header.
@interface NSScreen (WaylandColorDescription)
+ (NSColorSpace *) _colorSpaceFromDisplayColorInfo: (NSDictionary *) info;
@end

// The color description CoreGraphics read from the window system, as an autoreleased NSDictionary.
static NSDictionary *screenColorInfo(NSScreen *screen) {
    CFDictionaryRef info = _CGSDisplayCopyColorInfo([screen cgDirectDisplayID]);

    return [(NSDictionary *) info autorelease];
}

static NSNumber *screenColorNumber(NSDictionary *info, CFStringRef key) {
    id value = info != nil ? [info objectForKey: (id) key] : nil;

    return [value isKindOfClass: [NSNumber class]] ? value : nil;
}

static uint32_t screenColorEnum(NSDictionary *info, CFStringRef key, uint32_t fallback) {
    NSNumber *value = screenColorNumber(info, key);

    return value != nil ? [value unsignedIntValue] : fallback;
}

static CGFloat screenColorLuminance(NSDictionary *info, CFStringRef key, CGFloat fallback) {
    NSNumber *value = screenColorNumber(info, key);

    return value != nil ? [value doubleValue] : fallback;
}

// The chromaticity array of a parametric description, or NULL when it did not report one. The
// compositor sends each CIE 1931 xy coordinate multiplied by one million.
static NSArray *screenColorChromaticity(NSDictionary *info, CFStringRef key) {
    NSArray *values = [info objectForKey: (id) key];
    if (![values isKindOfClass: [NSArray class]] || [values count] != 8)
        return nil;
    for (id value in values)
        if (![value isKindOfClass: [NSNumber class]])
            return nil;
    return values;
}

static BOOL screenColorChromaticityIs(NSDictionary *info, CFStringRef key,
                                      const int32_t *expected, int32_t tolerance) {
    NSArray *values = screenColorChromaticity(info, key);
    if (values == nil)
        return NO;
    for (size_t i = 0; i < 8; i++)
        if (ABS([[values objectAtIndex: i] intValue] - expected[i]) > tolerance)
            return NO;
    return YES;
}

// A named space is preferred when the compositor said which one the output uses. A parametric
// description with no name is matched against the chromaticities of the spaces CoreGraphics knows;
// the matching is deliberately approximate because the protocol's fixed-point values are rounded.
static uint32_t screenColorPrimaries(NSDictionary *info) {
    uint32_t named = screenColorEnum(info, kCGSDisplayColorPrimariesKey, 0);
    if (named != 0)
        return named;

    static const int32_t sRGB[8] = {640000, 330000, 300000, 600000, 150000, 60000, 312700, 329000};
    static const int32_t displayP3[8] = {680000, 320000, 265000, 690000, 150000, 60000, 312700, 329000};
    static const int32_t dciP3[8] = {680000, 320000, 265000, 690000, 150000, 60000, 314000, 351000};
    static const int32_t bt2020[8] = {708000, 292000, 170000, 797000, 131000, 46000, 312700, 329000};
    static const int32_t adobeRGB[8] = {640000, 330000, 210000, 710000, 150000, 60000, 312700, 329000};

    if (screenColorChromaticityIs(info, kCGSDisplayColorPrimariesChromaticityKey, sRGB, 5000))
        return kCGSDisplayColorPrimariesSRGB;
    if (screenColorChromaticityIs(info, kCGSDisplayColorPrimariesChromaticityKey, displayP3, 5000))
        return kCGSDisplayColorPrimariesDisplayP3;
    if (screenColorChromaticityIs(info, kCGSDisplayColorPrimariesChromaticityKey, dciP3, 5000))
        return kCGSDisplayColorPrimariesDCIP3;
    if (screenColorChromaticityIs(info, kCGSDisplayColorPrimariesChromaticityKey, bt2020, 5000))
        return kCGSDisplayColorPrimariesBT2020;
    if (screenColorChromaticityIs(info, kCGSDisplayColorPrimariesChromaticityKey, adobeRGB, 5000))
        return kCGSDisplayColorPrimariesAdobeRGB;
    return kCGSDisplayColorPrimariesSRGB;
}

static uint32_t screenColorTransfer(NSDictionary *info) {
    uint32_t named = screenColorEnum(info, kCGSDisplayColorTransferFunctionKey, 0);
    if (named != 0)
        return named;

    uint32_t power = screenColorEnum(info, kCGSDisplayColorTransferFunctionPowerKey, 0);
    if (power >= 21500 && power <= 22500)
        return kCGSDisplayColorTransferFunctionGamma22;
    if (power >= 23500 && power <= 24500)
        return kCGSDisplayColorTransferFunctionCompoundPower24;
    return kCGSDisplayColorTransferFunctionSRGB;
}

// The named CoreGraphics space that describes the output's primaries and transfer function, or
// NULL when the pair has no name CoreGraphics knows. An ICC profile is preferred by -colorSpace.
static CGColorSpaceRef screenColorSpaceForDescription(NSDictionary *info) {
    uint32_t primaries = screenColorPrimaries(info);
    uint32_t transfer = screenColorTransfer(info);
    CFStringRef name = NULL;

    switch (primaries) {
    case kCGSDisplayColorPrimariesSRGB:
        if (transfer == kCGSDisplayColorTransferFunctionExtendedSRGB)
            name = kCGColorSpaceExtendedSRGB;
        else if (transfer == kCGSDisplayColorTransferFunctionExtendedLinear)
            name = kCGColorSpaceExtendedLinearSRGB;
        else
            name = kCGColorSpaceSRGB;
        break;
    case kCGSDisplayColorPrimariesDisplayP3:
        if (transfer == kCGSDisplayColorTransferFunctionExtendedSRGB)
            name = kCGColorSpaceExtendedDisplayP3;
        else if (transfer == kCGSDisplayColorTransferFunctionExtendedLinear)
            name = kCGColorSpaceExtendedLinearDisplayP3;
        else
            name = kCGColorSpaceDisplayP3;
        break;
    case kCGSDisplayColorPrimariesDCIP3:
        name = kCGColorSpaceDCIP3;
        break;
    case kCGSDisplayColorPrimariesAdobeRGB:
        name = kCGColorSpaceAdobeRGB1998;
        break;
    case kCGSDisplayColorPrimariesBT2020:
        if (transfer == kCGSDisplayColorTransferFunctionPQ)
            name = kCGColorSpaceITUR_2100_PQ;
        else if (transfer == kCGSDisplayColorTransferFunctionHLG)
            name = kCGColorSpaceITUR_2100_HLG;
        else if (transfer == kCGSDisplayColorTransferFunctionExtendedLinear)
            name = kCGColorSpaceExtendedLinearITUR_2020;
        else
            name = kCGColorSpaceITUR_2020;
        break;
    default:
        break;
    }
    return name != NULL ? CGColorSpaceCreateWithName(name) : NULL;
}

// The monitor name of an EDID base block: the display product name descriptor (tag 0xFC) among the four 18-byte
// descriptors that start at offset 54. Its text is at most 13 characters, ended by a line feed and padded with
// spaces (VESA E-EDID). Answers nil when there is none.
static NSString *monitorNameFromEDID(NSData *edid) {
    const uint8_t *bytes = [edid bytes];
    NSUInteger length = [edid length];

    for (NSUInteger offset = 54; offset <= 108 && offset + 18 <= length; offset += 18) {
        const uint8_t *descriptor = bytes + offset;

        if (descriptor[0] != 0 || descriptor[1] != 0 || descriptor[3] != 0xFC)
            continue;

        NSUInteger count = 0;
        while (count < 13 && descriptor[5 + count] != 0x0A)
            count++;
        while (count > 0 && descriptor[5 + count - 1] == ' ')
            count--;
        if (count > 0)
            return [[[NSString alloc] initWithBytes: descriptor + 5
                                             length: count
                                           encoding: NSASCIIStringEncoding] autorelease];
    }
    return nil;
}

@implementation NSScreen

- initWithFrame: (NSRect) frame visibleFrame: (NSRect) visibleFrame {
    NS_EXTRA(NSScreen, self)->_frame = frame;
    NS_EXTRA(NSScreen, self)->_visibleFrame = visibleFrame;
    return self;
}

- (void) dealloc {
    [NS_EXTRA(NSScreen, self)->_outputName release];
    if (NS_EXTRA(NSScreen, self)->_edid)
        [NS_EXTRA(NSScreen, self)->_edid release];
    NS_EXTRA_FREE(NSScreen, self);
    [super dealloc];
}

+ (NSScreen *) mainScreen {
    NSScreen *result = [[NSApp keyWindow] screen];

    if (result == nil)
        result = [[self screens] objectAtIndex: 0];

    return result;
}

+ (NSArray *) screens {
    // Without a display (connections to the window system denied) there are no screens.
    NSArray *screens = [[NSDisplay currentDisplay] screens];
    return screens != nil ? screens : @[];
}

- (NSWindowDepth) depth {
    return NS_EXTRA(NSScreen, self)->_depth;
}

- (NSRect) frame {
    return NS_EXTRA(NSScreen, self)->_frame;
}

- (NSRect) visibleFrame {
    return NS_EXTRA(NSScreen, self)->_visibleFrame;
}

- (CGFloat) userSpaceScaleFactor {
    return 1.0;
}

// The device pixels per point of the display this screen is made from.
- (CGFloat) backingScaleFactor {
    CGFloat scale = NS_EXTRA(NSScreen, self)->_backingScale;

    return scale >= 1.0 ? scale : 1.0;
}

// Whether the output's primaries contain the gamut. The window system reports them in the color
// description; without one the screen is sRGB.
- (BOOL) canRepresentDisplayGamut: (NSDisplayGamut) displayGamut {
    if (displayGamut == NSDisplayGamutSRGB)
        return YES;
    if (displayGamut != NSDisplayGamutP3)
        return NO;
    uint32_t primaries = screenColorPrimaries(screenColorInfo(self));
    return primaries == kCGSDisplayColorPrimariesDisplayP3 ||
           primaries == kCGSDisplayColorPrimariesDCIP3 ||
           primaries == kCGSDisplayColorPrimariesAdobeRGB ||
           primaries == kCGSDisplayColorPrimariesBT2020;
}

// The backing store of a screen has -backingScaleFactor pixels per point; the conversions scale the
// rect and nothing else.
- (NSRect) convertRectToBacking: (NSRect) rect {
    CGFloat scale = [self backingScaleFactor];

    return NSMakeRect(rect.origin.x * scale, rect.origin.y * scale,
                      rect.size.width * scale, rect.size.height * scale);
}

- (NSRect) convertRectFromBacking: (NSRect) rect {
    CGFloat scale = [self backingScaleFactor];

    if (!(scale > 0))
        scale = 1.0;
    return NSMakeRect(rect.origin.x / scale, rect.origin.y / scale,
                      rect.size.width / scale, rect.size.height / scale);
}

// The rect with its edges moved onto whole backing pixels as the options ask.
- (NSRect) backingAlignedRect: (NSRect) rect options: (NSAlignmentOptions) options {
    return [self convertRectFromBacking:
                         _NSAlignRectToPixelGrid([self convertRectToBacking: rect], options)];
}

// The output's color description, as an NSColorSpace. The ICC profile from the compositor wins;
// otherwise the reported primaries and transfer function name a color space. The sRGB space is the
// fallback for a display the compositor does not describe.
- (NSColorSpace *) colorSpace {
    NSColorSpace *space = [NSScreen _colorSpaceFromDisplayColorInfo: screenColorInfo(self)];
    return space != nil ? space : [NSColorSpace sRGBColorSpace];
}

// The name the monitor reports in its EDID when the display has one. Without an EDID the name the window
// system gives the output (a description or connector name), else a generic name with the display ID.
- (NSString *) localizedName {
    NSData *edid = NS_EXTRA(NSScreen, self)->_edid;
    NSString *name = edid != nil ? monitorNameFromEDID(edid) : nil;

    if (name != nil)
        return name;
    if (edid == nil && NS_EXTRA(NSScreen, self)->_outputName != nil)
        return NS_EXTRA(NSScreen, self)->_outputName;
    return [NSString stringWithFormat: @"Display %u",
                                       (unsigned) [self cgDirectDisplayID]];
}

// The headroom above SDR white is the output's maximum luminance divided by the luminance of its
// reference white. Without a description, the screen is standard dynamic range.
- (CGFloat) maximumExtendedDynamicRangeColorComponentValue {
    NSDictionary *info = screenColorInfo(self);
    CGFloat reference = screenColorLuminance(info, kCGSDisplayColorReferenceLuminanceKey, 0);
    CGFloat maximum = screenColorLuminance(info, kCGSDisplayColorMaxLuminanceKey, 0);

    if (reference <= 0 || maximum <= reference)
        return 1.0;
    return maximum / reference;
}

- (CGFloat) maximumPotentialExtendedDynamicRangeColorComponentValue {
    // The target luminance is the headroom available with a different reference white; the
    // primary-volume maximum is what the display reaches at its current reference white.
    NSDictionary *info = screenColorInfo(self);
    CGFloat reference = screenColorLuminance(info, kCGSDisplayColorReferenceLuminanceKey, 0);
    CGFloat maximum = screenColorLuminance(info, kCGSDisplayColorTargetMaxLuminanceKey, 0);
    if (maximum <= 0)
        maximum = screenColorLuminance(info, kCGSDisplayColorMaxLuminanceKey, 0);

    if (reference <= 0 || maximum <= reference)
        return 1.0;
    return maximum / reference;
}

- (CGFloat) maximumReferenceExtendedDynamicRangeColorComponentValue {
    NSDictionary *info = screenColorInfo(self);
    CGFloat reference = screenColorLuminance(info, kCGSDisplayColorReferenceLuminanceKey, 0);
    CGFloat maximum = screenColorLuminance(info, kCGSDisplayColorTargetMaxLuminanceKey, 0);

    if (reference <= 0 || maximum <= reference)
        return 0.0;
    return maximum / reference;
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
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode([self cgDirectDisplayID]);
    double rate = 0;

    if (mode != NULL) {
        rate = CGDisplayModeGetRefreshRate(mode);
        CGDisplayModeRelease(mode);
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
                                       NSStringFromRect(NS_EXTRA(NSScreen, self)->_frame),
                                       NSStringFromRect(NS_EXTRA(NSScreen, self)->_visibleFrame)];
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
        NSDeviceSize : [NSValue valueWithSize: NS_EXTRA(NSScreen, self)->_frame.size],
        NSDeviceResolution : [NSValue valueWithSize: NSMakeSize(dpi, dpi)],
        NSDeviceIsScreen : @"YES",
        NSDeviceColorSpaceName : NSCalibratedRGBColorSpace,
        NSDeviceBitsPerSample : @8,
    };
}

@end

@implementation NSScreen (Darling)
+ (NSColorSpace *) _colorSpaceFromDisplayColorInfo: (NSDictionary *) info {
    NSData *icc = [info objectForKey: (id) kCGSDisplayColorICCProfileKey];
    if ([icc isKindOfClass: [NSData class]]) {
        NSColorSpace *profile = [[[NSColorSpace alloc] initWithICCProfileData: icc] autorelease];
        if (profile != nil)
            return profile;
    }
    CGColorSpaceRef space = screenColorSpaceForDescription(info);
    if (space == NULL)
        return nil;
    NSColorSpace *result = [[[NSColorSpace alloc] initWithCGColorSpace: space] autorelease];
    CGColorSpaceRelease(space);
    return result;
}

- (NSData *) edid {
    return NS_EXTRA(NSScreen, self)->_edid;
}

- (void) setEdid: (NSData *) data {
    NSData *old = NS_EXTRA(NSScreen, self)->_edid;
    NS_EXTRA(NSScreen, self)->_edid = [data retain];
    [old release];
}

- (CGDirectDisplayID) cgDirectDisplayID {
    return NS_EXTRA(NSScreen, self)->_directDisplayID;
}

- (void) setCgDirectDisplayID: (CGDirectDisplayID) displayID {
    NS_EXTRA(NSScreen, self)->_directDisplayID = displayID;
}

- (void) _setBackingScaleFactor: (CGFloat) scale {
    NS_EXTRA(NSScreen, self)->_backingScale = scale;
}

- (void) _setOutputName: (NSString *) name {
    NSString *old = NS_EXTRA(NSScreen, self)->_outputName;

    NS_EXTRA(NSScreen, self)->_outputName = [name copy];
    [old release];
}

@end
