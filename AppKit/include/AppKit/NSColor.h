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

#import <AppKit/AppKitExport.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>

APPKIT_EXPORT NSNotificationName const NSSystemColorsDidChangeNotification;

typedef NSString *NSColorListName;
typedef NSString *NSColorName;
typedef NSString *NSColorSpaceName;

typedef NS_ENUM(NSInteger, NSColorType) {
    NSColorTypeComponentBased = 0,
    NSColorTypePattern = 1,
    NSColorTypeCatalog = 2,
};

@class NSImage;
@class NSPasteboard;
@class NSColorSpace;

typedef NSUInteger NSControlTint;
enum {
    NSDefaultControlTint = 0,
    NSBlueControlTint = 1,
    NSGraphiteControlTint = 6,
    NSClearControlTint = 7,
};

@interface NSColor : NSObject <NSCopying, NSCoding> {
    NSColorListName _catalogName;
    NSColorName _colorName;
    NSImage *_pattern;
}

@property(class, strong, readonly) NSColor *labelColor;

@property(class, strong, readonly) NSColor *textColor;
@property(class, strong, readonly) NSColor *selectedTextColor;
@property(class, strong, readonly) NSColor *textBackgroundColor;
@property(class, strong, readonly) NSColor *selectedTextBackgroundColor;
@property(class, strong, readonly) NSColor *keyboardFocusIndicatorColor;
@property(class, strong, readonly) NSColor *unemphasizedSelectedTextColor;
@property(class, strong, readonly) NSColor *unemphasizedSelectedTextBackgroundColor;

@property(class, strong, readonly) NSColor *linkColor;
@property(class, strong, readonly) NSColor *selectedContentBackgroundColor;
@property(class, strong, readonly) NSColor *unemphasizedSelectedContentBackgroundColor;

@property(class, strong, readonly) NSColor *selectedMenuItemTextColor;

@property(class, strong, readonly) NSColor *gridColor;
@property(class, strong, readonly) NSColor *headerTextColor;
@property(class, strong, readonly) NSArray<NSColor *> *alternatingContentBackgroundColors;

@property(class, strong, readonly) NSColor *controlAccentColor;
@property(class, strong, readonly) NSColor *controlColor;
@property(class, strong, readonly) NSColor *controlBackgroundColor;
@property(class, strong, readonly) NSColor *controlTextColor;
@property(class, strong, readonly) NSColor *disabledControlTextColor;
@property(class, strong, readonly) NSColor *selectedControlColor;
@property(class, strong, readonly) NSColor *selectedControlTextColor;
@property(class, strong, readonly) NSColor *alternateSelectedControlTextColor;

@property(class, strong, readonly) NSColor *windowBackgroundColor;

@property(class, strong, readonly) NSColor *highlightColor;
@property(class, strong, readonly) NSColor *shadowColor;

@property(class, strong, readonly) NSColor *alternateSelectedControlColor;
@property(class, strong, readonly) NSArray<NSColor *> *controlAlternatingRowBackgroundColors;
@property(class, strong, readonly) NSColor *controlHighlightColor;
@property(class, strong, readonly) NSColor *controlLightHighlightColor;
@property(class, strong, readonly) NSColor *controlShadowColor;
@property(class, strong, readonly) NSColor *controlDarkShadowColor;
@property(class, strong, readonly) NSColor *headerColor;
@property(class, strong, readonly) NSColor *knobColor;
@property(class, strong, readonly) NSColor *selectedKnobColor;
@property(class, strong, readonly) NSColor *scrollBarColor;
@property(class, strong, readonly) NSColor *secondarySelectedControlColor;
@property(class, strong, readonly) NSColor *selectedMenuItemColor;
@property(class, strong, readonly) NSColor *windowFrameColor;

@property(class, strong, readonly) NSColor *clearColor;

