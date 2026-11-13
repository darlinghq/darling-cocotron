/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Decoding of NSTabViewItem, NSTableColumn, NSScroller, NSClipView, NSTabView,
 * NSScrollView, NSTableView, NSOutlineView and NSComboBoxCell from NSArchiver
 * (typedstream) data. The archives are built here: for every class under test
 * a subclass writes, in its encodeWithCoder:, the layers of the class chain
 * (NSResponder, NSView, NSControl or NSCell, ...) in the order the decoders
 * read them, then the layout of the class itself. The subclass instance is
 * archived with NSArchiver and read back with NSUnarchiver, so the class under
 * test is decoded through its real -initWithCoder:. Class versions are set
 * before archiving because the archive records them and the decoders select the
 * layout from them. No window server is needed.
 *
 * The layouts of the controls are not documented; most come from the reports of
 * the contributor of the decoders (archives found in old nibs). These tests pin
 * the layouts the decoders accept; they cannot confirm them against macOS. The
 * layouts of NSTabView and NSTabViewItem are the ones recorded on Mac OS X
 * 10.14.4 (see appkit-nonkeyed-controls), and so are those of NSTableColumn,
 * NSScroller, NSClipView, NSScrollView, NSTableView, NSOutlineView and
 * NSComboBoxCell (see appkit-nonkeyed-containers).
 */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

// An object with nothing to store, used as a target or data source.
@interface TTarget : NSObject <NSCoding>
@end

@implementation TTarget
- (void) encodeWithCoder: (NSCoder *) coder
{
}
- (id) initWithCoder: (NSCoder *) coder
{
    return [super init];
}
@end

static void putObject(NSCoder *coder, id object)
{
    [coder encodeValueOfObjCType: "@" at: &object];
}

// NSResponder, then NSView at version 16: float, frame, bounds, superview,
// window, then subviews/flags/flags/object.
static void putViewLayers(NSCoder *coder, NSRect frame)
{
    float dummy = 0;
    NSMutableArray *subviews = [NSMutableArray array];
    short flags1 = 0, flags2 = 0x200;
    id other = nil;

    [coder encodeObject: nil];
    [coder encodeValuesOfObjCTypes: "f", &dummy];
    [coder encodeRect: frame];
    [coder encodeRect: frame];
    [coder encodeObject: nil];
    [coder encodeObject: nil];
    [coder encodeValuesOfObjCTypes: "@ss@", &subviews, &flags1, &flags2, &other];
}

// NSControl at version 0: tag, cell, flags.
static void putControlLayer(NSCoder *coder)
{
    int tag = 7;
    id cell = nil;
    unsigned short flags = 0;

    [coder encodeValuesOfObjCTypes: "i@s", &tag, &cell, &flags];
}

static void putTableViewLayer(NSCoder *coder)
{
    id headerView = nil, cornerView = nil;
    id columns = [NSMutableArray array];
    float spacingW = 4, spacingH = 5, rowHeight = 20;
    id background = nil, grid = nil;
    SEL action = @selector(description), doubleAction = @selector(hash);
    int flags = (int) (0x80000000u | 0x08000000u | 0x00008000u);

    [coder encodeValuesOfObjCTypes: "@@@ff@@f::i", &headerView, &cornerView,
                                    &columns, &spacingW, &spacingH,
                                    &background, &grid, &rowHeight, &action,
                                    &doubleAction, &flags];
    // The delegate, the data source and the target.
    [coder encodeObject: [[[TTarget alloc] init] autorelease]];
    [coder encodeObject: nil];
    [coder encodeObject: nil];
}

static id roundTrip(id object)
{
    NSData *data = [NSArchiver archivedDataWithRootObject: object];
    return [NSUnarchiver unarchiveObjectWithData: data];
}

// --- NSTabViewItem -----------------------------------------------------------

@interface TTabItem : NSTabViewItem
@end

