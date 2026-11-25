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

#import "NSFilePromise-Private.h"
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSPasteboardItem.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSApplication.h>
#import "NSPasteboardAliases.h"
#import <LaunchServices/LaunchServices.h>
#import <CoreFoundation/CFPasteboard_Private.h>
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
// Private: the type that marks pasteboard contents as copied by a smart (word
// level) selection, so pasting adds the spaces around it. The string is the
// one WebKit gives for it (BSD-licensed, Source/WebCore/platform/mac/
// PasteboardMac.mm, WebSmartPastePboardType).
NSString *const _NXSmartPaste = @"NeXT smart paste pasteboard type";
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

NSData *NSPasteboardDerivedDataForType(NSPasteboard *pasteboard, NSPasteboardType type) {
    if (![NSPasteboardCanonicalType(type) isEqual: NSPasteboardTypeFileURL])
        return nil;
    id paths = [pasteboard propertyListForType: NSFilenamesPboardType];
    if (![paths isKindOfClass: [NSArray class]] || [paths count] == 0 ||
        ![[paths objectAtIndex: 0] isKindOfClass: [NSString class]])
        return nil;
    return [[[NSURL fileURLWithPath: [paths objectAtIndex: 0]] absoluteString] dataUsingEncoding: NSUTF8StringEncoding];
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
    // QUIRK: a pasteboard holding a list of file names lists public.file-url too, reads as one file URL item per
    // name (-pasteboardItems), and gives the first file's URL as public.file-url data
    // (NSPasteboardDerivedDataForType). Not documented. Evidence: black-box observation on macOS 26.7.3 and 10.14.4
    // (tier 2; darling's tests/collection-view.md). Test: appkit-pasteboard-file-urls.m test_filenames_read_as_urls
    if ([result containsObject: NSFilenamesPboardType] && ![result containsObject: NSPasteboardTypeFileURL])
        [result addObject: NSPasteboardTypeFileURL];
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
- (id) _initDerivedFromPasteboard: (NSPasteboard *) pasteboard itemID: (uint64_t) identifier changeCount: (NSInteger) changeCount;
- (id) _initWithWritingObject: (id<NSPasteboardWriting>) object pasteboard: (NSPasteboard *) pasteboard;
- (NSArray *) _orderedTypes;
- (void) _attachToPasteboard: (NSPasteboard *) pasteboard itemID: (uint64_t) identifier;
- (id<NSPasteboardTypeOwner>) _promiseOwner;
- (NSData *) _storedDataForType: (NSPasteboardType) type;
@end

@interface NSPasteboard (NSPasteboardInternals)
- (NSArray *) _itemsExpandingFileNamesOf: (NSArray *) items;
- (CFPasteboardStatus) _writeItem: (NSPasteboardItem *) item asItemID: (CFPasteboardItemID) identifier;
- (CFPasteboardStatus) _promiseType: (NSPasteboardType) type ofItem: (CFPasteboardItemID) item owner: (id) owner;
- (CFPasteboardStatus) _statusOfSettingData: (NSData *) data forType: (NSPasteboardType) type ofItemID: (CFPasteboardItemID) item;
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

#pragma mark - CoreFoundation pasteboards

// The data of a pasteboard lives in CoreFoundation's pasteboard (the pboard service, or the process when
// the service is not there), shared with every other process and with the Pasteboard Manager. What stays
// here is the promise bookkeeping: the objects that promised data (-declareTypes:owner:, item data
// providers) live in this process, so CoreFoundation is given a provider that finds them again.

// The owners of the promises of one generation of a pasteboard; CoreFoundation holds it until the
// generation ends.
@interface NSPasteboardProvider : NSObject {
@public
    NSPasteboard *pasteboard;
    // "<item identifier>\t<type>" -> the owner (NSPasteboardTypeOwner or a promise owner of an item), until the
    // type is given its data
    NSMutableDictionary *owners;
    // Every owner that promised something in this generation, each once
    NSMutableArray *allOwners;
    CFIndex generation;
}
@end

@interface NSPasteboardCFState : NSObject {
@public
    CFPasteboardRef cf;
    NSString *name;
    BOOL unique;
    // Unretained: CoreFoundation owns it from the first promise until the generation ends.
    NSPasteboardProvider *provider;
}
@end

@interface NSPasteboard (NSPasteboardProviderSupport)
- (void) _providerDidEnd: (NSPasteboardProvider *) provider;
@end

static NSString *promiseKey(CFPasteboardItemID item, NSPasteboardType type) {
    return [NSString stringWithFormat: @"%llu\t%@", (unsigned long long) item, type];
}

// Owners are application objects (a text view's -pasteboard:provideDataForType:) that expect to run on
// the main thread, while CoreFoundation answers another process's read on one of its own threads.
// A process that has no application has nothing to hop to.
static void runOnOwnerThread(void (^block)(void)) {
    if ([NSThread isMainThread] || NSApp == nil) {
        block();
        return;
    }
    dispatch_sync(dispatch_get_main_queue(), block);
}

static CFPasteboardStatus providerProvide(CFPasteboardRef cf, CFPasteboardItemID item, CFStringRef flavor, void *info) {
    @autoreleasepool {
        NSPasteboardProvider *provider = (NSPasteboardProvider *) info;
        NSPasteboardType type = (NSPasteboardType) flavor;
        id owner = nil;
        @synchronized(provider) {
            owner = [[provider->owners objectForKey: promiseKey(item, type)] retain];
        }
        if (owner == nil)
            return kCFPasteboardNoProvider;
        runOnOwnerThread(^{
          if ([owner respondsToSelector: @selector(pasteboard:provideDataForType:)])
              [owner pasteboard: provider->pasteboard provideDataForType: type];
        });
        [owner release];
        // The owner supplies the data by setting it on the pasteboard, which clears the promise.
        return CFPasteboardIsDataPromised(cf, item, flavor) ? kCFPasteboardNoProvider : kCFPasteboardSuccess;
    }
}

// Every promise of the generation was kept: the owners have nothing left to provide.
static void providerAllProvided(CFPasteboardRef cf, void *info) {
    @autoreleasepool {
        NSPasteboardProvider *provider = (NSPasteboardProvider *) info;
        NSArray *distinct;
        @synchronized(provider) {
            distinct = [[provider->allOwners copy] autorelease];
        }
        NSPasteboard *pasteboard = provider->pasteboard;
        runOnOwnerThread(^{
          for (id owner in distinct) {
              if ([owner respondsToSelector: @selector(pasteboardFinishedWithDataProvider:)])
                  [owner pasteboardFinishedWithDataProvider: pasteboard];
          }
        });
    }
}

static void providerOwnerChanged(CFPasteboardRef cf, void *info) {
    @autoreleasepool {
        NSPasteboardProvider *provider = (NSPasteboardProvider *) info;
        // From a snapshot: an owner is application code and may write to the pasteboard from its callback.
        NSArray *distinct;
        @synchronized(provider) {
            distinct = [[provider->allOwners copy] autorelease];
        }
        NSPasteboard *pasteboard = provider->pasteboard;
        runOnOwnerThread(^{
          for (id owner in distinct) {
              if ([owner respondsToSelector: @selector(pasteboardChangedOwner:)])
                  [owner pasteboardChangedOwner: pasteboard];
          }
        });
    }
}

static void providerRelease(void *info) {
    @autoreleasepool {
        NSPasteboardProvider *provider = (NSPasteboardProvider *) info;
        [provider->pasteboard _providerDidEnd: provider];
        [provider release];
    }
}

static const CFPasteboardProviderCallbacks providerCallbacks = {
    0, providerProvide, providerAllProvided, providerOwnerChanged, providerRelease
};

@implementation NSPasteboardProvider

- (id) init {
    if ((self = [super init]))
    {
        owners = [NSMutableDictionary new];
        allOwners = [NSMutableArray new];
    }
    return self;
}

- (void) dealloc {
    [pasteboard release];
    [owners release];
    [allOwners release];
    [super dealloc];
}

@end

@implementation NSPasteboardCFState

- (void) dealloc {
    if (cf != NULL) {
        if (unique)
            CFPasteboardReleaseGlobally(cf);
        CFRelease(cf);
    }
    [name release];
    [super dealloc];
}

@end

// The CoreFoundation pasteboard behind an object, without creating the extras of one that has none
// (the read-only pasteboards of drag sessions are subclasses that never set it).
#define CF_STATE(obj) (NS_EXTRA_ALLOCATED(NSPasteboard, obj) ? NS_EXTRA(NSPasteboard, obj)->_cfState : nil)

@implementation NSPasteboard

+ (NSPasteboard *) generalPasteboard {
    return [self pasteboardWithName: NSGeneralPboard];
}

static NSMutableDictionary *namedPasteboards;

- (id) _initWithCFPasteboard: (CFPasteboardRef) cf unique: (BOOL) unique {
    if ((self = [super init])) {
        NSPasteboardCFState *state = [NSPasteboardCFState new];
        state->cf = (CFPasteboardRef) CFRetain(cf);
        state->name = (NSString *) CFPasteboardCopyName(cf);
        state->unique = unique;
        NS_EXTRA(NSPasteboard, self)->_cfState = state;
    }
    return self;
}

// The unique pasteboards that are alive, by name, so that the name finds the pasteboard again. They are not
// retained: a unique pasteboard that nobody holds any more is released in the pasteboard service.
static NSMutableDictionary *uniquePasteboards;

// One object per name in the process, so that the promises made through it are found again.
+ (NSPasteboard *) pasteboardWithName: (NSPasteboardName) name {
    if (name == nil)
        return nil;
    @synchronized([NSPasteboard class]) {
        if (namedPasteboards == nil)
            namedPasteboards = [NSMutableDictionary new];
        NSPasteboard *pasteboard = [namedPasteboards objectForKey: name];
        if (pasteboard != nil)
            return pasteboard;
        pasteboard = [[uniquePasteboards objectForKey: name] nonretainedObjectValue];
        if (pasteboard != nil)
            return [[pasteboard retain] autorelease];

        CFPasteboardRef cf = CFPasteboardCreate(NULL, (CFStringRef) name);
        if (cf == NULL)
            return nil;
        pasteboard = [[NSPasteboard alloc] _initWithCFPasteboard: cf unique: NO];
        CFRelease(cf);
        [namedPasteboards setObject: pasteboard forKey: name];
        [pasteboard release];
        return pasteboard;
    }
}

+ (NSPasteboard *) pasteboardWithUniqueName {
    CFPasteboardRef cf = CFPasteboardCreateUnique(NULL);
    if (cf == NULL)
        return nil;
    NSPasteboard *pasteboard = [[[NSPasteboard alloc] _initWithCFPasteboard: cf unique: YES] autorelease];
    CFRelease(cf);
    @synchronized([NSPasteboard class]) {
        if (uniquePasteboards == nil)
            uniquePasteboards = [NSMutableDictionary new];
        [uniquePasteboards setObject: [NSValue valueWithNonretainedObject: pasteboard] forKey: [pasteboard name]];
    }
    return pasteboard;
}

- (void) dealloc {
    NSPasteboardCFState *state = CF_STATE(self);
    if (state != nil && state->unique) {
        @synchronized([NSPasteboard class]) {
            NSValue *entry = [uniquePasteboards objectForKey: state->name];
            if ([entry nonretainedObjectValue] == self)
                [uniquePasteboards removeObjectForKey: state->name];
        }
    }
    if (NS_EXTRA_ALLOCATED(NSPasteboard, self))
        [NS_EXTRA(NSPasteboard, self)->_cfState release];
    NS_EXTRA_FREE(NSPasteboard, self);
    [super dealloc];
}

- (NSPasteboardName) name {
    NSPasteboardCFState *state = CF_STATE(self);
    return state != nil ? state->name : nil;
}

- (NSInteger) changeCount {
    NSPasteboardCFState *state = CF_STATE(self);
    return state != nil ? (NSInteger) CFPasteboardGetChangeCount(state->cf) : 0;
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
    NSPasteboardCFState *state = CF_STATE(self);
    return state != nil ? (NSInteger) CFPasteboardBeginGeneration(state->cf) : 0;
}

// NSPasteboardContentsCurrentHostOnly keeps the contents off Handoff / Universal Clipboard. This
// system has no such transfer, so the option changes nothing.
- (NSInteger) prepareForNewContentsWithOptions: (NSPasteboardContentsOptions) options {
    return [self clearContents];
}

// Only a pasteboard made with -pasteboardWithUniqueName is a resource of its own; the named ones
// belong to every process.
- (oneway void) releaseGlobally {
    NSPasteboardCFState *state = CF_STATE(self);
    if (state != nil && state->unique)
        CFPasteboardReleaseGlobally(state->cf);
}

#pragma mark Flat contents

// The flat API (-types, -dataForType:, -setData:forType:, ...) works on the first item.

- (CFPasteboardItemID) _firstItemCreating: (BOOL) create status: (CFPasteboardStatus *) status {
    NSPasteboardCFState *state = CF_STATE(self);
    CFIndex count = 0;
    CFPasteboardItemID item = 0;
    *status = CFPasteboardGetItemCount(state->cf, &count);
    if (*status != kCFPasteboardSuccess)
        return 0;
    if (count > 0)
        *status = CFPasteboardGetItemAtIndex(state->cf, 0, &item);
    else if (create)
        *status = CFPasteboardAddItem(state->cf, &item);
    else
        *status = kCFPasteboardBadIndex;
    return item;
}

// Runs a write on the first item. A process that did not begin the current generation may not add to it:
// the write then replaces the contents, the way a process that takes the pasteboard over does.
- (CFPasteboardStatus) _writeToFirstItem: (CFPasteboardStatus (^)(CFPasteboardItemID item)) write {
    NSPasteboardCFState *state = CF_STATE(self);
    CFPasteboardStatus status;
    CFPasteboardItemID item = [self _firstItemCreating: YES status: &status];
    if (status == kCFPasteboardSuccess)
        status = write(item);
    if (status == kCFPasteboardNotOwner) {
        if (CFPasteboardBeginGeneration(state->cf) == 0)
            return kCFPasteboardUnavailable;
        status = CFPasteboardAddItem(state->cf, &item);
        if (status == kCFPasteboardSuccess)
            status = write(item);
    }
    return status;
}

- (NSArray<NSPasteboardType> *) _typesOfItemID: (CFPasteboardItemID) item {
    NSPasteboardCFState *state = CF_STATE(self);
    CFArrayRef flavors = NULL;
    if (state == nil || CFPasteboardCopyFlavorsForItem(state->cf, item, &flavors) != kCFPasteboardSuccess)
        return nil;
    NSArray *types = [[(NSArray *) flavors copy] autorelease];
    CFRelease(flavors);
    return types;
}

- (NSData *) _dataForType: (NSPasteboardType) type ofItemID: (CFPasteboardItemID) item {
    NSPasteboardCFState *state = CF_STATE(self);
    if (state == nil || type == nil)
        return nil;
    // The UTI spelling first, then the older name of the same type, then the name as it was given: other
    // writers (the Pasteboard Manager) store whichever they like.
    NSPasteboardType canonical = NSPasteboardCanonicalType(type);
    NSMutableArray *candidates = [NSMutableArray arrayWithObject: canonical];
    NSPasteboardType legacy = NSPasteboardLegacyAliasOfType(canonical);
    if (legacy != nil)
        [candidates addObject: legacy];
    if (![candidates containsObject: type])
        [candidates addObject: type];
    for (NSPasteboardType candidate in candidates) {
        CFDataRef data = NULL;
        CFPasteboardStatus status = CFPasteboardCopyData(state->cf, item, (CFStringRef) candidate, &data);
        if (status == kCFPasteboardSuccess && data != NULL)
            return [(NSData *) data autorelease];
        if (status != kCFPasteboardBadFlavor)
            return nil;
    }
    return nil;
}

- (CFPasteboardStatus) _statusOfSettingData: (NSData *) data forType: (NSPasteboardType) type ofItemID: (CFPasteboardItemID) item {
    NSPasteboardCFState *state = CF_STATE(self);
    type = NSPasteboardCanonicalType(type);
    if (state == nil || data == nil || type == nil)
        return kCFPasteboardInvalid;
    CFPasteboardStatus status = CFPasteboardSetData(state->cf, item, (CFStringRef) type, (CFDataRef) data,
                                                    kCFPasteboardFlavorNoFlags);
    if (status != kCFPasteboardSuccess)
        return status;
    NSPasteboardProvider *provider = state->provider;
    if (provider != nil) {
        // The promise is kept; the owner has nothing left to provide for this type.
        @synchronized(provider) {
            [provider->owners removeObjectForKey: promiseKey(item, type)];
        }
    }
    return kCFPasteboardSuccess;
}

- (BOOL) _setData: (NSData *) data forType: (NSPasteboardType) type ofItemID: (CFPasteboardItemID) item {
    return [self _statusOfSettingData: data forType: type ofItemID: item] == kCFPasteboardSuccess;
}

- (NSArray<NSPasteboardType> *) types {
    NSPasteboardCFState *state = CF_STATE(self);
    if (state == nil)
        return [NSArray array];
    CFPasteboardStatus status;
    CFPasteboardItemID item = [self _firstItemCreating: NO status: &status];
    if (status != kCFPasteboardSuccess)
        return [NSArray array];
    NSArray *types = [self _typesOfItemID: item];
    return types != nil ? NSPasteboardTypesWithAliases(types) : [NSArray array];
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
    if (CF_STATE(self) == nil)
        return nil;
    CFPasteboardStatus status;
    CFPasteboardItemID item = [self _firstItemCreating: NO status: &status];
    if (status != kCFPasteboardSuccess)
        return nil;
    NSData *data = [self _dataForType: type ofItemID: item];
    return data != nil ? data : NSPasteboardDerivedDataForType(self, type);
}

- (NSString *) stringForType: (NSPasteboardType) type {
    NSData *data = [self dataForType: type];
    if (data == nil)
        return nil;

    // UTF-8 is what other clients' data is read as; data that is not valid UTF-8 (what -setString:forType:
    // stores for a type other than the string type) is read as Unicode.
    NSString *string = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
    if (string == nil && ![NSPasteboardCanonicalType(type) isEqual: NSPasteboardTypeString])
        string = [[[NSString alloc] initWithData: data encoding: NSUnicodeStringEncoding] autorelease];
    return string;
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

- (void) _providerDidEnd: (NSPasteboardProvider *) provider {
    NSPasteboardCFState *state = CF_STATE(self);
    @synchronized(state) {
        if (state->provider == provider)
            state->provider = nil;
    }
}

// The provider of the generation that is current now: the one CoreFoundation already holds, or a new one
// (isNew), which CoreFoundation takes over with the first promise made through it.
- (NSPasteboardProvider *) _providerCreating: (BOOL *) isNew {
    NSPasteboardCFState *state = CF_STATE(self);
    CFIndex generation = CFPasteboardGetChangeCount(state->cf);
    @synchronized(state) {
        NSPasteboardProvider *provider = state->provider;
        if (provider != nil && provider->generation == generation) {
            *isNew = NO;
            return provider;
        }
        provider = [NSPasteboardProvider new];
        provider->pasteboard = [self retain];
        provider->generation = generation;
        *isNew = YES;
        return provider;
    }
}

// Declares one type of an item as promised to the owner (nil: declared without data for now).
- (CFPasteboardStatus) _promiseType: (NSPasteboardType) type
                             ofItem: (CFPasteboardItemID) item
                              owner: (id) owner
{
    NSPasteboardCFState *state = CF_STATE(self);
    BOOL isNew = NO;
    NSPasteboardProvider *provider = [self _providerCreating: &isNew];
    @synchronized(provider) {
        if (owner != nil) {
            [provider->owners setObject: owner forKey: promiseKey(item, type)];
            BOOL known = NO;
            for (id other in provider->allOwners)
                known = known || other == owner;
            if (!known)
                [provider->allOwners addObject: owner];
        } else
            [provider->owners removeObjectForKey: promiseKey(item, type)];
    }
    // Not flagged as promised for the Pasteboard Manager: macOS reports the promises made through
    // NSPasteboard without that flag.
    CFPasteboardStatus status = CFPasteboardPromiseData(state->cf, item, (CFStringRef) type, kCFPasteboardFlavorNoFlags,
                                                        &providerCallbacks, provider);
    if (status == kCFPasteboardSuccess) {
        @synchronized(state) {
            state->provider = provider;
        }
    } else if (isNew) {
        [provider release];
    }
    return status;
}

- (NSInteger) declareTypes: (NSArray<NSPasteboardType> *) types
                     owner: (id<NSPasteboardTypeOwner>) owner
{
    if (CF_STATE(self) == nil || [self clearContents] == 0)
        return 0;
    return [self addTypes: types owner: owner];
}

- (NSInteger) addTypes: (NSArray<NSPasteboardType> *) types
                 owner: (id<NSPasteboardTypeOwner>) owner
{
    if (CF_STATE(self) == nil)
        return 0;
    for (NSPasteboardType declared in types) {
        // Stored under the UTI spelling; the 10.0 name of the same type reaches it too.
        NSPasteboardType type = NSPasteboardCanonicalType(declared);
        CFPasteboardStatus status = [self _writeToFirstItem: ^CFPasteboardStatus(CFPasteboardItemID item) {
          return [self _promiseType: type ofItem: item owner: owner];
        }];
        if (status != kCFPasteboardSuccess)
            return 0;
    }
    return [self changeCount];
}

- (BOOL) setData: (NSData *) data forType: (NSPasteboardType) type {
    if (CF_STATE(self) == nil || data == nil || type == nil)
        return NO;
    return [self _writeToFirstItem: ^CFPasteboardStatus(CFPasteboardItemID item) {
      return [self _statusOfSettingData: data forType: type ofItemID: item];
    }] == kCFPasteboardSuccess;
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

    NSPasteboardCFState *state = CF_STATE(self);
    if (state != nil) {
        // The items some process wrote (this one, another one, or the Pasteboard Manager).
        NSInteger changeCount = [self changeCount];
        CFIndex count = 0;
        if (CFPasteboardGetItemCount(state->cf, &count) != kCFPasteboardSuccess)
            return [NSArray array];
        NSMutableArray *items = [NSMutableArray array];
        for (CFIndex i = 0; i < count; i++) {
            CFPasteboardItemID identifier;
            if (CFPasteboardGetItemAtIndex(state->cf, i, &identifier) != kCFPasteboardSuccess)
                continue;
            NSPasteboardItem *item = [[NSPasteboardItem alloc] _initDerivedFromPasteboard: self
                                                                                  itemID: identifier
                                                                             changeCount: changeCount];
            [items addObject: item];
            [item release];
        }
        // A single item that is a list of file names (the 10.0 way, and what a drag from a file manager
        // brings) is every file of it as an item of its own.
        if ([items count] == 1)
            return [self _itemsExpandingFileNamesOf: items] ?: items;
        return items;
    }

    // A pasteboard that is not a CoreFoundation one (the read-only pasteboard of a drag session) has
    // one item, made of all the types there are.
    NSArray *flat = NSPasteboardCanonicalTypes([self types]);
    if ([flat count] == 0)
        return [NSArray array];
    NSArray *files = [self _itemsExpandingFileNamesOf: nil];
    if (files != nil)
        return files;
    NSPasteboardItem *item = [[[NSPasteboardItem alloc] _initDerivedFromPasteboard: self] autorelease];
    return [NSArray arrayWithObject: item];
}

// The single item holding a list of file names as one file URL item per file, or nil if it holds no
// such list. The list is read from the flat types, which are those of the first item; a pasteboard that
// holds file URLs of its own holds no such list.
- (NSArray *) _itemsExpandingFileNamesOf: (NSArray *) items {
    NSArray *flat = NSPasteboardCanonicalTypes([self types]);
    if (![flat containsObject: NSFilenamesPboardType] || [self _storesFileURLs])
        return nil;
    id paths = [self propertyListForType: NSFilenamesPboardType];
    if (![paths isKindOfClass: [NSArray class]] || [paths count] == 0)
        return nil;
    NSMutableArray *expanded = [NSMutableArray array];
    for (id path in paths) {
        if (![path isKindOfClass: [NSString class]])
            continue;
        NSPasteboardItem *item = [[[NSPasteboardItem alloc] init] autorelease];
        [item setString: [[NSURL fileURLWithPath: path] absoluteString] forType: NSPasteboardTypeFileURL];
        [expanded addObject: item];
    }
    return [expanded count] > 0 ? expanded : nil;
}

- (BOOL) _storesFileURLs {
    if (CF_STATE(self) != nil) {
        CFPasteboardStatus status;
        CFPasteboardItemID item = [self _firstItemCreating: NO status: &status];
        return status == kCFPasteboardSuccess &&
               [NSPasteboardCanonicalTypes([self _typesOfItemID: item]) containsObject: NSPasteboardTypeFileURL];
    }
    NSData *data = [self dataForType: NSPasteboardTypeFileURL];
    return data != nil && ![data isEqual: NSPasteboardDerivedDataForType(self, NSPasteboardTypeFileURL)];
}

- (NSUInteger) indexOfPasteboardItem: (NSPasteboardItem *) pasteboardItem {
    return [[self pasteboardItems] indexOfObjectIdenticalTo: pasteboardItem];
}

// Remembers the items a write produced under the change count the pasteboard has now, so that the very
// objects written are the ones read back until something else changes the pasteboard.
- (void) _rememberItems: (NSArray *) items {
    objc_setAssociatedObject(self, &kItemListKey,
                             [NSDictionary dictionaryWithObjectsAndKeys:
                                     [NSNumber numberWithInteger: [self changeCount]], @"changeCount",
                                     items, @"items", nil],
                             OBJC_ASSOCIATION_RETAIN);
}

// Puts the data and the promises of a standalone item into the CoreFoundation item. Types without data
// are promised to the item (data providers).
- (CFPasteboardStatus) _writeItem: (NSPasteboardItem *) item asItemID: (CFPasteboardItemID) identifier {
    id<NSPasteboardTypeOwner> owner = nil;
    for (NSPasteboardType type in [item _orderedTypes]) {
        NSData *data = [item _storedDataForType: type];
        CFPasteboardStatus status;
        if (data != nil) {
            status = [self _statusOfSettingData: data forType: type ofItemID: identifier];
        } else {
            if (owner == nil)
                owner = [item _promiseOwner];
            status = [self _promiseType: type ofItem: identifier owner: owner];
        }
        if (status != kCFPasteboardSuccess)
            return status;
    }
    return kCFPasteboardSuccess;
}

// File URLs of any item also appear as the older list of file names, which is how applications that
// predate file URLs read them.
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

    // File promises are also the legacy promise type, listing the files' types
    // (macOS 26.7.3 adds it to the types of a written NSFilePromiseProvider).
    NSMutableArray *promisedTypes = [NSMutableArray array];
    for (NSPasteboardItem *item in items) {
        NSData *data = [item _storedDataForType: NSFilePromiseContentTypeType];
        NSString *type = data != nil ? [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease] : nil;
        if ([type length] > 0)
            [promisedTypes addObject: type];
    }
    if ([promisedTypes count] > 0) {
        [self addTypes: [NSArray arrayWithObject: NSFilesPromisePboardType] owner: nil];
        [self setPropertyList: promisedTypes forType: NSFilesPromisePboardType];
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
    NSPasteboardCFState *state = CF_STATE(self);
    if (state == nil)
        return NO;

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
    if ([items count] == firstNew)
        return YES;

    NSMutableArray *attachments = [NSMutableArray array];
    for (NSUInteger i = firstNew; i < [items count]; i++) {
        NSPasteboardItem *item = [items objectAtIndex: i];
        CFPasteboardItemID identifier = 0;
        CFPasteboardStatus status = CFPasteboardAddItem(state->cf, &identifier);
        if (status == kCFPasteboardNotOwner && firstNew == 0 && i == 0) {
            // Nothing was cleared before: the write replaces the contents, as a write to the flat types does.
            if (CFPasteboardBeginGeneration(state->cf) == 0)
                return NO;
            status = CFPasteboardAddItem(state->cf, &identifier);
        }
        if (status == kCFPasteboardSuccess)
            status = [self _writeItem: item asItemID: identifier];
        if (status != kCFPasteboardSuccess)
            return NO;
        [attachments addObject: [NSNumber numberWithUnsignedLongLong: identifier]];
    }

    [self _writeLegacyTypesOfItems: [items subarrayWithRange: NSMakeRange(firstNew, [items count] - firstNew)]];
    [self _rememberItems: items];
    for (NSUInteger i = firstNew; i < [items count]; i++)
        [[items objectAtIndex: i] _attachToPasteboard: self itemID: [[attachments objectAtIndex: i - firstNew] unsignedLongLongValue]];
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

// Whether a URL read from a pasteboard is one the URL reading options ask for: a file URL when
// NSPasteboardURLReadingFileURLsOnlyKey is set, and an item whose type conforms to one of the
// NSPasteboardURLReadingContentsConformToTypesKey types when that is given
static BOOL urlPassesReadingOptions(NSURL *url, NSDictionary *options)
{
    if ([[options objectForKey: NSPasteboardURLReadingFileURLsOnlyKey] boolValue] && ![url isFileURL])
        return NO;
    NSArray *types = [options objectForKey: NSPasteboardURLReadingContentsConformToTypesKey];
    if (types == nil)
        return YES;
    id type = nil;
    if (![url isFileURL] || ![url getResourceValue: &type forKey: NSURLTypeIdentifierKey error: NULL] ||
        ![type isKindOfClass: [NSString class]])
        return NO;
    for (NSString *wanted in types)
        if ([wanted isKindOfClass: [NSString class]] && NSPasteboardTypeConformsTo(type, wanted))
            return YES;
    return NO;
}

// The item read as the first of the classes it can be read as, or nil
- (id) _objectForItem: (NSPasteboardItem *) item
              classes: (NSArray<Class> *) classArray
              options: (NSDictionary<NSPasteboardReadingOptionKey, id> *) options
{
    for (Class cls in classArray) {
        if ([cls isSubclassOfClass: [NSPasteboardItem class]])
            return item;
        if (![cls conformsToProtocol: @protocol(NSPasteboardReading)])
            continue;

        NSPasteboardType type = readableTypeOfItem(item, cls, self, options);
        if (type == nil)
            continue;
        if ([cls isSubclassOfClass: [NSFilePromiseReceiver class]]) {
            // A promise is made of several of the item's types.
            id receiver = [[[cls alloc] _initWithPasteboardItem: item] autorelease];
            if (receiver != nil)
                return receiver;
            continue;
        }
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
        if ([object isKindOfClass: [NSURL class]] && !urlPassesReadingOptions(object, options))
            continue;
        return object;
    }
    return nil;
}

- (NSArray *) readObjectsForClasses: (NSArray<Class> *) classArray
                            options: (NSDictionary<NSPasteboardReadingOptionKey, id> *) options
{
    NSMutableArray *result = [NSMutableArray array];
    for (NSPasteboardItem *item in [self pasteboardItems]) {
        id object = [self _objectForItem: item classes: classArray options: options];
        if (object != nil)
            [result addObject: object];
    }
    return result;
}

- (BOOL) canReadObjectForClasses: (NSArray<Class> *) classArray
                         options: (NSDictionary<NSPasteboardReadingOptionKey, id> *) options
{
    // Whatever -readObjectsForClasses:options: would read, so that the two agree
    for (NSPasteboardItem *item in [self pasteboardItems])
        if ([self _objectForItem: item classes: classArray options: options] != nil)
            return YES;
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
