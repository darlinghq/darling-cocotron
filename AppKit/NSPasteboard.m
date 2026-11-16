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
#import <AppKit/NSPasteboardItem.h>
#import <AppKit/NSRaise.h>
#import "NSPasteboardAliases.h"
#import <LaunchServices/LaunchServices.h>
#import <objc/runtime.h>

// The pasteboard types. The UTI names are what macOS uses for NSPasteboardTypeXxx; the older
// NSXxxPboardType names are the 10.0 - 10.5 strings (see NSPasteboardAliases.h).
const NSPasteboardType NSPasteboardTypeString = @"public.utf8-plain-text";
const NSPasteboardType NSPasteboardTypePDF = @"com.adobe.pdf";
const NSPasteboardType NSPasteboardTypePNG = @"public.png";
const NSPasteboardType NSPasteboardTypeTIFF = @"public.tiff";
const NSPasteboardType NSPasteboardTypeRTF = @"public.rtf";
const NSPasteboardType NSPasteboardTypeRTFD = @"com.apple.flat-rtfd";
const NSPasteboardType NSPasteboardTypeHTML = @"public.html";
const NSPasteboardType NSPasteboardTypeTabularText = @"public.utf8-tab-separated-values-text";
const NSPasteboardType NSPasteboardTypeFont = @"com.apple.cocoa.pasteboard.character-formatting";
const NSPasteboardType NSPasteboardTypeRuler = @"com.apple.cocoa.pasteboard.paragraph-formatting";
const NSPasteboardType NSPasteboardTypeURL = @"public.url";
const NSPasteboardType NSPasteboardTypeColor = @"com.apple.cocoa.pasteboard.color";
const NSPasteboardType NSPasteboardTypeFileURL = @"public.file-url";
const NSPasteboardType NSPasteboardTypeMultipleTextSelection = @"com.apple.cocoa.pasteboard.multiple-text-selection";

const NSPasteboardType NSColorPboardType = @"NSColor pasteboard type";
const NSPasteboardType NSFileContentsPboardType = @"NXFileContentsPboardType";
const NSPasteboardType NSFilenamesPboardType = @"NSFilenamesPboardType";
const NSPasteboardType NSFontPboardType = @"NeXT font pasteboard type";
const NSPasteboardType NSPDFPboardType = @"Apple PDF pasteboard type";
const NSPasteboardType NSPICTPboardType = @"Apple PICT pasteboard type";
const NSPasteboardType NSPostScriptPboardType = @"NeXT Encapsulated PostScript v1.2 pasteboard type";
const NSPasteboardType NSRTFDPboardType = @"NeXT RTFD pasteboard type";
const NSPasteboardType NSRTFPboardType = @"NeXT Rich Text Format v1.0 pasteboard type";
const NSPasteboardType NSRulerPboardType = @"NeXT ruler pasteboard type";
const NSPasteboardType NSStringPboardType = @"NSStringPboardType";
const NSPasteboardType NSTabularTextPboardType = @"NeXT tabular text pasteboard type";
const NSPasteboardType NSTIFFPboardType = @"NeXT TIFF v4.0 pasteboard type";
const NSPasteboardType NSURLPboardType = @"Apple URL pasteboard type";
const NSPasteboardType NSHTMLPboardType = @"Apple HTML pasteboard type";
const NSPasteboardType NSVCardPboardType = @"Apple VCard pasteboard type";
const NSPasteboardType NSInkTextPboardType = @"Apple InkText pasteboard type";
const NSPasteboardType NSMultipleTextSelectionPboardType = @"Apple multiple text selection pasteboard type";

const NSPasteboardType NSFilesPromisePboardType =
        @"Apple files promise pasteboard type";

NSString *const NSPasteboardURLReadingFileURLsOnlyKey =
        @"NSPasteboardURLReadingFileURLsOnlyKey";

// The older pasteboard names are the names of the CFPasteboards on macOS, so both spellings reach
// the same pasteboard.
const NSPasteboardName NSPasteboardNameDrag = @"Apple CFPasteboard drag";
const NSPasteboardName NSPasteboardNameFind = @"Apple CFPasteboard find";
const NSPasteboardName NSPasteboardNameFont = @"Apple CFPasteboard font";
const NSPasteboardName NSPasteboardNameGeneral = @"Apple CFPasteboard general";
const NSPasteboardName NSPasteboardNameRuler = @"Apple CFPasteboard ruler";

