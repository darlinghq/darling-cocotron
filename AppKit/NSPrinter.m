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
#import <dispatch/dispatch.h>

// Darling has no print queue backend yet (PrintCore is stubbed), so there is one built-in
// printer: a PostScript printer that takes the standard paper sizes.
static NSString *const GenericPrinterName = @"Generic PostScript Printer";
static NSString *const GenericPrinterType = @"PostScript";

// Paper sizes in points, by the names print info uses (and their short forms).
static NSSize paperSizeForName(NSString *name) {
    static NSDictionary *sizes = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSValue *letter = [NSValue valueWithSize: NSMakeSize(612, 792)];
        NSValue *legal = [NSValue valueWithSize: NSMakeSize(612, 1008)];
        NSValue *a3 = [NSValue valueWithSize: NSMakeSize(842, 1191)];
        NSValue *a4 = [NSValue valueWithSize: NSMakeSize(595, 842)];
        NSValue *a5 = [NSValue valueWithSize: NSMakeSize(420, 595)];
        NSValue *tabloid = [NSValue valueWithSize: NSMakeSize(792, 1224)];
        sizes = [[NSDictionary alloc] initWithObjectsAndKeys:
                letter, @"US Letter", letter, @"Letter", legal, @"US Legal", legal, @"Legal",
                a3, @"A3", a4, @"A4", a5, @"A5", tabloid, @"Tabloid", nil];
    });
    NSValue *size = name != nil ? [sizes objectForKey: name] : nil;
    return size != nil ? [size sizeValue] : NSZeroSize;
}

static NSPrinter *genericPrinter = nil;

@interface NSPrinter ()
+ (NSPrinter *) _genericPrinter;
- initWithName: (NSString *) name type: (NSString *) type;
@end

@implementation NSPrinter

+ (NSPrinter *) _genericPrinter {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        genericPrinter = [[NSPrinter alloc] initWithName: GenericPrinterName type: GenericPrinterType];
    });
    return genericPrinter;
}

+ (NSArray *) printerNames {
    return [NSArray arrayWithObject: GenericPrinterName];
}

+ (NSArray *) printerTypes {
    return [NSArray arrayWithObject: GenericPrinterType];
}

+ (NSPrinter *) printerWithName: (NSString *) name {
    return [name isEqualToString: GenericPrinterName] ? [self _genericPrinter] : nil;
}

+ (NSPrinter *) printerWithType: (NSString *) type {
    return [type isEqualToString: GenericPrinterType] ? [self _genericPrinter] : nil;
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
    return _name;
}

- (NSString *) type {
    return _type;
}

- (int) languageLevel {
    return 2;
}

// NSZeroSize for a paper the printer does not know.
- (NSSize) pageSizeForPaper: (NSString *) paperName {
    return paperSizeForName(paperName);
}

- (NSDictionary *) deviceDescription {
    return [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool: YES], NSDeviceIsPrinter,
        [NSValue valueWithSize: [self pageSizeForPaper: @"US Letter"]], NSDeviceSize,
        [NSValue valueWithSize: NSMakeSize(72.0, 72.0)], NSDeviceResolution,
        NSDeviceRGBColorSpace, NSDeviceColorSpaceName,
        [NSNumber numberWithInt: 8], NSDeviceBitsPerSample,
        nil];
}

// The remaining NSPrinter queries (PPD table lookups) have no backend: they do nothing and
// return the zero value.
- (NSMethodSignature *) methodSignatureForSelector: (SEL) aSelector {
    NSMethodSignature *signature = [super methodSignatureForSelector: aSelector];
    return signature != nil ? signature : [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void) forwardInvocation: (NSInvocation *) anInvocation {
}

@end
