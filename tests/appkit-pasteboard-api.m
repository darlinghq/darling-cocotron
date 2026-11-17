/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSPasteboard: the type names, unique pasteboards, the item API (-writeObjects:,
 * -pasteboardItems, -readObjectsForClasses:options:, -canReadObjectForClasses:options:),
 * NSPasteboardItem and the NSPasteboardWriting / NSPasteboardReading adopters, the file
 * content methods. Expected values are what macOS 10.14.4 and 26.7.3 answer for the same calls
 * (probes of the observations: vd-upstream/mac-probes/v615_pasteboard*.m). Only private
 * (unique) pasteboards are used, never the general one. No window server needed.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <unistd.h>

// The API under test, declared here so that the test also builds against an SDK that predates it.
@interface NSPasteboard (V615Test)
+ (NSPasteboard *) pasteboardWithUniqueName;
- (NSInteger) prepareForNewContentsWithOptions: (NSUInteger) options;
- (NSArray *) pasteboardItems;
- (NSUInteger) indexOfPasteboardItem: (id) item;
- (BOOL) writeObjects: (NSArray *) objects;
- (NSArray *) readObjectsForClasses: (NSArray *) classes options: (NSDictionary *) options;
- (BOOL) canReadObjectForClasses: (NSArray *) classes options: (NSDictionary *) options;
- (BOOL) canReadItemWithDataConformingToTypes: (NSArray *) types;
- (BOOL) writeFileContents: (NSString *) filename;
- (NSString *) readFileContentsType: (NSString *) type toFile: (NSString *) filename;
- (BOOL) writeFileWrapper: (NSFileWrapper *) wrapper;
- (NSFileWrapper *) readFileWrapper;
+ (NSArray *) typesFilterableTo: (NSString *) type;
@end

@interface NSPasteboardItem (V615Test)
- (NSArray *) types;
- (NSString *) availableTypeFromArray: (NSArray *) types;
- (BOOL) setDataProvider: (id) provider forTypes: (NSArray *) types;
- (BOOL) setData: (NSData *) data forType: (NSString *) type;
- (BOOL) setString: (NSString *) string forType: (NSString *) type;
- (BOOL) setPropertyList: (id) plist forType: (NSString *) type;
- (NSData *) dataForType: (NSString *) type;
- (NSString *) stringForType: (NSString *) type;
- (id) propertyListForType: (NSString *) type;
@end

static int failures;

#define CHECK(cond, ...) \
    do { \
        if (!(cond)) { \
            failures++; \
            printf("FAIL line %d: ", __LINE__); \
            printf(__VA_ARGS__); \
            printf("\n"); \
        } \
    } while (0)

static BOOL has(NSArray *a, id o) { return [a containsObject: o]; }

