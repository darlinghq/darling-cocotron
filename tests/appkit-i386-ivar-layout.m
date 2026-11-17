// Copyright (C) 2026 Lubos Dolezel
//
// On the legacy (32-bit) Objective-C ABI an application's subclass of an
// AppKit class is compiled against Apple's instance layout: its instance
// variables sit at offsets fixed at compile time, directly after the AppKit
// class's instance size. So each public AppKit class must report that size,
// keep the instance variables that public headers declare at their offsets,
// and the runtime must see the class and its subclasses as laid out one after
// the other (OBJC_DEBUG_FRAGILE_SUPERCLASSES=YES warns when a subclass's first
// instance variable is not past the last instance variable of its superclass).
//
// The expected values are what Mac OS X 10.14.4 reports for the same classes
// through the public runtime API (class_getInstanceSize, class_copyIvarList,
// ivar_getOffset; black-box observation, i386). The layout checks only run on
// the legacy ABI; the extra-state accessors at the end run everywhere.
#import <AppKit/AppKit.h>
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

#if !__LP64__
static const struct {
    const char *cls;
    size_t size;
} sizes[] = {
    {"NSResponder", 8},   {"NSView", 80},   {"NSWindow", 132},
    {"NSPanel", 132},     {"NSApplication", 76}, {"NSControl", 92},
    {"NSButton", 92},     {"NSCell", 20},
    // larger in Darling than on the Mac, so an application's subclass
    // overlapped them
    {"NSBrowser", 160},   {"NSColorWell", 108},
    // smaller in Darling than on the Mac
    {"NSText", 84},       {"NSTextView", 84},
    {"NSSavePanel", 248}, {"NSOpenPanel", 256},
    {"NSTabView", 148},   {"NSMenuItemCell", 116},
    {"NSPopUpButtonCell", 128}, {"NSStepper", 108},
    {"NSSegmentedControl", 108}, {"NSSearchField", 116},
    {"NSComboBox", 104},  {"NSTableHeaderView", 116},
    {"NSMenuView", 156},  {"NSPrintInfo", 12},
    {"NSEvent", 60},      {"NSDocumentController", 24},
    // the public classes that differed from the Mac in instance size (the
    // larger ones overlapped an application's subclass); each is a class that
    // an application can subclass or whose instance variables it can read
    {"NSAlert", 120}, {"NSAnimation", 76}, {"NSAnimationContext", 32},
    {"NSAppearance", 32}, {"NSArrayController", 132}, {"NSBezierPath", 88},
    {"NSBrowserCell", 20}, {"NSCachedImageRep", 44}, {"NSCollectionView", 272},
    {"NSCollectionViewItem", 68}, {"NSColorList", 36}, {"NSColorPanel", 252},
    {"NSColorSpace", 36}, {"NSComboBoxCell", 88}, {"NSController", 60},
    {"NSCursor", 20}, {"NSCustomImageRep", 40}, {"NSCustomTouchBarItem", 72},
    {"NSDatePickerCell", 104}, {"NSDictionaryController", 184},
    {"NSDockTile", 60}, {"NSDrawer", 100}, {"NSEPSImageRep", 44},
    {"NSFontDescriptor", 28}, {"NSFontManager", 52}, {"NSFontPanel", 612},
    {"NSGestureRecognizer", 72}, {"NSGlyphInfo", 8}, {"NSGradient", 32},
    {"NSGraphicsContext", 4}, {"NSGroupTouchBarItem", 60},
    {"NSHelpManager", 32}, {"NSLayoutConstraint", 52}, {"NSLayoutGuide", 96},
    {"NSLayoutManager", 216}, {"NSLevelIndicatorCell", 120},
    {"NSMutableParagraphStyle", 48}, {"NSNib", 32}, {"NSObjectController", 92},
    {"NSOpenGLPixelBuffer", 16}, {"NSOpenGLPixelFormat", 24},
    {"NSPDFImageRep", 44}, {"NSPICTImageRep", 48}, {"NSPageLayout", 188},
    {"NSParagraphStyle", 48}, {"NSPasteboardItem", 24}, {"NSPathCell", 104},
    {"NSPathComponentCell", 76}, {"NSPathControl", 112}, {"NSPopover", 96},
    {"NSPrintOperation", 4}, {"NSPrintPanel", 248}, {"NSPrinter", 48},
    {"NSRulerView", 144}, {"NSRunningApplication", 80}, {"NSScreen", 32},
    {"NSSearchFieldCell", 96}, {"NSSegmentedCell", 84}, {"NSShadow", 40},
    {"NSSharingService", 8}, {"NSSharingServicePicker", 8},
    {"NSSliderCell", 104}, {"NSSound", 40}, {"NSSpellChecker", 84},
    {"NSSplitViewController", 64}, {"NSSplitViewItem", 12},
    {"NSStackView", 148}, {"NSStatusBar", 20}, {"NSStepperCell", 88},
    {"NSStoryboard", 8}, {"NSTabViewItem", 72}, {"NSTableCellView", 104},
    {"NSTextAttachment", 16}, {"NSTextAttachmentCell", 24},
    {"NSTextBlock", 32}, {"NSTextList", 20}, {"NSTextTable", 52},
    {"NSTextTableBlock", 60}, {"NSTitlebarAccessoryViewController", 88},
    {"NSTokenField", 120}, {"NSTokenFieldCell", 128}, {"NSToolbarItem", 72},
    {"NSToolbarItemGroup", 84}, {"NSTouchBar", 52}, {"NSTouchBarItem", 36},
    {"NSTrackingArea", 40}, {"NSTreeController", 140}, {"NSTreeNode", 32},
    {"NSTypesetter", 12}, {"NSUserDefaultsController", 84},
    {"NSViewAnimation", 120}, {"NSVisualEffectView", 140}, {"NSWorkspace", 20},
    // the stub classes of AppKit and UIFoundation that were smaller than on the Mac
    {"NSATSTypesetter", 100}, {"NSCIImageRep", 32},
    {"NSClickGestureRecognizer", 112}, {"NSCollectionViewFlowLayout", 252},
    {"NSCollectionViewFlowLayoutInvalidationContext", 68},
    {"NSCollectionViewGridLayout", 268}, {"NSCollectionViewLayout", 128},
    {"NSCollectionViewLayoutAttributes", 256},
    {"NSCollectionViewLayoutInvalidationContext", 64},
    {"NSCollectionViewTransitionLayout", 208},
    {"NSCollectionViewUpdateItem", 64}, {"NSColorPickerTouchBarItem", 100},
    {"NSDataAsset", 8}, {"NSDraggingImageComponent", 28},
    {"NSDraggingItem", 40}, {"NSFilePromiseProvider", 44}, {"NSGridCell", 48},
    {"NSGridColumn", 48}, {"NSGridRow", 56}, {"NSGridView", 128},
    {"NSInputManager", 64}, {"NSLayoutAnchor", 32}, {"NSLayoutDimension", 32},
    {"NSLayoutXAxisAnchor", 32}, {"NSLayoutYAxisAnchor", 32},
    {"NSMagnificationGestureRecognizer", 104}, {"NSMovie", 24},
    {"NSPageController", 120}, {"NSPanGestureRecognizer", 120},
    {"NSPasteboard", 48}, {"NSPersistentDocument", 80},
    {"NSPopoverTouchBarItem", 80}, {"NSPredicateEditor", 240},
    {"NSPredicateEditorRowTemplate", 36}, {"NSPressGestureRecognizer", 108},
    {"NSPressureConfiguration", 12}, {"NSRotationGestureRecognizer", 104},
    {"NSRuleEditor", 204}, {"NSScrubber", 172},
    {"NSScrubberArrangedView", 100}, {"NSScrubberFlowLayout", 28},
    {"NSScrubberImageItemView", 156}, {"NSScrubberItemView", 132},
    {"NSScrubberLayout", 12}, {"NSScrubberProportionalLayout", 16},
    {"NSScrubberTextItemView", 152},
    {"NSSharingServicePickerTouchBarItem", 68}, {"NSSliderAccessory", 32},
    {"NSSliderTouchBarItem", 72}, {"NSSpeechSynthesizer", 8},
    {"NSStringDrawingContext", 8}, {"NSTabViewController", 64},
    {"NSTableRowView", 112}, {"NSTableViewRowAction", 28},
    {"NSTextAlternatives", 16}, {"NSTextFinder", 28},
    {"NSTextInputContext", 48},
    // the instance size agreed already; the instance variables did not
    {"NSTextContainer", 28}, {"NSProgressIndicator", 144},
};

