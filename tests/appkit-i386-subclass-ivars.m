// Copyright (C) 2026 Lubos Dolezel
//
// An application's subclass of an AppKit class, compiled against the Mac's
// layout of the legacy (32-bit) Objective-C ABI, keeps its own instance
// variables in the bytes that follow the class's Apple instance size (for
// example 160 bytes for NSBrowser and 108 for NSColorWell). AppKit must neither
// write into those bytes nor read its own state back from them. The expected
// sizes are what Mac OS X 10.14.4 reports. Besides NSBrowser and NSColorWell,
// the classes that used to be larger than Apple's (NSCursor, NSTrackingArea,
// NSToolbarItem, NSSplitViewItem, NSPasteboardItem, NSTextAttachment,
// NSMutableParagraphStyle, NSTypesetter, NSTextBlock, NSTextTable,
// NSTextTableBlock, NSBrowserCell, NSTextAttachmentCell, NSCustomImageRep,
// NSLayoutConstraint) are covered by the table-driven checks at the end.
//
// Two checks per class:
//  - an ordinary subclass with its own instance variables keeps them intact
//    while the AppKit state is used, and AppKit state survives writes to them
//    (all ABIs);
//  - on the legacy ABI, an instance with spare bytes at Apple's size, standing
//    for the object of a subclass compiled against the Mac layout, has that
//    memory left alone and AppKit's state does not depend on it.
#import <AppKit/AppKit.h>
#import <AppKit/NSPanGestureRecognizer.h>
#import <AppKit/NSTabViewController.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>

static int failures;

#define CHECK(cond, ...)                                                       \
    do {                                                                       \
        if (!(cond)) {                                                         \
            printf("FAIL: " __VA_ARGS__);                                      \
            printf("\n");                                                      \
            failures++;                                                        \
        }                                                                      \
    } while (0)

@interface SubBrowser : NSBrowser {
    int ownCounter;
    id ownObject;
    double ownValue;
}
@end
@implementation SubBrowser
- (void) setOwn {
    ownCounter = 0x1234abcd;
    ownObject = (id) 0x5a5a5a5a;
    ownValue = 3.25;
}
- (BOOL) ownIntact {
    return ownCounter == 0x1234abcd && ownObject == (id) 0x5a5a5a5a && ownValue == 3.25;
}
@end

@interface SubColorWell : NSColorWell {
    int ownCounter;
    id ownObject;
    double ownValue;
}
@end
@implementation SubColorWell
- (void) setOwn {
    ownCounter = 0x1234abcd;
    ownObject = (id) 0x5a5a5a5a;
    ownValue = 3.25;
}
- (BOOL) ownIntact {
    return ownCounter == 0x1234abcd && ownObject == (id) 0x5a5a5a5a && ownValue == 3.25;
}
@end

static void flipBrowser(NSBrowser *b, BOOL v) {
    [b setTitled: v];
    [b setHasHorizontalScroller: v];
    [b setSeparatesColumns: v];
    [b setTakesTitleFromPreviousColumn: v];
    [b setAllowsMultipleSelection: v];
    [b setAllowsBranchSelection: v];
    [b setAllowsEmptySelection: v];
    [b setAcceptsArrowKeys: v];
    [b setMaxVisibleColumns: v ? 5 : 2];
}

static int browserState(NSBrowser *b) {
    return [b isTitled] | ([b hasHorizontalScroller] << 1) |
           ([b separatesColumns] << 2) | ([b takesTitleFromPreviousColumn] << 3) |
           ([b allowsMultipleSelection] << 4) | ([b allowsBranchSelection] << 5) |
           ([b allowsEmptySelection] << 6) | ([b acceptsArrowKeys] << 7) |
           ((int) [b maxVisibleColumns] << 8);
}

static int wellState(NSColorWell *w) {
    return [w isBordered] | ([w isEnabled] << 1) | ([w isContinuous] << 2) |
           ([w isActive] << 3);
}