static void testConstants(void) {
    CHECK([NSPasteboardTypeString isEqual: @"public.utf8-plain-text"], "string %s", [NSPasteboardTypeString UTF8String]);
    CHECK([NSPasteboardTypePDF isEqual: @"com.adobe.pdf"], "pdf");
    CHECK([NSPasteboardTypePNG isEqual: @"public.png"], "png");
    CHECK([NSPasteboardTypeTIFF isEqual: @"public.tiff"], "tiff");
    CHECK([NSPasteboardTypeRTF isEqual: @"public.rtf"], "rtf");
    CHECK([NSPasteboardTypeRTFD isEqual: @"com.apple.flat-rtfd"], "rtfd");
    CHECK([NSPasteboardTypeHTML isEqual: @"public.html"], "html");
    CHECK([NSPasteboardTypeTabularText isEqual: @"public.utf8-tab-separated-values-text"], "tabular");
    CHECK([NSPasteboardTypeFont isEqual: @"com.apple.cocoa.pasteboard.character-formatting"], "font");
    CHECK([NSPasteboardTypeRuler isEqual: @"com.apple.cocoa.pasteboard.paragraph-formatting"], "ruler");
    CHECK([NSPasteboardTypeURL isEqual: @"public.url"], "url");
    CHECK([NSPasteboardTypeColor isEqual: @"com.apple.cocoa.pasteboard.color"], "color");
    CHECK([NSPasteboardTypeFileURL isEqual: @"public.file-url"], "file url");
    CHECK([NSPasteboardTypeMultipleTextSelection isEqual: @"com.apple.cocoa.pasteboard.multiple-text-selection"], "multi");

    CHECK([NSStringPboardType isEqual: @"NSStringPboardType"], "old string");
    CHECK([NSTIFFPboardType isEqual: @"NeXT TIFF v4.0 pasteboard type"], "old tiff");
    CHECK([NSPDFPboardType isEqual: @"Apple PDF pasteboard type"], "old pdf");
    CHECK([NSRTFPboardType isEqual: @"NeXT Rich Text Format v1.0 pasteboard type"], "old rtf");
    CHECK([NSRTFDPboardType isEqual: @"NeXT RTFD pasteboard type"], "old rtfd");
    CHECK([NSHTMLPboardType isEqual: @"Apple HTML pasteboard type"], "old html");
    CHECK([NSURLPboardType isEqual: @"Apple URL pasteboard type"], "old url");
    CHECK([NSColorPboardType isEqual: @"NSColor pasteboard type"], "old color");
    CHECK([NSFontPboardType isEqual: @"NeXT font pasteboard type"], "old font");
    CHECK([NSRulerPboardType isEqual: @"NeXT ruler pasteboard type"], "old ruler");
    CHECK([NSTabularTextPboardType isEqual: @"NeXT tabular text pasteboard type"], "old tabular");
    CHECK([NSFilenamesPboardType isEqual: @"NSFilenamesPboardType"], "old filenames");
    CHECK([NSFileContentsPboardType isEqual: @"NXFileContentsPboardType"], "old file contents");

    CHECK([NSGeneralPboard isEqual: @"Apple CFPasteboard general"], "general name");
    CHECK([NSPasteboardNameGeneral isEqual: NSGeneralPboard], "general names agree");
    CHECK([NSFindPboard isEqual: @"Apple CFPasteboard find"], "find name");
    CHECK([NSFontPboard isEqual: @"Apple CFPasteboard font"], "font name");
    CHECK([NSRulerPboard isEqual: @"Apple CFPasteboard ruler"], "ruler name");
    CHECK([NSDragPboard isEqual: @"Apple CFPasteboard drag"], "drag name");
}

static void testUniqueAndCounts(void) {
    NSPasteboard *a = [NSPasteboard pasteboardWithUniqueName];
    NSPasteboard *b = [NSPasteboard pasteboardWithUniqueName];
    CHECK(a != nil && b != nil && ![[a name] isEqual: [b name]], "unique names differ");
    CHECK([NSPasteboard pasteboardWithName: [a name]] == a, "the name finds the pasteboard again");
    CHECK([[a types] count] == 0, "a new pasteboard has no types");
    CHECK([[a pasteboardItems] count] == 0, "a new pasteboard has no items");

    NSInteger count = [a clearContents];
    CHECK(count == [a changeCount], "clearContents returns the change count");
    NSInteger before = [a changeCount];
    NSInteger prepared = [a prepareForNewContentsWithOptions: 0];
    CHECK(prepared == [a changeCount] && prepared != before, "prepareForNewContents clears and returns the count");
    before = [a changeCount];
    CHECK([a prepareForNewContentsWithOptions: 1] != before, "host-only option still clears");
    [a releaseGlobally];
    [b releaseGlobally];
}