// An instance variable that Darling and the Mac name differently is listed
// with both names (alt); the one that exists is checked.
static const struct {
    const char *cls;
    const char *ivar;
    ptrdiff_t offset;
    const char *alt;
} offsets[] = {
    {"NSResponder", "_nextResponder", 4},
    {"NSView", "_frame", 8},       {"NSView", "_bounds", 24},
    {"NSView", "_superview", 40},  {"NSView", "_subviews", 44},
    {"NSView", "_window", 48},     {"NSView", "_layer", 60},
    {"NSWindow", "_frame", 8},     {"NSWindow", "_contentView", 24},
    {"NSWindow", "_delegate", 28}, {"NSWindow", "_firstResponder", 32},
    {"NSWindow", "_level", 60},    {"NSWindow", "_backgroundColor", 64},
    {"NSApplication", "_currentEvent", 8}, {"NSApplication", "_keyWindow", 16},
    {"NSApplication", "_mainWindow", 20},  {"NSApplication", "_delegate", 24},
    {"NSApplication", "_running", 50},     {"NSApplication", "_mainMenu", 56},
    {"NSControl", "_aux", 80},     {"NSControl", "_cell", 84},
    {"NSTextContainer", "_layoutManager", 4}, {"NSTextContainer", "_textView", 8},
    {"NSTextContainer", "_size", 12}, {"NSTextContainer", "_lineFragmentPadding", 20},
    {"NSProgressIndicator", "_isBezeled", 80},
    {"NSProgressIndicator", "_isIndeterminate", 81},
    {"NSProgressIndicator", "_minimum", 84, "_minValue"},
    {"NSProgressIndicator", "_maximum", 92, "_maxValue"},
    {"NSProgressIndicator", "_value", 100},
    {"NSProgressIndicator", "_animationDelay", 112},
    {"NSColorWell", "_color", 92},
    {"NSBrowser", "_delegate", 100}, {"NSBrowser", "_doubleAction", 104},
    {"NSBrowser", "_matrixClass", 108}, {"NSBrowser", "_cellPrototype", 112},
    {"NSBrowser", "_titles", 132},
    {"NSTabView", "_tabViewItems", 80, "_items"},
    {"NSTabView", "_selectedTabViewItem", 84, "_selectedItem"},
    {"NSTabView", "_font", 88}, {"NSTabView", "_delegate", 100},
    {"NSTabView", "_drawsBackground", 105},
    {"NSPopUpButtonCell", "_menu", 116}, {"NSPopUpButtonCell", "_selectedIndex", 120},
    {"NSEvent", "_type", 4}, {"NSEvent", "_location", 8, "_locationInWindow"},
    {"NSEvent", "_modifierFlags", 16}, {"NSEvent", "_timestamp", 24},
    {"NSEvent", "_windowNumber", 32},
};

