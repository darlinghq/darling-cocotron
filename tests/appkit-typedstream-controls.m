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
 * The layouts of the controls are not documented; they come from the reports of
 * the contributor of the decoders (archives found in old nibs). These tests pin
 * the layouts the decoders accept; they cannot confirm them against macOS.
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
    int state = 0;
    id responder = nil, tabView = nil;

    putObject(coder, identifier);
    putObject(coder, label);
    putObject(coder, view);
    putObject(coder, color);
    [coder encodeValueOfObjCType: "i" at: &state];
    putObject(coder, responder);
    putObject(coder, tabView);
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

@interface TColumnV1 : NSTableColumn
@end
@interface TColumnV2 : NSTableColumn
@end

@implementation TColumnV1
- (void) encodeWithCoder: (NSCoder *) coder
{
    id identifier = @"name", header = @"Header", data = @"Data";
    float w = 120, minW = 20, maxW = 300;
    char resizable = 0, editable = 1;

    [coder encodeValuesOfObjCTypes: "@@@fffcc", &identifier, &header, &data, &w,
                                    &minW, &maxW, &resizable, &editable];
}
@end

@implementation TColumnV2
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
    class_setVersion([NSTableColumn class], 1);
    NSTableColumn *v1 = roundTrip([[[TColumnV1 alloc] init] autorelease]);
    expect([[v1 identifier] isEqual: @"name"], "v1 column identifier");
    expect([v1 width] == 120 && [v1 minWidth] == 20 && [v1 maxWidth] == 300, "v1 column widths");
    expect(![v1 isResizable] && [v1 isEditable], "v1 column flags");
    expect([[v1 headerCell] isEqual: @"Header"] && [[v1 dataCell] isEqual: @"Data"], "v1 column cells");

    class_setVersion([NSTableColumn class], 2);
    NSTableColumn *v2 = roundTrip([[[TColumnV2 alloc] init] autorelease]);
    expect([[v2 identifier] isEqual: @"size"], "v2 column identifier");
    expect([v2 width] == 90 && [v2 minWidth] == 15 && [v2 maxWidth] == 250, "v2 column widths");
    expect([v2 isResizable] && ![v2 isEditable], "v2 column flags");
    expect([[v2 headerCell] isEqual: @"Header2"] && [[v2 dataCell] isEqual: @"Data2"], "v2 column cells");
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
    char arrows = 1, size = 1;

    putViewLayers(coder, NSMakeRect(0, 0, 15, 100));
    putControlLayer(coder);
    putObject(coder, target);
    [coder encodeValuesOfObjCTypes: "ff:", &value, &proportion, &action];
    [coder encodeValueOfObjCType: "c" at: &arrows];
    [coder encodeValueOfObjCType: "c" at: &size];
}
@end

static void test_quirk_typedstream_scroller(void)
{
    class_setVersion([NSView class], 16);
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
    char copyOnScroll = 1, drawsBackground = 0, other = 0;

    putViewLayers(coder, NSMakeRect(0, 0, 200, 100));
    [coder encodeObject: background];
    [coder encodeValuesOfObjCTypes: "@@ccc", &cursor, &docView, &copyOnScroll,
                                    &drawsBackground, &other];
}
@end

static void test_quirk_typedstream_clip_view(void)
{
    class_setVersion([NSView class], 16);
    NSClipView *clip = roundTrip([[[TClipView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)] autorelease]);
    expect([clip isKindOfClass: [NSClipView class]], "clip view decodes");
    expect([clip copiesOnScroll], "clip view copies on scroll");
    expect(![clip drawsBackground], "clip view does not draw its background");
    expect([clip documentView] == nil, "clip view has no document view");
}

// --- NSTabView ---------------------------------------------------------------

@interface TTabViewV2 : NSTabView
@end
@interface TTabViewV3 : NSTabView
@end

static void putTabViewLayer(NSCoder *coder)
{
    id items = [NSMutableArray array], font = nil;
    int type = NSBottomTabsBezelBorder;
    BOOL draws = YES, truncated = YES;

    putViewLayers(coder, NSMakeRect(0, 0, 300, 200));
    putObject(coder, items);
    putObject(coder, font);
    [coder encodeValueOfObjCType: "i" at: &type];
    [coder encodeValueOfObjCType: @encode(BOOL) at: &draws];
    [coder encodeValueOfObjCType: @encode(BOOL) at: &truncated];
    [coder encodeObject: nil];
}

@implementation TTabViewV2
- (void) encodeWithCoder: (NSCoder *) coder
{
    int selected = -1;

    putTabViewLayer(coder);
    [coder encodeValueOfObjCType: "i" at: &selected];
}
@end

@implementation TTabViewV3
- (void) encodeWithCoder: (NSCoder *) coder
{
    NSUInteger selected = NSNotFound;

    putTabViewLayer(coder);
    [coder encodeValueOfObjCType: @encode(NSUInteger) at: &selected];
}
@end