static void testString(void) {
    NSPasteboard *a = [NSPasteboard pasteboardWithUniqueName];
    [a clearContents];
    CHECK([a writeObjects: @[ @"héllo" ]], "write string");
    NSArray *types = [a types];
    CHECK(has(types, NSPasteboardTypeString) && has(types, NSStringPboardType), "types has both spellings: %s", [[types description] UTF8String]);
    CHECK([types indexOfObject: NSPasteboardTypeString] < [types indexOfObject: NSStringPboardType], "UTI first");
    NSArray *items = [a pasteboardItems];
    CHECK([items count] == 1, "one item");
    NSPasteboardItem *item = items.firstObject;
    CHECK([[item types] isEqual: @[ NSPasteboardTypeString ]], "item types %s", [[[item types] description] UTF8String]);
    CHECK([[item stringForType: NSPasteboardTypeString] isEqual: @"héllo"], "item string");
    CHECK([[a dataForType: NSPasteboardTypeString] length] == 6, "data is UTF-8");
    CHECK([[a stringForType: NSStringPboardType] isEqual: @"héllo"], "old name reads the same data");
    CHECK([[a availableTypeFromArray: @[ NSStringPboardType ]] isEqual: NSStringPboardType], "available, old name");
    CHECK([[a availableTypeFromArray: @[ NSPasteboardTypeString ]] isEqual: NSPasteboardTypeString], "available, new name");
    CHECK([a indexOfPasteboardItem: item] == 0, "index of item");

    CHECK([a canReadObjectForClasses: @[ [NSString class] ] options: nil], "can read NSString");
    CHECK([a canReadObjectForClasses: @[ [NSAttributedString class] ] options: nil], "can read NSAttributedString");
    CHECK(![a canReadObjectForClasses: @[ [NSURL class] ] options: nil], "cannot read NSURL");
    CHECK(![a canReadObjectForClasses: @[ [NSImage class] ] options: nil], "cannot read NSImage");
    CHECK(![a canReadObjectForClasses: @[ [NSColor class] ] options: nil], "cannot read NSColor");
    CHECK([a canReadObjectForClasses: @[ [NSPasteboardItem class] ] options: nil], "can read items");

    NSArray *read = [a readObjectsForClasses: @[ [NSString class] ] options: nil];
    CHECK([read isEqual: @[ @"héllo" ]], "read NSString");
    read = [a readObjectsForClasses: @[ [NSURL class], [NSString class] ] options: nil];
    CHECK([read isEqual: @[ @"héllo" ]], "classes in order: the first that fits");
    read = [a readObjectsForClasses: @[ [NSPasteboardItem class] ] options: nil];
    CHECK([read count] == 1, "read items");
    read = [a readObjectsForClasses: @[ [NSAttributedString class] ] options: nil];
    CHECK([read count] == 1 && [[read[0] string] isEqual: @"héllo"], "read attributed");
    CHECK([a readObjectsForClasses: nil options: nil] != nil, "nil classes: an empty result");
    CHECK([[a readObjectsForClasses: @[] options: nil] count] == 0, "no classes, no objects");

    CHECK([a canReadItemWithDataConformingToTypes: @[ @"public.text" ]], "conforms to public.text");
    CHECK(![a canReadItemWithDataConformingToTypes: @[ @"public.image" ]], "does not conform to public.image");

    // 10.0 API into the same data
    [a clearContents];
    [a setString: @"abc" forType: NSStringPboardType];
    types = [a types];
    CHECK(has(types, NSPasteboardTypeString) && has(types, NSStringPboardType), "old write: both spellings");
    CHECK([[a dataForType: NSPasteboardTypeString] length] == 3, "old write read by new name");
    CHECK([[[a pasteboardItems].firstObject types] isEqual: @[ NSPasteboardTypeString ]], "old write: one UTI item type");
    [a clearContents];
    [a declareTypes: @[ NSStringPboardType, NSTIFFPboardType ] owner: nil];
    types = [a types];
    CHECK([types isEqual: (@[ NSPasteboardTypeString, NSStringPboardType, NSPasteboardTypeTIFF, NSTIFFPboardType ])],
          "declareTypes with the old names: %s", [[types description] UTF8String]);
    [a releaseGlobally];
}