const NSPasteboardName NSDragPboard = @"Apple CFPasteboard drag";
const NSPasteboardName NSFindPboard = @"Apple CFPasteboard find";
const NSPasteboardName NSFontPboard = @"Apple CFPasteboard font";
const NSPasteboardName NSGeneralPboard = @"Apple CFPasteboard general";
const NSPasteboardName NSRulerPboard = @"Apple CFPasteboard ruler";

const NSPasteboardReadingOptionKey
        NSPasteboardURLReadingContentsConformToTypesKey =
                @"NSPasteboardURLReadingContentsConformToTypesKey";

#pragma mark - Type names

static NSArray<NSArray<NSPasteboardType> *> *aliasPairs(void) {
    // { UTI, older name }; the older name names the same data.
    static NSArray *pairs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      pairs = [@[
          @[ NSPasteboardTypeString, NSStringPboardType ],
          @[ NSPasteboardTypeTIFF, NSTIFFPboardType ],
          @[ NSPasteboardTypePDF, NSPDFPboardType ],
          @[ NSPasteboardTypeRTF, NSRTFPboardType ],
          @[ NSPasteboardTypeRTFD, NSRTFDPboardType ],
          @[ NSPasteboardTypeHTML, NSHTMLPboardType ],
          @[ NSPasteboardTypeTabularText, NSTabularTextPboardType ],
          @[ NSPasteboardTypeFont, NSFontPboardType ],
          @[ NSPasteboardTypeRuler, NSRulerPboardType ],
          @[ NSPasteboardTypeColor, NSColorPboardType ],
          @[ NSPasteboardTypeMultipleTextSelection, NSMultipleTextSelectionPboardType ],
      ] retain];
    });
    return pairs;
}

static NSDictionary<NSPasteboardType, NSPasteboardType> *legacyToCanonical(void) {
    static NSDictionary *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      NSMutableDictionary *result = [NSMutableDictionary dictionary];
      for (NSArray *pair in aliasPairs())
          result[pair[1]] = pair[0];
      table = [result copy];
    });
    return table;
}

static NSDictionary<NSPasteboardType, NSPasteboardType> *canonicalToLegacy(void) {
    static NSDictionary *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      NSMutableDictionary *result = [NSMutableDictionary dictionary];
      for (NSArray *pair in aliasPairs())
          result[pair[0]] = pair[1];
      table = [result copy];
    });
    return table;
}

NSPasteboardType NSPasteboardCanonicalType(NSPasteboardType type) {
    if (type == nil)
        return nil;
    NSPasteboardType canonical = legacyToCanonical()[type];
    return canonical != nil ? canonical : type;
}

NSPasteboardType NSPasteboardLegacyAliasOfType(NSPasteboardType type) {
    return type == nil ? nil : canonicalToLegacy()[type];
}

NSArray<NSPasteboardType> *NSPasteboardCanonicalTypes(NSArray<NSPasteboardType> *types) {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity: [types count]];
    for (NSPasteboardType type in types) {
        NSPasteboardType canonical = NSPasteboardCanonicalType(type);
        if (![result containsObject: canonical])
            [result addObject: canonical];
    }
    return result;
}

NSArray<NSPasteboardType> *NSPasteboardTypesWithAliases(NSArray<NSPasteboardType> *types) {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity: [types count] * 2];
    for (NSPasteboardType canonical in NSPasteboardCanonicalTypes(types)) {
        [result addObject: canonical];
        NSPasteboardType legacy = NSPasteboardLegacyAliasOfType(canonical);
        if (legacy != nil && ![result containsObject: legacy])
            [result addObject: legacy];
    }
    return result;
}