@implementation TTabItem
- (void) encodeWithCoder: (NSCoder *) coder
{
    id identifier = @"first", label = @"First", view = nil, color = nil;
    id responder = nil, lastKeyView = nil, tabView = nil;

    [coder encodeValuesOfObjCTypes: "@@@@@@@", &identifier, &view, &label, &color, &responder, &lastKeyView, &tabView];
}
@end

static void test_quirk_typedstream_tab_view_item(void)
{
    NSTabViewItem *item = roundTrip([[[TTabItem alloc] init] autorelease]);
    expect([item isKindOfClass: [NSTabViewItem class]], "tab view item decodes");
    expect([[item identifier] isEqual: @"first"], "tab view item identifier");
    expect([[item label] isEqual: @"First"], "tab view item label");
}

// --- NSTableColumn -----------------------------------------------------------

@interface TColumn : NSTableColumn
@end

// One layout in every class version: identifier, widths, cells, flags, then the table view.
@implementation TColumn
- (void) encodeWithCoder: (NSCoder *) coder
{
    id identifier = @"size", header = @"Header2", data = @"Data2", tableView = nil;
    float w = 90, minW = 15, maxW = 250;
    char resizable = 1, editable = 0;

    [coder encodeValuesOfObjCTypes: "@fff@@cc", &identifier, &w, &minW, &maxW,
                                    &header, &data, &resizable, &editable];
    [coder encodeObject: tableView];
}
@end

static void test_quirk_typedstream_table_column(void)
{
    NSTableColumn *col = roundTrip([[[TColumn alloc] init] autorelease]);
    expect([[col identifier] isEqual: @"size"], "column identifier");
    expect([col width] == 90 && [col minWidth] == 15 && [col maxWidth] == 250, "column widths");
    expect([col isResizable] && ![col isEditable], "column flags");
    expect([[col headerCell] isEqual: @"Header2"] && [[col dataCell] isEqual: @"Data2"], "column cells");
}

// --- NSScroller --------------------------------------------------------------

@interface TScroller : NSScroller
@end

@implementation TScroller
- (void) encodeWithCoder: (NSCoder *) coder
{
    id target = [[[TTarget alloc] init] autorelease];
    float value = 0.25, proportion = 0.5;
    SEL action = @selector(description);
    char unknown = 0, flags = 0x20; // control size small in bits 5-6

    putViewLayers(coder, NSMakeRect(0, 0, 15, 100));
    putControlLayer(coder);
    putObject(coder, target);
    [coder encodeValuesOfObjCTypes: "ff:", &value, &proportion, &action];
    [coder encodeValueOfObjCType: "c" at: &unknown];
    [coder encodeValueOfObjCType: "c" at: &flags];
}
@end

static void test_quirk_typedstream_scroller(void)
{
    class_setVersion([NSView class], 16);
    class_setVersion([NSScroller class], 211);
    NSScroller *scroller = roundTrip([[[TScroller alloc] initWithFrame: NSMakeRect(0, 0, 15, 100)] autorelease]);
    expect([scroller isKindOfClass: [NSScroller class]], "scroller decodes");
    expect([scroller floatValue] == 0.25f, "scroller value");
    expect([scroller knobProportion] == 0.5f, "scroller knob proportion");
    expect([scroller action] == @selector(description), "scroller action");
    expect([[scroller target] isKindOfClass: [TTarget class]], "scroller target");
    expect([scroller controlSize] == NSSmallControlSize, "scroller control size");
}

// --- NSClipView --------------------------------------------------------------

@interface TClipView : NSClipView
@end

@implementation TClipView
- (void) encodeWithCoder: (NSCoder *) coder
{
    id background = nil, cursor = nil, docView = nil;
    char other = 0, doesNotCopy = 0, drawsBackground = 0;

    // Version 58: the document view, then background, cursor and three bytes.
    putViewLayers(coder, NSMakeRect(0, 0, 200, 100));
    [coder encodeObject: docView];
    [coder encodeValuesOfObjCTypes: "@@ccc", &background, &cursor, &other, &doesNotCopy, &drawsBackground];
}
@end