static void testURLs(void) {
    NSPasteboard *a = [NSPasteboard pasteboardWithUniqueName];
    [a clearContents];
    NSURL *web = [NSURL URLWithString: @"http://example.com/x%20y"];
    NSURL *file = [NSURL fileURLWithPath: @"/tmp"];
    CHECK([a writeObjects: (@[ web, file ])], "write urls");
    NSArray *items = [a pasteboardItems];
    CHECK([items count] == 2, "two items");
    CHECK(has([items[0] types], NSPasteboardTypeURL), "first item is a URL");
    CHECK(has([items[1] types], NSPasteboardTypeFileURL), "second item is a file URL");
    CHECK([[items[0] stringForType: NSPasteboardTypeURL] isEqual: @"http://example.com/x%20y"], "URL string");
    CHECK(has([a types], NSFilenamesPboardType), "the file names list is there for old readers");
    NSArray *names = [a propertyListForType: NSFilenamesPboardType];
    CHECK([names isEqual: @[ @"/tmp" ]], "file names list: %s", [[names description] UTF8String]);

    NSArray *read = [a readObjectsForClasses: @[ [NSURL class] ] options: nil];
    CHECK([read count] == 2 && [read[0] isKindOfClass: [NSURL class]], "both read as URLs");
    CHECK([[read[0] host] isEqual: @"example.com"], "web URL host");
    CHECK([read[1] isFileURL] && [[read[1] path] isEqual: @"/tmp"], "file URL path");
    read = [a readObjectsForClasses: @[ [NSURL class] ]
                            options: @{ NSPasteboardURLReadingFileURLsOnlyKey: @YES }];
    CHECK([read count] == 1 && [read[0] isFileURL], "file URLs only: %lu", (unsigned long)[read count]);
    CHECK([[NSURL URLFromPasteboard: a] isFileURL], "URLFromPasteboard");

    // A drop of files in the 10.0 shape: every file is an item
    [a clearContents];
    [a declareTypes: @[ NSFilenamesPboardType ] owner: nil];
    [a setPropertyList: @[ @"/tmp", @"/usr" ] forType: NSFilenamesPboardType];
    items = [a pasteboardItems];
    CHECK([items count] == 2, "file name list: one item per file (%lu)", (unsigned long)[items count]);
    read = [a readObjectsForClasses: @[ [NSURL class] ] options: nil];
    CHECK([read count] == 2 && [[read[1] path] isEqual: @"/usr"], "file name list reads as URLs");
    [a releaseGlobally];
}

static void testColorImageAttributed(void) {
    NSPasteboard *a = [NSPasteboard pasteboardWithUniqueName];
    [a clearContents];
    CHECK([a writeObjects: @[ [NSColor colorWithSRGBRed: 0.1 green: 0.2 blue: 0.3 alpha: 1] ]], "write color");
    CHECK(has([a types], NSPasteboardTypeColor) && has([a types], NSColorPboardType), "color types");
    NSArray *read = [a readObjectsForClasses: @[ [NSColor class] ] options: nil];
    CHECK([read count] == 1 && [read[0] isKindOfClass: [NSColor class]], "read color");
    CHECK([NSColor colorFromPasteboard: a] != nil, "colorFromPasteboard");

    [a clearContents];
    NSImage *image = [[[NSImage alloc] initWithSize: NSMakeSize(4, 4)] autorelease];
    [image lockFocus];
    [[NSColor redColor] set];
    NSRectFill(NSMakeRect(0, 0, 4, 4));
    [image unlockFocus];
    CHECK([a writeObjects: @[ image ]], "write image");
    CHECK(has([a types], NSPasteboardTypeTIFF) && has([a types], NSTIFFPboardType), "image types");
    read = [a readObjectsForClasses: @[ [NSImage class] ] options: nil];
    CHECK([read count] == 1 && [read[0] isKindOfClass: [NSImage class]], "read image");
    CHECK([NSImage canInitWithPasteboard: a], "canInitWithPasteboard");
    CHECK([[NSImage alloc] initWithPasteboard: a] != nil, "initWithPasteboard");

    [a clearContents];
    NSAttributedString *rich = [[[NSAttributedString alloc] initWithString: @"rich" attributes: nil] autorelease];
    CHECK([a writeObjects: @[ rich ]], "write attributed");
    CHECK(has([a types], NSPasteboardTypeRTF) && has([a types], NSPasteboardTypeString), "attributed types: RTF and text");
    CHECK([[a types] indexOfObject: NSPasteboardTypeRTF] < [[a types] indexOfObject: NSPasteboardTypeString], "RTF first");
    read = [a readObjectsForClasses: @[ [NSAttributedString class] ] options: nil];
    CHECK([read count] == 1 && [[read[0] string] isEqual: @"rich"], "read attributed back");
    [a releaseGlobally];
}

