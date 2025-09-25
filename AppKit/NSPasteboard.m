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

#import <AppKit/NSDisplay.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSRaise.h>

const NSPasteboardType NSPasteboardTypeString = @"NSStringPboardType";
const NSPasteboardType NSPasteboardTypePDF = @"NSPDFPboardType";
const NSPasteboardType NSPasteboardTypePNG = @"NSPDFPboardType";
const NSPasteboardType NSPasteboardTypeTIFF = @"NSTIFFPboardType";
const NSPasteboardType NSPasteboardTypeRTF = @"NSRTFPboardType";
const NSPasteboardType NSPasteboardTypeRTFD = @"NSRTFDPboardType";
const NSPasteboardType NSPasteboardTypeHTML = @"NSPasteboardTypeHTML";
const NSPasteboardType NSPasteboardTypeTabularText = @"NSTabularTextPboardType";
const NSPasteboardType NSPasteboardTypeFont = @"NSFontPboardType";
const NSPasteboardType NSPasteboardTypeRuler = @"NSRulerPboardType";
const NSPasteboardType NSPasteboardTypeColor = @"NSColorPboardType";
const NSPasteboardType NSPasteboardTypeFileURL = @"public.file-url";
const NSPasteboardType NSPasteboardTypeMultipleTextSelection =
        @"com.apple.cocoa.pasteboard.multiple-text-selection";

const NSPasteboardType NSColorPboardType = @"NSColorPboardType";
const NSPasteboardType NSFileContentsPboardType = @"NSFileContentsPboardType";
const NSPasteboardType NSFilenamesPboardType = @"NSFilenamesPboardType";
const NSPasteboardType NSFontPboardType = @"NSFontPboardType";
const NSPasteboardType NSPDFPboardType = @"NSPDFPboardType";
const NSPasteboardType NSPICTPboardType = @"NSPICTPboardType";
const NSPasteboardType NSPostScriptPboardType = @"NSPostScriptPboardType";
const NSPasteboardType NSRTFDPboardType = @"NSRTFDPboardType";
const NSPasteboardType NSRTFPboardType = @"NSRTFPboardType";
const NSPasteboardType NSRulerPboardType = @"NSRulerPboardType";
const NSPasteboardType NSStringPboardType = @"NSStringPboardType";
const NSPasteboardType NSTabularTextPboardType = @"NSTabularTextPboardType";
const NSPasteboardType NSTIFFPboardType = @"NSTIFFPboardType";
const NSPasteboardType NSURLPboardType = @"NSURLPboardType";
const NSPasteboardType NSHTMLPboardType = @"Apple HTML pasteboard type";
const NSPasteboardType NSVCardPboardType = @"NSVCardPboardType";
const NSPasteboardType NSInkTextPboardType = @"Apple InkText pasteboard type";
const NSPasteboardType NSMultipleTextSelectionPboardType =
        @"Apple multiple text selection pasteboard type";

const NSPasteboardType NSFilesPromisePboardType =
        @"Apple files promise pasteboard type";

const NSPasteboardName NSPasteboardNameDrag = @"Apple CFPasteboard drag";
NSString *const NSPasteboardURLReadingFileURLsOnlyKey =
        @"NSPasteboardURLReadingFileURLsOnlyKey";

const NSPasteboardName NSDragPboard = @"NSDragPboard";
const NSPasteboardName NSFindPboard = @"NSFindPboard";
const NSPasteboardName NSFontPboard = @"NSFontPboard";
const NSPasteboardName NSGeneralPboard = @"NSGeneralPboard";
const NSPasteboardName NSRulerPboard = @"NSRulerPboard";

const NSPasteboardName NSPasteboardNameFind = @"Apple CFPasteboard find";
const NSPasteboardName NSPasteboardNameFont = @"Apple CFPasteboard font";
const NSPasteboardName NSPasteboardNameGeneral = @"Apple CFPasteboard general";

const NSPasteboardReadingOptionKey
        NSPasteboardURLReadingContentsConformToTypesKey =
                @"NSPasteboardURLReadingContentsConformToTypesKey";

@implementation NSPasteboard

+ (NSPasteboard *) generalPasteboard {
    return [self pasteboardWithName: NSGeneralPboard];
}

+ (NSPasteboard *) pasteboardWithName: (NSPasteboardName) name {
    return [[NSDisplay currentDisplay] pasteboardWithName: name];
}

- (NSPasteboardName) name {
    NSUnimplementedMethod();
    return nil;
}

- (NSInteger) changeCount {
    NSUnimplementedMethod();
    return 0;
}

- (NSInteger) clearContents {
    NSUnimplementedMethod();
    return 0;
}

- (oneway void) releaseGlobally {
    NSUnimplementedMethod();
}

- (NSArray<NSPasteboardType> *) types {
    NSUnimplementedMethod();
    return nil;
}

- (NSPasteboardType) availableTypeFromArray: (NSArray<NSPasteboardType> *) types
{
    NSArray<NSPasteboardType> *available = [self types];
    for (NSPasteboardType type in types) {
        if ([available containsObject: type]) {
            return type;
        }
    }
    return nil;
}

- (NSData *) dataForType: (NSPasteboardType) type {
    NSUnimplementedMethod();
    return nil;
}

- (NSString *) stringForType: (NSPasteboardType) type {
    NSData *data = [self dataForType: type];

    return [[[NSString alloc] initWithData: data
                                  encoding: NSUnicodeStringEncoding]
            autorelease];
}

- (id) propertyListForType: (NSPasteboardType) type {
    NSData *data = [self dataForType: type];
    NSString *errorDesc = nil;
    id plist = [NSPropertyListSerialization
            propertyListFromData: data
                mutabilityOption: NSPropertyListImmutable
                          format: NULL
                errorDescription: &errorDesc];
    if (plist && errorDesc == nil) {
        return plist;
    }
    NSLog(@"propertyListForType: produced error: %@", errorDesc);
    return nil;
}

- (NSInteger) declareTypes: (NSArray<NSPasteboardType> *) types
                     owner: (id<NSPasteboardTypeOwner>) owner
{
    NSUnimplementedMethod();
    return 0;
}

- (NSInteger) addTypes: (NSArray<NSPasteboardType> *) types
                 owner: (id<NSPasteboardTypeOwner>) owner
{
    NSUnimplementedMethod();
    return 0;
}

- (BOOL) setData: (NSData *) data forType: (NSPasteboardType) type {
    NSUnimplementedMethod();
    return NO;
}

- (BOOL) setString: (NSString *) string forType: (NSPasteboardType) type {
    NSData *data = [string dataUsingEncoding: NSUnicodeStringEncoding];
    return [self setData: data forType: type];
}

- (BOOL) setPropertyList: (id) plist forType: (NSPasteboardType) type {
    NSString *errorDesc = nil;
    NSData *data = [NSPropertyListSerialization
            dataFromPropertyList: plist
                          format: NSPropertyListXMLFormat_v1_0
                errorDescription: &errorDesc];
    if (data && errorDesc == nil) {
        return [self setData: data forType: type];
    }
    NSLog(@"setPropertyList:forType: produced error: %@", errorDesc);
    return NO;
}

- (BOOL) canReadItemWithDataConformingToTypes:(NSArray<NSString *> *) types {
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return NO;
}

- (nullable NSArray *)readObjectsForClasses:(NSArray<Class> *)classArray options:(nullable NSDictionary<NSPasteboardReadingOptionKey, id> *) options {
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

@end