static void test_quirk_typedstream_clip_view(void)
{
    class_setVersion([NSView class], 16);
    class_setVersion([NSClipView class], 58);
    NSClipView *clip = roundTrip([[[TClipView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)] autorelease]);
    expect([clip isKindOfClass: [NSClipView class]], "clip view decodes");
    expect([clip copiesOnScroll], "clip view copies on scroll");
    expect(![clip drawsBackground], "clip view does not draw its background");
    expect([clip documentView] == nil, "clip view has no document view");
}

// --- NSTabView ---------------------------------------------------------------

@interface TTabViewV2 : NSTabView
@end
@interface TTabViewV1 : NSTabView
@end

static void putTabViewLayer(NSCoder *coder, BOOL withDrawsBackground)
{
    id items = [NSMutableArray array], selected = nil, font = nil;
    int type = NSBottomTabsBezelBorder;
    char truncated = 1, draws = 1;

    putViewLayers(coder, NSMakeRect(0, 0, 300, 200));
    if (withDrawsBackground) {
        [coder encodeValuesOfObjCTypes: "@@@icc", &items, &selected, &font, &type, &truncated, &draws];
    } else {
        [coder encodeValuesOfObjCTypes: "@@@ic", &items, &selected, &font, &type, &truncated];
    }
    [coder encodeObject: nil];
}

@implementation TTabViewV2
- (void) encodeWithCoder: (NSCoder *) coder
{
    putTabViewLayer(coder, YES);
}
@end

@implementation TTabViewV1
- (void) encodeWithCoder: (NSCoder *) coder
{
    putTabViewLayer(coder, NO);
}
@end

static void test_quirk_typedstream_tab_view(void)
{
    class_setVersion([NSView class], 16);
    class_setVersion([NSTabView class], 2);
    NSTabView *v2 = roundTrip([[[TTabViewV2 alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)] autorelease]);
    expect([v2 tabViewType] == NSBottomTabsBezelBorder, "v2 tab view type");
    expect([v2 drawsBackground] && [[v2 tabViewItems] count] == 0, "v2 tab view state");
    expect([v2 allowsTruncatedLabels], "v2 tab view truncated labels");

    // Before version 2 there is no draws-background byte: the background is drawn.
    class_setVersion([NSTabView class], 1);
    NSTabView *v1 = roundTrip([[[TTabViewV1 alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)] autorelease]);
    expect([v1 tabViewType] == NSBottomTabsBezelBorder, "v1 tab view type");
    expect([v1 drawsBackground] && [[v1 tabViewItems] count] == 0, "v1 tab view state");
    expect([v1 allowsTruncatedLabels], "v1 tab view truncated labels");
}

// --- NSScrollView ------------------------------------------------------------

@interface TScrollViewNew : NSScrollView
@end
@interface TScrollViewOld : NSScrollView
@end

@implementation TScrollViewNew
- (void) encodeWithCoder: (NSCoder *) coder
{
    id clip = [[[TClipView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)] autorelease];
    id vertical = [[[TScroller alloc] initWithFrame: NSMakeRect(0, 0, 15, 100)] autorelease];
    id horizontal = nil, corner = nil, header = nil;
    float hPage = 12, vPage = 14, hLine = 11, vLine = 13;
    int flags = (int) 0x80000000u; // vertical scroller

    // Version 226: vertical scroller, horizontal scroller, content view, header clip view and
    // corner view, then the four scroll amounts and the flag word.
    putViewLayers(coder, NSMakeRect(0, 0, 215, 100));
    [coder encodeObject: vertical];
    [coder encodeObject: horizontal];
    [coder encodeObject: clip];
    [coder encodeObject: header];
    [coder encodeObject: corner];
    [coder encodeValuesOfObjCTypes: "ffffi", &hPage, &vPage, &hLine, &vLine, &flags];
}
@end