static void checkSubclasses(void) {
    SubBrowser *b = [[SubBrowser alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)];
    [b setOwn];
    flipBrowser(b, YES);
    CHECK([b ownIntact], "SubBrowser lost its own ivars after setters");
    CHECK(browserState(b) == (0xff | (5 << 8)), "NSBrowser state %x after setting all flags", browserState(b));
    flipBrowser(b, NO);
    CHECK([b ownIntact], "SubBrowser lost its own ivars after the second set");
    CHECK(browserState(b) == (2 << 8), "NSBrowser state %x after clearing all flags", browserState(b));
    [b release];

    SubColorWell *w = [[SubColorWell alloc] initWithFrame: NSMakeRect(0, 0, 40, 24)];
    [w setOwn];
    [w setColor: [NSColor redColor]];
    [w setBordered: NO];
    [w setEnabled: NO];
    [w setContinuous: NO];
    CHECK([w ownIntact], "SubColorWell lost its own ivars after setters");
    CHECK(wellState(w) == 0, "NSColorWell state %x after clearing the flags", wellState(w));
    [w setBordered: YES];
    [w setEnabled: YES];
    [w setContinuous: YES];
    CHECK([w ownIntact], "SubColorWell lost its own ivars after the second set");
    CHECK(wellState(w) == 7, "NSColorWell state %x after setting the flags", wellState(w));
    CHECK([[w color] isEqual: [NSColor redColor]], "NSColorWell lost its color");
    [w release];
}


// Table-driven cases: each class has a way to create an initialised instance
// from an allocated one, a way to change its state through the public API and
// a summary of that state.
typedef id (^CreateBlock)(id allocated);
typedef void (^TouchBlock)(id object);
typedef long (^StateBlock)(id object);

static const struct {
    const char *name;
    size_t appleSize;
} cases[] = {
    {"NSCursor", 20}, {"NSTrackingArea", 40}, {"NSToolbarItem", 72},
    {"NSSplitViewItem", 12}, {"NSPasteboardItem", 24}, {"NSTextAttachment", 16},
    {"NSMutableParagraphStyle", 48}, {"NSTypesetter", 12}, {"NSTextBlock", 32},
    {"NSTextTable", 52}, {"NSTextTableBlock", 60}, {"NSBrowserCell", 20},
    {"NSTextAttachmentCell", 24}, {"NSCustomImageRep", 40},
    {"NSLayoutConstraint", 52},
};

#define OWN_IVARS                                                              \
    {                                                                          \
        int ownCounter;                                                        \
        id ownObject;                                                          \
        double ownValue;                                                       \
    }                                                                          \
    -(void) setOwn;                                                            \
    -(BOOL) ownIntact;                                                         \
    @end
#define OWN_IMPL                                                               \
    -(void) setOwn {                                                           \
        ownCounter = 0x1234abcd;                                               \
        ownObject = (id) 0x5a5a5a5a;                                           \
        ownValue = 3.25;                                                       \
    }                                                                          \
    -(BOOL) ownIntact {                                                        \
        return ownCounter == 0x1234abcd && ownObject == (id) 0x5a5a5a5a &&     \
               ownValue == 3.25;                                               \
    }                                                                          \
    @end