// The parent types of the UTIs a pasteboard commonly holds. The UTI database is consulted too (for
// types this table does not know), but a pasteboard has to answer for these without it.
static NSArray<NSPasteboardType> *parentTypes(NSPasteboardType type) {
    static NSDictionary *parents;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      parents = [@{
          @"public.utf8-plain-text": @[ @"public.plain-text" ],
          @"public.utf16-plain-text": @[ @"public.plain-text" ],
          @"public.utf16-external-plain-text": @[ @"public.plain-text" ],
          @"public.utf8-tab-separated-values-text": @[ @"public.plain-text", @"public.tabular-text" ],
          @"public.plain-text": @[ @"public.text" ],
          @"public.rtf": @[ @"public.text" ],
          @"public.html": @[ @"public.text" ],
          @"com.apple.flat-rtfd": @[ @"public.composite-content" ],
          @"public.text": @[ @"public.data", @"public.content" ],
          @"public.tiff": @[ @"public.image" ],
          @"public.png": @[ @"public.image" ],
          @"public.jpeg": @[ @"public.image" ],
          @"com.compuserve.gif": @[ @"public.image" ],
          @"com.adobe.pdf": @[ @"public.data", @"public.content" ],
          @"public.image": @[ @"public.data", @"public.content" ],
          @"public.file-url": @[ @"public.url" ],
          @"public.url": @[ @"public.data" ],
      } retain];
    });
    return parents[type];
}

BOOL NSPasteboardTypeConformsTo(NSPasteboardType type, NSPasteboardType conformsTo) {
    type = NSPasteboardCanonicalType(type);
    conformsTo = NSPasteboardCanonicalType(conformsTo);
    if ([type isEqual: conformsTo])
        return YES;
    for (NSPasteboardType parent in parentTypes(type)) {
        if (NSPasteboardTypeConformsTo(parent, conformsTo))
            return YES;
    }
    if (type == nil || conformsTo == nil)
        return NO;
    return UTTypeConformsTo((CFStringRef) type, (CFStringRef) conformsTo) ? YES : NO;
}

#pragma mark - Pasteboard item lists

// The items of the last -writeObjects: are remembered with the change count they produced: a
// pasteboard holds one flat set of types (the first item), so the others live beside it until
// something else changes the pasteboard.
static const char kItemListKey;

@interface NSPasteboardItem (NSPasteboardPrivate)
- (id) _initDerivedFromPasteboard: (NSPasteboard *) pasteboard;
- (id) _initWithWritingObject: (id<NSPasteboardWriting>) object pasteboard: (NSPasteboard *) pasteboard;
- (NSArray *) _orderedTypes;
- (BOOL) _hasStoredDataOrPromiseForType: (NSPasteboardType) type;
- (NSPasteboardType) _promiseOnlyOwnerType;
- (void) _attachToPasteboard: (NSPasteboard *) pasteboard;
- (id<NSPasteboardTypeOwner>) _promiseOwner;
- (NSData *) _storedDataForType: (NSPasteboardType) type;
@end

static NSData *dataFromPropertyList(id plist) {
    if (plist == nil)
        return nil;
    if ([plist isKindOfClass: [NSData class]])
        return plist;
    if ([plist isKindOfClass: [NSString class]])
        return [(NSString *) plist dataUsingEncoding: NSUTF8StringEncoding];
    NSString *error = nil;
    NSData *data = [NSPropertyListSerialization dataFromPropertyList: plist
                                                              format: NSPropertyListXMLFormat_v1_0
                                                    errorDescription: &error];
    return data;
}

@implementation NSPasteboard

+ (NSPasteboard *) generalPasteboard {
    return [self pasteboardWithName: NSGeneralPboard];
}

+ (NSPasteboard *) pasteboardWithName: (NSPasteboardName) name {
    return [[NSDisplay currentDisplay] pasteboardWithName: name];
}

+ (NSPasteboard *) pasteboardWithUniqueName {
    NSString *uuid = [[NSUUID UUID] UUIDString];
    return [self pasteboardWithName: [@"Apple CFPasteboard unique " stringByAppendingString: uuid]];
}

- (NSPasteboardName) name {
    NSUnimplementedMethod();
    return nil;
}

- (NSInteger) changeCount {
    NSUnimplementedMethod();
    return 0;
}

