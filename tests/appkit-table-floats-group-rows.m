// NSTableView floatsGroupRows: documented default YES, settable, inherited by NSOutlineView.
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

int main(void)
{
    @autoreleasepool
    {
        NSTableView *table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        expect(table.floatsGroupRows, @"table view floats group rows by default");
        table.floatsGroupRows = NO;
        expect(!table.floatsGroupRows, @"table view keeps NO");
        table.floatsGroupRows = YES;
        expect(table.floatsGroupRows, @"table view keeps YES");
        [table release];

        NSOutlineView *outline = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        expect(outline.floatsGroupRows, @"outline view floats group rows by default");
        [outline setFloatsGroupRows:NO];
        expect(![outline floatsGroupRows], @"outline view keeps NO");
        [outline release];

        NSLog(@"PASS: NSTableView floatsGroupRows");
    }
    return 0;
}