@interface Provider : NSObject <NSPasteboardItemDataProvider> {
@public
    int provided;
    int finished;
}
@end
@implementation Provider
- (void) pasteboard: (NSPasteboard *) pasteboard item: (NSPasteboardItem *) item provideDataForType: (NSString *) type {
    provided++;
    [item setString: @"promised" forType: type];
}
- (void) pasteboardFinishedWithDataProvider: (NSPasteboard *) pasteboard {
    finished++;
}
@end

// An application class that takes part in writing and reading
@interface Note : NSObject <NSPasteboardWriting, NSPasteboardReading> {
@public
    NSString *text;
}
@end
@implementation Note
- (NSArray *) writableTypesForPasteboard: (NSPasteboard *) pasteboard { return @[ @"com.example.note" ]; }
- (id) pasteboardPropertyListForType: (NSString *) type { return [@"note:" stringByAppendingString: text]; }
+ (NSArray *) readableTypesForPasteboard: (NSPasteboard *) pasteboard { return @[ @"com.example.note" ]; }
+ (NSPasteboardReadingOptions) readingOptionsForType: (NSString *) type pasteboard: (NSPasteboard *) pasteboard { return NSPasteboardReadingAsString; }
- (id) initWithPasteboardPropertyList: (id) propertyList ofType: (NSString *) type {
    if ((self = [super init]))
        text = [propertyList copy];
    return self;
}
@end

static void testItems(void) {
    NSPasteboard *a = [NSPasteboard pasteboardWithUniqueName];
    [a clearContents];
    NSPasteboardItem *item = [[[NSPasteboardItem alloc] init] autorelease];
    CHECK([[item types] count] == 0, "a new item has no types");
    CHECK([item setString: @"s" forType: @"public.utf8-plain-text"], "setString");
    CHECK([item setData: [@"d" dataUsingEncoding: NSUTF8StringEncoding] forType: @"com.example.d"], "setData");
    CHECK([item setPropertyList: @{ @"k": @1 } forType: @"com.example.plist"], "setPropertyList");
    CHECK([[item types] isEqual: (@[ @"public.utf8-plain-text", @"com.example.d", @"com.example.plist" ])], "types in order of setting");
    CHECK([[item propertyListForType: @"com.example.plist"] isEqual: @{ @"k": @1 }], "property list round trip");
    CHECK([[item dataForType: @"com.example.plist"] length] > 0, "property list stored as data");
    CHECK([item stringForType: @"nope"] == nil, "unknown type: nil string");
    CHECK([item dataForType: @"nope"] == nil, "unknown type: nil data");

    CHECK([a writeObjects: (@[ item, @"second" ])], "write items");
    NSArray *items = [a pasteboardItems];
    CHECK([items count] == 2, "two items");
    CHECK(has([a types], @"com.example.d") && has([a types], @"com.example.plist"), "the first item's types are the pasteboard's");
    CHECK([[items[1] stringForType: NSPasteboardTypeString] isEqual: @"second"], "second item data");
    CHECK([[items[1] availableTypeFromArray: (@[ @"x", NSPasteboardTypeString ])] isEqual: NSPasteboardTypeString], "available type of an item: %s", [[items[1] availableTypeFromArray: (@[ @"x", NSPasteboardTypeString ])] UTF8String]);
    CHECK([[a readObjectsForClasses: @[ [NSString class] ] options: nil] isEqual: (@[ @"s", @"second" ])], "both items read as strings");

    // Adding to what is there
    CHECK([a writeObjects: @[ @"third" ]], "append");
    CHECK([[a pasteboardItems] count] == 3, "append: three items");
    CHECK([a writeObjects: @[]], "an empty write is fine");
    CHECK([[a pasteboardItems] count] == 3, "an empty write changes nothing");
    [a clearContents];
    CHECK([[a pasteboardItems] count] == 0, "clearContents empties the items");

    // An application class
    Note *note = [[[Note alloc] init] autorelease];
    note->text = @"hello";
    CHECK([a writeObjects: @[ note ]], "write own class");
    CHECK([[a stringForType: @"com.example.note"] isEqual: @"note:hello"], "own class data");
    NSArray *read = [a readObjectsForClasses: @[ [Note class] ] options: nil];
    CHECK([read count] == 1 && [((Note *) read[0])->text isEqual: @"note:hello"], "own class read back");
    CHECK([a canReadObjectForClasses: @[ [Note class] ] options: nil], "can read own class");

    // A promise
    [a clearContents];
    Provider *provider = [[[Provider alloc] init] autorelease];
    NSPasteboardItem *promised = [[[NSPasteboardItem alloc] init] autorelease];
    CHECK([promised setDataProvider: (id) provider forTypes: (@[ @"public.utf8-plain-text", @"com.example.lazy" ])], "setDataProvider");
    CHECK([[promised types] count] == 2, "promised types are listed");
    CHECK([a writeObjects: @[ promised ]], "write promised");
    CHECK(provider->provided == 0, "nothing provided before it is read");
    CHECK([[a stringForType: @"com.example.lazy"] isEqual: @"promised"], "read provides the data");
    CHECK(provider->provided == 1, "provider called once");
    CHECK([[a stringForType: @"com.example.lazy"] isEqual: @"promised"] && provider->provided == 1, "and only once");
    [a clearContents];
    CHECK(provider->finished <= 1, "finished at most once");
    [a releaseGlobally];
}

