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

#import <AppKit/NSColor_CGColor.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContextFunctions.h>
#import <AppKit/NSImage.h>
#import <ApplicationServices/ApplicationServices.h>

#import <Foundation/NSDebug.h>

#import <AppKit/conversions.h>

@implementation NSColor_CGColor

- initWithColorRef: (CGColorRef) colorRef spaceName: (NSString *) spaceName {
    _catalogName = @"";
    _colorRef = CGColorRetain(colorRef);
    _colorSpaceName = [spaceName copy];
    _pattern = nil;

    if (_colorRef != nil &&
        [_colorSpaceName isEqualToString: NSPatternColorSpace]) {
        CGPatternRef pattern = CGColorGetPattern(_colorRef);
        _pattern = (NSImage *) CGPatternGetImage(pattern);
    }

    return self;
}

- (void) dealloc {
    [_catalogName release];
    CGColorRelease(_colorRef);
    [_colorSpaceName release];
    [_pattern release];
    [super dealloc];
}

+ (NSColor *) colorWithColorRef: (CGColorRef) colorRef
                      spaceName: (NSString *) spaceName
{
    return [[[self alloc] initWithColorRef: colorRef
                                 spaceName: spaceName] autorelease];
}

+ (NSColor *) colorWithGray: (CGFloat) gray
                      alpha: (CGFloat) alpha
                  spaceName: (NSString *) spaceName
{
    NSColor *result;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
    CGFloat components[2] = {gray, alpha};
    CGColorRef cgColor = CGColorCreate(colorSpace, components);

    result = [self colorWithColorRef: cgColor spaceName: spaceName];

    CGColorSpaceRelease(colorSpace);
    CGColorRelease(cgColor);

    return result;
}

+ (NSColor *) colorWithCyan: (CGFloat) cyan
                    magenta: (CGFloat) magenta
                     yellow: (CGFloat) yellow
                      black: (CGFloat) black
                      alpha: (CGFloat) alpha
                  spaceName: (NSString *) spaceName
{
    NSColor *result;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceCMYK();
    CGFloat components[5] = {cyan, magenta, yellow, black, alpha};
    CGColorRef cgColor = CGColorCreate(colorSpace, components);

    result = [self colorWithColorRef: cgColor spaceName: spaceName];

    CGColorSpaceRelease(colorSpace);
    CGColorRelease(cgColor);

    return result;
}

+ (NSColor *) colorWithRed: (CGFloat) red
                     green: (CGFloat) green
                      blue: (CGFloat) blue
                     alpha: (CGFloat) alpha
                 spaceName: (NSString *) spaceName
{
    NSColor *result;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat components[4] = {red, green, blue, alpha};
    CGColorRef cgColor = CGColorCreate(colorSpace, components);

    result = [self colorWithColorRef: cgColor spaceName: spaceName];

    CGColorSpaceRelease(colorSpace);
    CGColorRelease(cgColor);

    return result;
}

+ (NSColor *) colorWithHue: (CGFloat) hue
                saturation: (CGFloat) saturation
                brightness: (CGFloat) brightness
                     alpha: (CGFloat) alpha
                 spaceName: (NSString *) spaceName
{
    CGFloat red, green, blue;

    NSColorHSBToRGB(hue, saturation, brightness, &red, &green, &blue);

    return [self colorWithRed: red
                        green: green
                         blue: blue
                        alpha: alpha
                    spaceName: spaceName];
}

- (BOOL) isEqual: otherObject {
    if (self == otherObject)
        return YES;

    if ([otherObject isKindOfClass: [self class]]) {
        NSColor_CGColor *other = otherObject;

        return CGColorEqualToColor(_colorRef, other->_colorRef);
    }

    return NO;
}

- (NSString *) description {
    return [NSString
            stringWithFormat: @"<%@ colorRef=%@>", [self class], _colorRef];
}

- (NSInteger) numberOfComponents {
    return CGColorGetNumberOfComponents(_colorRef);
}

- (void) getComponents: (CGFloat *) components {
    NSInteger i, count = CGColorGetNumberOfComponents(_colorRef);
    const CGFloat *comps = CGColorGetComponents(_colorRef);

    for (i = 0; i < count; i++)
        components[i] = comps[i];
}