// Nothing here lets a process refuse another one the pasteboard, so no behaviour is ever "ask" or
// "deny". The general pasteboard reports the default (macOS never changes it until the first
// access alert has been shown) and every other pasteboard "always allow", as documented.
- (NSPasteboardAccessBehavior) accessBehavior {
    if ([[self name] isEqual: NSPasteboardNameGeneral])
        return NSPasteboardAccessBehaviorDefault;
    return NSPasteboardAccessBehaviorAlwaysAllow;
}

- (NSInteger) clearContents {
    NSUnimplementedMethod();
    return 0;
}

// NSPasteboardContentsCurrentHostOnly keeps the contents off Handoff / Universal Clipboard. This
// system has no such transfer, so the option changes nothing.
- (NSInteger) prepareForNewContentsWithOptions: (NSPasteboardContentsOptions) options {
    return [self clearContents];
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
    NSArray<NSPasteboardType> *available = NSPasteboardTypesWithAliases([self types]);
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
    if (data == nil)
        return nil;

    NSStringEncoding encoding = [NSPasteboardCanonicalType(type) isEqual: NSPasteboardTypeString]
            ? NSUTF8StringEncoding : NSUnicodeStringEncoding;
    return [[[NSString alloc] initWithData: data encoding: encoding] autorelease];
}

