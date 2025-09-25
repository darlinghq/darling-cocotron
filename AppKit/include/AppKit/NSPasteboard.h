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
#import <Foundation/Foundation.h>

typedef NSString *NSPasteboardType;
typedef NSString *NSPasteboardName;

// New Pasteboard Types (added in 10.6) and interchangeable with the old
// pasteboard types in Cocotron
APPKIT_EXPORT const NSPasteboardType NSPasteboardTypeString;
APPKIT_EXPORT const NSPasteboardType NSPasteboardTypePDF;
APPKIT_EXPORT const NSPasteboardType NSPasteboardTypePNG;
APPKIT_EXPORT const NSPasteboardType NSPasteboardTypeTIFF;
APPKIT_EXPORT const NSPasteboardType NSPasteboardTypeRTF;
APPKIT_EXPORT const NSPasteboardType NSPasteboardTypeRTFD;
APPKIT_EXPORT const NSPasteboardType NSPasteboardTypeHTML;
APPKIT_EXPORT const NSPasteboardType NSPasteboardTypeTabularText;
APPKIT_EXPORT const NSPasteboardType NSPasteboardTypeFont;
APPKIT_EXPORT const NSPasteboardType NSPasteboardTypeRuler;
APPKIT_EXPORT const NSPasteboardType NSPasteboardTypeColor;
APPKIT_EXPORT const NSPasteboardType NSPasteboardTypeFileURL;
APPKIT_EXPORT const NSPasteboardType NSPasteboardTypeMultipleTextSelection;

// Old Pasteboard Types
APPKIT_EXPORT const NSPasteboardType NSColorPboardType;
APPKIT_EXPORT const NSPasteboardType NSFileContentsPboardType;
APPKIT_EXPORT const NSPasteboardType NSFilenamesPboardType;
APPKIT_EXPORT const NSPasteboardType NSFontPboardType;
APPKIT_EXPORT const NSPasteboardType NSPDFPboardType;
APPKIT_EXPORT const NSPasteboardType NSPICTPboardType;
APPKIT_EXPORT const NSPasteboardType NSPostScriptPboardType;
APPKIT_EXPORT const NSPasteboardType NSRTFDPboardType;
APPKIT_EXPORT const NSPasteboardType NSRTFPboardType;
APPKIT_EXPORT const NSPasteboardType NSRulerPboardType;
APPKIT_EXPORT const NSPasteboardType NSStringPboardType;
APPKIT_EXPORT const NSPasteboardType NSTabularTextPboardType;
APPKIT_EXPORT const NSPasteboardType NSTIFFPboardType;
APPKIT_EXPORT const NSPasteboardType NSURLPboardType;
APPKIT_EXPORT const NSPasteboardType NSHTMLPboardType;
APPKIT_EXPORT const NSPasteboardType NSVCardPboardType;
APPKIT_EXPORT const NSPasteboardType NSInkTextPboardType;
APPKIT_EXPORT const NSPasteboardType NSMultipleTextSelectionPboardType;

APPKIT_EXPORT const NSPasteboardType NSFilesPromisePboardType;
APPKIT_EXPORT const NSPasteboardType NSPasteboardNameDrag;
APPKIT_EXPORT const NSPasteboardType NSPasteboardURLReadingFileURLsOnlyKey;

APPKIT_EXPORT const NSPasteboardName NSDragPboard;
APPKIT_EXPORT const NSPasteboardName NSFindPboard;
APPKIT_EXPORT const NSPasteboardName NSFontPboard;
APPKIT_EXPORT const NSPasteboardName NSGeneralPboard;
APPKIT_EXPORT const NSPasteboardName NSRulerPboard;

APPKIT_EXPORT const NSPasteboardName NSPasteboardNameFind;
APPKIT_EXPORT const NSPasteboardName NSPasteboardNameFont;
APPKIT_EXPORT const NSPasteboardName NSPasteboardNameGeneral;

typedef NSString *NSPasteboardReadingOptionKey;

APPKIT_EXPORT const NSPasteboardReadingOptionKey
        NSPasteboardURLReadingContentsConformToTypesKey;

@class NSPasteboard;

// @interface NSObject (NSPasteboard)
@protocol NSPasteboardTypeOwner
- (void) pasteboard: (NSPasteboard *) sender
        provideDataForType: (NSPasteboardType) type;
- (void) pasteboardChangedOwner: (NSPasteboard *) sender;
@end

@interface NSPasteboard : NSObject

+ (NSPasteboard *) generalPasteboard;
+ (NSPasteboard *) pasteboardWithName: (NSPasteboardName) name;

- (NSPasteboardName) name;
- (NSInteger) changeCount;

- (NSInteger) clearContents;
- (oneway void) releaseGlobally;

- (NSArray<NSPasteboardType> *) types;
- (NSPasteboardType) availableTypeFromArray:
        (NSArray<NSPasteboardType> *) types;

- (NSData *) dataForType: (NSPasteboardType) type;
- (NSString *) stringForType: (NSPasteboardType) type;
- propertyListForType: (NSPasteboardType) type;

- (NSInteger) declareTypes: (NSArray<NSPasteboardType> *) types
                     owner: (id<NSPasteboardTypeOwner>) owner;
- (NSInteger) addTypes: (NSArray<NSPasteboardType> *) types
                 owner: (id<NSPasteboardTypeOwner>) owner;

- (BOOL) setData: (NSData *) data forType: (NSPasteboardType) type;
- (BOOL) setString: (NSString *) string forType: (NSPasteboardType) type;
- (BOOL) setPropertyList: plist forType: (NSPasteboardType) type;
- (BOOL) canReadItemWithDataConformingToTypes:(NSArray<NSString *> *) types;
- (NSArray *)readObjectsForClasses:(NSArray<Class> *)classArray options:(NSDictionary<NSPasteboardReadingOptionKey, id> *) options;

@end

@protocol NSPasteboardReading <NSObject>

// TODO

@end

@protocol NSPasteboardWriting <NSObject>

// TODO

@end