@implementation TScrollViewOld
- (void) encodeWithCoder: (NSCoder *) coder
{
    id clip = [[[TClipView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)] autorelease];
    id vertical = [[[TScroller alloc] initWithFrame: NSMakeRect(0, 0, 15, 100)] autorelease];
    id horizontal = nil;
    float page = 6, line = 5;
    short flagsHigh = (short) 0x8400; // vertical scroller, border type 2

    // Versions 1-16: vertical scroller, horizontal scroller and content view, the amounts and
    // the upper half of the flag word as a short, in one group.
    putViewLayers(coder, NSMakeRect(0, 0, 215, 100));
    [coder encodeValuesOfObjCTypes: "@@@ffs", &vertical, &horizontal, &clip, &page, &line, &flagsHigh];
}
@end

static void test_quirk_typedstream_scroll_view(void)
{
    class_setVersion([NSView class], 16);
    class_setVersion([NSScroller class], 211);
    class_setVersion([NSClipView class], 58);
    class_setVersion([NSScrollView class], 226);
    NSScrollView *newer = roundTrip([[[TScrollViewNew alloc] initWithFrame: NSMakeRect(0, 0, 215, 100)] autorelease]);
    expect([[newer contentView] isKindOfClass: [NSClipView class]], "version 226 scroll view content view");
    expect([newer hasVerticalScroller] && ![newer hasHorizontalScroller], "version 226 scroll view scrollers");
    expect([newer horizontalLineScroll] == 11 && [newer verticalPageScroll] == 14, "version 226 scroll amounts");

    class_setVersion([NSScrollView class], 10);
    NSScrollView *older = roundTrip([[[TScrollViewOld alloc] initWithFrame: NSMakeRect(0, 0, 215, 100)] autorelease]);
    expect([[older contentView] isKindOfClass: [NSClipView class]], "version 10 scroll view content view");
    expect([older borderType] == NSBezelBorder, "version 10 scroll view border");
    expect([older hasVerticalScroller] && ![older hasHorizontalScroller], "version 10 scroll view scrollers");
    expect([older horizontalLineScroll] == 5 && [older verticalPageScroll] == 6, "version 10 scroll amounts");
}

// --- NSTableView and NSOutlineView ---------------------------------------------

@interface TTableView : NSTableView
@end
@interface TOutlineView : NSOutlineView
@end

@implementation TTableView
- (void) encodeWithCoder: (NSCoder *) coder
{
    putViewLayers(coder, NSMakeRect(0, 0, 300, 200));
    putControlLayer(coder);
    putTableViewLayer(coder);
}
@end

@implementation TOutlineView
- (void) encodeWithCoder: (NSCoder *) coder
{
    // Nothing follows the table view layout.
    putViewLayers(coder, NSMakeRect(0, 0, 300, 200));
    putControlLayer(coder);
    putTableViewLayer(coder);
}
@end

static void test_quirk_typedstream_table_view(void)
{
    class_setVersion([NSView class], 16);
    NSTableView *table = roundTrip([[[TTableView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)] autorelease]);
    expect([table isKindOfClass: [NSTableView class]], "table view decodes");
    expect([table rowHeight] == 20, "table view row height");
    expect([table intercellSpacing].width == 4 && [table intercellSpacing].height == 5, "table view spacing");
    expect([table doubleAction] == @selector(hash), "table view double action");
    expect([[table delegate] isKindOfClass: [TTarget class]], "table view delegate comes first");
    expect([table allowsColumnReordering] && [table allowsMultipleSelection], "table view flag bits");
    expect(![table allowsColumnResizing] && ![table allowsEmptySelection], "table view clear flag bits");
    expect([[table tableColumns] count] == 0, "table view columns");
}

static void test_quirk_typedstream_outline_view(void)
{
    class_setVersion([NSView class], 16);
    NSOutlineView *outline = roundTrip([[[TOutlineView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)] autorelease]);
    expect([outline isKindOfClass: [NSOutlineView class]], "outline view decodes");
    expect([outline indentationPerLevel] == 20, "outline view indentation follows the row height");
    expect([outline indentationMarkerFollowsCell], "outline view marker follows cell");
    expect([outline autoresizesOutlineColumn], "outline view autoresizes outline column");
    expect(![outline autosaveExpandedItems], "outline view does not autosave expanded items");
    expect([outline rowHeight] == 20, "outline view inherits the table layout");
}

