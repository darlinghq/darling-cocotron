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
#import <AppKit/AppKitIvarLayout.h>
#import <Foundation/Foundation.h>

typedef NSString *NSPasteboardType NS_EXTENSIBLE_STRING_ENUM;
typedef NSString *NSPasteboardName NS_EXTENSIBLE_STRING_ENUM;

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
APPKIT_EXPORT const NSPasteboardType NSPasteboardTypeURL;
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
APPKIT_EXPORT const NSPasteboardName NSPasteboardNameDrag;
APPKIT_EXPORT const NSPasteboardType NSPasteboardURLReadingFileURLsOnlyKey;

APPKIT_EXPORT const NSPasteboardName NSDragPboard;
APPKIT_EXPORT const NSPasteboardName NSFindPboard;
APPKIT_EXPORT const NSPasteboardName NSFontPboard;
APPKIT_EXPORT const NSPasteboardName NSGeneralPboard;
APPKIT_EXPORT const NSPasteboardName NSRulerPboard;

APPKIT_EXPORT const NSPasteboardName NSPasteboardNameFind;
APPKIT_EXPORT const NSPasteboardName NSPasteboardNameFont;
APPKIT_EXPORT const NSPasteboardName NSPasteboardNameRuler;
APPKIT_EXPORT const NSPasteboardName NSPasteboardNameGeneral;

typedef NSString *NSPasteboardReadingOptionKey NS_STRING_ENUM;

APPKIT_EXPORT const NSPasteboardReadingOptionKey
        NSPasteboardURLReadingContentsConformToTypesKey;

@class NSPasteboard;
@class NSPasteboardItem;
@protocol NSPasteboardWriting;
@protocol NSPasteboardReading;
@class NSFileWrapper;

// @interface NSObject (NSPasteboard)
@protocol NSPasteboardTypeOwner
- (void) pasteboard: (NSPasteboard *) sender
        provideDataForType: (NSPasteboardType) type;
@optional
- (void) pasteboardChangedOwner: (NSPasteboard *) sender;
@end

// What the system lets a process do with a pasteboard it did not fill (macOS 15.4). Nothing is
// enforced here: the general pasteboard reports the default, any other one always allows.
typedef NS_ENUM(NSInteger, NSPasteboardAccessBehavior) {
    NSPasteboardAccessBehaviorDefault = 0,
    NSPasteboardAccessBehaviorAsk = 1,
    NSPasteboardAccessBehaviorAlwaysAllow = 2,
    NSPasteboardAccessBehaviorAlwaysDeny = 3,
};

typedef NS_OPTIONS(NSUInteger, NSPasteboardContentsOptions) {
    NSPasteboardContentsCurrentHostOnly = 1 << 0,
};

typedef NS_OPTIONS(NSUInteger, NSPasteboardWritingOptions) {
    NSPasteboardWritingPromised = 1 << 9,
};

typedef NS_OPTIONS(NSUInteger, NSPasteboardReadingOptions) {
    NSPasteboardReadingAsData = 0,
    NSPasteboardReadingAsString = 1 << 0,
    NSPasteboardReadingAsPropertyList = 1 << 1,
    NSPasteboardReadingAsKeyedArchive = 1 << 2,
};

@interface NSPasteboard : NSObject {
    NS_LEGACY_IVAR_PAD(_NSPasteboardReserved, 44)
}

@property(class, readonly, retain, nonnull) NSPasteboard *generalPasteboard;
+ (NSPasteboard *) pasteboardWithName: (NSPasteboardName) name;
+ (NSPasteboard *) pasteboardWithUniqueName;

- (NSPasteboardName) name;
- (NSInteger) changeCount;
@property(readonly, assign) NSPasteboardAccessBehavior accessBehavior;

- (NSInteger) prepareForNewContentsWithOptions: (NSPasteboardContentsOptions) options;
- (NSInteger) clearContents;
- (oneway void) releaseGlobally;