@interface SubNSCursor : NSCursor OWN_IVARS
@implementation SubNSCursor OWN_IMPL
@interface SubNSTrackingArea : NSTrackingArea OWN_IVARS
@implementation SubNSTrackingArea OWN_IMPL
@interface SubNSToolbarItem : NSToolbarItem OWN_IVARS
@implementation SubNSToolbarItem OWN_IMPL
@interface SubNSSplitViewItem : NSSplitViewItem OWN_IVARS
@implementation SubNSSplitViewItem OWN_IMPL
@interface SubNSPasteboardItem : NSPasteboardItem OWN_IVARS
@implementation SubNSPasteboardItem OWN_IMPL
@interface SubNSTextAttachment : NSTextAttachment OWN_IVARS
@implementation SubNSTextAttachment OWN_IMPL
@interface SubNSMutableParagraphStyle : NSMutableParagraphStyle OWN_IVARS
@implementation SubNSMutableParagraphStyle OWN_IMPL
@interface SubNSTypesetter : NSTypesetter OWN_IVARS
@implementation SubNSTypesetter OWN_IMPL
@interface SubNSTextBlock : NSTextBlock OWN_IVARS
@implementation SubNSTextBlock OWN_IMPL
@interface SubNSTextTable : NSTextTable OWN_IVARS
@implementation SubNSTextTable OWN_IMPL
@interface SubNSTextTableBlock : NSTextTableBlock OWN_IVARS
@implementation SubNSTextTableBlock OWN_IMPL
@interface SubNSBrowserCell : NSBrowserCell OWN_IVARS
@implementation SubNSBrowserCell OWN_IMPL
@interface SubNSTextAttachmentCell : NSTextAttachmentCell OWN_IVARS
@implementation SubNSTextAttachmentCell OWN_IMPL
@interface SubNSCustomImageRep : NSCustomImageRep OWN_IVARS
@implementation SubNSCustomImageRep OWN_IMPL
@interface SubNSLayoutConstraint : NSLayoutConstraint OWN_IVARS
@implementation SubNSLayoutConstraint OWN_IMPL

@interface SubStubNSTableRowView : NSTableRowView OWN_IVARS
@implementation SubStubNSTableRowView OWN_IMPL
@interface SubStubNSCollectionViewLayout : NSCollectionViewLayout OWN_IVARS
@implementation SubStubNSCollectionViewLayout OWN_IMPL
@interface SubStubNSCollectionViewFlowLayout : NSCollectionViewFlowLayout OWN_IVARS
@implementation SubStubNSCollectionViewFlowLayout OWN_IMPL
@interface SubStubNSClickGestureRecognizer : NSClickGestureRecognizer OWN_IVARS
@implementation SubStubNSClickGestureRecognizer OWN_IMPL
@interface SubStubNSPanGestureRecognizer : NSPanGestureRecognizer OWN_IVARS
@implementation SubStubNSPanGestureRecognizer OWN_IMPL
@interface SubStubNSScrubberItemView : NSScrubberItemView OWN_IVARS
@implementation SubStubNSScrubberItemView OWN_IMPL
@interface SubStubNSScrubberTextItemView : NSScrubberTextItemView OWN_IVARS
@implementation SubStubNSScrubberTextItemView OWN_IMPL
@interface SubStubNSPageController : NSPageController OWN_IVARS
@implementation SubStubNSPageController OWN_IMPL
@interface SubStubNSTabViewController : NSTabViewController OWN_IVARS
@implementation SubStubNSTabViewController OWN_IMPL
@interface SubStubNSPasteboard : NSPasteboard OWN_IVARS
@implementation SubStubNSPasteboard OWN_IMPL
@interface SubStubNSRuleEditor : NSRuleEditor OWN_IVARS
@implementation SubStubNSRuleEditor OWN_IMPL
@interface SubStubNSLayoutDimension : NSLayoutDimension OWN_IVARS
@implementation SubStubNSLayoutDimension OWN_IMPL
@interface SubStubNSTextFinder : NSTextFinder OWN_IVARS
@implementation SubStubNSTextFinder OWN_IMPL
@interface SubStubNSDraggingItem : NSDraggingItem OWN_IVARS
@implementation SubStubNSDraggingItem OWN_IMPL