- (CGFloat) alphaComponent {
    return CGColorGetAlpha(_colorRef);
}

- (NSColor *) colorWithAlphaComponent: (CGFloat) alpha {
    CGColorRef ref = CGColorCreateCopyWithAlpha(_colorRef, alpha);
    NSColor *result = [[[[self class] alloc] initWithColorRef: ref
                                                    spaceName: _colorSpaceName]
            autorelease];

    CGColorRelease(ref);
    return result;
}

#define REC601_LUMINANCE_R 0.299f
#define REC601_LUMINANCE_G 0.587f
#define REC601_LUMINANCE_B 0.114f

static inline CGFloat calibratedWhiteFromRGB(CGFloat r, CGFloat g, CGFloat b) {
    return (REC601_LUMINANCE_R * r, REC601_LUMINANCE_G * g,
            REC601_LUMINANCE_B * b);
}

- (NSColor *) colorUsingColorSpaceName: (NSString *) otherSpaceName
                                device: (NSDictionary *) device
{
    if (otherSpaceName == nil ||
        [otherSpaceName isEqualToString: _colorSpaceName])
        return self;

    // Most of these are crude

    CGColorSpaceRef colorSpace = CGColorGetColorSpace(_colorRef);
    const CGFloat *components = CGColorGetComponents(_colorRef);

    if ([_colorSpaceName isEqualToString: NSDeviceBlackColorSpace]) {
    } else if ([_colorSpaceName isEqualToString: NSDeviceWhiteColorSpace]) {
        CGFloat white = components[0];
        CGFloat alpha = components[1];

        if ([otherSpaceName isEqualToString: NSCalibratedRGBColorSpace] ||
            colorSpace == nil)
            return [NSColor colorWithCalibratedRed: white
                                             green: white
                                              blue: white
                                             alpha: alpha];

        if ([otherSpaceName isEqualToString: NSDeviceRGBColorSpace])
            return [NSColor colorWithDeviceRed: white
                                         green: white
                                          blue: white
                                         alpha: alpha];

        if ([otherSpaceName isEqualToString: NSDeviceCMYKColorSpace])
            return [NSColor colorWithDeviceCyan: 0
                                        magenta: 0
                                         yellow: 0
                                          black: 1 - white
                                          alpha: alpha];

        NSLog(@"Other space %@ from NSDeviceWhiteColorSpace", otherSpaceName);
    } else if ([_colorSpaceName isEqualToString: NSDeviceRGBColorSpace]) {
        CGFloat red = components[0];
        CGFloat green = components[1];
        CGFloat blue = components[2];
        CGFloat alpha = components[3];

        if ([otherSpaceName isEqualToString: NSDeviceWhiteColorSpace])
            return [NSColor colorWithDeviceWhite: calibratedWhiteFromRGB(
                                                          red, green, blue)
                                           alpha: alpha];

        if ([otherSpaceName isEqualToString: NSDeviceCMYKColorSpace])
            return [NSColor colorWithDeviceCyan: 1.0 - red
                                        magenta: 1.0 - green
                                         yellow: 1.0 - blue
                                          black: 0.0
                                          alpha: alpha];

        if ([otherSpaceName isEqualToString: NSCalibratedRGBColorSpace])
            return [NSColor colorWithCalibratedRed: red
                                             green: green
                                              blue: blue
                                             alpha: alpha];

        if ([otherSpaceName isEqualToString: NSCalibratedWhiteColorSpace])
            return [NSColor colorWithCalibratedWhite: calibratedWhiteFromRGB(
                                                              red, green, blue)
                                               alpha: alpha];

        NSLog(@"Other space %@ from NSDeviceRGBColorSpace", otherSpaceName);
    } else if ([_colorSpaceName isEqualToString: NSDeviceCMYKColorSpace]) {
        CGFloat cyan = components[0];
        CGFloat magenta = components[1];
        CGFloat yellow = components[2];
        CGFloat black = components[3];
        CGFloat alpha = components[4];

        if ([otherSpaceName isEqualToString: NSCalibratedRGBColorSpace]) {
            CGFloat white = 1 - black;
            CGFloat red = (cyan > white ? 0 : white - cyan);
            CGFloat green = (magenta > white ? 0 : white - magenta);
            CGFloat blue = (yellow > white ? 0 : white - yellow);

            return [NSColor colorWithCalibratedRed: red
                                             green: green
                                              blue: blue
                                             alpha: alpha];
        }

        if ([otherSpaceName isEqualToString: NSCalibratedWhiteColorSpace]) {
            CGFloat white = 1 - cyan - magenta - yellow - black;

            return [NSColor colorWithCalibratedWhite: (white > 0 ? white : 0)
                                               alpha: alpha];
        }

        NSLog(@"Other space %@ from NSDeviceCMYKColorSpace", otherSpaceName);
    } else if ([_colorSpaceName isEqualToString: NSCalibratedBlackColorSpace]) {
    } else if ([_colorSpaceName isEqualToString: NSCalibratedWhiteColorSpace]) {
        CGFloat white = components[0];
        CGFloat alpha = components[1];

        if ([otherSpaceName isEqualToString: NSCalibratedRGBColorSpace] ||
            colorSpace == nil)
            return [NSColor colorWithCalibratedRed: white
                                             green: white
                                              blue: white
                                             alpha: alpha];

        if ([otherSpaceName isEqualToString: NSDeviceRGBColorSpace])
            return [NSColor colorWithDeviceRed: white
                                         green: white
                                          blue: white
                                         alpha: alpha];

        if ([otherSpaceName isEqualToString: NSDeviceCMYKColorSpace])
            return [NSColor colorWithDeviceCyan: 0
                                        magenta: 0
                                         yellow: 0
                                          black: 1 - white
                                          alpha: alpha];

        if ([otherSpaceName isEqualToString: NSPatternColorSpace]) {
            CGColorSpaceRef currentColorSpace = CGColorGetColorSpace(_colorRef);
            CGColorSpaceRef patternColorSpace =
                    CGColorSpaceCreatePattern(currentColorSpace);
            CGPatternCallbacks callbacks = {0, drawPattern, releasePatternInfo};
            NSImage *image =
                    [[NSImage alloc] initWithSize: NSMakeSize(1.0, 1.0)];
            CGPatternRef pattern = CGPatternCreate(
                    image, CGRectMake(0, 0, 1, 1), CGAffineTransformIdentity, 1,
                    1, kCGPatternTilingNoDistortion, YES, &callbacks);
            CGColorRef cgColor = CGColorCreateWithPattern(patternColorSpace,
                                                          pattern, components);

            return [self initWithColorRef: cgColor
                                spaceName: NSPatternColorSpace];
        }

        NSLog(@"Other space %@ from NSCalibratedWhiteColorSpace",
              otherSpaceName);
    } else if ([_colorSpaceName isEqualToString: NSCalibratedRGBColorSpace]) {
        CGFloat red = components[0];
        CGFloat green = components[1];
        CGFloat blue = components[2];
        CGFloat alpha = components[3];

        if ([otherSpaceName isEqualToString: NSDeviceWhiteColorSpace])
            return [NSColor colorWithDeviceWhite: calibratedWhiteFromRGB(
                                                          red, green, blue)
                                           alpha: alpha];

        if ([otherSpaceName isEqualToString: NSDeviceCMYKColorSpace])
            return [NSColor colorWithDeviceCyan: 1.0 - red
                                        magenta: 1.0 - green
                                         yellow: 1.0 - blue
                                          black: 0.0
                                          alpha: alpha];

        if ([otherSpaceName isEqualToString: NSCalibratedWhiteColorSpace])
            return [NSColor colorWithCalibratedWhite: calibratedWhiteFromRGB(
                                                              red, green, blue)
                                               alpha: alpha];

        if ([otherSpaceName isEqualToString: NSDeviceRGBColorSpace])
            return [NSColor colorWithDeviceRed: red
                                         green: green
                                          blue: blue
                                         alpha: alpha];

        if ([otherSpaceName isEqualToString: NSPatternColorSpace]) {
            CGColorSpaceRef currentColorSpace = CGColorGetColorSpace(_colorRef);
            CGColorSpaceRef patternColorSpace =
                    CGColorSpaceCreatePattern(currentColorSpace);
            CGPatternCallbacks callbacks = {0, drawPattern, releasePatternInfo};
            NSImage *image =
                    [[NSImage alloc] initWithSize: NSMakeSize(1.0, 1.0)];
            CGPatternRef pattern = CGPatternCreate(
                    image, CGRectMake(0, 0, 1, 1), CGAffineTransformIdentity, 1,
                    1, kCGPatternTilingNoDistortion, YES, &callbacks);
            CGColorRef cgColor = CGColorCreateWithPattern(patternColorSpace,
                                                          pattern, components);

            return [self initWithColorRef: cgColor
                                spaceName: NSPatternColorSpace];
        }

        NSLog(@"Other space %@ from NSCalibratedRGBColorSpace", otherSpaceName);
    } else if ([_colorSpaceName isEqualToString: NSNamedColorSpace]) {
        CGFloat red = components[0], green = components[1],
                blue = components[2], alpha = components[3];

        if ([otherSpaceName isEqualToString: NSPatternColorSpace]) {
            CGColorSpaceRef currentColorSpace = CGColorGetColorSpace(_colorRef);
            CGColorSpaceRef patternColorSpace =
                    CGColorSpaceCreatePattern(currentColorSpace);
            CGPatternCallbacks callbacks = {0, drawPattern, releasePatternInfo};
            NSImage *image =
                    [[NSImage alloc] initWithSize: NSMakeSize(1.0, 1.0)];
            CGPatternRef pattern = CGPatternCreate(
                    image, CGRectMake(0, 0, 1, 1), CGAffineTransformIdentity, 1,
                    1, kCGPatternTilingNoDistortion, YES, &callbacks);
            CGColorRef cgColor = CGColorCreateWithPattern(patternColorSpace,
                                                          pattern, components);

            return [self initWithColorRef: cgColor
                                spaceName: NSPatternColorSpace];
        }

        if ([otherSpaceName isEqualToString: NSDeviceRGBColorSpace])
            return [NSColor colorWithDeviceRed: red
                                         green: green
                                          blue: blue
                                         alpha: alpha];

        NSLog(@"Other space %@ from NSNamedColorSpace", otherSpaceName);
    } else if ([_colorSpaceName isEqualToString: NSCustomColorSpace]) {
        CGFloat white = components[0], alpha = components[1];

        if ([otherSpaceName isEqualToString: NSDeviceRGBColorSpace])
            return [NSColor colorWithDeviceRed: white
                                         green: white
                                          blue: white
                                         alpha: alpha];

        if ([otherSpaceName isEqualToString: NSPatternColorSpace]) {
            CGColorSpaceRef currentColorSpace = CGColorGetColorSpace(_colorRef);
            CGColorSpaceRef patternColorSpace =
                    CGColorSpaceCreatePattern(currentColorSpace);
            CGPatternCallbacks callbacks = {0, drawPattern, releasePatternInfo};
            NSImage *image =
                    [[NSImage alloc] initWithSize: NSMakeSize(1.0, 1.0)];
            CGPatternRef pattern = CGPatternCreate(
                    image, CGRectMake(0, 0, 1, 1), CGAffineTransformIdentity, 1,
                    1, kCGPatternTilingNoDistortion, YES, &callbacks);
            CGColorRef cgColor = CGColorCreateWithPattern(patternColorSpace,
                                                          pattern, components);

            return [self initWithColorRef: cgColor
                                spaceName: NSPatternColorSpace];
        }

        NSLog(@"Other space %@ from NSCustomColorSpace", otherSpaceName);
    }

    NSLog(@"Unable to convert color to space %@ from %@", otherSpaceName,
          _colorSpaceName);

    return nil;
}