// --- NSComboBoxCell ----------------------------------------------------------

@interface TComboCell : NSComboBoxCell
@end

@implementation TComboCell
- (void) encodeWithCoder: (NSCoder *) coder
{
    // NSCell (version 55): flags, then value, image/font, formatter, represented object.
    int flags = 0, flags2 = 0;
    id value = @"item", image = nil, formatter = nil, represented = nil;
    // NSActionCell (version 17): tag and action, then target and control view.
    int tag = 3;
    SEL action = @selector(description);
    // NSTextFieldCell (version 61): flags, background and text colour.
    char textFlags = 1;
    id background = nil, textColor = nil;
    // NSComboBoxCell: visible items, scroller, data source, completes.
    int visible = 8;
    char scroller = 0, usesDataSource = 1, completes = 1;
    id list = [NSMutableArray arrayWithObjects: @"a", @"b", nil];
    id dataSource = [[[TTarget alloc] init] autorelease];

    [coder encodeValuesOfObjCTypes: "ii", &flags, &flags2];
    [coder encodeValuesOfObjCTypes: "@@@@", &value, &image, &formatter, &represented];
    [coder encodeValuesOfObjCTypes: "i:", &tag, &action];
    [coder encodeObject: nil];
    [coder encodeObject: nil];
    [coder encodeValuesOfObjCTypes: "c@@", &textFlags, &background, &textColor];
    [coder encodeValuesOfObjCTypes: "iccc", &visible, &scroller, &usesDataSource, &completes];
    // Pop-up list, data source (the cell uses one), delegate, button cell and table view.
    [coder encodeObject: list];
    [coder encodeObject: dataSource];
    [coder encodeObject: nil];
    [coder encodeObject: nil];
    [coder encodeObject: nil];
}
@end

static void test_quirk_typedstream_combo_box_cell(void)
{
    class_setVersion([NSCell class], 55);
    class_setVersion([NSActionCell class], 17);
    class_setVersion([NSTextFieldCell class], 61);
    class_setVersion([NSComboBoxCell class], 2);
    NSComboBoxCell *cell = roundTrip([[[TComboCell alloc] initTextCell: @""] autorelease]);
    expect([cell isKindOfClass: [NSComboBoxCell class]], "combo box cell decodes");
    expect([cell numberOfVisibleItems] == 8, "combo box visible items");
    expect(![cell hasVerticalScroller], "combo box scroller");
    expect([cell usesDataSource] && [cell completes], "combo box data source and completion flags");
    expect([[cell dataSource] isKindOfClass: [TTarget class]], "combo box data source");
    expect([cell tag] == 3, "combo box cell inherits the action cell layer");
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        struct {
            const char *name;
            void (*test)(void);
        } tests[] = {
            {"tab view item", test_quirk_typedstream_tab_view_item},
            {"table column", test_quirk_typedstream_table_column},
            {"scroller", test_quirk_typedstream_scroller},
            {"clip view", test_quirk_typedstream_clip_view},
            {"tab view", test_quirk_typedstream_tab_view},
            {"scroll view", test_quirk_typedstream_scroll_view},
            {"table view", test_quirk_typedstream_table_view},
            {"outline view", test_quirk_typedstream_outline_view},
            {"combo box cell", test_quirk_typedstream_combo_box_cell},
        };

        for (size_t i = 0; i < sizeof(tests) / sizeof(tests[0]); i++) {
            @try {
                tests[i].test();
            } @catch (NSException *e) {
                fprintf(stderr, "FAIL: %s raised %s: %s\n", tests[i].name,
                        [[e name] UTF8String], [[e reason] UTF8String]);
                failures++;
            }
        }
    }
    if (failures == 0)
        printf("typedstream controls: PASS\n");
    return failures == 0 ? 0 : 1;
}