@property(class, strong, readonly) NSColor *blackColor;
@property(class, strong, readonly) NSColor *blueColor;
@property(class, strong, readonly) NSColor *brownColor;
@property(class, strong, readonly) NSColor *cyanColor;
@property(class, strong, readonly) NSColor *darkGrayColor;
@property(class, strong, readonly) NSColor *grayColor;
@property(class, strong, readonly) NSColor *greenColor;
@property(class, strong, readonly) NSColor *lightGrayColor;
@property(class, strong, readonly) NSColor *magentaColor;
@property(class, strong, readonly) NSColor *orangeColor;
@property(class, strong, readonly) NSColor *purpleColor;
@property(class, strong, readonly) NSColor *redColor;
@property(class, strong, readonly) NSColor *whiteColor;
@property(class, strong, readonly) NSColor *yellowColor;

@property(copy, readonly) NSImage *patternImage;

@property(readonly) NSInteger numberOfComponents;

@property(readonly) CGFloat alphaComponent;
@property(readonly) CGFloat whiteComponent;
@property(readonly) CGFloat redComponent;
@property(readonly) CGFloat greenComponent;
@property(readonly) CGFloat blueComponent;
@property(readonly) CGFloat cyanComponent;
@property(readonly) CGFloat magentaComponent;
@property(readonly) CGFloat yellowComponent;
@property(readonly) CGFloat blackComponent;
@property(readonly) CGFloat hueComponent;
@property(readonly) CGFloat saturationComponent;
@property(readonly) CGFloat brightnessComponent;
@property(copy, readonly) NSColorListName catalogNameComponent;
@property(copy, readonly) NSColorName colorNameComponent;

@property(readonly) CGColorRef CGColor;
@property(readonly) NSColorType type;

@property(class) BOOL ignoresAlpha;
@property(copy, readonly) NSColorSpaceName colorSpaceName;

+ (NSColor *) highlightColor;
+ (NSColor *) shadowColor;
+ (NSColor *) gridColor;

+ (NSColor *) alternateSelectedControlColor;
+ (NSColor *) alternateSelectedControlTextColor;
+ (NSColor *) controlColor;
+ (NSControlTint) currentControlTint;
+ (NSColor *) secondarySelectedControlColor;
+ (NSColor *) selectedControlColor;
+ (NSColor *) controlTextColor;
+ (NSColor *) selectedControlTextColor;
+ (NSColor *) disabledControlTextColor;
+ (NSColor *) controlBackgroundColor;
+ (NSColor *) controlDarkShadowColor;
+ (NSColor *) controlHighlightColor;
+ (NSColor *) controlLightHighlightColor;
+ (NSColor *) controlShadowColor;
+ (NSArray *) controlAlternatingRowBackgroundColors;

+ (NSColor *) keyboardFocusIndicatorColor;

+ (NSColor *) textColor;
+ (NSColor *) textBackgroundColor;
+ (NSColor *) selectedTextColor;
+ (NSColor *) selectedTextBackgroundColor;

+ (NSColor *) headerColor;
+ (NSColor *) headerTextColor;

+ (NSColor *) scrollBarColor;
+ (NSColor *) knobColor;
+ (NSColor *) selectedKnobColor;

+ (NSColor *) windowBackgroundColor;
+ (NSColor *) windowFrameColor;

+ (NSColor *) selectedMenuItemColor;
+ (NSColor *) selectedMenuItemTextColor;

// private
+ (NSColor *) mainMenuBarColor;
+ (NSColor *) menuBackgroundColor;
+ (NSColor *) menuItemTextColor;

+ (NSColor *) clearColor;

+ (NSColor *) blackColor;
+ (NSColor *) blueColor;
+ (NSColor *) brownColor;
+ (NSColor *) cyanColor;
+ (NSColor *) darkGrayColor;
+ (NSColor *) grayColor;
+ (NSColor *) greenColor;
+ (NSColor *) lightGrayColor;
+ (NSColor *) magentaColor;
+ (NSColor *) orangeColor;
+ (NSColor *) purpleColor;
+ (NSColor *) redColor;
+ (NSColor *) whiteColor;
+ (NSColor *) yellowColor;