- (NSString *) colorSpaceName {
    return _colorSpaceName;
}

- (void) getWhite: (CGFloat *) white alpha: (CGFloat *) alpha {
    CGColorSpaceRef colorSpace = CGColorGetColorSpace(_colorRef);
    CGColorSpaceModel model = CGColorSpaceGetModel(colorSpace);
    const CGFloat *components = CGColorGetComponents(_colorRef);

    if (model == kCGColorSpaceModelMonochrome) {
        if (white != NULL)
            *white = components[0];
        if (alpha != NULL)
            *alpha = components[1];
        return;
    }

    NSLog(@"-[%@ %s] failed, space=%@", [self class], _cmd, _colorSpaceName);
}

- (void) getRed: (CGFloat *) red
          green: (CGFloat *) green
           blue: (CGFloat *) blue
          alpha: (CGFloat *) alpha
{
    CGColorSpaceRef colorSpace = CGColorGetColorSpace(_colorRef);
    CGColorSpaceModel model = CGColorSpaceGetModel(colorSpace);
    const CGFloat *components = CGColorGetComponents(_colorRef);

    if (model == kCGColorSpaceModelRGB) {
        if (red != NULL)
            *red = components[0];
        if (green != NULL)
            *green = components[1];
        if (blue != NULL)
            *blue = components[2];
        if (alpha != NULL)
            *alpha = components[3];
        return;
    }

    if (model == kCGColorSpaceModelMonochrome) {
        if (red != NULL)
            *red = components[0];
        if (green != NULL)
            *green = components[0];
        if (blue != NULL)
            *blue = components[0];
        if (alpha != NULL)
            *alpha = components[1];
        return;
    }

    NSLog(@"-[%@ %s] failed, space=%@", [self class], _cmd, _colorSpaceName);
}