static void test_quirk_typedstream_tab_view(void)
{
    class_setVersion([NSView class], 16);
    class_setVersion([NSTabView class], 2);
    NSTabView *v2 = roundTrip([[[TTabViewV2 alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)] autorelease]);
    expect([v2 tabViewType] == NSBottomTabsBezelBorder, "v2 tab view type");
    expect([v2 drawsBackground] && [[v2 tabViewItems] count] == 0, "v2 tab view state");

    class_setVersion([NSTabView class], 3);
    NSTabView *v3 = roundTrip([[[TTabViewV3 alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)] autorelease]);
    expect([v3 tabViewType] == NSBottomTabsBezelBorder, "v3 tab view type");
    expect([v3 drawsBackground] && [[v3 tabViewItems] count] == 0, "v3 tab view state");
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
    float hLine = 11, hPage = 12, vLine = 13, vPage = 14;
    int flags = 0;

    putViewLayers(coder, NSMakeRect(0, 0, 215, 100));
    [coder encodeObject: clip];
    [coder encodeObject: vertical];
    [coder encodeObject: horizontal];
    [coder encodeObject: corner];
    [coder encodeObject: header];
    [coder encodeValuesOfObjCTypes: "ffffi", &hLine, &hPage, &vLine, &vPage, &flags];
}
@end

@implementation TScrollViewOld
- (void) encodeWithCoder: (NSCoder *) coder
{
    id clip = [[[TClipView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)] autorelease];
    id vertical = [[[TScroller alloc] initWithFrame: NSMakeRect(0, 0, 15, 100)] autorelease];
    NSInteger border = NSBezelBorder;
    BOOL dynamically = YES, rulers = NO, yes = YES, no = NO;
    float hLine = 5, hPage = 6, vLine = 7, vPage = 8;

    putViewLayers(coder, NSMakeRect(0, 0, 215, 100));
    [coder encodeObject: clip];
    [coder encodeValueOfObjCType: @encode(NSInteger) at: &border];
    [coder encodeValueOfObjCType: @encode(BOOL) at: &dynamically];
    [coder encodeValueOfObjCType: @encode(BOOL) at: &rulers];
    [coder encodeValueOfObjCType: "f" at: &hLine];
    [coder encodeValueOfObjCType: "f" at: &hPage];
    [coder encodeValueOfObjCType: "f" at: &vLine];
    [coder encodeValueOfObjCType: "f" at: &vPage];
    [coder encodeValueOfObjCType: @encode(BOOL) at: &no];
    [coder encodeValueOfObjCType: @encode(BOOL) at: &yes];
    putObject(coder, vertical);
    [coder encodeValueOfObjCType: @encode(BOOL) at: &no];
    [coder encodeValueOfObjCType: @encode(BOOL) at: &no];
    [coder encodeValueOfObjCType: @encode(BOOL) at: &no];
    [coder encodeValueOfObjCType: @encode(BOOL) at: &no];
}
@end

static void test_quirk_typedstream_scroll_view(void)
{
    class_setVersion([NSView class], 16);
    class_setVersion([NSScrollView class], 20);
    NSScrollView *newer = roundTrip([[[TScrollViewNew alloc] initWithFrame: NSMakeRect(0, 0, 215, 100)] autorelease]);
    expect([[newer contentView] isKindOfClass: [NSClipView class]], "version 20 scroll view content view");
    expect([newer hasVerticalScroller] && ![newer hasHorizontalScroller], "version 20 scroll view scrollers");
    expect([newer horizontalLineScroll] == 11 && [newer verticalPageScroll] == 14, "version 20 scroll amounts");

    class_setVersion([NSScrollView class], 1);
    NSScrollView *older = roundTrip([[[TScrollViewOld alloc] initWithFrame: NSMakeRect(0, 0, 215, 100)] autorelease]);
    expect([[older contentView] isKindOfClass: [NSClipView class]], "version 1 scroll view content view");
    expect([older borderType] == NSBezelBorder, "version 1 scroll view border");
    expect([older hasVerticalScroller] && ![older hasHorizontalScroller], "version 1 scroll view scrollers");
    expect([older horizontalLineScroll] == 5 && [older verticalPageScroll] == 8, "version 1 scroll amounts");
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
    BOOL autoResizes = NO, follows = NO, autosave = YES;
    float indentation = 12;
    id column = nil;

    putViewLayers(coder, NSMakeRect(0, 0, 300, 200));
    putControlLayer(coder);
    putTableViewLayer(coder);
    [coder encodeValueOfObjCType: @encode(BOOL) at: &autoResizes];
    [coder encodeValueOfObjCType: @encode(BOOL) at: &follows];
    [coder encodeValueOfObjCType: @encode(BOOL) at: &autosave];
    [coder encodeValueOfObjCType: "f" at: &indentation];
    [coder encodeObject: column];
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
    expect([table allowsColumnReordering] && [table allowsMultipleSelection], "table view flag bits");
    expect(![table allowsColumnResizing] && ![table allowsEmptySelection], "table view clear flag bits");
    expect([[table tableColumns] count] == 0, "table view columns");
}

static void test_quirk_typedstream_outline_view(void)
{
    class_setVersion([NSView class], 16);
    NSOutlineView *outline = roundTrip([[[TOutlineView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)] autorelease]);
    expect([outline isKindOfClass: [NSOutlineView class]], "outline view decodes");
    expect([outline indentationPerLevel] == 12, "outline view indentation");
    expect(![outline indentationMarkerFollowsCell], "outline view marker follows cell");
    expect(![outline autoresizesOutlineColumn], "outline view autoresizes outline column");
    expect([outline autosaveExpandedItems], "outline view autosaves expanded items");
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
    [coder encodeObject: list];
    [coder encodeObject: dataSource];
    [coder encodeObject: nil];
    [coder encodeObject: nil];
}
@end

static void test_quirk_typedstream_combo_box_cell(void)
{
    class_setVersion([NSCell class], 55);
    class_setVersion([NSActionCell class], 17);
    class_setVersion([NSTextFieldCell class], 61);
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