// classes whose subclass chains an application can extend
static const char *chained[] = {
    "NSResponder", "NSView", "NSWindow", "NSPanel", "NSSavePanel", "NSOpenPanel",
    "NSApplication", "NSControl", "NSButton", "NSPopUpButton", "NSTextField",
    "NSViewController", "NSWindowController", "NSOpenGLView", "NSClipView",
    "NSScrollView", "NSMatrix", "NSTableView", "NSOutlineView",
    "NSText", "NSTextView", "NSTabView", "NSBrowser", "NSColorWell",
    "NSButtonCell", "NSMenuItemCell", "NSPopUpButtonCell", "NSStepper",
    "NSSegmentedControl", "NSSearchField", "NSComboBox", "NSTableHeaderView",
    "NSMenuView", "NSProgressIndicator",
};

static ptrdiff_t ivarOffset(Class cls, const char *name) {
    unsigned count = 0;
    Ivar *list = class_copyIvarList(cls, &count);
    ptrdiff_t result = -1;
    for (unsigned i = 0; i < count; i++)
        if (strcmp(ivar_getName(list[i]), name) == 0)
            result = ivar_getOffset(list[i]);
    free(list);
    return result;
}

static void checkLayout(void) {
    for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
        Class cls = objc_getClass(sizes[i].cls);
        CHECK(cls != Nil, "%s is missing", sizes[i].cls);
        if (cls != Nil)
            CHECK(class_getInstanceSize(cls) == sizes[i].size,
                  "%s instance size %zu, expected %zu", sizes[i].cls,
                  class_getInstanceSize(cls), sizes[i].size);
    }
    for (size_t i = 0; i < sizeof(offsets) / sizeof(offsets[0]); i++) {
        Class cls = objc_getClass(offsets[i].cls);
        if (cls == Nil)
            continue;
        ptrdiff_t offset = ivarOffset(cls, offsets[i].ivar);
        if (offset < 0 && offsets[i].alt != NULL)
            offset = ivarOffset(cls, offsets[i].alt);
        CHECK(offset == offsets[i].offset, "%s.%s at %td, expected %td",
              offsets[i].cls, offsets[i].ivar, offset, offsets[i].offset);
    }
    for (size_t i = 0; i < sizeof(chained) / sizeof(chained[0]); i++) {
        Class cls = objc_getClass(chained[i]);
        if (cls == Nil)
            continue;
        unsigned count = 0;
        Ivar *list = class_copyIvarList(cls, &count);
        for (unsigned j = 0; j < count; j++)
            // an instance variable at or past the end of the instance (such as
            // a zero-sized trailing one) overlaps the first one of any subclass
            CHECK((size_t) ivar_getOffset(list[j]) < class_getInstanceSize(cls),
                  "%s.%s at %td is not inside the %zu byte instance",
                  chained[i], ivar_getName(list[j]), ivar_getOffset(list[j]),
                  class_getInstanceSize(cls));
        // the runtime's own check: this class's first instance variable is
        // past the last one of the closest superclass that has any
        if (count > 0) {
            Class super_ = class_getSuperclass(cls);
            unsigned superCount = 0;
            Ivar *superList = NULL;
            while (super_ != Nil) {
                superList = class_copyIvarList(super_, &superCount);
                if (superCount > 0)
                    break;
                free(superList);
                superList = NULL;
                super_ = class_getSuperclass(super_);
            }
            if (superCount > 0) {
                ptrdiff_t last = ivar_getOffset(superList[superCount - 1]);
                CHECK(ivar_getOffset(list[0]) > last,
                      "ivars of %s and %s overlap (%td <= %td)",
                      class_getName(super_), chained[i],
                      ivar_getOffset(list[0]), last);
                CHECK((size_t) ivar_getOffset(list[0]) >= class_getInstanceSize(super_),
                      "first ivar of %s at %td is inside %s (%zu bytes)",
                      chained[i], ivar_getOffset(list[0]),
                      class_getName(super_), class_getInstanceSize(super_));
            }
            free(superList);
        }
        free(list);
    }
}
#endif