- (void) getHue: (CGFloat *) huep
        saturation: (CGFloat *) saturationp
        brightness: (CGFloat *) brightnessp
             alpha: (CGFloat *) alphap
{
    CGColorSpaceRef colorSpace = CGColorGetColorSpace(_colorRef);
    CGColorSpaceModel model = CGColorSpaceGetModel(colorSpace);
    const CGFloat *components = CGColorGetComponents(_colorRef);

    if (model == kCGColorSpaceModelRGB) {
        CGFloat red = components[0];
        CGFloat green = components[1];
        CGFloat blue = components[2];
        CGFloat alpha = components[3];

        NSColorRGBToHSB(red, green, blue, huep, saturationp, brightnessp);

        if (alphap != NULL)
            *alphap = alpha;

        return;
    }

    NSLog(@"-[%@ %s] failed, space=%@", [self class], _cmd, _colorSpaceName);
}

- (void) getCyan: (CGFloat *) cyan
         magenta: (CGFloat *) magenta
          yellow: (CGFloat *) yellow
           black: (CGFloat *) black
           alpha: (CGFloat *) alpha
{
    CGColorSpaceRef colorSpace = CGColorGetColorSpace(_colorRef);
    CGColorSpaceModel model = CGColorSpaceGetModel(colorSpace);
    const CGFloat *components = CGColorGetComponents(_colorRef);

    if (model == kCGColorSpaceModelCMYK) {
        if (cyan != NULL)
            *cyan = components[0];
        if (magenta != NULL)
            *magenta = components[1];
        if (yellow != NULL)
            *yellow = components[2];
        if (black != NULL)
            *black = components[3];
        if (alpha != NULL)
            *alpha = components[4];
        return;
    }

    NSLog(@"-[%@ %s] failed", [self class], _cmd);
}

- (NSColorListName) catalogNameComponent {
    return _catalogName;
}

- (NSImage *) patternImage {
    return _pattern;
}

- (CGColorRef) CGColor {
    return CGColorRetain(_colorRef);
}

- (void) setStroke {
    CGContextSetStrokeColorWithColor(NSCurrentGraphicsPort(), _colorRef);
}

- (void) setFill {
    CGContextSetFillColorWithColor(NSCurrentGraphicsPort(), _colorRef);
}

static void drawPattern(void *info, CGContextRef cgContext) {
    NSImage *image = (NSImage *) info;
    NSSize size = [image size];
    NSGraphicsContext *context =
            [NSGraphicsContext graphicsContextWithGraphicsPort: cgContext
                                                       flipped: NO];

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: context];
    [image drawInRect: NSMakeRect(0, 0, size.width, size.height)
             fromRect: NSZeroRect
            operation: NSCompositeCopy
             fraction: 1.0];
    [NSGraphicsContext restoreGraphicsState];
}

static void releasePatternInfo(void *info) {
    [(NSImage *) info release];
}

@end