+ (NSColor *) colorWithDeviceWhite: (CGFloat) white alpha: (CGFloat) alpha;
+ (NSColor *) colorWithWhite: (CGFloat) white alpha: (CGFloat) alpha;
+ (NSColor *) colorWithDeviceRed: (CGFloat) red
                           green: (CGFloat) green
                            blue: (CGFloat) blue
                           alpha: (CGFloat) alpha;
+ (NSColor *) colorWithRed: (CGFloat) red
                     green: (CGFloat) green
                      blue: (CGFloat) blue
                     alpha: (CGFloat) alpha;
+ (NSColor *) colorWithSRGBRed: (CGFloat) red
                         green: (CGFloat) green
                          blue: (CGFloat) blue
                         alpha: (CGFloat) alpha;
+ (NSColor *) colorWithDeviceHue: (CGFloat) hue
                      saturation: (CGFloat) saturation
                      brightness: (CGFloat) brightness
                           alpha: (CGFloat) alpha;
+ (NSColor *) colorWithDeviceCyan: (CGFloat) cyan
                          magenta: (CGFloat) magenta
                           yellow: (CGFloat) yellow
                            black: (CGFloat) black
                            alpha: (CGFloat) alpha;

+ (NSColor *) colorWithCalibratedWhite: (CGFloat) white alpha: (CGFloat) alpha;
+ (NSColor *) colorWithCalibratedRed: (CGFloat) red
                               green: (CGFloat) green
                                blue: (CGFloat) blue
                               alpha: (CGFloat) alpha;
+ (NSColor *) colorWithCalibratedHue: (CGFloat) hue
                          saturation: (CGFloat) saturation
                          brightness: (CGFloat) brightness
                               alpha: (CGFloat) alpha;

+ (NSColor *) colorWithGenericGamma22White:(CGFloat) white 
                                     alpha:(CGFloat) alpha;

+ (NSColor *) colorWithCatalogName: (NSString *) catalogName
                         colorName: (NSString *) colorName;

+ (NSColor *) colorFromPasteboard: (NSPasteboard *) pasteboard;

+ (NSColor *) colorWithPatternImage: (NSImage *) image;

- (NSString *) colorSpaceName;

- (NSInteger) numberOfComponents;
- (void) getComponents: (CGFloat *) components;

- (void) getWhite: (CGFloat *) white alpha: (CGFloat *) alpha;
- (void) getRed: (CGFloat *) red
          green: (CGFloat *) green
           blue: (CGFloat *) blue
          alpha: (CGFloat *) alpha;
- (void) getHue: (CGFloat *) hue
        saturation: (CGFloat *) saturation
        brightness: (CGFloat *) brightness
             alpha: (CGFloat *) alpha;
- (void) getCyan: (CGFloat *) cyan
         magenta: (CGFloat *) magenta
          yellow: (CGFloat *) yellow
           black: (CGFloat *) black
           alpha: (CGFloat *) alpha;

- (CGFloat) whiteComponent;

- (CGFloat) redComponent;
- (CGFloat) greenComponent;
- (CGFloat) blueComponent;

- (CGFloat) hueComponent;
- (CGFloat) saturationComponent;
- (CGFloat) brightnessComponent;

- (CGFloat) cyanComponent;
- (CGFloat) magentaComponent;
- (CGFloat) yellowComponent;
- (CGFloat) blackComponent;

- (CGFloat) alphaComponent;

- (NSColor *) colorWithAlphaComponent: (CGFloat) alpha;

- (NSColor *) colorUsingColorSpaceName: (NSString *) colorSpace;
- (NSColor *) colorUsingColorSpaceName: (NSString *) colorSpace
                                device: (NSDictionary *) device;
- (NSColor *) colorUsingColorSpace: (NSColorSpace *) space;

- (NSColor *) blendedColorWithFraction: (CGFloat) fraction
                               ofColor: (NSColor *) color;

- (void) set;
- (void) setStroke;
- (void) setFill;

- (void) drawSwatchInRect: (NSRect) rect;

- (void) writeToPasteboard: (NSPasteboard *) pasteboard;

@end