// Classes that keep state beyond Apple's footprint in side storage must still
// hold it per object.
static void checkExtraState(void) {
    NSButton *first = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 80, 20)];
    NSButton *second = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 80, 20)];
    [first setContentTintColor: [NSColor redColor]];
    CHECK([first contentTintColor] != nil, "NSButton lost its content tint color");
    CHECK([second contentTintColor] == nil, "NSButton extras are shared between objects");
    [first release];
    [second release];

    NSPanel *panel = [[NSPanel alloc] initWithContentRect: NSMakeRect(0, 0, 100, 100)
                                                styleMask: NSTitledWindowMask
                                                  backing: NSBackingStoreBuffered
                                                    defer: YES];
    [panel setWorksWhenModal: YES];
    [panel setBecomesKeyOnlyIfNeeded: YES];
    CHECK([panel worksWhenModal], "NSPanel lost worksWhenModal");
    CHECK([panel becomesKeyOnlyIfNeeded], "NSPanel lost becomesKeyOnlyIfNeeded");
    [panel release];

    // copies of objects with extra state or side storage keep the state and do
    // not share it
    NSBrowserCell *cell = [[NSBrowserCell alloc] initTextCell: @"cell"];
    [cell setLeaf: YES];
    [cell setLoaded: YES];
    NSBrowserCell *cellCopy = [cell copy];
    [cell setLeaf: NO];
    CHECK([cellCopy isLeaf] && [cellCopy isLoaded], "NSBrowserCell copy lost its state");
    CHECK(![cell isLeaf] && [cellCopy isLeaf], "NSBrowserCell copy shares its state");
    [cellCopy release];
    [cell release];

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier: @"item"];
    [item setLabel: @"label"];
    [item setTag: 5];
    NSToolbarItem *itemCopy = [item copy];
    [item setTag: 6];
    CHECK([[itemCopy label] isEqualToString: @"label"] && [itemCopy tag] == 5,
          "NSToolbarItem copy lost or shares its state");
    [itemCopy release];
    [item release];

    NSImage *image = [[NSImage alloc] initWithSize: NSMakeSize(8, 8)];
    NSTextAttachmentCell *attachmentCell = [[NSTextAttachmentCell alloc] initImageCell: image];
    NSTextAttachmentCell *attachmentCellCopy = [attachmentCell copy];
    CHECK([attachmentCellCopy image] == image, "NSTextAttachmentCell copy lost its image");
    [attachmentCellCopy release];
    [attachmentCell release];
    [image release];

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    [style setLineSpacing: 4];
    NSParagraphStyle *styleCopy = [style copy];
    NSMutableParagraphStyle *styleMutableCopy = [style mutableCopy];
    [style setLineSpacing: 9];
    CHECK([styleCopy lineSpacing] == 4 && [styleMutableCopy lineSpacing] == 4,
          "NSParagraphStyle copies lost or share their state");
    [styleCopy release];
    [styleMutableCopy release];
    [style release];
}

int main(void) {
    @autoreleasepool {
#if !__LP64__
        checkLayout();
#endif
        checkExtraState();
    }
    if (failures != 0)
        return 1;
    printf("OK\n");
    return 0;
}