static void caseBlocks(const char *name, CreateBlock *create, TouchBlock *touch, StateBlock *state) {
    static NSImage *image;
    static id owner;
    if (image == nil) {
        image = [[NSImage alloc] initWithSize: NSMakeSize(16, 16)];
        owner = [[NSObject alloc] init];
    }
    if (strcmp(name, "NSCursor") == 0) {
        *create = ^id(id o) { return [o initWithImage: image hotSpot: NSMakePoint(3, 4)]; };
        *touch = ^(id o) { [o setOnMouseEntered: YES]; [o setOnMouseExited: YES]; };
        *state = ^long(id o) {
            return (long) ([o hotSpot].x * 10 + [o hotSpot].y) + [o isSetOnMouseEntered] * 100 +
                   [o isSetOnMouseExited] * 1000 + ([o image] == image) * 10000;
        };
    } else if (strcmp(name, "NSTrackingArea") == 0) {
        *create = ^id(id o) {
            return [o initWithRect: NSMakeRect(1, 2, 30, 40)
                           options: NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
                             owner: owner
                          userInfo: nil];
        };
        *touch = ^(id o) {};
        *state = ^long(id o) {
            return (long) [o rect].size.width + (long) [o options] * 100 + ([o owner] == owner) * 100000;
        };
    } else if (strcmp(name, "NSToolbarItem") == 0) {
        *create = ^id(id o) { return [o initWithItemIdentifier: @"item"]; };
        *touch = ^(id o) {
            [o setLabel: @"label"];
            [o setTag: 7];
            [o setEnabled: NO];
            [o setMinSize: NSMakeSize(10, 20)];
            [o setMaxSize: NSMakeSize(30, 40)];
        };
        *state = ^long(id o) {
            return (long) [[o label] length] + [o tag] * 10 + [o isEnabled] * 1000 +
                   [[o itemIdentifier] length] * 10000 + (long) [o maxSize].height * 100000;
        };
    } else if (strcmp(name, "NSSplitViewItem") == 0) {
        *create = ^id(id o) { return [o init]; };
        *touch = ^(id o) { [o setCanCollapse: YES]; [o setHoldingPriority: 300]; };
        *state = ^long(id o) { return [o canCollapse] + (long) [o holdingPriority] * 10; };
    } else if (strcmp(name, "NSPasteboardItem") == 0) {
        *create = ^id(id o) { return [o init]; };
        *touch = ^(id o) { [o setString: @"text" forType: NSPasteboardTypeString]; };
        *state = ^long(id o) {
            return (long) [[o types] count] + (long) [[o stringForType: NSPasteboardTypeString] length] * 10;
        };
    } else if (strcmp(name, "NSTextAttachment") == 0) {
        *create = ^id(id o) {
            NSFileWrapper *wrapper = [[[NSFileWrapper alloc] initRegularFileWithContents: [NSData data]] autorelease];
            return [o initWithFileWrapper: wrapper];
        };
        *touch = ^(id o) {
            NSTextAttachmentCell *cell = [[[NSTextAttachmentCell alloc] initImageCell: image] autorelease];
            [o setAttachmentCell: cell];
        };
        *state = ^long(id o) {
            return ([o fileWrapper] != nil) + ([[o attachmentCell] image] == image) * 10;
        };
    } else if (strcmp(name, "NSMutableParagraphStyle") == 0) {
        *create = ^id(id o) { return [o init]; };
        *touch = ^(id o) {
            [o setAlignment: NSCenterTextAlignment];
            [o setLineSpacing: 3];
            [o setParagraphSpacing: 5];
            [o setFirstLineHeadIndent: 7];
            [o setLineBreakMode: NSLineBreakByClipping];
        };
        *state = ^long(id o) {
            return (long) [o alignment] + (long) [o lineSpacing] * 10 + (long) [o paragraphSpacing] * 100 +
                   (long) [o firstLineHeadIndent] * 1000 + (long) [o lineBreakMode] * 10000;
        };
    } else if (strcmp(name, "NSTypesetter") == 0) {
        *create = ^id(id o) { return [o init]; };
        *touch = ^(id o) {
            [o setHyphenationFactor: 0.5];
            [o setLineFragmentPadding: 3];
            [o setUsesFontLeading: NO];
        };
        *state = ^long(id o) {
            return (long) ([o hyphenationFactor] * 10) + (long) [o lineFragmentPadding] * 100 +
                   [o usesFontLeading] * 10000;
        };
    } else if (strcmp(name, "NSTextBlock") == 0) {
        *create = ^id(id o) { return [o init]; };
        *touch = ^(id o) {
            [o setBackgroundColor: [NSColor redColor]];
            [o setContentWidth: 25 type: NSTextBlockAbsoluteValueType];
            [o setWidth: 4 type: NSTextBlockAbsoluteValueType forLayer: NSTextBlockPadding];
        };
        *state = ^long(id o) {
            return ([o backgroundColor] != nil) + (long) [o contentWidth] * 10 +
                   (long) [o widthForLayer: NSTextBlockPadding edge: NSMinXEdge] * 1000;
        };
    } else if (strcmp(name, "NSTextTable") == 0) {
        *create = ^id(id o) { return [o init]; };
        *touch = ^(id o) { [o setNumberOfColumns: 3]; [o setCollapsesBorders: YES]; [o setHidesEmptyCells: YES]; };
        *state = ^long(id o) {
            return (long) [o numberOfColumns] + [o collapsesBorders] * 10 + [o hidesEmptyCells] * 100;
        };
    } else if (strcmp(name, "NSTextTableBlock") == 0) {
        *create = ^id(id o) {
            return [o initWithTable: [[[NSTextTable alloc] init] autorelease]
                        startingRow: 2 rowSpan: 3 startingColumn: 4 columnSpan: 5];
        };
        *touch = ^(id o) { [o setBackgroundColor: [NSColor blueColor]]; };
        *state = ^long(id o) {
            return (long) [o startingRow] + [o rowSpan] * 10 + [o startingColumn] * 100 +
                   [o columnSpan] * 1000 + ([o table] != nil) * 10000 + ([o backgroundColor] != nil) * 100000;
        };
    } else if (strcmp(name, "NSBrowserCell") == 0) {
        *create = ^id(id o) { return [o initTextCell: @"cell"]; };
        *touch = ^(id o) { [o setLeaf: YES]; [o setLoaded: YES]; };
        *state = ^long(id o) {
            return (long) [[o stringValue] length] + [o isLeaf] * 10 + [o isLoaded] * 100;
        };
    } else if (strcmp(name, "NSTextAttachmentCell") == 0) {
        *create = ^id(id o) { return [o initImageCell: image]; };
        *touch = ^(id o) {
            NSTextAttachment *a = [[NSTextAttachment alloc] initWithData: nil ofType: nil];
            [o setAttachment: a];
            [a release];
        };
        *state = ^long(id o) { return [o image] == image; };
    } else if (strcmp(name, "NSCustomImageRep") == 0) {
        *create = ^id(id o) { return [o initWithDrawSelector: @selector(description) delegate: owner]; };
        *touch = ^(id o) { [o setSize: NSMakeSize(21, 22)]; };
        *state = ^long(id o) {
            return (long) [o size].width + (long) [o size].height * 100 +
                   ([o drawSelector] == @selector(description)) * 100000 + ([o delegate] == owner) * 1000000;
        };
    } else if (strcmp(name, "NSLayoutConstraint") == 0) {
        *create = ^id(id o) { return [o init]; };
        *touch = ^(id o) {
            [o setConstant: 12];
            [o setPriority: 250];
            [o setIdentifier: @"ident"];
        };
        *state = ^long(id o) {
            return (long) [o constant] + (long) [o priority] * 100 + (long) [[o identifier] length] * 100000;
        };
    }
}