static void testFileContents(void) {
    NSString *dir = NSTemporaryDirectory();
    NSString *src = [dir stringByAppendingPathComponent: [NSString stringWithFormat: @"v615-%d.txt", getpid()]];
    NSString *dst = [dir stringByAppendingPathComponent: [NSString stringWithFormat: @"v615-%d-out.txt", getpid()]];
    [@"file body" writeToFile: src atomically: YES encoding: NSUTF8StringEncoding error: nil];

    NSPasteboard *a = [NSPasteboard pasteboardWithUniqueName];
    [a clearContents];
    CHECK([a writeFileContents: src], "writeFileContents");
    CHECK(has([a types], NSFileContentsPboardType), "file contents type");
    CHECK(has([a types], @"NXTypedFileContentsPboardType:txt"), "file contents type with the extension");
    CHECK([[a readFileContentsType: nil toFile: dst] isEqual: dst], "readFileContentsType returns the path");
    CHECK([[NSString stringWithContentsOfFile: dst encoding: NSUTF8StringEncoding error: nil] isEqual: @"file body"], "contents");

    [a clearContents];
    NSFileWrapper *wrapper = [[[NSFileWrapper alloc] initRegularFileWithContents: [@"wrapped" dataUsingEncoding: NSUTF8StringEncoding]] autorelease];
    [wrapper setPreferredFilename: @"w.txt"];
    CHECK([a writeFileWrapper: wrapper], "writeFileWrapper");
    NSFileWrapper *back = [a readFileWrapper];
    CHECK([back isRegularFile] && [[back regularFileContents] length] == 7, "readFileWrapper");
    CHECK([a dataForType: NSFileContentsPboardType] != nil, "wrapper contents are under the file contents type too");

    [[NSFileManager defaultManager] removeItemAtPath: src error: nil];
    [[NSFileManager defaultManager] removeItemAtPath: dst error: nil];
    [a releaseGlobally];
}

static void testFilterServices(void) {
    CHECK([[NSPasteboard typesFilterableTo: NSPasteboardTypePNG] containsObject: NSPasteboardTypePNG], "a type is filterable to itself");
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        testConstants();
        testUniqueAndCounts();
        testString();
        testURLs();
        testColorImageAttributed();
        testItems();
        testFileContents();
        testFilterServices();
    }
    if (failures)
        return 1;
    puts("pasteboard api: PASS");
    return 0;
}