- (BOOL) writeObjects: (NSArray<id<NSPasteboardWriting> > *) objects;
- (NSArray *) readObjectsForClasses: (NSArray<Class> *) classArray
                            options: (NSDictionary<NSPasteboardReadingOptionKey, id> *) options;
@property(nullable, readonly, copy) NSArray<NSPasteboardItem *> *pasteboardItems;
- (NSUInteger) indexOfPasteboardItem: (NSPasteboardItem *) pasteboardItem;
- (BOOL) canReadItemWithDataConformingToTypes: (NSArray<NSString *> *) types;
- (BOOL) canReadObjectForClasses: (NSArray<Class> *) classArray
                         options: (NSDictionary<NSPasteboardReadingOptionKey, id> *) options;

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

@end

// Services that convert the contents of a pasteboard (deprecated, 10.0 - 10.12 in practice): no
// filters are installed, so a type can only be "filtered" to itself.
@interface NSPasteboard (FilterServices)
+ (NSArray<NSPasteboardType> *) typesFilterableTo: (NSPasteboardType) type;
+ (NSPasteboard *) pasteboardByFilteringFile: (NSString *) filename;
+ (NSPasteboard *) pasteboardByFilteringData: (NSData *) data ofType: (NSPasteboardType) type;
+ (NSPasteboard *) pasteboardByFilteringTypesInPasteboard: (NSPasteboard *) pboard;
@end

// File contents (the NXFileContentsPboardType and file wrapper types).
@interface NSPasteboard (NSFileContents)
- (BOOL) writeFileContents: (NSString *) filename;
- (NSString *) readFileContentsType: (NSPasteboardType) type toFile: (NSString *) filename;
- (BOOL) writeFileWrapper: (NSFileWrapper *) wrapper;
- (NSFileWrapper *) readFileWrapper;
@end

// The informal protocol of the types owners of the 10.0 API; NSPasteboardTypeOwner replaces it.
@interface NSObject (NSPasteboardOwner)
- (void) pasteboard: (NSPasteboard *) sender provideDataForType: (NSPasteboardType) type;
- (void) pasteboardChangedOwner: (NSPasteboard *) sender;
@end

// The objects -writeObjects: accepts: NSString, NSAttributedString, NSURL, NSColor, NSImage,
// NSPasteboardItem, and any class of the application that adopts the protocol.
@protocol NSPasteboardWriting <NSObject>
@required
- (NSArray<NSPasteboardType> *) writableTypesForPasteboard: (NSPasteboard *) pasteboard;
@optional
- (NSPasteboardWritingOptions) writingOptionsForType: (NSPasteboardType) type
                                          pasteboard: (NSPasteboard *) pasteboard;
@required
- (nullable id) pasteboardPropertyListForType: (NSPasteboardType) type;
@end

@protocol NSPasteboardReading <NSObject>
@required
+ (NSArray<NSPasteboardType> *) readableTypesForPasteboard: (NSPasteboard *) pasteboard;
@optional
+ (NSPasteboardReadingOptions) readingOptionsForType: (NSPasteboardType) type
                                          pasteboard: (NSPasteboard *) pasteboard;
- (nullable id) initWithPasteboardPropertyList: (id) propertyList ofType: (NSPasteboardType) type;
@end

@interface NSURL (NSPasteboardSupport) <NSPasteboardWriting, NSPasteboardReading>
+ (NSURL *) URLFromPasteboard: (NSPasteboard *) pasteBoard;
- (void) writeToPasteboard: (NSPasteboard *) pasteBoard;
@end

@interface NSString (NSPasteboardSupport) <NSPasteboardWriting, NSPasteboardReading>
@end

@interface NSAttributedString (NSPasteboardSupport) <NSPasteboardWriting, NSPasteboardReading>
@end

APPKIT_EXPORT NSPasteboardType const NSPasteboardTypeSound;
APPKIT_EXPORT NSPasteboardType const NSPasteboardTypeTextFinderOptions;
APPKIT_EXPORT NSPasteboardType const NSPasteboardTypeFindPanelSearchOptions;