// Subclasses of the classes above, with instance variables of their own: those
// stay intact while the AppKit state is used.
static void checkTableSubclasses(void) {
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        char subName[64];
        snprintf(subName, sizeof(subName), "Sub%s", cases[i].name);
        Class sub = objc_getClass(subName);
        CreateBlock create = nil;
        TouchBlock touch = nil;
        StateBlock state = nil;
        caseBlocks(cases[i].name, &create, &touch, &state);
        CHECK(sub != Nil && create != nil, "no case for %s", cases[i].name);
        if (sub == Nil || create == nil)
            continue;
        id object = create([sub alloc]);
        CHECK(object != nil, "%s could not be created", subName);
        if (object == nil)
            continue;
        [object setOwn];
        touch(object);
        long expected = state(object);
        CHECK([object ownIntact], "%s lost its own ivars after the setters", subName);
        [object setOwn];
        CHECK(state(object) == expected, "%s state changed (%ld, expected %ld)", subName, state(object), expected);
        CHECK([object ownIntact], "%s lost its own ivars after reading the state", subName);
        [object release];
#if !__LP64__
        CHECK(ivar_getOffset(class_getInstanceVariable(sub, "ownCounter")) == (ptrdiff_t) cases[i].appleSize,
              "%s's first ivar at %td, expected Apple's %zu", subName,
              ivar_getOffset(class_getInstanceVariable(sub, "ownCounter")), cases[i].appleSize);
#endif
    }
}


