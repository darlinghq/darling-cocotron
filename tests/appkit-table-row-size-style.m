// NSTableView rowSizeStyle: documented default Custom, effectiveRowSizeStyle for Default,
// and row heights following the style.
#import <AppKit/AppKit.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

@interface Rows : NSObject
@end
@implementation Rows
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return 3; }
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row { return @"x"; }
@end

static CGFloat lineHeight(NSControlSize size)
{
    return [[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:size]] defaultLineHeightForFont];
}

static CGFloat rowHeight(NSTableView *table)
{
    return [table rectOfRow:2].size.height - table.intercellSpacing.height;
}

int main(void)
{
    @autoreleasepool
    {
        Rows *rows = [[Rows alloc] init];
        NSTableView *table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        [table addTableColumn:[[[NSTableColumn alloc] initWithIdentifier:@"c"] autorelease]];
        table.dataSource = (id)rows;
        table.rowHeight = 40;

        expect(table.rowSizeStyle == NSTableViewRowSizeStyleCustom, @"default style is Custom");
        expect(table.effectiveRowSizeStyle == NSTableViewRowSizeStyleCustom, @"effective style of Custom");
        expect(rowHeight(table) == 40, @"Custom rows use rowHeight");

        table.rowSizeStyle = NSTableViewRowSizeStyleSmall;
        expect(rowHeight(table) == lineHeight(NSControlSizeSmall), @"Small rows fit the small system font");
        expect([table rectOfRow:2].origin.y == 2 * [table rectOfRow:0].size.height, @"Small rows are stacked");

        table.rowSizeStyle = NSTableViewRowSizeStyleDefault;
        expect(table.rowSizeStyle == NSTableViewRowSizeStyleDefault, @"Default is kept");
        expect(table.effectiveRowSizeStyle == NSTableViewRowSizeStyleMedium, @"Default resolves to Medium");
        expect(rowHeight(table) == lineHeight(NSControlSizeRegular), @"Medium rows fit the regular system font");

        table.rowSizeStyle = NSTableViewRowSizeStyleCustom;
        expect(rowHeight(table) == 40, @"back to rowHeight for Custom");
        expect(table.rowHeight == 40, @"rowHeight is untouched by the style");

        NSOutlineView *outline = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        [outline setRowSizeStyle:NSTableViewRowSizeStyleLarge];
        expect([outline rowSizeStyle] == NSTableViewRowSizeStyleLarge, @"outline view keeps Large");

        [outline release];
        [table release];
        [rows release];
        NSLog(@"PASS: NSTableView rowSizeStyle");
    }
    return 0;
}