- (id) propertyListForType: (NSPasteboardType) type {
    NSData *data = [self dataForType: type];
    if (data == nil)
        return nil;
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
    NSStringEncoding encoding = [NSPasteboardCanonicalType(type) isEqual: NSPasteboardTypeString]
            ? NSUTF8StringEncoding : NSUnicodeStringEncoding;
    NSData *data = [string dataUsingEncoding: encoding];
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

#pragma mark Items

- (NSArray<NSPasteboardItem *> *) pasteboardItems {
    NSDictionary *remembered = objc_getAssociatedObject(self, &kItemListKey);
    if (remembered != nil && [remembered[@"changeCount"] integerValue] == [self changeCount])
        return [[remembered[@"items"] copy] autorelease];

    // Whatever else wrote the pasteboard (a legacy -setData:forType:, another process) has
    // one item, made of all the types there are.
    NSArray *flat = NSPasteboardCanonicalTypes([self types]);
    if ([flat count] == 0)
        return [NSArray array];

    // Except for a list of file names (the 10.0 way, and what a drag from a file manager brings):
    // every file of it is an item of its own, a file URL.
    if ([flat containsObject: NSFilenamesPboardType] && ![flat containsObject: NSPasteboardTypeFileURL]) {
        id paths = [self propertyListForType: NSFilenamesPboardType];
        if ([paths isKindOfClass: [NSArray class]] && [paths count] > 0) {
            NSMutableArray *items = [NSMutableArray array];
            for (id path in paths) {
                if (![path isKindOfClass: [NSString class]])
                    continue;
                NSPasteboardItem *item = [[[NSPasteboardItem alloc] init] autorelease];
                [item setString: [[NSURL fileURLWithPath: path] absoluteString] forType: NSPasteboardTypeFileURL];
                [items addObject: item];
            }
            if ([items count] > 0)
                return items;
        }
    }

    NSPasteboardItem *item = [[[NSPasteboardItem alloc] _initDerivedFromPasteboard: self] autorelease];
    return [NSArray arrayWithObject: item];
}

- (NSUInteger) indexOfPasteboardItem: (NSPasteboardItem *) pasteboardItem {
    return [[self pasteboardItems] indexOfObjectIdenticalTo: pasteboardItem];
}

// Remembers the items a write produced under the change count the pasteboard has now.
- (void) _rememberItems: (NSArray *) items {
    objc_setAssociatedObject(self, &kItemListKey,
                             [NSDictionary dictionaryWithObjectsAndKeys:
                                     [NSNumber numberWithInteger: [self changeCount]], @"changeCount",
                                     items, @"items", nil],
                             OBJC_ASSOCIATION_RETAIN);
}

// The flat contents of the pasteboard are the first item. File URLs of any item also appear as the
// older list of file names, which is how applications that predate file URLs read them.
- (void) _writeFirstItemToTypes: (NSPasteboardItem *) item {
    for (NSPasteboardType type in [item _orderedTypes]) {
        NSData *data = [item _storedDataForType: type];
        if (data != nil) {
            [self addTypes: [NSArray arrayWithObject: type] owner: nil];
            [self setData: data forType: type];
        } else {
            [self addTypes: [NSArray arrayWithObject: type] owner: [item _promiseOwner]];
        }
    }
}

- (void) _writeLegacyTypesOfItems: (NSArray *) items {
    NSMutableArray *paths = [NSMutableArray array];
    for (NSPasteboardItem *item in items) {
        NSData *data = [item _storedDataForType: NSPasteboardTypeFileURL];
        if (data == nil)
            continue;
        NSString *string = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
        NSURL *url = string != nil ? [NSURL URLWithString: string] : nil;
        if ([url isFileURL] && [url path] != nil)
            [paths addObject: [url path]];
    }
    if ([paths count] > 0) {
        [self addTypes: [NSArray arrayWithObject: NSFilenamesPboardType] owner: nil];
        [self setPropertyList: paths forType: NSFilenamesPboardType];
    }

    // The 10.0 URL type holds the URL of the first item that is one.
    for (NSPasteboardItem *item in items) {
        NSData *data = [item _storedDataForType: NSPasteboardTypeURL];
        if (data == nil)
            data = [item _storedDataForType: NSPasteboardTypeFileURL];
        NSString *string = data != nil ? [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease] : nil;
        if (string != nil) {
            [self addTypes: [NSArray arrayWithObject: NSURLPboardType] owner: nil];
            [self setPropertyList: [NSArray arrayWithObjects: string, @"", nil] forType: NSURLPboardType];
            break;
        }
    }
}

- (BOOL) writeObjects: (NSArray<id<NSPasteboardWriting> > *) objects {
    // The objects are added to what the pasteboard holds (-clearContents is the caller's call).
    NSMutableArray *items = [NSMutableArray arrayWithArray: [self pasteboardItems]];
    NSUInteger firstNew = [items count];

    for (id object in objects) {
        NSPasteboardItem *item = nil;
        if ([object isKindOfClass: [NSPasteboardItem class]])
            item = object;
        else if ([object conformsToProtocol: @protocol(NSPasteboardWriting)])
            item = [[[NSPasteboardItem alloc] _initWithWritingObject: object pasteboard: self] autorelease];

        if (item == nil) {
            // Not a writer: skipped, and the others are still written.
            NSLog(@"Instances of class %@ not valid for NSPasteboard -writeObjects:.  The class %@ does "
                  "not implement the NSPasteboardWriting protocol.",
                  [object class], [object class]);
            continue;
        }
        [items addObject: item];
    }

    if (firstNew == 0 && [items count] > 0) {
        [self _writeFirstItemToTypes: [items objectAtIndex: 0]];
        [[items objectAtIndex: 0] _attachToPasteboard: self];
    }
    [self _writeLegacyTypesOfItems: [items subarrayWithRange: NSMakeRange(firstNew, [items count] - firstNew)]];
    [self _rememberItems: items];
    return YES;
}

#pragma mark Reading objects

// The data of a pasteboard item for one type, converted the way the class asked for.
static id readingValue(NSPasteboardItem *item, NSPasteboardType type, Class cls, NSPasteboard *pasteboard) {
    NSPasteboardReadingOptions options = NSPasteboardReadingAsData;
    if ([cls respondsToSelector: @selector(readingOptionsForType:pasteboard:)])
        options = [cls readingOptionsForType: type pasteboard: pasteboard];

    NSData *data = [item dataForType: type];
    if (data == nil)
        return nil;

    if (options & NSPasteboardReadingAsKeyedArchive)
        return [NSKeyedUnarchiver unarchiveObjectWithData: data];
    if (options & NSPasteboardReadingAsPropertyList)
        return [item propertyListForType: type];
    if (options & NSPasteboardReadingAsString)
        return [item stringForType: type];
    return data;
}

// The types of the item that the class can read, in the class's order of preference.
static NSPasteboardType readableTypeOfItem(NSPasteboardItem *item, Class cls, NSPasteboard *pasteboard,
                                           NSDictionary *options)
{
    NSArray *itemTypes = [item types];
    BOOL fileURLsOnly = [[options objectForKey: NSPasteboardURLReadingFileURLsOnlyKey] boolValue]
            && [cls isSubclassOfClass: [NSURL class]];

    for (NSPasteboardType readable in [cls readableTypesForPasteboard: pasteboard]) {
        if (fileURLsOnly && !NSPasteboardTypeConformsTo(readable, NSPasteboardTypeFileURL))
            continue;
        for (NSPasteboardType itemType in itemTypes) {
            if (NSPasteboardTypeConformsTo(itemType, readable))
                return itemType;
        }
    }
    return nil;
}

- (NSArray *) readObjectsForClasses: (NSArray<Class> *) classArray
                            options: (NSDictionary<NSPasteboardReadingOptionKey, id> *) options
{
    NSMutableArray *result = [NSMutableArray array];

    for (NSPasteboardItem *item in [self pasteboardItems]) {
        for (Class cls in classArray) {
            if ([cls isSubclassOfClass: [NSPasteboardItem class]]) {
                [result addObject: item];
                break;
            }
            if (![cls conformsToProtocol: @protocol(NSPasteboardReading)])
                continue;

            NSPasteboardType type = readableTypeOfItem(item, cls, self, options);
            if (type == nil)
                continue;
            id value = readingValue(item, type, cls, self);
            if (value == nil)
                continue;

            id object = value;
            NSPasteboardReadingOptions readingOptions = NSPasteboardReadingAsData;
            if ([cls respondsToSelector: @selector(readingOptionsForType:pasteboard:)])
                readingOptions = [cls readingOptionsForType: type pasteboard: self];
            if (!(readingOptions & NSPasteboardReadingAsKeyedArchive) &&
                [cls instancesRespondToSelector: @selector(initWithPasteboardPropertyList:ofType:)])
                object = [[[cls alloc] initWithPasteboardPropertyList: value ofType: type] autorelease];

            if (object == nil)
                continue;
            if ([[options objectForKey: NSPasteboardURLReadingFileURLsOnlyKey] boolValue] &&
                [object isKindOfClass: [NSURL class]] && ![object isFileURL])
                continue;
            [result addObject: object];
            break;
        }
    }
    return result;
}

- (BOOL) canReadObjectForClasses: (NSArray<Class> *) classArray
                         options: (NSDictionary<NSPasteboardReadingOptionKey, id> *) options
{
    for (NSPasteboardItem *item in [self pasteboardItems]) {
        for (Class cls in classArray) {
            if ([cls isSubclassOfClass: [NSPasteboardItem class]])
                return YES;
            if ([cls conformsToProtocol: @protocol(NSPasteboardReading)] &&
                readableTypeOfItem(item, cls, self, options) != nil)
                return YES;
        }
    }
    return NO;
}

- (BOOL) canReadItemWithDataConformingToTypes: (NSArray<NSString *> *) types {
    for (NSPasteboardItem *item in [self pasteboardItems]) {
        for (NSPasteboardType itemType in [item types]) {
            for (NSString *type in types) {
                if (NSPasteboardTypeConformsTo(itemType, type))
                    return YES;
            }
        }
    }
    return NO;
}

@end

@implementation NSPasteboard (FilterServices)

// No conversion services are installed, so the only type the contents can be filtered to is the
// type itself.
+ (NSArray<NSPasteboardType> *) typesFilterableTo: (NSPasteboardType) type {
    return [NSArray arrayWithObject: type];
}

+ (NSPasteboard *) pasteboardByFilteringData: (NSData *) data ofType: (NSPasteboardType) type {
    NSPasteboard *pasteboard = [self pasteboardWithUniqueName];
    [pasteboard declareTypes: [NSArray arrayWithObject: type] owner: nil];
    [pasteboard setData: data forType: type];
    return pasteboard;
}

+ (NSPasteboard *) pasteboardByFilteringFile: (NSString *) filename {
    NSData *data = [NSData dataWithContentsOfFile: filename];
    if (data == nil)
        return nil;
    NSPasteboard *pasteboard = [self pasteboardWithUniqueName];
    [pasteboard declareTypes: [NSArray arrayWithObject: NSFileContentsPboardType] owner: nil];
    [pasteboard setData: data forType: NSFileContentsPboardType];
    return pasteboard;
}

+ (NSPasteboard *) pasteboardByFilteringTypesInPasteboard: (NSPasteboard *) source {
    NSPasteboard *pasteboard = [self pasteboardWithUniqueName];
    NSArray *types = NSPasteboardCanonicalTypes([source types]);
    [pasteboard declareTypes: types owner: nil];
    for (NSPasteboardType type in types) {
        NSData *data = [source dataForType: type];
        if (data != nil)
            [pasteboard setData: data forType: type];
    }
    return pasteboard;
}

@end

// A file's contents are put on a pasteboard under NXFileContentsPboardType and, when the name has
// an extension, under a type that carries the extension.
static NSPasteboardType typedFileContentsType(NSString *extension) {
    return [@"NXTypedFileContentsPboardType:" stringByAppendingString: extension];
}

@implementation NSPasteboard (NSFileContents)

- (BOOL) _writeFileContents: (NSData *) data extension: (NSString *) extension {
    NSMutableArray *types = [NSMutableArray array];
    if ([extension length] > 0)
        [types addObject: typedFileContentsType(extension)];
    [types addObject: NSFileContentsPboardType];

    [self addTypes: types owner: nil];
    for (NSPasteboardType type in types)
        [self setData: data forType: type];
    return YES;
}

- (BOOL) writeFileContents: (NSString *) filename {
    NSData *data = [NSData dataWithContentsOfFile: filename];
    if (data == nil)
        return NO;
    return [self _writeFileContents: data extension: [filename pathExtension]];
}

- (NSString *) readFileContentsType: (NSPasteboardType) type toFile: (NSString *) filename {
    if (type == nil) {
        NSString *typed = nil;
        for (NSPasteboardType candidate in [self types]) {
            if ([candidate hasPrefix: @"NXTypedFileContentsPboardType:"])
                typed = candidate;
        }
        type = typed != nil ? typed : NSFileContentsPboardType;
    }
    NSData *data = [self dataForType: type];
    if (data == nil || ![data writeToFile: filename atomically: YES])
        return nil;
    return filename;
}

- (BOOL) writeFileWrapper: (NSFileWrapper *) wrapper {
    if ([wrapper isRegularFile]) {
        NSData *contents = [wrapper regularFileContents];
        if (contents == nil)
            return NO;
        return [self _writeFileContents: contents
                              extension: [[wrapper preferredFilename] pathExtension]];
    }
    NSData *serialized = [wrapper serializedRepresentation];
    if (serialized == nil)
        return NO;
    return [self _writeFileContents: serialized extension: nil];
}

- (NSFileWrapper *) readFileWrapper {
    NSPasteboardType typed = nil;
    for (NSPasteboardType candidate in [self types]) {
        if ([candidate hasPrefix: @"NXTypedFileContentsPboardType:"])
            typed = candidate;
    }
    NSData *data = [self dataForType: typed != nil ? typed : NSFileContentsPboardType];
    if (data == nil)
        return nil;

    NSFileWrapper *wrapper = nil;
    if (typed == nil)
        wrapper = [[[NSFileWrapper alloc] initWithSerializedRepresentation: data] autorelease];
    if (wrapper == nil)
        wrapper = [[[NSFileWrapper alloc] initRegularFileWithContents: data] autorelease];
    if (typed != nil)
        [wrapper setPreferredFilename: [@"file." stringByAppendingString:
                                                [typed substringFromIndex: [@"NXTypedFileContentsPboardType:" length]]]];
    return wrapper;
}

@end

NSPasteboardType const NSPasteboardTypeSound = @"com.apple.cocoa.pasteboard.sound";
NSPasteboardType const NSPasteboardTypeTextFinderOptions = @"com.apple.cocoa.pasteboard.find-panel-search-options";
NSPasteboardType const NSPasteboardTypeFindPanelSearchOptions = @"com.apple.cocoa.pasteboard.find-panel-search-options";