// Stub classes that applications subclass (gesture recognizers, collection view
// layouts, table row views, ...): a subclass compiled against the Mac layout
// starts at Apple's instance size, and the variables of the stub and its
// superclasses must not reach into it. The objects are created without -init,
// only the layout is under test.
static const struct {
    const char *name;
    size_t appleSize;
} stubCases[] = {
    {"NSTableRowView", 112},
    {"NSCollectionViewLayout", 128},
    {"NSCollectionViewFlowLayout", 252},
    {"NSClickGestureRecognizer", 112},
    {"NSPanGestureRecognizer", 120},
    {"NSScrubberItemView", 132},
    {"NSScrubberTextItemView", 152},
    {"NSPageController", 120},
    {"NSTabViewController", 64},
    {"NSPasteboard", 48},
    {"NSRuleEditor", 204},
    {"NSLayoutDimension", 32},
    {"NSTextFinder", 28},
    {"NSDraggingItem", 40},
};

static void checkStubSubclasses(void) {
    for (size_t i = 0; i < sizeof(stubCases) / sizeof(stubCases[0]); i++) {
        char subName[96];
        snprintf(subName, sizeof(subName), "SubStub%s", stubCases[i].name);
        Class sub = objc_getClass(subName);
        CHECK(sub != Nil, "%s is missing", subName);
        if (sub == Nil)
            continue;
        id object = class_createInstance(sub, 0);
        [object setOwn];
        CHECK([object ownIntact], "%s lost its own ivars", subName);
#if !__LP64__
        CHECK(ivar_getOffset(class_getInstanceVariable(sub, "ownCounter")) == (ptrdiff_t) stubCases[i].appleSize,
              "%s's first ivar at %td, expected Apple's %zu", subName,
              ivar_getOffset(class_getInstanceVariable(sub, "ownCounter")), stubCases[i].appleSize);
        CHECK(class_getInstanceSize(class_getSuperclass(sub)) == stubCases[i].appleSize,
              "%s's superclass is %zu bytes, expected Apple's %zu", subName,
              class_getInstanceSize(class_getSuperclass(sub)), stubCases[i].appleSize);
#endif
        object_dispose(object);
    }
}

#if !__LP64__
static const unsigned char pattern = 0xa5;
enum { spare = 32 };

// An object of `cls` with spare bytes right after Apple's instance size, standing
// for the instance variables of a subclass compiled against the Mac layout.
static id spareInstance(const char *name, size_t appleSize, unsigned char **spareBytes) {
    Class cls = objc_getClass(name);
    id object = class_createInstance(cls, spare);
    *spareBytes = (unsigned char *) object + appleSize;
    return object;
}

