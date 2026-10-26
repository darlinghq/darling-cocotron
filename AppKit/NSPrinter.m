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

#import <AppKit/NSPrinter.h>
#import <AppKit/NSGraphics.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>

@implementation NSPrinter

static NSPrinter *s_genericPrinter = nil;

+ (void) initialize {
    if (self == [NSPrinter class]) {
        s_genericPrinter = [[NSPrinter alloc] initWithName: @"Generic PostScript Printer" type: @"PostScript"];
    }
}

+ (NSArray *) printerNames {
    return [NSArray arrayWithObject: @"Generic PostScript Printer"];
}

+ (NSArray *) printerTypes {
    return [NSArray arrayWithObject: @"PostScript"];
}

+ (NSPrinter *) printerWithName: (NSString *) name {
    if (name == nil || [name length] == 0)
        return s_genericPrinter;
    return [[[self alloc] initWithName: name type: @"PostScript"] autorelease];
}

+ (NSPrinter *) printerWithType: (NSString *) type {
    if (type == nil || [type length] == 0)
        return s_genericPrinter;
    return [[[self alloc] initWithName: @"Generic PostScript Printer" type: type] autorelease];
}

- initWithName: (NSString *) name type: (NSString *) type {
    self = [super init];
    if (self) {
        _name = [name copy];
        _type = [type copy];
    }
    return self;
}

- (void) dealloc {
    [_name release];
    [_type release];
    [super dealloc];
}

- (NSString *) name {
    return _name ? _name : @"Generic PostScript Printer";
}

- (NSString *) type {
    return _type ? _type : @"PostScript";
}

- (int) languageLevel {
    return 2;
}

- (NSSize) pageSizeForPaper: (NSString *) paperName {
    // Default US Letter: 8.5 x 11 inches at 72 dpi = 612 x 792 points
    return NSMakeSize(612.0, 792.0);
}

- (NSRect) imageablePageBoundsForPaper: (NSString *) paperName {
    // 0.25 inch margins = 18 points margin
    return NSMakeRect(18.0, 18.0, 576.0, 756.0);
}

- (NSRect) rectForPaper: (NSString *) paperName {
    return NSMakeRect(0.0, 0.0, 612.0, 792.0);
}

- (BOOL) isColor {
    return YES;
}

- (BOOL) isFontAvailable: (NSString *) fontName {
    return YES;
}

- (BOOL) isOutputOrderNormal {
    return YES;
}

- (NSDictionary *) deviceDescription {
    return [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool: YES], NSDeviceIsPrinter,
        [NSValue valueWithSize: [self pageSizeForPaper: nil]], NSDeviceSize,
        [NSValue valueWithSize: NSMakeSize(72.0, 72.0)], NSDeviceResolution,
        NSDeviceRGBColorSpace, NSDeviceColorSpaceName,
        [NSNumber numberWithInt: 8], NSDeviceBitsPerSample,
        nil];
}

- (NSMethodSignature *) methodSignatureForSelector: (SEL) aSelector {
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void) forwardInvocation: (NSInvocation *) anInvocation {
    NSLog(@"NSPrinter stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