static int spareIntact(const unsigned char *bytes) {
    for (int i = 0; i < spare; i++)
        if (bytes[i] != pattern)
            return 0;
    return 1;
}

static void checkAppleLayoutBrowser(void) {
    unsigned char *own;
    NSBrowser *b = spareInstance("NSBrowser", 160, &own);
    b = [b initWithFrame: NSMakeRect(0, 0, 300, 200)];
    flipBrowser(b, YES);
    int expected = browserState(b);
    memset(own, pattern, spare);
    CHECK(browserState(b) == expected, "NSBrowser state depends on the bytes after Apple's 160");
    flipBrowser(b, NO);
    CHECK(spareIntact(own), "NSBrowser wrote past Apple's 160 byte instance");
    CHECK(browserState(b) == (2 << 8), "NSBrowser state %x with a subclass's ivars set", browserState(b));
    CHECK(spareIntact(own), "NSBrowser wrote past Apple's 160 byte instance (reading)");
    [b release];
}

static void checkAppleLayoutColorWell(void) {
    unsigned char *own;
    NSColorWell *w = spareInstance("NSColorWell", 108, &own);
    w = [w initWithFrame: NSMakeRect(0, 0, 40, 24)];
    [w setBordered: YES];
    [w setEnabled: YES];
    [w setContinuous: YES];
    [w setColor: [NSColor blueColor]];
    int expected = wellState(w);
    memset(own, pattern, spare);
    CHECK(wellState(w) == expected, "NSColorWell state depends on the bytes after Apple's 108");
    [w setBordered: NO];
    [w setColor: [NSColor greenColor]];
    CHECK(spareIntact(own), "NSColorWell wrote past Apple's 108 byte instance");
    CHECK(![w isBordered] && [[w color] isEqual: [NSColor greenColor]],
          "NSColorWell state wrong with a subclass's ivars set");
    [w release];
}
// The legacy-ABI check for the table: an instance of the class itself with
// spare bytes after Apple's size (a subclass's instance variables) keeps them
// through creation, use and release, and its state does not depend on them.
static void checkAppleLayoutTable(void) {
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        CreateBlock create = nil;
        TouchBlock touch = nil;
        StateBlock state = nil;
        caseBlocks(cases[i].name, &create, &touch, &state);
        unsigned char *own;
        id object = spareInstance(cases[i].name, cases[i].appleSize, &own);
        memset(own, pattern, spare);
        object = create(object);
        CHECK(object != nil, "%s could not be created with spare bytes", cases[i].name);
        if (object == nil)
            continue;
        CHECK(spareIntact(own), "%s wrote past Apple's %zu byte instance when created", cases[i].name,
              cases[i].appleSize);
        touch(object);
        long expected = state(object);
        CHECK(spareIntact(own), "%s wrote past Apple's %zu byte instance when used", cases[i].name,
              cases[i].appleSize);
        CHECK(state(object) == expected, "%s state depends on the bytes after Apple's %zu", cases[i].name,
              cases[i].appleSize);
        [object release];
    }
}
#endif

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        checkSubclasses();
        checkTableSubclasses();
        checkStubSubclasses();
#if !__LP64__
        CHECK(class_getInstanceSize([SubBrowser class]) >= 160 + 16, "SubBrowser size %zu",
              class_getInstanceSize([SubBrowser class]));
        CHECK(ivar_getOffset(class_getInstanceVariable([SubBrowser class], "ownCounter")) == 160,
              "SubBrowser's first ivar is not at Apple's 160");
        CHECK(ivar_getOffset(class_getInstanceVariable([SubColorWell class], "ownCounter")) == 108,
              "SubColorWell's first ivar is not at Apple's 108");
        checkAppleLayoutBrowser();
        checkAppleLayoutColorWell();
        checkAppleLayoutTable();
#endif
    }
    if (failures != 0)
        return 1;
    printf("OK\n");
    return 0;
}
